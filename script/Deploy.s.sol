// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {DiamondDividendVault} from "../src/DiamondDividendVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ══════════════════════════════════════════════════════════════════════════════
//                              MAIN DEPLOYMENT SCRIPT
// ══════════════════════════════════════════════════════════════════════════════

/// @title DeployScript
/// @notice Main deployment script for DiamondDividendVault on production networks
/// @dev Deploy the first-ever ERC-4626 + ERC-1726 hybrid yield vault
/// @dev Requires PRIVATE_KEY and UNDERLYING_ASSET environment variables
contract DeployScript is Script {
    /// @notice Main deployment function
    /// @dev Set environment variables before running:
    ///      - PRIVATE_KEY: Deployer private key (required)
    ///      - UNDERLYING_ASSET: Address of underlying ERC20 token (required)
    ///      - LZ_ENDPOINT: LayerZero endpoint address (optional, for cross-chain)
    ///      - TOKEN_NAME: Custom token name (optional, defaults to "Hybrid Yield Token")
    ///      - TOKEN_SYMBOL: Custom token symbol (optional, defaults to "hyTOKEN")
    function run() external {
        // Load required environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address underlyingAsset = vm.envAddress("UNDERLYING_ASSET");

        // Validate underlying asset
        require(underlyingAsset != address(0), "UNDERLYING_ASSET cannot be zero address");

        // Load optional environment variables
        address lzEndpoint = vm.envOr("LZ_ENDPOINT", address(0));
        string memory name = vm.envOr("TOKEN_NAME", string("Hybrid Yield Token"));
        string memory symbol = vm.envOr("TOKEN_SYMBOL", string("hyTOKEN"));

        vm.startBroadcast(deployerPrivateKey);

        DiamondDividendVault vault = new DiamondDividendVault(
            IERC20(underlyingAsset),
            name,
            symbol,
            lzEndpoint
        );

        vm.stopBroadcast();

        // Log deployment info
        console.log("");
        console.log("=== DiamondDividendVault Deployed ===");
        console.log("Address:", address(vault));
        console.log("Underlying asset:", underlyingAsset);
        console.log("Name:", name);
        console.log("Symbol:", symbol);
        console.log("");
        console.log("Features:");
        console.log("  - ERC-4626 vault (deposit/withdraw/redeem)");
        console.log("  - ERC-1726 weighted dividends");
        console.log("  - Holding duration multipliers (1x to 2x)");
        console.log("  - Balance tier rewards (anti-whale)");
        console.log("  - Cross-chain ready:", lzEndpoint != address(0));
        console.log("");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//                              TESTNET DEPLOYMENT SCRIPT
// ══════════════════════════════════════════════════════════════════════════════

/// @title DeployWithMockScript
/// @notice Deployment with mock underlying token for testnets
/// @dev Only use on testnets - deploys a mock ERC20 as underlying
contract DeployWithMockScript is Script {
    /// @notice Deploy with a mock underlying token
    /// @dev Set environment variables before running:
    ///      - PRIVATE_KEY: Deployer private key (required)
    ///      - LZ_ENDPOINT: LayerZero endpoint address (optional)
    ///      - MOCK_DECIMALS: Decimals for mock token (optional, defaults to 18)
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address lzEndpoint = vm.envOr("LZ_ENDPOINT", address(0));
        uint8 mockDecimals = uint8(vm.envOr("MOCK_DECIMALS", uint256(18)));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock underlying token
        MockERC20 mockToken = new MockERC20("Mock USDC", "mUSDC", mockDecimals);
        console.log("Mock token deployed at:", address(mockToken));

        // Deploy vault
        DiamondDividendVault vault = new DiamondDividendVault(
            IERC20(address(mockToken)),
            "Hybrid Yield USDC",
            "hyUSDC",
            lzEndpoint
        );
        console.log("DiamondDividendVault deployed at:", address(vault));

        // Mint mock tokens to deployer for testing
        uint256 mintAmount = 1_000_000 * (10 ** mockDecimals);
        mockToken.mint(msg.sender, mintAmount);
        console.log("Minted", mintAmount / (10 ** mockDecimals), "mock tokens to deployer");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Testnet Deployment Complete ===");
        console.log("Mock Token:", address(mockToken));
        console.log("Vault:", address(vault));
        console.log("");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//                              MOCK ERC20 FOR DEPLOYMENT
// ══════════════════════════════════════════════════════════════════════════════

/// @title MockERC20
/// @notice Simple mock ERC20 for testnet deployments
/// @dev Unrestricted minting - only use on testnets
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Initialize mock token
    /// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _decimals Token decimals
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    /// @notice Mint tokens to an address (unrestricted for testing)
    /// @param to Recipient address
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @notice Burn tokens from caller
    /// @param amount Amount to burn
    function burn(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
    }

    /// @notice Approve spender to transfer tokens
    /// @param spender Address to approve
    /// @param amount Amount to approve
    /// @return success Always returns true
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer tokens to recipient
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return success Always returns true if sufficient balance
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfer tokens from one address to another
    /// @param from Source address
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return success Always returns true if sufficient balance and allowance
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");

        // Check and update allowance (handle infinite approval)
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            allowance[from][msg.sender] = currentAllowance - amount;
        }

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
