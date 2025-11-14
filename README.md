<h1 align="center">Nara Stable Omnichain Vault</h1>

<p align="center">
  <strong>USDe & StakedUSDe - Omnichain stablecoin vault with integrated minting, staking, and cross-chain functionality</strong>
</p>

---

## 🚀 Quick Start

**New to the project? Start here:**

### Deploy on Arbitrum Sepolia (5 minutes)

```bash
# 1. Set your addresses in deploy/FullSystem.arbitrum-sepolia.ts
# 2. Deploy everything
npx hardhat deploy --network arbitrum-sepolia --tags FullSystem
```

📘 **[Full Quick Start Guide](./QUICK_START_ARBITRUM_SEPOLIA.md)**

---

## 📚 Documentation

| Document                                                        | Description                                                 |
| --------------------------------------------------------------- | ----------------------------------------------------------- |
| **[Quick Start](./QUICK_START_ARBITRUM_SEPOLIA.md)**            | 🎯 Deploy complete system on Arbitrum Sepolia (recommended) |
| **[Cross-Chain Deployment](./docs/CROSS_CHAIN_DEPLOYMENT.md)**  | 🌐 Deploy OFT infrastructure for omnichain functionality    |
| **[USDe Integration](./docs/USDE_INTEGRATION.md)** | 🏦 USDe + MCT vault architecture and admin flows |
| **[StakedUSDe Integration](./docs/STAKED_USDE_INTEGRATION.md)** | 💰 Staking system with rewards and cooldowns |
| **[Project Structure](./docs/PROJECT_STRUCTURE.md)**            | 📁 System architecture and contract overview                |
| **[LayerZero OVault Guide](./docs/LAYERZERO_OVAULT_GUIDE.md)**  | 🔧 Advanced LayerZero integration details                   |

---

## ✨ Key Features

### Core Functionality

- ✅ **Multi-Collateral Stablecoin** - Accept USDC, USDT, DAI and other stablecoins
- ✅ **Integrated Minting** - Direct collateral → USDe minting in single transaction
- ✅ **1:1 Backing** - USDe maintains 1:1 peg with MCT (multi-collateral token)

### Staking & Rewards

- ✅ **StakedUSDe (sUSDe)** - Stake USDe to earn rewards
- ✅ **Automated Rewards** - Operator-controlled distribution with 8-hour vesting
- ✅ **Deflationary Controls** - Burn mechanism to manage exchange rates
- ✅ **Cooldown Periods** - 90-day default cooldown for unstaking (configurable)

### Security Features

- ✅ **Redemption Cooldowns** - Lock-first redemption with cancellation support
- ✅ **Emergency Pause** - Pause all mints, redeems, and staking operations
- ✅ **Rate Limiting** - Max mint/redeem per block to prevent attacks
- ✅ **Blacklist Controls** - Restrict addresses from staking/transferring

### Omnichain (Cross-Chain)

- ✅ **Transfer Across Chains** - Send USDe/sUSDe to any LayerZero-supported chain
- ✅ **Cross-Chain Minting** - Deposit collateral on Chain A, receive USDe on Chain B
- ✅ **Cross-Chain Staking** - Stake USDe on Chain A, receive sUSDe on Chain B
- ✅ **Unified Interface** - Single transaction from user perspective

---

## 🏗️ System Architecture

```
Hub Chain (Arbitrum Sepolia)          Spoke Chains (Base, OP, etc.)
┌─────────────────────────┐          ┌──────────────────────┐
│ MultiCollateralToken    │          │                      │
│ USDe (ERC4626 Vault)    │          │                      │
│ StakedUSDe (Staking)    │          │                      │
│ StakingRewardsDistrib.  │          │                      │
└─────────────────────────┘          └──────────────────────┘
          │                                     │
          ▼                                     ▼
┌─────────────────────────┐          ┌──────────────────────┐
│ MCTOFTAdapter           │◄────────►│ MCTOFT               │
│ USDeOFTAdapter          │◄────────►│ USDeOFT              │
│ StakedUSDeOFTAdapter    │◄────────►│ StakedUSDeOFT        │
│ USDeComposer            │          │                      │
│ StakedUSDeComposer      │          │                      │
└─────────────────────────┘          └──────────────────────┘
       LayerZero V2 Messaging
```

---

## 📦 What Gets Deployed

### Core Contracts (Hub Chain Only)

1. **MultiCollateralToken** - Accepts multiple stablecoins as collateral
2. **USDe** - Stablecoin vault with integrated minting
3. **StakedUSDe** - Staking vault for earning rewards
4. **StakingRewardsDistributor** - Automated reward distribution

### OFT Infrastructure (Hub + Spoke Chains)

5. **MCTOFTAdapter / MCTOFT** - Cross-chain MCT transfers
6. **USDeOFTAdapter / USDeOFT** - Cross-chain USDe transfers
7. **StakedUSDeOFTAdapter / StakedUSDeOFT** - Cross-chain sUSDe transfers
8. **Composers** - Cross-chain vault operations

---

## 🎯 Usage Examples

### Mint USDe

```javascript
// Deposit 100 USDC to mint 100 USDe
await usdc.approve(usde.address, 100e6);
await usde.mintWithCollateral(usdc.address, 100e6);
```

### Stake USDe

```javascript
// Stake 50 USDe to receive sUSDe
await usde.approve(stakedUsde.address, ethers.utils.parseEther("50"));
await stakedUsde.deposit(ethers.utils.parseEther("50"), yourAddress);
```

### Redeem USDe (with Cooldown)

```javascript
// Step 1: Request redemption (locks USDe)
await usde.cooldownRedeem(usdc.address, ethers.utils.parseEther("100"));

// Step 2: Wait 7 days...

// Step 3: Complete redemption (receive USDC)
await usde.completeRedeem();

// OR cancel anytime:
await usde.cancelRedeem();
```

### Unstake sUSDe (with Cooldown)

```javascript
// Step 1: Start cooldown
await stakedUsde.cooldownShares(ethers.utils.parseEther("50"));

// Step 2: Wait 90 days...

// Step 3: Claim USDe
await stakedUsde.unstake(yourAddress);
```

---

## 🛠️ Development

### Install Dependencies

```bash
pnpm install
```

### Compile Contracts

```bash
pnpm compile
```

### Run Tests

```bash
pnpm test
```

### Deploy

```bash
# Core system on Arbitrum Sepolia
npx hardhat deploy --network arbitrum-sepolia --tags FullSystem

# OFT infrastructure for cross-chain
npx hardhat deploy --network arbitrum-sepolia --tags ovault
npx hardhat deploy --network base-sepolia --tags ovault
```

---

## 📖 Advanced Topics

For detailed technical information, see:

- **[LayerZero OVault Integration](./docs/LAYERZERO_OVAULT_GUIDE.md)** - Deep dive into OVault architecture
- **[Contract Details](./docs/PROJECT_STRUCTURE.md)** - All contracts explained
- **[Cross-Chain Setup](./docs/CROSS_CHAIN_DEPLOYMENT.md)** - Multi-chain deployment guide

---

## 🔑 Key Contracts

### Core Contracts

| Contract                    | Description                       | Location                 |
| --------------------------- | --------------------------------- | ------------------------ |
| `MultiCollateralToken`      | Multi-collateral backing          | `contracts/mct/`         |
| `USDe`                      | Stablecoin vault with minting     | `contracts/usde/`        |
| `StakedUSDe`                | Staking vault with cooldowns | `contracts/staked-usde/` |
| `StakingRewardsDistributor` | Automated rewards                 | `contracts/staked-usde/` |

### OFT Infrastructure

| Contract               | Chain Type | Description                             |
| ---------------------- | ---------- | --------------------------------------- |
| `MCTOFTAdapter`        | Hub        | Lockbox for MCT cross-chain transfers   |
| `USDeOFTAdapter`       | Hub        | Lockbox for USDe cross-chain transfers  |
| `StakedUSDeOFTAdapter` | Hub        | Lockbox for sUSDe cross-chain transfers |
| `MCTOFT`               | Spoke      | Mint/burn OFT for MCT on spoke chains   |
| `USDeOFT`              | Spoke      | Mint/burn OFT for USDe on spoke chains  |
| `StakedUSDeOFT`        | Spoke      | Mint/burn OFT for sUSDe on spoke chains |

### Composers

| Contract             | Description                           |
| -------------------- | ------------------------------------- |
| `USDeComposer`       | Cross-chain deposit/redeem operations |
| `StakedUSDeComposer` | Cross-chain staking operations        |

---

## 🔐 Security

- **Access Control**: Role-based permissions (Admin, Gatekeeper, Collateral Manager, Rewarder)
- **Rate Limiting**: Max mint/redeem per block
- **Cooldown Periods**: Time-locks for redemptions and unstaking
- **Pause Functionality**: Emergency stop for all operations
- **Blacklist System**: Soft and full restriction levels
- **No Renounce**: Admin roles cannot be renounced

---

## 📞 Support

**Need Help?**

1. Check the [Quick Start Guide](./QUICK_START_ARBITRUM_SEPOLIA.md)
2. Review [Documentation](#-documentation)
3. See [LayerZero Docs](https://docs.layerzero.network/)

---

## 📄 License

GPL-3.0

---

<p align="center">
  Built by <strong>Nara</strong> • Powered by <a href="https://layerzero.network">LayerZero V2</a>
</p>
