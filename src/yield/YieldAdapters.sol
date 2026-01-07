// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ══════════════════════════════════════════════════════════════════════════════
//                              YIELD ADAPTER INTERFACE
// ══════════════════════════════════════════════════════════════════════════════

/// @title IYieldAdapter
/// @notice Standard interface for yield source adapters
/// @dev All adapters must implement this interface for the DiamondDividendVault vault
interface IYieldAdapter {
    /// @notice Deposit assets into the yield source
    /// @param amount Amount of underlying asset to deposit
    /// @return shares Amount of shares/tokens received from the protocol
    function deposit(uint256 amount) external returns (uint256 shares);

    /// @notice Withdraw assets from the yield source
    /// @param amount Amount of underlying asset to withdraw
    /// @return assets Actual amount of assets withdrawn
    function withdraw(uint256 amount) external returns (uint256 assets);

    /// @notice Harvest any accrued rewards from the yield source
    /// @return rewards Amount of rewards harvested (in underlying asset terms)
    function harvest() external returns (uint256 rewards);

    /// @notice Get the current balance in the yield source
    /// @return Current balance in underlying asset terms
    function getBalance() external view returns (uint256);

    /// @notice Get the current APY of the yield source
    /// @return APY in basis points (e.g., 500 = 5%)
    function getAPY() external view returns (uint256);

    /// @notice Get the underlying asset address
    /// @return Address of the underlying asset token
    function asset() external view returns (address);
}

// ══════════════════════════════════════════════════════════════════════════════
//                              AAVE V3 ADAPTER
// ══════════════════════════════════════════════════════════════════════════════

/// @title AaveV3Adapter
/// @notice Adapter for depositing into Aave V3 lending pools
/// @dev Handles supply, withdraw, and rewards claiming from Aave V3
contract AaveV3Adapter is IYieldAdapter {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Aave V3 pool contract address
    address public immutable pool;

    /// @notice Aave aToken received for deposits
    address public immutable aToken;

    /// @notice Underlying asset being deposited
    address public immutable override asset;

    /// @notice DiamondDividendVault vault address (only caller allowed)
    address public immutable vault;

    /// @notice Aave rewards controller for claiming incentives
    address public immutable rewardsController;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when caller is not the authorized vault
    error OnlyVault();

    /// @notice Thrown when deposit fails
    error DepositFailed();

    /// @notice Thrown when withdrawal fails
    error WithdrawFailed();

    // ═══════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Restricts function access to the vault only
    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize the Aave V3 adapter
    /// @param _pool Aave V3 pool contract address
    /// @param _aToken The aToken for the underlying asset
    /// @param _asset Underlying asset address
    /// @param _vault DiamondDividendVault vault address
    /// @param _rewardsController Aave rewards controller address
    constructor(
        address _pool,
        address _aToken,
        address _asset,
        address _vault,
        address _rewardsController
    ) {
        pool = _pool;
        aToken = _aToken;
        asset = _asset;
        vault = _vault;
        rewardsController = _rewardsController;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IYieldAdapter
    /// @dev Supplies assets to Aave V3 and returns the aToken balance received
    function deposit(uint256 amount) external override onlyVault returns (uint256) {
        if (amount == 0) return 0;

        // Transfer assets from vault
        IERC20(asset).safeTransferFrom(vault, address(this), amount);
        IERC20(asset).forceApprove(pool, amount);

        // Get balance before to calculate actual received
        uint256 balanceBefore = IERC20(aToken).balanceOf(address(this));

        // Supply to Aave V3 (referral code 0)
        IAavePool(pool).supply(asset, amount, address(this), 0);

        // Return actual aTokens received
        uint256 balanceAfter = IERC20(aToken).balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Withdraws assets from Aave V3 directly to the vault
    function withdraw(uint256 amount) external override onlyVault returns (uint256) {
        if (amount == 0) return 0;

        // Withdraw from Aave directly to vault
        uint256 withdrawn = IAavePool(pool).withdraw(asset, amount, vault);
        if (withdrawn == 0) revert WithdrawFailed();

        return withdrawn;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Claims all available Aave rewards and sends to vault
    function harvest() external override onlyVault returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = aToken;

        // Claim all rewards directly to vault
        try IAaveRewardsController(rewardsController).claimAllRewards(assets, vault) returns (
            address[] memory rewardsList,
            uint256[] memory claimedAmounts
        ) {
            // Sum up all claimed rewards (multiple reward tokens possible)
            uint256 totalRewards;
            for (uint256 i = 0; i < claimedAmounts.length;) {
                totalRewards += claimedAmounts[i];
                unchecked { ++i; }
            }
            return totalRewards;
        } catch {
            // No rewards available or claim failed
            return 0;
        }
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Returns current aToken balance (1:1 with underlying + accrued interest)
    function getBalance() external view override returns (uint256) {
        return IERC20(aToken).balanceOf(address(this));
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Fetches current supply APY from Aave V3 pool
    function getAPY() external view override returns (uint256) {
        // Aave stores rates in ray (1e27)
        // liquidityRate is per-second rate, annualized
        IAavePool.ReserveData memory data = IAavePool(pool).getReserveData(asset);

        // Convert ray (1e27) to basis points (1e4)
        // APY = liquidityRate / 1e23 to get bps
        // Note: This is the simple rate, not compounded
        return data.currentLiquidityRate / 1e23;
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//                              COMPOUND V3 ADAPTER
// ══════════════════════════════════════════════════════════════════════════════

/// @title CompoundV3Adapter
/// @notice Adapter for depositing into Compound V3 (Comet) markets
/// @dev Handles supply, withdraw, and COMP rewards claiming
contract CompoundV3Adapter is IYieldAdapter {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Compound V3 Comet contract address
    address public immutable comet;

    /// @notice Underlying asset being deposited
    address public immutable override asset;

    /// @notice DiamondDividendVault vault address (only caller allowed)
    address public immutable vault;

    /// @notice Compound rewards contract for claiming COMP
    address public immutable rewardsContract;

    /// @notice COMP token address for harvesting
    address public immutable compToken;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when caller is not the authorized vault
    error OnlyVault();

    /// @notice Thrown when withdrawal fails
    error WithdrawFailed();

    // ═══════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Restricts function access to the vault only
    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize the Compound V3 adapter
    /// @param _comet Compound V3 Comet contract address
    /// @param _asset Underlying asset address
    /// @param _vault DiamondDividendVault vault address
    /// @param _rewardsContract Compound rewards contract address
    /// @param _compToken COMP token address
    constructor(
        address _comet,
        address _asset,
        address _vault,
        address _rewardsContract,
        address _compToken
    ) {
        comet = _comet;
        asset = _asset;
        vault = _vault;
        rewardsContract = _rewardsContract;
        compToken = _compToken;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IYieldAdapter
    /// @dev Supplies assets to Compound V3
    function deposit(uint256 amount) external override onlyVault returns (uint256) {
        if (amount == 0) return 0;

        IERC20(asset).safeTransferFrom(vault, address(this), amount);
        IERC20(asset).forceApprove(comet, amount);

        uint256 balanceBefore = IComet(comet).balanceOf(address(this));
        IComet(comet).supply(asset, amount);
        uint256 balanceAfter = IComet(comet).balanceOf(address(this));

        return balanceAfter - balanceBefore;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Withdraws assets from Compound V3
    function withdraw(uint256 amount) external override onlyVault returns (uint256) {
        if (amount == 0) return 0;

        uint256 balanceBefore = IERC20(asset).balanceOf(vault);
        IComet(comet).withdrawTo(vault, asset, amount);
        uint256 balanceAfter = IERC20(asset).balanceOf(vault);

        uint256 withdrawn = balanceAfter - balanceBefore;
        if (withdrawn == 0) revert WithdrawFailed();

        return withdrawn;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Claims COMP rewards and transfers to vault
    function harvest() external override onlyVault returns (uint256) {
        // Claim COMP rewards
        try ICometRewards(rewardsContract).claim(comet, address(this), true) {
            // Transfer any claimed COMP to vault
            uint256 compBalance = IERC20(compToken).balanceOf(address(this));
            if (compBalance > 0) {
                IERC20(compToken).safeTransfer(vault, compBalance);
                return compBalance;
            }
        } catch {
            // Claim failed - no rewards available
        }
        return 0;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Returns current balance in Compound V3
    function getBalance() external view override returns (uint256) {
        return IComet(comet).balanceOf(address(this));
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Calculates approximate APY from Compound V3 supply rate
    function getAPY() external view override returns (uint256) {
        // Get utilization and supply rate
        uint256 utilization = IComet(comet).getUtilization();
        uint256 ratePerSecond = IComet(comet).getSupplyRate(utilization);

        // Compound V3 rates are per-second, scaled by 1e18
        // APY = (ratePerSecond * secondsPerYear) / 1e14 to get bps
        // secondsPerYear = 31536000
        // Simple rate approximation (not compounded)
        return (ratePerSecond * 31536000) / 1e14;
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//                              YEARN V3 ADAPTER
// ══════════════════════════════════════════════════════════════════════════════

/// @title YearnV3Adapter
/// @notice Adapter for depositing into Yearn V3 vaults
/// @dev Yearn auto-compounds so no manual harvesting needed
contract YearnV3Adapter is IYieldAdapter {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Yearn V3 vault address
    address public immutable yearnVault;

    /// @notice Underlying asset being deposited
    address public immutable override asset;

    /// @notice DiamondDividendVault vault address (only caller allowed)
    address public immutable vault;

    /// @notice Last recorded price per share for APY calculation
    uint256 private _lastPricePerShare;

    /// @notice Timestamp of last price recording
    uint256 private _lastPriceTimestamp;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when caller is not the authorized vault
    error OnlyVault();

    /// @notice Thrown when withdrawal fails
    error WithdrawFailed();

    // ═══════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Restricts function access to the vault only
    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize the Yearn V3 adapter
    /// @param _yearnVault Yearn V3 vault address
    /// @param _asset Underlying asset address
    /// @param _vault DiamondDividendVault vault address
    constructor(address _yearnVault, address _asset, address _vault) {
        yearnVault = _yearnVault;
        asset = _asset;
        vault = _vault;

        // Initialize price tracking
        _lastPricePerShare = IYearnVault(_yearnVault).pricePerShare();
        _lastPriceTimestamp = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IYieldAdapter
    /// @dev Deposits into Yearn vault and receives shares
    function deposit(uint256 amount) external override onlyVault returns (uint256) {
        if (amount == 0) return 0;

        IERC20(asset).safeTransferFrom(vault, address(this), amount);
        IERC20(asset).forceApprove(yearnVault, amount);

        uint256 shares = IYearnVault(yearnVault).deposit(amount, address(this));
        return shares;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Withdraws from Yearn vault, converting shares to assets
    function withdraw(uint256 amount) external override onlyVault returns (uint256) {
        if (amount == 0) return 0;

        // Calculate shares needed for desired asset amount
        uint256 pricePerShare = IYearnVault(yearnVault).pricePerShare();
        uint256 sharesNeeded = (amount * 1e18) / pricePerShare;

        // Ensure we don't try to withdraw more shares than we have
        uint256 ourShares = IERC20(yearnVault).balanceOf(address(this));
        if (sharesNeeded > ourShares) {
            sharesNeeded = ourShares;
        }

        // Withdraw from Yearn V3
        uint256 assets = IYearnVault(yearnVault).redeem(sharesNeeded, vault, address(this));
        if (assets == 0) revert WithdrawFailed();

        return assets;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Yearn auto-compounds, so harvest just updates APY tracking
    function harvest() external override onlyVault returns (uint256) {
        // Update price tracking for APY calculation
        uint256 currentPrice = IYearnVault(yearnVault).pricePerShare();

        // Calculate appreciation since last check
        uint256 appreciation;
        if (currentPrice > _lastPricePerShare) {
            uint256 shares = IERC20(yearnVault).balanceOf(address(this));
            appreciation = (shares * (currentPrice - _lastPricePerShare)) / 1e18;
        }

        // Update tracking
        _lastPricePerShare = currentPrice;
        _lastPriceTimestamp = block.timestamp;

        // Yearn compounds automatically - appreciation is already in our shares
        // Return 0 as no separate rewards to claim
        return 0;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Returns current value of shares in underlying asset terms
    function getBalance() external view override returns (uint256) {
        uint256 shares = IERC20(yearnVault).balanceOf(address(this));
        return (shares * IYearnVault(yearnVault).pricePerShare()) / 1e18;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Calculates approximate APY based on price per share changes
    function getAPY() external view override returns (uint256) {
        uint256 currentPrice = IYearnVault(yearnVault).pricePerShare();
        uint256 timeDelta = block.timestamp - _lastPriceTimestamp;

        // Need at least 1 hour of data
        if (timeDelta < 1 hours || _lastPricePerShare == 0) {
            return 0;
        }

        // Calculate rate of return
        if (currentPrice <= _lastPricePerShare) {
            return 0;
        }

        uint256 growth = ((currentPrice - _lastPricePerShare) * 1e18) / _lastPricePerShare;
        uint256 secondsPerYear = 365 days;

        // Annualize and convert to bps
        // APY = growth * (secondsPerYear / timeDelta) * 10000 / 1e18
        return (growth * secondsPerYear * 10000) / (timeDelta * 1e18);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//                              EIGENLAYER ADAPTER
// ══════════════════════════════════════════════════════════════════════════════

/// @title EigenLayerAdapter
/// @notice Adapter for restaking via EigenLayer
/// @dev Note: EigenLayer has delayed withdrawals - this is handled gracefully
contract EigenLayerAdapter is IYieldAdapter {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice EigenLayer StrategyManager contract
    address public immutable strategyManager;

    /// @notice EigenLayer DelegationManager for withdrawals
    address public immutable delegationManager;

    /// @notice EigenLayer strategy for our asset
    address public immutable strategy;

    /// @notice Underlying asset (typically stETH or LST)
    address public immutable override asset;

    /// @notice DiamondDividendVault vault address (only caller allowed)
    address public immutable vault;

    /// @notice Pending withdrawal amount (due to delayed withdrawals)
    uint256 public pendingWithdrawal;

    /// @notice Withdrawal root hash for pending withdrawal
    bytes32 public pendingWithdrawalRoot;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when caller is not the authorized vault
    error OnlyVault();

    /// @notice Thrown when there's already a pending withdrawal
    error WithdrawalPending();

    /// @notice Thrown when completing withdrawal before it's ready
    error WithdrawalNotReady();

    // ═══════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Restricts function access to the vault only
    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize the EigenLayer adapter
    /// @param _strategyManager EigenLayer StrategyManager address
    /// @param _delegationManager EigenLayer DelegationManager address
    /// @param _strategy EigenLayer strategy for the asset
    /// @param _asset Underlying asset address (LST)
    /// @param _vault DiamondDividendVault vault address
    constructor(
        address _strategyManager,
        address _delegationManager,
        address _strategy,
        address _asset,
        address _vault
    ) {
        strategyManager = _strategyManager;
        delegationManager = _delegationManager;
        strategy = _strategy;
        asset = _asset;
        vault = _vault;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IYieldAdapter
    /// @dev Deposits into EigenLayer strategy
    function deposit(uint256 amount) external override onlyVault returns (uint256) {
        if (amount == 0) return 0;

        IERC20(asset).safeTransferFrom(vault, address(this), amount);
        IERC20(asset).forceApprove(strategyManager, amount);

        uint256 shares = IEigenStrategyManager(strategyManager).depositIntoStrategy(
            IEigenStrategy(strategy),
            IERC20(asset),
            amount
        );

        return shares;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Queues withdrawal from EigenLayer (delayed withdrawal system)
    /// @notice Due to EigenLayer's design, withdrawals are delayed 7+ days
    function withdraw(uint256 amount) external override onlyVault returns (uint256) {
        if (amount == 0) return 0;
        if (pendingWithdrawal > 0) revert WithdrawalPending();

        // Queue the withdrawal
        IEigenStrategy[] memory strategies = new IEigenStrategy[](1);
        strategies[0] = IEigenStrategy(strategy);

        uint256[] memory shares = new uint256[](1);
        shares[0] = _assetsToShares(amount);

        // Queue withdrawal in DelegationManager
        IEigenDelegationManager.QueuedWithdrawalParams[] memory params =
            new IEigenDelegationManager.QueuedWithdrawalParams[](1);

        params[0] = IEigenDelegationManager.QueuedWithdrawalParams({
            strategies: strategies,
            shares: shares,
            withdrawer: address(this)
        });

        bytes32[] memory roots = IEigenDelegationManager(delegationManager).queueWithdrawals(params);
        pendingWithdrawalRoot = roots[0];
        pendingWithdrawal = amount;

        // Return 0 - actual assets will be available after delay
        // Vault should track this as pending
        return 0;
    }

    /// @notice Complete a pending withdrawal after the delay period
    /// @dev Must be called after withdrawal delay (7+ days) has passed
    function completeWithdrawal() external onlyVault returns (uint256) {
        if (pendingWithdrawal == 0) return 0;

        // Attempt to complete the withdrawal
        // This will revert if not ready
        try IEigenDelegationManager(delegationManager).completeQueuedWithdrawal(
            _buildWithdrawalStruct(),
            new IERC20[](1),
            0, // middlewareTimesIndex
            true // receiveAsTokens
        ) {
            uint256 amount = pendingWithdrawal;
            pendingWithdrawal = 0;
            pendingWithdrawalRoot = bytes32(0);

            // Transfer to vault
            uint256 balance = IERC20(asset).balanceOf(address(this));
            if (balance > 0) {
                IERC20(asset).safeTransfer(vault, balance);
            }

            return balance;
        } catch {
            revert WithdrawalNotReady();
        }
    }

    /// @inheritdoc IYieldAdapter
    /// @dev EigenLayer rewards come from AVS - simplified implementation
    function harvest() external override onlyVault returns (uint256) {
        // In production, this would claim rewards from RewardsCoordinator
        // Rewards depend on which AVS operators you're delegated to
        return 0;
    }

    /// @inheritdoc IYieldAdapter
    /// @dev Returns current staked balance in underlying terms
    function getBalance() external view override returns (uint256) {
        uint256 shares = IEigenStrategy(strategy).shares(address(this));
        return IEigenStrategy(strategy).sharesToUnderlyingView(shares);
    }

    /// @inheritdoc IYieldAdapter
    /// @dev APY from EigenLayer is variable based on AVS rewards
    function getAPY() external pure override returns (uint256) {
        // EigenLayer APY varies based on AVS rewards
        // Would need off-chain data to calculate accurately
        return 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Convert asset amount to EigenLayer shares
    function _assetsToShares(uint256 amount) internal view returns (uint256) {
        return IEigenStrategy(strategy).underlyingToSharesView(amount);
    }

    /// @dev Build withdrawal struct for completion
    function _buildWithdrawalStruct() internal view returns (IEigenDelegationManager.Withdrawal memory) {
        IEigenStrategy[] memory strategies = new IEigenStrategy[](1);
        strategies[0] = IEigenStrategy(strategy);

        uint256[] memory shares = new uint256[](1);
        shares[0] = _assetsToShares(pendingWithdrawal);

        return IEigenDelegationManager.Withdrawal({
            staker: address(this),
            delegatedTo: address(0), // Would need to track actual delegate
            withdrawer: address(this),
            nonce: 0, // Would need to track
            startBlock: 0, // Would need to track
            strategies: strategies,
            shares: shares
        });
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//                         EXTERNAL PROTOCOL INTERFACES
// ══════════════════════════════════════════════════════════════════════════════

/// @notice Aave V3 Pool interface (minimal)
interface IAavePool {
    struct ReserveData {
        // Stores the reserve configuration
        uint256 configuration;
        // Liquidity index in ray (1e27)
        uint128 liquidityIndex;
        // Current supply rate in ray
        uint128 currentLiquidityRate;
        // Variable borrow index in ray
        uint128 variableBorrowIndex;
        // Current variable borrow rate in ray
        uint128 currentVariableBorrowRate;
        // Current stable borrow rate in ray
        uint128 currentStableBorrowRate;
        // Timestamp of last update
        uint40 lastUpdateTimestamp;
        // Token ID (for isolation mode)
        uint16 id;
        // aToken address
        address aTokenAddress;
        // Stable debt token address
        address stableDebtTokenAddress;
        // Variable debt token address
        address variableDebtTokenAddress;
        // Interest rate strategy address
        address interestRateStrategyAddress;
        // Accumulated fees
        uint128 accruedToTreasury;
        // Unbacked aTokens
        uint128 unbacked;
        // Isolation mode total debt
        uint128 isolationModeTotalDebt;
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getReserveData(address asset) external view returns (ReserveData memory);
}

/// @notice Aave V3 Rewards Controller interface (minimal)
interface IAaveRewardsController {
    function claimAllRewards(
        address[] calldata assets,
        address to
    ) external returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}

/// @notice Compound V3 Comet interface (minimal)
interface IComet {
    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function withdrawTo(address to, address asset, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function getSupplyRate(uint256 utilization) external view returns (uint64);
    function getUtilization() external view returns (uint256);
}

/// @notice Compound V3 Rewards interface (minimal)
interface ICometRewards {
    function claim(address comet, address src, bool shouldAccrue) external;
}

/// @notice Yearn V3 Vault interface (minimal)
interface IYearnVault {
    function deposit(uint256 amount, address recipient) external returns (uint256 shares);
    function withdraw(uint256 shares, address recipient, address owner) external returns (uint256 assets);
    function redeem(uint256 shares, address recipient, address owner) external returns (uint256 assets);
    function pricePerShare() external view returns (uint256);
}

/// @notice EigenLayer StrategyManager interface (minimal)
interface IEigenStrategyManager {
    function depositIntoStrategy(
        IEigenStrategy strategy,
        IERC20 token,
        uint256 amount
    ) external returns (uint256 shares);
}

/// @notice EigenLayer DelegationManager interface (minimal)
interface IEigenDelegationManager {
    struct QueuedWithdrawalParams {
        IEigenStrategy[] strategies;
        uint256[] shares;
        address withdrawer;
    }

    struct Withdrawal {
        address staker;
        address delegatedTo;
        address withdrawer;
        uint256 nonce;
        uint32 startBlock;
        IEigenStrategy[] strategies;
        uint256[] shares;
    }

    function queueWithdrawals(
        QueuedWithdrawalParams[] calldata queuedWithdrawalParams
    ) external returns (bytes32[] memory);

    function completeQueuedWithdrawal(
        Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    ) external;
}

/// @notice EigenLayer Strategy interface (minimal)
interface IEigenStrategy {
    function shares(address user) external view returns (uint256);
    function sharesToUnderlyingView(uint256 amountShares) external view returns (uint256);
    function underlyingToSharesView(uint256 amountUnderlying) external view returns (uint256);
    function userUnderlyingView(address user) external view returns (uint256);
}
