<h1 align="center">Nara Stable Omnichain Vault</h1>

<p align="center">
  <strong>naraUSD & NaraUSDPlus - Omnichain stablecoin vault with integrated minting, staking, and cross-chain functionality</strong>
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

📘 **[Full Quick Start Guide](./DEPLOYMENT_QUICK_START.md)**

---

## 📚 Documentation

| Document                                                        | Description                                                 |
| --------------------------------------------------------------- | ----------------------------------------------------------- |
| **[Quick Start](./DEPLOYMENT_QUICK_START.md)**                  | 🎯 Deploy complete system on Arbitrum Sepolia (recommended) |
| **[Cross-Chain Deployment](./docs/CROSS_CHAIN_DEPLOYMENT.md)**  | 🌐 Deploy OFT infrastructure for omnichain functionality    |
| **[naraUSD Integration](./docs/NARAUSD_INTEGRATION.md)**              | 🏦 naraUSD + MCT vault architecture and admin flows            |
| **[NaraUSDPlus Integration](./docs/STAKED_NARAUSD_INTEGRATION.md)** | 💰 Staking system with rewards and cooldowns                |
| **[Project Structure](./docs/PROJECT_STRUCTURE.md)**            | 📁 System architecture and contract overview                |
| **[LayerZero OVault Guide](./docs/LAYERZERO_OVAULT_GUIDE.md)**  | 🔧 Advanced LayerZero integration details                   |

---

## ✨ Key Features

### Core Functionality

- ✅ **Multi-Collateral Stablecoin** - Accept USDC, USDT, DAI and other stablecoins
- ✅ **Integrated Minting** - Direct collateral → naraUSD minting in single transaction
- ✅ **1:1 Backing** - naraUSD maintains 1:1 peg with MCT (multi-collateral token)

### Staking & Rewards

- ✅ **NaraUSDPlus (naraUSD+)** - Stake naraUSD to earn rewards
- ✅ **Automated Rewards** - Operator-controlled distribution with 8-hour vesting
- ✅ **Deflationary Controls** - Burn mechanism to manage exchange rates
- ✅ **Cooldown Periods** - 90-day default cooldown for unstaking (configurable)

### Security Features

- ✅ **Redemption Cooldowns** - Lock-first redemption with cancellation support
- ✅ **Emergency Pause** - Pause all mints, redeems, and staking operations
- ✅ **Rate Limiting** - Max mint/redeem per block to prevent attacks
- ✅ **Blacklist Controls** - Restrict addresses from staking/transferring

### Omnichain (Cross-Chain)

- ✅ **Transfer Across Chains** - Send naraUSD/naraUSD+ to any LayerZero-supported chain
- ✅ **Cross-Chain Minting** - Deposit collateral on Chain A, receive naraUSD on Chain B
- ✅ **Cross-Chain Staking** - Stake naraUSD on Chain A, receive naraUSD+ on Chain B
- ✅ **Unified Interface** - Single transaction from user perspective

---

## 🏗️ System Architecture

```
Hub Chain (Arbitrum Sepolia)          Spoke Chains (Base, OP, etc.)
┌─────────────────────────┐          ┌──────────────────────┐
│ MultiCollateralToken    │          │                      │
│ (MCT - Hub Only!)       │          │                      │
│ naraUSD (ERC4626 Vault)    │          │                      │
│ NaraUSDPlus (Staking)    │          │                      │
│ StakingRewardsDistrib.  │          │                      │
└─────────────────────────┘          └──────────────────────┘
          │                                     │
          ▼                                     ▼
┌─────────────────────────┐          ┌──────────────────────┐
│ MCTOFTAdapter*          │          │ (No MCTOFT)          │
│ NaraUSDOFTAdapter          │◄────────►│ NaraUSDOFT              │
│ NaraUSDPlusOFTAdapter    │◄────────►│ NaraUSDPlusOFT        │
│ NaraUSDComposer            │          │                      │
│ NaraUSDPlusComposer      │          │                      │
└─────────────────────────┘          └──────────────────────┘
       LayerZero V2 Messaging

       * MCTOFTAdapter exists for validation only
         (see MCT Architecture note below)
```

### 🔑 Important: MCT Architecture (Hub-Only)

**MCT (MultiCollateralToken) does NOT go cross-chain:**

- **MCT stays on hub chain only** - It's an internal backing token, invisible to users
- **Users never interact with MCT directly** - They deposit collateral (USDC/USDT) and receive naraUSD
- **Cross-chain flow**: Users send collateral → Hub mints naraUSD → naraUSD goes cross-chain

**Why MCTOFTAdapter exists:**

- MCTOFTAdapter exists on hub chain but is **validation only**
- It satisfies `VaultComposerSync` constructor validation (requires `ASSET_OFT.token() == VAULT.asset()`)
- It is **NEVER wired to spoke chains** and **NEVER used for cross-chain operations**
- See `contracts/mct/MCTOFTAdapter.sol` for detailed explanation

**What actually goes cross-chain:**

- ✅ **naraUSD** - Via NaraUSDOFTAdapter (hub) ↔ NaraUSDOFT (spoke)
- ✅ **NaraUSDPlus** - Via NaraUSDPlusOFTAdapter (hub) ↔ NaraUSDPlusOFT (spoke)
- ✅ **Collateral (USDC/USDT)** - Via Stargate or other collateral OFTs
- ❌ **MCT** - Stays on hub only

---

## 📦 What Gets Deployed

### Core Contracts (Hub Chain Only)

1. **MultiCollateralToken** - Accepts multiple stablecoins as collateral
2. **naraUSD** - Stablecoin vault with integrated minting
3. **NaraUSDPlus** - Staking vault for earning rewards
4. **StakingRewardsDistributor** - Automated reward distribution

### OFT Infrastructure (Hub + Spoke Chains)

5. **MCTOFTAdapter** (Hub only) - Validation only, NOT for cross-chain (see MCT Architecture above)
6. **NaraUSDOFTAdapter / NaraUSDOFT** - Cross-chain naraUSD transfers
7. **NaraUSDPlusOFTAdapter / NaraUSDPlusOFT** - Cross-chain naraUSD+ transfers
8. **Composers** - Cross-chain vault operations

---

## 🎯 Usage Examples

### Mint naraUSD (Hub Chain)

```javascript
// Deposit 100 USDC to mint 100 naraUSD
// Note: MCT is created internally - users never see it
await usdc.approve(narausd.address, 100e6);
await narausd.mintWithCollateral(usdc.address, 100e6);
```

### Mint naraUSD Cross-Chain (Single Transaction)

```javascript
// User on Base sends USDC → receives naraUSD on Base
// 1. USDC bridges to hub via collateral OFT
// 2. NaraUSDComposer mints naraUSD on hub (MCT handled internally)
// 3. naraUSD bridges back to Base
// All in one transaction from user's perspective
await stargateUSDC.send(
  hubChainId,
  composerAddress,
  amount,
  composeMessage, // includes destination for naraUSD
);
```

### Stake naraUSD

```javascript
// Stake 50 naraUSD to receive naraUSD+
await narausd.approve(naraUSDPlus.address, ethers.utils.parseEther("50"));
await naraUSDPlus.deposit(ethers.utils.parseEther("50"), yourAddress);
```

### Redeem naraUSD (with Cooldown)

```javascript
// Step 1: Request redemption (locks naraUSD)
await narausd.cooldownRedeem(usdc.address, ethers.utils.parseEther("100"));

// Step 2: Wait 7 days...

// Step 3: Complete redemption (receive USDC)
await narausd.completeRedeem();

// OR cancel anytime:
await narausd.cancelRedeem();
```

### Unstake naraUSD+ (with Cooldown)

```javascript
// Step 1: Start cooldown
await naraUSDPlus.cooldownShares(ethers.utils.parseEther("50"));

// Step 2: Wait 90 days...

// Step 3: Claim naraUSD
await naraUSDPlus.unstake(yourAddress);
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

| Contract                    | Description                   | Location                 |
| --------------------------- | ----------------------------- | ------------------------ |
| `MultiCollateralToken`      | Multi-collateral backing      | `contracts/mct/`         |
| `naraUSD`                      | Stablecoin vault with minting | `contracts/narausd/`        |
| `NaraUSDPlus`                | Staking vault with cooldowns  | `contracts/narausd-plus/` |
| `StakingRewardsDistributor` | Automated rewards             | `contracts/narausd-plus/` |

### OFT Infrastructure

| Contract               | Chain Type | Description                                      |
| ---------------------- | ---------- | ------------------------------------------------ |
| `MCTOFTAdapter`        | Hub        | **Validation only** - MCT doesn't go cross-chain |
| `NaraUSDOFTAdapter`       | Hub        | Lockbox for naraUSD cross-chain transfers           |
| `NaraUSDPlusOFTAdapter` | Hub        | Lockbox for naraUSD+ cross-chain transfers          |
| `NaraUSDOFT`              | Spoke      | Mint/burn OFT for naraUSD on spoke chains           |
| `NaraUSDPlusOFT`        | Spoke      | Mint/burn OFT for naraUSD+ on spoke chains          |

### Composers

| Contract             | Description                                                     |
| -------------------- | --------------------------------------------------------------- |
| `NaraUSDComposer`       | Cross-chain collateral deposits (USDC → naraUSD), MCT stays on hub |
| `NaraUSDPlusComposer` | Cross-chain staking operations (naraUSD → naraUSD+)                   |

---

## 🔐 Security

- **Access Control**: Role-based permissions (Admin, Gatekeeper, Collateral Manager, Rewarder)
- **Rate Limiting**: Max mint/redeem per block
- **Cooldown Periods**: Time-locks for redemptions and unstaking
- **Pause Functionality**: Emergency stop for all operations
- **Blacklist System**: Soft and full restriction levels
- **No Renounce**: Admin roles cannot be renounced
- **Hub-Only MCT**: MCT never goes cross-chain, reducing attack surface

---

## 📞 Support

**Need Help?**

1. Check the [Quick Start Guide](./DEPLOYMENT_QUICK_START.md)
2. Review [Documentation](#-documentation)
3. See [LayerZero Docs](https://docs.layerzero.network/)

---

## 📄 License

GPL-3.0

---

## 📖 Additional Documentation

For detailed technical information:

- **MCT Architecture**: See `MCT_ARCHITECTURE.md` for why MCT stays on hub and why MCTOFTAdapter exists but isn't used for cross-chain
- **Contract Documentation**: See `contracts/mct/MCTOFTAdapter.sol` and `contracts/narausd/NaraUSDComposer.sol` for detailed NatSpec documentation

---

<p align="center">
  Built by <strong>Nara</strong> • Powered by <a href="https://layerzero.network">LayerZero V2</a>
</p>
