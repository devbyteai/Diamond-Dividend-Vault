# Architecture

Deep dive into the Diamond Dividend Vault technical architecture.

## Contract Hierarchy

```
DiamondDividendVault
├── ERC4626 (OpenZeppelin)
│   └── ERC20 (Share token)
├── Ownable
├── Pausable
├── ReentrancyGuard
├── IDividendPayingToken (ERC-1726)
└── IDiamondDividendVault
```

## Core Mechanisms

### 1. Magnified Dividend Math

The ERC-1726 implementation uses magnified fixed-point arithmetic for precision:

```solidity
MAGNITUDE = 2^128  // ~38 decimal precision

// When dividends are distributed:
magnifiedDividendPerShare += (dividendAmount * MAGNITUDE) / totalWeightedShares

// User's dividend calculation:
dividend = (magnifiedDividendPerShare * weightedBalance + correction) / MAGNITUDE
```

This prevents rounding errors even for tiny dividend amounts distributed across millions of tokens.

### 2. Weighted Share Calculation

```solidity
weightedShare = balance × holdingMultiplier × balanceMultiplier / BPS²

// Where:
// - balance = user's token balance
// - holdingMultiplier = tier based on holding duration (10000-20000 bps)
// - balanceMultiplier = tier based on balance size (9000-12000 bps)
// - BPS² = 100000000 (normalize two multipliers)
```

### 3. Dividend Correction on Transfer

When tokens transfer, corrections maintain dividend fairness:

```solidity
// On transfer FROM:
_magnifiedDividendCorrections[from] += magnifiedDividendPerShare * oldWeightedFrom

// On transfer TO:
_magnifiedDividendCorrections[to] -= magnifiedDividendPerShare * newWeightedTo
```

This ensures users only receive dividends for shares they actually held during distribution.

## Holding Duration Tracking

```solidity
struct HoldingInfo {
    uint256 firstHoldTimestamp;   // First deposit ever
    uint256 lastResetTimestamp;   // Last time balance went to 0
    uint256 totalHoldingTime;     // Cumulative non-zero balance time
}
```

Duration calculation:
- If balance > 0: `currentTime - lastResetTimestamp + totalHoldingTime`
- If balance == 0: `totalHoldingTime` (preserved)
- Reset only when balance returns from 0

## Yield Flow

```
1. User deposits underlying asset
2. Vault issues shares (ERC-4626)
3. Assets deployed to yield adapters (Aave, Compound, etc.)
4. Periodic harvest() collects yield
5. Yield distributed as ETH dividends
6. Users claim via withdrawDividend()
```

### Yield Adapter Interface

```solidity
interface IYieldAdapter {
    function deposit(uint256 amount) external returns (uint256 shares);
    function withdraw(uint256 amount) external returns (uint256 assets);
    function harvest() external returns (uint256 rewards);
    function getBalance() external view returns (uint256);
    function getAPY() external view returns (uint256);
}
```

## Governance Architecture

```
User Vote → DiamondGovernor → Queue in Timelock → Execute on Vault
              (weighted)         (2 day delay)

Voting Power = getUserWeightedShares(account)
Quorum = 4% of totalWeightedShares
```

### Proposal Types

1. **HoldingTierUpdate**: Modify duration tiers
2. **BalanceTierUpdate**: Modify balance tiers
3. **YieldReallocation**: Change yield source allocations
4. **ProtocolParameter**: General configuration
5. **Emergency**: Higher quorum actions

## Cross-Chain (LayerZero)

```solidity
// Send dividend claim to another chain
function claimCrossChainDividend(uint16 dstChainId) external payable {
    uint256 dividend = withdrawableDividendOf(msg.sender);
    // Mark as withdrawn locally
    _withdrawnDividends[msg.sender] += dividend;
    // Send via LayerZero
    lzEndpoint.send{value: msg.value}(...);
}
```

## Storage Layout

### Dividend State
- `_magnifiedDividendPerShare`: Global accumulator
- `_magnifiedDividendCorrections`: Per-user corrections
- `_withdrawnDividends`: Per-user claimed amounts
- `totalDividendsDistributed`: Total ever distributed

### Tier State
- `_holdingTiers[]`: Duration tier configs
- `_balanceTiers[]`: Balance tier configs
- `_holdingInfo[user]`: Per-user holding data

### Weighted Shares
- `_totalWeightedShares`: Sum of all weighted shares
- `_userWeightedShares[user]`: Cached per-user weighted shares

## Gas Considerations

| Operation | Approximate Gas |
|-----------|----------------|
| deposit() | ~120,000 |
| withdraw() | ~100,000 |
| withdrawDividend() | ~50,000 |
| transfer() | ~80,000 |
| claimCrossChainDividend() | ~200,000 + LZ fees |

### Optimization Techniques

1. **Cached weighted shares**: Avoid recalculation on every operation
2. **Unchecked math**: Safe operations use unchecked blocks
3. **Storage packing**: Related data in single slots where possible
4. **Lazy updates**: Weighted shares only recalculated when needed

## Security Model

### Access Control

| Function | Access |
|----------|--------|
| deposit/withdraw | Anyone |
| distributeDividends | Anyone |
| setHoldingTier | Owner/Timelock |
| setBalanceTier | Owner/Timelock |
| pause/unpause | Owner |
| setTimelock | Owner |

### Invariants

1. `sum(userWeightedShares) == totalWeightedShares`
2. `withdrawableDividend + withdrawnDividend == accumulatedDividend`
3. Holding duration never decreases (unless balance goes to 0)
4. Soulbound badges cannot transfer

### Reentrancy Protection

- All external calls protected by `nonReentrant`
- ETH transfers use checks-effects-interactions pattern
- Cross-chain calls are fire-and-forget with retry mechanism

## Upgrade Path

The contracts are not upgradeable by design. Migration path:

1. Deploy new version
2. Users withdraw from old vault
3. Users deposit to new vault
4. Historical holding time can be preserved via migration snapshot
