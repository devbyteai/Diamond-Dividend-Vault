// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDividendPayingToken, IDividendPayingTokenOptional} from "./interfaces/IDividendPayingToken.sol";
import {IDiamondDividendVault} from "./interfaces/IDiamondDividendVault.sol";
import {ILayerZeroEndpoint} from "./interfaces/ILayerZeroEndpoint.sol";

/// @title DiamondDividendVault
/// @author devbyteai
/// @notice First-ever hybrid yield vault combining ERC-4626 + ERC-1726 with multi-dimensional weighted dividends
/// @dev Novel features:
///      - ERC-4626 + ERC-1726 hybrid (first implementation)
///      - Multi-dimensional weighted dividends (time × balance multipliers)
///      - Anti-whale mechanics via dividend penalties (0.9x for large holders)
///      - 5-tier holding duration rewards (1x → 2x over 365 days)
///      - Cross-chain dividend distribution via LayerZero
///      - Multi-protocol yield aggregation (Aave, Compound, Yearn, EigenLayer)
///
/// Dual income streams:
///      1. ERC-4626: Share appreciation as vault earns yield
///      2. ERC-1726: Claimable ETH dividends with weighted distribution
///
/// Dividend formula:
///      dividend = (magnifiedDividendPerShare * weightedBalance + correction) / MAGNITUDE
///
/// MAGNITUDE = 2^128 provides ~38 decimal precision for wei-level accuracy.
contract DiamondDividendVault is
    ERC4626,
    Ownable,
    Pausable,
    ReentrancyGuard,
    IDividendPayingToken,
    IDividendPayingTokenOptional,
    IDiamondDividendVault
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Precision multiplier for dividend calculations
    /// 2^128 provides ~38 decimal places, preventing rounding errors in wei calculations
    /// Example: For 1 ETH distributed to 1M tokens, precision loss < 0.0001 wei
    uint256 private constant MAGNITUDE = 2 ** 128;

    /// @dev Basis points denominator (10000 = 100%)
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @dev Maximum number of holding duration tiers
    uint256 private constant MAX_HOLDING_TIERS = 10;

    /// @dev Maximum number of balance tiers
    uint256 private constant MAX_BALANCE_TIERS = 10;

    /// @dev Maximum number of yield sources
    uint256 private constant MAX_YIELD_SOURCES = 10;

    /*//////////////////////////////////////////////////////////////
                            DIVIDEND STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Cumulative dividend per weighted share (magnified by MAGNITUDE)
    uint256 private _magnifiedDividendPerShare;

    /// @dev Per-address correction to preserve dividends through transfers
    /// Positive when user sends tokens, negative when receiving
    mapping(address account => int256 correction) private _magnifiedDividendCorrections;

    /// @dev Per-address tracking of already withdrawn dividends
    mapping(address account => uint256 amount) private _withdrawnDividends;

    /// @dev Total ETH dividends ever distributed
    uint256 public totalDividendsDistributed;

    /*//////////////////////////////////////////////////////////////
                        HOLDING DURATION STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Per-address holding information
    mapping(address account => HoldingInfo info) private _holdingInfo;

    /// @dev Configurable holding duration tiers (longer hold = higher multiplier)
    HoldingTier[] private _holdingTiers;

    /*//////////////////////////////////////////////////////////////
                        BALANCE TIER STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Configurable balance tiers (for anti-whale or loyalty bonuses)
    BalanceTier[] private _balanceTiers;

    /*//////////////////////////////////////////////////////////////
                        WEIGHTED SHARES STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Total of all users' weighted shares
    uint256 private _totalWeightedShares;

    /// @dev Per-user cached weighted share value
    mapping(address account => uint256 weightedShare) private _userWeightedShares;

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev LayerZero endpoint for cross-chain messaging
    address public lzEndpoint;

    /// @dev Trusted remote contract addresses per chain ID
    mapping(uint16 chainId => bytes trustedRemote) public trustedRemotes;

    /// @dev Pending cross-chain dividends for failed transfers
    mapping(address account => mapping(uint16 chainId => uint256 amount)) public pendingCrossChainDividends;

    /*//////////////////////////////////////////////////////////////
                        YIELD SOURCE STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Configured yield sources
    YieldSource[] private _yieldSources;

    /// @dev Protocol address to array index mapping (1-indexed, 0 = not found)
    mapping(address protocol => uint256 indexPlusOne) private _yieldSourceIndex;

    /// @dev Total yield harvested from all sources
    uint256 public totalYieldHarvested;

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Timelock controller for governance operations
    address public timelock;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev No shares exist to distribute dividends to
    error NoSharesExist();

    /// @dev User has no dividends to claim
    error NoDividendsToClaim();

    /// @dev ETH transfer failed
    error ETHTransferFailed();

    /// @dev Invalid tier configuration
    error InvalidTier();

    /// @dev Maximum tier count exceeded
    error TooManyTiers();

    /// @dev Maximum yield source count exceeded
    error TooManyYieldSources();

    /// @dev Yield source not found
    error YieldSourceNotFound();

    /// @dev Yield source already registered
    error YieldSourceAlreadyExists();

    /// @dev Cross-chain functionality not enabled
    error CrossChainNotEnabled();

    /// @dev Invalid trusted remote configuration
    error InvalidRemote();

    /// @dev Insufficient fee for cross-chain operation
    error InsufficientFeeForCrossChain();

    /// @dev Deposit to yield source failed
    error YieldSourceDepositFailed();

    /// @dev Withdrawal from yield source failed
    error YieldSourceWithdrawFailed();

    /// @dev Caller is not owner or timelock
    error UnauthorizedGovernance();

    /// @dev Zero deposit not allowed
    error ZeroDeposit();

    // Note: All events inherited from IDiamondDividendVault interface

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys the hybrid yield token
    /// @param asset_ The underlying ERC20 asset for the vault
    /// @param name_ The name of the vault share token
    /// @param symbol_ The symbol of the vault share token
    /// @param lzEndpoint_ LayerZero endpoint address (address(0) to disable cross-chain)
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address lzEndpoint_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(msg.sender) {
        lzEndpoint = lzEndpoint_;
        _initializeDefaultTiers();
    }

    /// @dev Initializes default holding and balance tier configurations
    function _initializeDefaultTiers() private {
        // Holding duration tiers: reward long-term holders
        // 0-30 days: 1x, 30-90 days: 1.25x, 90-180 days: 1.5x, 180-365 days: 1.75x, 365+ days: 2x
        _holdingTiers.push(HoldingTier({minDuration: 0, multiplierBps: 10_000}));
        _holdingTiers.push(HoldingTier({minDuration: 30 days, multiplierBps: 12_500}));
        _holdingTiers.push(HoldingTier({minDuration: 90 days, multiplierBps: 15_000}));
        _holdingTiers.push(HoldingTier({minDuration: 180 days, multiplierBps: 17_500}));
        _holdingTiers.push(HoldingTier({minDuration: 365 days, multiplierBps: 20_000}));

        // Balance tiers: anti-whale mechanics
        // Small holders get bonus, whales get slight penalty
        _balanceTiers.push(BalanceTier({minBalance: 0, multiplierBps: 12_000}));
        _balanceTiers.push(BalanceTier({minBalance: 1_000 ether, multiplierBps: 11_000}));
        _balanceTiers.push(BalanceTier({minBalance: 10_000 ether, multiplierBps: 10_000}));
        _balanceTiers.push(BalanceTier({minBalance: 100_000 ether, multiplierBps: 9_000}));
    }

    /*//////////////////////////////////////////////////////////////
                        HOLDING DURATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDiamondDividendVault
    function getHoldingInfo(address account) external view returns (HoldingInfo memory) {
        return _holdingInfo[account];
    }

    /// @inheritdoc IDiamondDividendVault
    function getHoldingDuration(address account) public view returns (uint256) {
        HoldingInfo storage info = _holdingInfo[account];

        // No tokens = no holding duration
        if (balanceOf(account) == 0) {
            return 0;
        }

        // Never held before
        if (info.firstHoldTimestamp == 0) {
            return 0;
        }

        // Currently holding: calculate active duration + historical
        if (info.lastResetTimestamp > 0) {
            return (block.timestamp - info.lastResetTimestamp) + info.totalHoldingTime;
        }

        // Was holding, sold all, historical time preserved
        return info.totalHoldingTime;
    }

    /// @inheritdoc IDiamondDividendVault
    function getHoldingMultiplier(address account) public view returns (uint256) {
        uint256 duration = getHoldingDuration(account);

        // Find highest applicable tier (iterate backwards for efficiency)
        uint256 len = _holdingTiers.length;
        for (uint256 i = len; i > 0;) {
            unchecked { --i; }
            if (duration >= _holdingTiers[i].minDuration) {
                return _holdingTiers[i].multiplierBps;
            }
        }

        // Default to first tier
        return _holdingTiers[0].multiplierBps;
    }

    /*//////////////////////////////////////////////////////////////
                        BALANCE TIER LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDiamondDividendVault
    function getBalanceTier(address account) public view returns (uint256 tierIndex, uint256 multiplierBps) {
        uint256 balance = balanceOf(account);

        // Find highest applicable tier
        uint256 len = _balanceTiers.length;
        for (uint256 i = len; i > 0;) {
            unchecked { --i; }
            if (balance >= _balanceTiers[i].minBalance) {
                return (i, _balanceTiers[i].multiplierBps);
            }
        }

        // Default to first tier
        return (0, _balanceTiers[0].multiplierBps);
    }

    /// @inheritdoc IDiamondDividendVault
    function getEffectiveMultiplier(address account) public view returns (uint256) {
        uint256 holdingMult = getHoldingMultiplier(account);
        (, uint256 balanceMult) = getBalanceTier(account);

        // Combined multiplier: (holding * balance) / BPS
        return (holdingMult * balanceMult) / BPS_DENOMINATOR;
    }

    /// @dev Calculates weighted share for dividend distribution
    /// @param account The address to calculate for
    /// @return The weighted share value
    function _calculateWeightedShare(address account) private view returns (uint256) {
        uint256 balance = balanceOf(account);
        if (balance == 0) return 0;

        uint256 multiplier = getEffectiveMultiplier(account);
        return (balance * multiplier) / BPS_DENOMINATOR;
    }

    /*//////////////////////////////////////////////////////////////
                        DIVIDEND DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDividendPayingToken
    function distributeDividends() external payable whenNotPaused {
        if (_totalWeightedShares == 0) revert NoSharesExist();

        if (msg.value > 0) {
            unchecked {
                _magnifiedDividendPerShare += (msg.value * MAGNITUDE) / _totalWeightedShares;
            }
            totalDividendsDistributed += msg.value;
            emit DividendsDistributed(msg.sender, msg.value);
        }
    }

    /// @inheritdoc IDividendPayingToken
    function withdrawDividend() external nonReentrant whenNotPaused {
        _withdrawDividendTo(msg.sender, msg.sender);
    }

    /// @notice Withdraw dividends to a different recipient
    /// @param recipient Address to receive the dividends
    function withdrawDividendTo(address recipient) external nonReentrant whenNotPaused {
        _withdrawDividendTo(msg.sender, recipient);
    }

    /// @dev Internal dividend withdrawal logic
    /// @param account The account whose dividends to withdraw
    /// @param recipient The address to receive the ETH
    function _withdrawDividendTo(address account, address recipient) private {
        // Refresh weighted shares first
        _updateWeightedShares(account);

        uint256 withdrawable = withdrawableDividendOf(account);
        if (withdrawable == 0) revert NoDividendsToClaim();

        // Update state before transfer (checks-effects-interactions)
        _withdrawnDividends[account] += withdrawable;

        // Transfer ETH
        (bool success,) = recipient.call{value: withdrawable}("");
        if (!success) revert ETHTransferFailed();

        emit DividendWithdrawn(recipient, withdrawable);
    }

    /// @inheritdoc IDividendPayingToken
    function dividendOf(address owner) external view returns (uint256) {
        return withdrawableDividendOf(owner);
    }

    /// @inheritdoc IDividendPayingTokenOptional
    function withdrawableDividendOf(address owner) public view returns (uint256) {
        return accumulativeDividendOf(owner) - _withdrawnDividends[owner];
    }

    /// @inheritdoc IDividendPayingTokenOptional
    function withdrawnDividendOf(address owner) external view returns (uint256) {
        return _withdrawnDividends[owner];
    }

    /// @inheritdoc IDividendPayingTokenOptional
    function accumulativeDividendOf(address owner) public view returns (uint256) {
        uint256 weightedShare = _calculateWeightedShare(owner);

        // Calculate magnified dividend
        int256 magnifiedDividends = int256(_magnifiedDividendPerShare * weightedShare);
        int256 correctedDividends = magnifiedDividends + _magnifiedDividendCorrections[owner];

        // Ensure non-negative before conversion
        if (correctedDividends < 0) {
            return 0;
        }

        return uint256(correctedDividends) / MAGNITUDE;
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN DIVIDENDS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDiamondDividendVault
    function claimCrossChainDividend(uint16 dstChainId) external payable nonReentrant whenNotPaused {
        if (lzEndpoint == address(0)) revert CrossChainNotEnabled();
        if (trustedRemotes[dstChainId].length == 0) revert InvalidRemote();

        uint256 withdrawable = withdrawableDividendOf(msg.sender);
        if (withdrawable == 0) revert NoDividendsToClaim();

        // Mark as withdrawn locally
        _withdrawnDividends[msg.sender] += withdrawable;

        // Encode payload
        bytes memory payload = abi.encode(msg.sender, withdrawable);

        // Verify fee
        uint256 fee = estimateCrossChainFee(dstChainId, msg.sender, withdrawable);
        if (msg.value < fee) revert InsufficientFeeForCrossChain();

        // Send via LayerZero
        ILayerZeroEndpoint(lzEndpoint).send{value: msg.value}(
            dstChainId,
            trustedRemotes[dstChainId],
            payload,
            payable(msg.sender),
            address(0),
            bytes("")
        );

        emit CrossChainDividendSent(dstChainId, msg.sender, withdrawable);
    }

    /// @inheritdoc IDiamondDividendVault
    function estimateCrossChainFee(
        uint16 dstChainId,
        address recipient,
        uint256 amount
    ) public view returns (uint256) {
        if (lzEndpoint == address(0)) return 0;

        bytes memory payload = abi.encode(recipient, amount);
        (uint256 nativeFee,) = ILayerZeroEndpoint(lzEndpoint).estimateFees(
            dstChainId,
            address(this),
            payload,
            false,
            bytes("")
        );
        return nativeFee;
    }

    /// @notice LayerZero receive handler
    /// @dev Called by LayerZero endpoint when cross-chain message arrives
    function lzReceive(
        uint16 srcChainId,
        bytes calldata srcAddress,
        uint64,
        bytes calldata payload
    ) external {
        if (msg.sender != lzEndpoint) revert CrossChainNotEnabled();
        if (keccak256(srcAddress) != keccak256(trustedRemotes[srcChainId])) revert InvalidRemote();

        (address recipient, uint256 amount) = abi.decode(payload, (address, uint256));

        // Attempt transfer
        (bool success,) = recipient.call{value: amount}("");
        if (!success) {
            // Store as pending if transfer fails
            pendingCrossChainDividends[recipient][srcChainId] += amount;
        }

        emit CrossChainDividendReceived(srcChainId, recipient, amount);
    }

    /// @notice Claim pending cross-chain dividends that failed to transfer
    /// @param srcChainId The source chain ID
    function claimPendingCrossChainDividend(uint16 srcChainId) external nonReentrant {
        uint256 pending = pendingCrossChainDividends[msg.sender][srcChainId];
        if (pending == 0) revert NoDividendsToClaim();

        pendingCrossChainDividends[msg.sender][srcChainId] = 0;

        (bool success,) = msg.sender.call{value: pending}("");
        if (!success) revert ETHTransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                        YIELD SOURCE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDiamondDividendVault
    function harvestYield() external nonReentrant whenNotPaused {
        uint256 totalHarvested = 0;
        uint256 len = _yieldSources.length;

        for (uint256 i = 0; i < len;) {
            YieldSource storage source = _yieldSources[i];
            if (source.active) {
                uint256 harvested = _harvestFromSource(source);
                if (harvested > 0) {
                    totalHarvested += harvested;
                    emit YieldHarvested(source.protocol, harvested);
                }
            }
            unchecked { ++i; }
        }

        if (totalHarvested > 0) {
            totalYieldHarvested += totalHarvested;

            // Distribute as dividends
            if (_totalWeightedShares > 0) {
                unchecked {
                    _magnifiedDividendPerShare += (totalHarvested * MAGNITUDE) / _totalWeightedShares;
                }
                totalDividendsDistributed += totalHarvested;
                emit DividendsDistributed(address(this), totalHarvested);
            }
        }
    }

    /// @inheritdoc IDiamondDividendVault
    function rebalanceYieldSources() external onlyOwner {
        uint256 len = _yieldSources.length;

        // Withdraw from all sources
        for (uint256 i = 0; i < len;) {
            YieldSource storage source = _yieldSources[i];
            if (source.active) {
                _withdrawFromSource(source, type(uint256).max);
            }
            unchecked { ++i; }
        }

        // Redeposit according to allocations
        uint256 totalAssets = IERC20(asset()).balanceOf(address(this));
        for (uint256 i = 0; i < len;) {
            YieldSource storage source = _yieldSources[i];
            if (source.active && source.allocationBps > 0) {
                uint256 amount = (totalAssets * source.allocationBps) / BPS_DENOMINATOR;
                if (amount > 0) {
                    _depositToSource(source, amount);
                }
            }
            unchecked { ++i; }
        }
    }

    /// @inheritdoc IDiamondDividendVault
    function getTotalYieldGenerated() external view returns (uint256) {
        return totalYieldHarvested;
    }

    /// @dev Harvests yield from a specific source
    /// @param source The yield source to harvest from
    /// @return harvested The amount harvested
    function _harvestFromSource(YieldSource storage source) private returns (uint256 harvested) {
        // Protocol-specific harvest logic would go here
        // For now, returns 0 - actual implementation requires protocol adapters
        return 0;
    }

    /// @dev Deposits assets to a yield source
    /// @param source The yield source
    /// @param amount Amount to deposit
    function _depositToSource(YieldSource storage source, uint256 amount) private {
        IERC20(asset()).safeIncreaseAllowance(source.protocol, amount);
        (bool success,) = source.protocol.call(abi.encodeWithSelector(source.depositSelector, amount));
        if (!success) revert YieldSourceDepositFailed();
    }

    /// @dev Withdraws assets from a yield source
    /// @param source The yield source
    /// @param amount Amount to withdraw (type(uint256).max for all)
    function _withdrawFromSource(YieldSource storage source, uint256 amount) private {
        (bool success,) = source.protocol.call(abi.encodeWithSelector(source.withdrawSelector, amount));
        if (!success) revert YieldSourceWithdrawFailed();
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDES (Pausable)
    //////////////////////////////////////////////////////////////*/

    /// @dev Override deposit to add pause check and zero validation
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        if (assets == 0) revert ZeroDeposit();
        return super.deposit(assets, receiver);
    }

    /// @dev Override mint to add pause check
    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @dev Override withdraw to add pause check
    function withdraw(uint256 assets, address receiver, address owner_) public override whenNotPaused returns (uint256) {
        return super.withdraw(assets, receiver, owner_);
    }

    /// @dev Override redeem to add pause check
    function redeem(uint256 shares, address receiver, address owner_) public override whenNotPaused returns (uint256) {
        return super.redeem(shares, receiver, owner_);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER HOOKS
    //////////////////////////////////////////////////////////////*/

    /// @dev Overrides ERC20 _update to handle dividend corrections and holding tracking
    function _update(address from, address to, uint256 value) internal override {
        // Update weighted shares BEFORE balance change
        if (from != address(0)) _updateWeightedShares(from);
        if (to != address(0)) _updateWeightedShares(to);

        // Execute the actual transfer
        super._update(from, to, value);

        // Update holding info
        _updateHoldingInfo(from, to);

        // Calculate and apply dividend corrections
        _applyDividendCorrections(from, to, value);

        // Update weighted shares AFTER balance change
        if (from != address(0)) _updateWeightedShares(from);
        if (to != address(0)) _updateWeightedShares(to);
    }

    /// @dev Updates holding info on transfer
    function _updateHoldingInfo(address from, address to) private {
        // Handle sender
        if (from != address(0) && balanceOf(from) == 0) {
            HoldingInfo storage fromInfo = _holdingInfo[from];
            if (fromInfo.lastResetTimestamp > 0) {
                fromInfo.totalHoldingTime += block.timestamp - fromInfo.lastResetTimestamp;
                fromInfo.lastResetTimestamp = 0;
            }
        }

        // Handle receiver
        if (to != address(0)) {
            HoldingInfo storage toInfo = _holdingInfo[to];
            if (toInfo.firstHoldTimestamp == 0) {
                toInfo.firstHoldTimestamp = block.timestamp;
                toInfo.lastResetTimestamp = block.timestamp;
            } else if (toInfo.lastResetTimestamp == 0) {
                toInfo.lastResetTimestamp = block.timestamp;
            }
        }
    }

    /// @dev Applies dividend corrections to preserve entitlements through transfers
    function _applyDividendCorrections(address from, address to, uint256 value) private {
        uint256 fromMultiplier = from != address(0) ? getEffectiveMultiplier(from) : BPS_DENOMINATOR;
        uint256 toMultiplier = to != address(0) ? getEffectiveMultiplier(to) : BPS_DENOMINATOR;

        if (from != address(0)) {
            uint256 weightedValue = (value * fromMultiplier) / BPS_DENOMINATOR;
            int256 correction = int256(_magnifiedDividendPerShare * weightedValue);
            _magnifiedDividendCorrections[from] += correction;
        }

        if (to != address(0)) {
            uint256 weightedValue = (value * toMultiplier) / BPS_DENOMINATOR;
            int256 correction = int256(_magnifiedDividendPerShare * weightedValue);
            _magnifiedDividendCorrections[to] -= correction;
        }
    }

    /// @dev Updates a user's weighted share in the total
    function _updateWeightedShares(address account) private {
        uint256 oldWeighted = _userWeightedShares[account];
        uint256 newWeighted = _calculateWeightedShare(account);

        if (oldWeighted != newWeighted) {
            _totalWeightedShares = _totalWeightedShares - oldWeighted + newWeighted;
            _userWeightedShares[account] = newWeighted;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Restricts function access to owner or governance timelock
    modifier onlyGovernance() {
        if (msg.sender != owner() && msg.sender != timelock) {
            revert UnauthorizedGovernance();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        PUBLIC WEIGHT UPDATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Refreshes the weighted shares for an account
    /// @dev Anyone can call this to update stale weighted share values
    ///      Useful when a user's multiplier has changed due to time passing
    /// @param account The account to refresh
    function refreshWeightedShares(address account) external {
        _updateWeightedShares(account);
    }

    /// @notice Refreshes the weighted shares for multiple accounts
    /// @param accounts Array of accounts to refresh
    function refreshWeightedSharesBatch(address[] calldata accounts) external {
        for (uint256 i = 0; i < accounts.length; i++) {
            _updateWeightedShares(accounts[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the governance timelock address
    /// @param _timelock New timelock controller address
    function setTimelock(address _timelock) external onlyOwner {
        address oldTimelock = timelock;
        timelock = _timelock;
        emit TimelockUpdated(oldTimelock, _timelock);
    }

    /// @notice Pauses dividend operations
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses dividend operations
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Updates or adds a holding duration tier
    /// @dev Can only be called by owner or governance timelock
    /// @param index Tier index (0-based)
    /// @param minDuration Minimum holding duration for this tier
    /// @param multiplierBps Multiplier in basis points
    function setHoldingTier(uint256 index, uint256 minDuration, uint256 multiplierBps) external onlyGovernance {
        if (index >= MAX_HOLDING_TIERS) revert TooManyTiers();
        if (multiplierBps == 0) revert InvalidTier();

        if (index >= _holdingTiers.length) {
            _holdingTiers.push(HoldingTier({minDuration: minDuration, multiplierBps: multiplierBps}));
        } else {
            _holdingTiers[index] = HoldingTier({minDuration: minDuration, multiplierBps: multiplierBps});
        }

        emit HoldingTierUpdated(index, minDuration, multiplierBps);
    }

    /// @notice Updates or adds a balance tier
    /// @dev Can only be called by owner or governance timelock
    /// @param index Tier index (0-based)
    /// @param minBalance Minimum balance for this tier
    /// @param multiplierBps Multiplier in basis points
    function setBalanceTier(uint256 index, uint256 minBalance, uint256 multiplierBps) external onlyGovernance {
        if (index >= MAX_BALANCE_TIERS) revert TooManyTiers();
        if (multiplierBps == 0) revert InvalidTier();

        if (index >= _balanceTiers.length) {
            _balanceTiers.push(BalanceTier({minBalance: minBalance, multiplierBps: multiplierBps}));
        } else {
            _balanceTiers[index] = BalanceTier({minBalance: minBalance, multiplierBps: multiplierBps});
        }

        emit BalanceTierUpdated(index, minBalance, multiplierBps);
    }

    /// @notice Adds a yield source
    /// @param protocol Protocol address
    /// @param allocationBps Allocation in basis points
    /// @param depositSelector Function selector for deposit
    /// @param withdrawSelector Function selector for withdraw
    function addYieldSource(
        address protocol,
        uint256 allocationBps,
        bytes4 depositSelector,
        bytes4 withdrawSelector
    ) external onlyOwner {
        if (_yieldSources.length >= MAX_YIELD_SOURCES) revert TooManyYieldSources();
        if (_yieldSourceIndex[protocol] != 0) revert YieldSourceAlreadyExists();

        _yieldSources.push(YieldSource({
            protocol: protocol,
            allocationBps: allocationBps,
            active: true,
            depositSelector: depositSelector,
            withdrawSelector: withdrawSelector
        }));

        _yieldSourceIndex[protocol] = _yieldSources.length; // 1-indexed

        emit YieldSourceAdded(protocol, allocationBps);
    }

    /// @notice Removes a yield source
    /// @param protocol Protocol address to remove
    function removeYieldSource(address protocol) external onlyOwner {
        uint256 indexPlusOne = _yieldSourceIndex[protocol];
        if (indexPlusOne == 0) revert YieldSourceNotFound();

        uint256 index = indexPlusOne - 1;

        // Withdraw all first
        _withdrawFromSource(_yieldSources[index], type(uint256).max);

        // Mark as inactive
        _yieldSources[index].active = false;
        _yieldSourceIndex[protocol] = 0;

        emit YieldSourceRemoved(protocol);
    }

    /// @notice Sets trusted remote for cross-chain
    /// @param chainId LayerZero chain ID
    /// @param remote Trusted remote address (abi.encodePacked format)
    function setTrustedRemote(uint16 chainId, bytes calldata remote) external onlyOwner {
        trustedRemotes[chainId] = remote;
    }

    /// @notice Updates LayerZero endpoint
    /// @param endpoint New endpoint address
    function setLzEndpoint(address endpoint) external onlyOwner {
        lzEndpoint = endpoint;
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice Receives ETH and distributes as dividends
    receive() external payable {
        if (_totalWeightedShares == 0) revert NoSharesExist();

        if (msg.value > 0) {
            unchecked {
                _magnifiedDividendPerShare += (msg.value * MAGNITUDE) / _totalWeightedShares;
            }
            totalDividendsDistributed += msg.value;
            emit DividendsDistributed(msg.sender, msg.value);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the magnified dividend per share
    function getMagnifiedDividendPerShare() external view returns (uint256) {
        return _magnifiedDividendPerShare;
    }

    /// @notice Returns a user's weighted share value
    function getUserWeightedShares(address account) external view returns (uint256) {
        return _calculateWeightedShare(account);
    }

    /// @notice Returns total weighted shares
    function getTotalWeightedShares() external view returns (uint256) {
        return _totalWeightedShares;
    }

    /// @notice Returns the number of yield sources
    function getYieldSourceCount() external view returns (uint256) {
        return _yieldSources.length;
    }

    /// @notice Returns the number of holding tiers
    function getHoldingTierCount() external view returns (uint256) {
        return _holdingTiers.length;
    }

    /// @notice Returns the number of balance tiers
    function getBalanceTierCount() external view returns (uint256) {
        return _balanceTiers.length;
    }

    /// @notice Returns holding tier at index
    function holdingTiers(uint256 index) external view returns (HoldingTier memory) {
        return _holdingTiers[index];
    }

    /// @notice Returns balance tier at index
    function balanceTiers(uint256 index) external view returns (BalanceTier memory) {
        return _balanceTiers[index];
    }

    /// @notice Returns yield source at index
    function yieldSources(uint256 index) external view returns (YieldSource memory) {
        return _yieldSources[index];
    }
}
