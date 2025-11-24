<h1 align="center">Nara Stable Omnichain Vault</h1>

<p align="center">
  <strong>nUSD & StakednUSD - Omnichain stablecoin vault with integrated minting, staking, and cross-chain functionality</strong>
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
| **[nUSD Integration](./docs/NUSD_INTEGRATION.md)** | 🏦 nUSD + MCT vault architecture and admin flows |
| **[StakednUSD Integration](./docs/STAKED_NUSD_INTEGRATION.md)** | 💰 Staking system with rewards and cooldowns |
| **[Project Structure](./docs/PROJECT_STRUCTURE.md)**            | 📁 System architecture and contract overview                |
| **[LayerZero OVault Guide](./docs/LAYERZERO_OVAULT_GUIDE.md)**  | 🔧 Advanced LayerZero integration details                   |

---

## ✨ Key Features

### Core Functionality

- ✅ **Multi-Collateral Stablecoin** - Accept USDC, USDT, DAI and other stablecoins
- ✅ **Integrated Minting** - Direct collateral → nUSD minting in single transaction
- ✅ **1:1 Backing** - nUSD maintains 1:1 peg with MCT (multi-collateral token)

### Staking & Rewards

- ✅ **StakednUSD (snUSD)** - Stake nUSD to earn rewards
- ✅ **Automated Rewards** - Operator-controlled distribution with 8-hour vesting
- ✅ **Deflationary Controls** - Burn mechanism to manage exchange rates
- ✅ **Cooldown Periods** - 90-day default cooldown for unstaking (configurable)

### Security Features

- ✅ **Redemption Cooldowns** - Lock-first redemption with cancellation support
- ✅ **Emergency Pause** - Pause all mints, redeems, and staking operations
- ✅ **Rate Limiting** - Max mint/redeem per block to prevent attacks
- ✅ **Blacklist Controls** - Restrict addresses from staking/transferring

### Omnichain (Cross-Chain)

- ✅ **Transfer Across Chains** - Send nUSD/snUSD to any LayerZero-supported chain
- ✅ **Cross-Chain Minting** - Deposit collateral on Chain A, receive nUSD on Chain B
- ✅ **Cross-Chain Staking** - Stake nUSD on Chain A, receive snUSD on Chain B
- ✅ **Unified Interface** - Single transaction from user perspective

---

## 🏗️ System Architecture

```
Hub Chain (Arbitrum Sepolia)          Spoke Chains (Base, OP, etc.)
┌─────────────────────────┐          ┌──────────────────────┐
│ MultiCollateralToken    │          │                      │
│ (MCT - Hub Only!)       │          │                      │
│ nUSD (ERC4626 Vault)    │          │                      │
│ StakednUSD (Staking)    │          │                      │
│ StakingRewardsDistrib.  │          │                      │
└─────────────────────────┘          └──────────────────────┘
          │                                     │
          ▼                                     ▼
┌─────────────────────────┐          ┌──────────────────────┐
│ MCTOFTAdapter*          │          │ (No MCTOFT)          │
│ nUSDOFTAdapter          │◄────────►│ nUSDOFT              │
│ StakednUSDOFTAdapter    │◄────────►│ StakednUSDOFT        │
│ nUSDComposer            │          │                      │
│ StakednUSDComposer      │          │                      │
└─────────────────────────┘          └──────────────────────┘
       LayerZero V2 Messaging
       
       * MCTOFTAdapter exists for validation only
         (see MCT Architecture note below)
```

### 🔑 Important: MCT Architecture (Hub-Only)

**MCT (MultiCollateralToken) does NOT go cross-chain:**

- **MCT stays on hub chain only** - It's an internal backing token, invisible to users
- **Users never interact with MCT directly** - They deposit collateral (USDC/USDT) and receive nUSD
- **Cross-chain flow**: Users send collateral → Hub mints nUSD → nUSD goes cross-chain

**Why MCTOFTAdapter exists:**
- MCTOFTAdapter exists on hub chain but is **validation only**
- It satisfies `VaultComposerSync` constructor validation (requires `ASSET_OFT.token() == VAULT.asset()`)
- It is **NEVER wired to spoke chains** and **NEVER used for cross-chain operations**
- See `contracts/mct/MCTOFTAdapter.sol` for detailed explanation

**What actually goes cross-chain:**
- ✅ **nUSD** - Via nUSDOFTAdapter (hub) ↔ nUSDOFT (spoke)
- ✅ **StakednUSD** - Via StakednUSDOFTAdapter (hub) ↔ StakednUSDOFT (spoke)
- ✅ **Collateral (USDC/USDT)** - Via Stargate or other collateral OFTs
- ❌ **MCT** - Stays on hub only

---

## 📦 What Gets Deployed

### Core Contracts (Hub Chain Only)

1. **MultiCollateralToken** - Accepts multiple stablecoins as collateral
2. **nUSD** - Stablecoin vault with integrated minting
3. **StakednUSD** - Staking vault for earning rewards
4. **StakingRewardsDistributor** - Automated reward distribution

### OFT Infrastructure (Hub + Spoke Chains)

5. **MCTOFTAdapter** (Hub only) - Validation only, NOT for cross-chain (see MCT Architecture above)
6. **nUSDOFTAdapter / nUSDOFT** - Cross-chain nUSD transfers
7. **StakednUSDOFTAdapter / StakednUSDOFT** - Cross-chain snUSD transfers
8. **Composers** - Cross-chain vault operations

---

## 🎯 Usage Examples

### Mint nUSD (Hub Chain)

```javascript
// Deposit 100 USDC to mint 100 nUSD
// Note: MCT is created internally - users never see it
await usdc.approve(nusd.address, 100e6);
await nusd.mintWithCollateral(usdc.address, 100e6);
```

### Mint nUSD Cross-Chain (Single Transaction)

```javascript
// User on Base sends USDC → receives nUSD on Base
// 1. USDC bridges to hub via collateral OFT
// 2. nUSDComposer mints nUSD on hub (MCT handled internally)
// 3. nUSD bridges back to Base
// All in one transaction from user's perspective
await stargateUSDC.send(
  hubChainId,
  composerAddress,
  amount,
  composeMessage // includes destination for nUSD
);
```

### Stake nUSD

```javascript
// Stake 50 nUSD to receive snUSD
await nusd.approve(stakedNusd.address, ethers.utils.parseEther("50"));
await stakedNusd.deposit(ethers.utils.parseEther("50"), yourAddress);
```

### Redeem nUSD (with Cooldown)

```javascript
// Step 1: Request redemption (locks nUSD)
await nusd.cooldownRedeem(usdc.address, ethers.utils.parseEther("100"));

// Step 2: Wait 7 days...

// Step 3: Complete redemption (receive USDC)
await nusd.completeRedeem();

// OR cancel anytime:
await nusd.cancelRedeem();
```

### Unstake snUSD (with Cooldown)

```javascript
// Step 1: Start cooldown
await stakedNusd.cooldownShares(ethers.utils.parseEther("50"));

// Step 2: Wait 90 days...

// Step 3: Claim nUSD
await stakedNusd.unstake(yourAddress);
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
| `nUSD`                      | Stablecoin vault with minting     | `contracts/usde/`        |
| `StakednUSD`                | Staking vault with cooldowns | `contracts/staked-usde/` |
| `StakingRewardsDistributor` | Automated rewards                 | `contracts/staked-usde/` |

### OFT Infrastructure

| Contract               | Chain Type | Description                                      |
| ---------------------- | ---------- | ------------------------------------------------ |
| `MCTOFTAdapter`        | Hub        | **Validation only** - MCT doesn't go cross-chain |
| `nUSDOFTAdapter`       | Hub        | Lockbox for nUSD cross-chain transfers           |
| `StakednUSDOFTAdapter` | Hub        | Lockbox for snUSD cross-chain transfers          |
| `nUSDOFT`              | Spoke      | Mint/burn OFT for nUSD on spoke chains           |
| `StakednUSDOFT`        | Spoke      | Mint/burn OFT for snUSD on spoke chains          |

### Composers

| Contract             | Description                                                     |
| -------------------- | --------------------------------------------------------------- |
| `nUSDComposer`       | Cross-chain collateral deposits (USDC → nUSD), MCT stays on hub |
| `StakednUSDComposer` | Cross-chain staking operations (nUSD → snUSD)                   |

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

1. Check the [Quick Start Guide](./QUICK_START_ARBITRUM_SEPOLIA.md)
2. Review [Documentation](#-documentation)
3. See [LayerZero Docs](https://docs.layerzero.network/)

---

## 📄 License

GPL-3.0

---

## 📖 Additional Documentation

For detailed technical information:
- **MCT Architecture**: See `MCT_ARCHITECTURE.md` for why MCT stays on hub and why MCTOFTAdapter exists but isn't used for cross-chain
- **Contract Documentation**: See `contracts/mct/MCTOFTAdapter.sol` and `contracts/usde/nUSDComposer.sol` for detailed NatSpec documentation

---

<p align="center">
  Built by <strong>Nara</strong> • Powered by <a href="https://layerzero.network">LayerZero V2</a>
</p>
