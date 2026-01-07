<p align="center">
  <h1 align="center">Diamond Dividend Vault</h1>
  <p align="center">
    <strong>First-ever ERC-4626 + ERC-1726 hybrid yield vault with weighted dividend distribution</strong>
  </p>
  <p align="center">
    <a href="https://github.com/devbyteai/Diamond-Dividend-Vault/actions"><img src="https://img.shields.io/badge/build-passing-brightgreen?style=flat-square" alt="Build"></a>
    <a href="https://github.com/devbyteai/Diamond-Dividend-Vault/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="License"></a>
    <img src="https://img.shields.io/badge/solidity-0.8.24-363636?style=flat-square" alt="Solidity">
    <img src="https://img.shields.io/badge/foundry-latest-orange?style=flat-square" alt="Foundry">
  </p>
</p>

---

## Overview

Diamond Dividend Vault is a novel DeFi primitive that combines **yield-bearing vault mechanics** with **weighted dividend distribution**. Unlike traditional yield aggregators that compound returns, this protocol harvests yield from multiple DeFi sources and distributes it as claimable ETH dividends—weighted by holding duration and balance tiers.

**Key Innovations:**
- Dual income: share appreciation + ETH dividends
- Loyalty rewards: 2x multiplier for 1-year holders
- Anti-whale: reduced dividends for large positions
- Governance: vote with weighted shares, not raw balance

## Novel Features

| Innovation | Description | Industry First |
|:-----------|:------------|:--------------:|
| ERC-4626 + ERC-1726 Hybrid | Vault shares that pay dividends | ✓ |
| Multi-dimensional Weighting | Time × Balance multipliers | ✓ |
| Dividend-based Anti-whale | 0.9x penalty for whales | ✓ |
| 5-tier Duration Rewards | Progressive 1x → 2x over 365 days | ✓ |
| Soulbound Loyalty Badges | On-chain SVG achievement NFTs | ✓ |
| Yield-to-Dividend Pipeline | Harvest DeFi yield, distribute as dividends | ✓ |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Diamond Dividend Vault                        │
│                    (ERC-4626 + ERC-1726)                        │
├─────────────────────────────────────────────────────────────────┤
│  Deposit USDC  ──►  Receive Shares  ──►  Earn Weighted Dividends │
└───────────────────────────┬─────────────────────────────────────┘
                            │
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
      ┌─────────┐     ┌─────────┐     ┌─────────┐
      │ Aave V3 │     │Compound │     │ Yearn   │
      │         │     │   V3    │     │   V3    │
      └────┬────┘     └────┬────┘     └────┬────┘
           │               │               │
           └───────────────┼───────────────┘
                           ▼
                    ┌─────────────┐
                    │ ETH Dividends│
                    │  (Weighted)  │
                    └─────────────┘
```

## Tokenomics

### Holding Duration Multipliers

| Duration | Multiplier | Effective Bonus |
|:---------|:----------:|:---------------:|
| 0 - 30 days | 1.00x | — |
| 30 - 90 days | 1.25x | +25% |
| 90 - 180 days | 1.50x | +50% |
| 180 - 365 days | 1.75x | +75% |
| 365+ days | 2.00x | +100% |

### Balance Tier Multipliers (Anti-Whale)

| Balance | Multiplier | Rationale |
|:--------|:----------:|:----------|
| < 1,000 | 1.20x | Small holder bonus |
| 1K - 10K | 1.10x | Medium holder bonus |
| 10K - 100K | 1.00x | Standard rate |
| > 100K | 0.90x | Whale penalty |

### Dividend Formula

```solidity
weightedShares = balance × holdingMultiplier × balanceMultiplier
userDividend = (weightedShares / totalWeightedShares) × totalDividends
```

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Installation

```bash
git clone https://github.com/devbyteai/Diamond-Dividend-Vault.git
cd Diamond-Dividend-Vault
forge install
forge build
```

### Run Tests

```bash
forge test
```

### Deploy

```bash
# Configure environment
cp .env.example .env
# Edit .env with your values

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## Usage

```solidity
// Deposit underlying asset
vault.deposit(1000e6, msg.sender);  // 1000 USDC

// Check your weighted position
uint256 multiplier = vault.getEffectiveMultiplier(msg.sender);
uint256 weightedShares = vault.getUserWeightedShares(msg.sender);

// Check claimable dividends
uint256 pending = vault.withdrawableDividendOf(msg.sender);

// Claim dividends
vault.withdrawDividend();

// Check holding duration
uint256 days = vault.getHoldingDuration(msg.sender) / 1 days;
```

## Project Structure

```
├── src/
│   ├── DiamondDividendVault.sol      # Core vault contract
│   ├── governance/
│   │   ├── DiamondGovernor.sol       # DAO voting (weighted)
│   │   ├── DiamondTimelock.sol       # 2-day execution delay
│   │   └── interfaces/
│   ├── badges/
│   │   ├── LoyaltyBadge.sol          # Soulbound NFTs
│   │   ├── BadgeSVGRenderer.sol      # On-chain SVG
│   │   └── interfaces/
│   ├── analytics/
│   │   ├── APYCalculator.sol         # Real-time APY
│   │   └── interfaces/
│   ├── yield/
│   │   └── YieldAdapters.sol         # Aave, Compound, Yearn
│   └── interfaces/
├── test/
│   ├── DiamondDividendVault.t.sol
│   ├── governance/
│   ├── badges/
│   └── analytics/
├── script/
│   ├── Deploy.s.sol
│   └── DeployGovernance.s.sol
└── docs/
    ├── ARCHITECTURE.md
    ├── NOVELTY.md
    └── SECURITY.md
```

## Governance

The protocol is governed by a DAO where voting power equals weighted shares:

- **Proposal Threshold**: Minimum weighted shares to create proposals
- **Quorum**: 4% of total weighted shares
- **Timelock**: 2-day delay before execution
- **Proposal Types**: Tier configs, yield allocations, protocol parameters

## Loyalty Badges

Soulbound (non-transferable) NFTs awarded for holding milestones:

| Badge | Requirement | Rarity |
|:------|:------------|:-------|
| 🥉 Bronze | 30 days | Common |
| 🥈 Silver | 90 days | Uncommon |
| 🥇 Gold | 180 days | Rare |
| 💎 Diamond | 365 days | Legendary |

On-chain SVG artwork. No external dependencies.

## Security

| Measure | Implementation |
|:--------|:---------------|
| Reentrancy | OpenZeppelin ReentrancyGuard |
| Access Control | Ownable + Timelock |
| Emergency | Pausable |
| Math | Magnified fixed-point (2^128) |
| Compilation | Solidity 0.8.24 (overflow checks) |

### Audit Status

⚠️ **UNAUDITED** - This code has not been professionally audited. Use at your own risk.

## Gas Optimization

- IR-based compilation via `via_ir = true`
- Optimized for 10,000 runs
- Cached weighted share calculations
- Efficient storage packing
- Unchecked blocks for safe arithmetic

## Documentation

- [Architecture Deep-Dive](docs/ARCHITECTURE.md)
- [What Makes This Novel](docs/NOVELTY.md)
- [Security Considerations](docs/SECURITY.md)

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Write tests for your changes
4. Ensure all tests pass (`forge test`)
5. Commit your changes
6. Push to your fork
7. Open a Pull Request

## Author

Created by [@devbyteai](https://github.com/devbyteai)

## License

[MIT](LICENSE)

---

<p align="center">
  <sub>Built with <a href="https://book.getfoundry.sh/">Foundry</a></sub>
</p>
