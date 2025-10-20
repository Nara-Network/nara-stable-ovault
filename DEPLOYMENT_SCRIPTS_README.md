# 📜 Deployment Scripts Overview

Complete guide to all available deployment scripts for the USDe OVault system.

## 📂 Available Scripts

### 1. `FullSystem.sepolia.ts` - **RECOMMENDED FOR SEPOLIA**

**Purpose**: Deploy the complete system in one command  
**Network**: Sepolia Testnet  
**Status**: ✅ Ready to use

**Deploys**:

- MultiCollateralToken (MCT) with USDC
- USDe vault
- StakedUSDe vault
- StakingRewardsDistributor

**Configuration**:

- USDC: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` (pre-configured)
- Hub Chain: Sepolia (pre-configured)
- Only need to set: `ADMIN_ADDRESS` and `OPERATOR_ADDRESS`

**Usage**:

```bash
# 1. Edit deploy/FullSystem.sepolia.ts
#    - Set ADMIN_ADDRESS
#    - Set OPERATOR_ADDRESS

# 2. Deploy
npx hardhat deploy --network sepolia --tags FullSystem
```

**Features**:

- ✅ Automatic role granting
- ✅ Complete setup in one transaction batch
- ✅ Verification commands included in output
- ✅ Pre-configured with Sepolia USDC

---

### 2. `USDe.example.ts` - Phased Deployment (MCT + USDe)

**Purpose**: Deploy just the MCT and USDe contracts  
**Network**: Any (configure in hardhat.config)  
**Status**: 📝 Template (rename to use)

**Deploys**:

- MultiCollateralToken (MCT)
- USDe vault

**Configuration Required**:

```typescript
const ADMIN_ADDRESS = "0x...";
const INITIAL_SUPPORTED_ASSETS = ["0x..."]; // USDC, USDT, DAI, etc.
const MAX_MINT_PER_BLOCK = "1000000000000000000000000";
const MAX_REDEEM_PER_BLOCK = "1000000000000000000000000";
```

**Usage**:

```bash
# 1. Copy and configure
cp deploy/USDe.example.ts deploy/USDe.ts
# Edit ADMIN_ADDRESS and INITIAL_SUPPORTED_ASSETS

# 2. Deploy
npx hardhat deploy --network <your-network> --tags USDe
```

**Use Cases**:

- Production deployment (phased approach)
- Non-Sepolia networks
- Custom collateral assets
- Need to test MCT/USDe before staking

---

### 3. `StakedUSDe.example.ts` - Phased Deployment (StakedUSDe)

**Purpose**: Deploy StakedUSDe and StakingRewardsDistributor  
**Network**: Any (configure in hardhat.config)  
**Status**: 📝 Template (rename to use)

**Deploys**:

- StakedUSDe vault
- StakingRewardsDistributor

**Prerequisites**:

- USDe must be deployed first
- Get USDe address from previous deployment

**Configuration Required**:

```typescript
const ADMIN_ADDRESS = "0x...";
const OPERATOR_ADDRESS = "0x...";
const USDE_ADDRESS = "0x..."; // From USDe deployment
const INITIAL_REWARDER = "0x..."; // Optional
```

**Usage**:

```bash
# 1. Copy and configure
cp deploy/StakedUSDe.example.ts deploy/StakedUSDe.ts
# Edit ADMIN_ADDRESS, OPERATOR_ADDRESS, and USDE_ADDRESS

# 2. Deploy
npx hardhat deploy --network <your-network> --tags StakedUSDe
```

**Use Cases**:

- Production deployment (phased approach)
- Deploy staking after USDe is tested
- Upgrade staking system independently

---

### 4. `MyOvault.ts` - LayerZero OVault (Cross-Chain)

**Purpose**: Deploy cross-chain OFT adapters and OFTs  
**Network**: Multi-chain (hub + spokes)  
**Status**: ⚙️ Advanced (requires LayerZero setup)

**Deploys**:

- On Hub: OFT Adapters (lockbox model)
- On Spokes: OFTs (mint/burn model)
- Composer contracts

**Configuration**:
Managed via `devtools/deployConfig.ts`:

```typescript
const _hubEid = EndpointId.SEPOLIA_V2_TESTNET;
const _spokeEids = [
  EndpointId.OPTSEP_V2_TESTNET,
  EndpointId.BASESEP_V2_TESTNET,
];
```

**Usage**:

```bash
# Deploy on each chain
npx hardhat lz:deploy --network sepolia
npx hardhat lz:deploy --network optimism-sepolia
npx hardhat lz:deploy --network base-sepolia

# Wire peers
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts
```

**Use Cases**:

- Enable cross-chain USDe transfers
- Enable cross-chain sUSDe transfers
- Multi-chain DeFi integration

---

## 🎯 Which Script Should I Use?

### For Testing on Sepolia

✅ **Use `FullSystem.sepolia.ts`**

- Fastest setup
- Pre-configured
- Everything in one deployment

### For Production Deployment

✅ **Use `USDe.example.ts` + `StakedUSDe.example.ts`**

- Phased approach
- Test each module independently
- Better control

### For Cross-Chain Support

✅ **Use `MyOvault.ts` after core deployment**

- Deploy core contracts first
- Then add cross-chain support
- Requires LayerZero knowledge

---

## 📊 Deployment Comparison

| Feature           | FullSystem.sepolia.ts | USDe + StakedUSDe | MyOvault.ts         |
| ----------------- | --------------------- | ----------------- | ------------------- |
| **Complexity**    | ⭐ Simple             | ⭐⭐ Moderate     | ⭐⭐⭐ Advanced     |
| **Time**          | 5 minutes             | 10 minutes        | 30+ minutes         |
| **Control**       | Low                   | High              | Very High           |
| **Best For**      | Testing               | Production        | Cross-chain         |
| **Prerequisites** | None                  | None              | Core contracts + LZ |

---

## 🔄 Deployment Workflows

### Workflow 1: Quick Testing (Sepolia)

```
1. Edit FullSystem.sepolia.ts (set addresses)
2. Deploy: npx hardhat deploy --network sepolia --tags FullSystem
3. Test mint/stake/rewards
```

### Workflow 2: Production (Mainnet)

```
1. Copy USDe.example.ts → USDe.ts
2. Configure (admin, assets, limits)
3. Deploy: npx hardhat deploy --network mainnet --tags USDe
4. Test USDe thoroughly
5. Copy StakedUSDe.example.ts → StakedUSDe.ts
6. Configure (admin, operator, usde address)
7. Deploy: npx hardhat deploy --network mainnet --tags StakedUSDe
8. Test staking thoroughly
```

### Workflow 3: Cross-Chain Expansion

```
1. Complete Workflow 1 or 2
2. Configure devtools/deployConfig.ts
3. Deploy OVault on hub: npx hardhat lz:deploy --network <hub>
4. Deploy OVault on spokes: npx hardhat lz:deploy --network <spoke>
5. Wire peers: npx hardhat lz:oapp:wire
6. Test cross-chain transfers
```

---

## 🛠️ Configuration Files

### Hardhat Deploy Tags

Each script has deployment tags for selective deployment:

| Script                | Tags                                  | Command             |
| --------------------- | ------------------------------------- | ------------------- |
| FullSystem.sepolia.ts | `FullSystem`, `Sepolia`, `Complete`   | `--tags FullSystem` |
| USDe.example.ts       | `USDe`, `MCT`, `MultiCollateralToken` | `--tags USDe`       |
| StakedUSDe.example.ts | `StakedUSDe`, `Staking`               | `--tags StakedUSDe` |

### Network Configuration

Networks are configured in `hardhat.config.ts`:

- `sepolia` - Sepolia testnet
- `mainnet` - Ethereum mainnet
- `optimism-sepolia` - OP Sepolia testnet
- `base-sepolia` - Base Sepolia testnet

---

## 📝 Configuration Checklist

Before deploying, ensure you have:

### Required for All Scripts

- [ ] `.env` file with `MNEMONIC` or `PRIVATE_KEY`
- [ ] Native token (ETH) for gas
- [ ] Admin address (multisig recommended for production)

### FullSystem.sepolia.ts

- [ ] Admin address set
- [ ] Operator address set
- [ ] Sepolia ETH for gas
- [ ] (Optional) Sepolia USDC for testing

### USDe.example.ts

- [ ] Admin address set
- [ ] Collateral asset addresses
- [ ] Max mint/redeem limits configured
- [ ] Renamed to `USDe.ts`

### StakedUSDe.example.ts

- [ ] Admin address set
- [ ] Operator address set
- [ ] USDe address from previous deployment
- [ ] Initial rewarder configured (optional)
- [ ] Renamed to `StakedUSDe.ts`

### MyOvault.ts

- [ ] Core contracts deployed
- [ ] LayerZero endpoints configured
- [ ] Hub and spoke chains decided
- [ ] `devtools/deployConfig.ts` updated

---

## 🧪 Post-Deployment Verification

After any deployment, verify:

1. **Contracts Deployed**

   ```bash
   # Check deployment files
   ls -la deployments/<network>/
   ```

2. **Roles Granted**

   ```bash
   npx hardhat console --network <network>
   # Check roles as shown in DEPLOYMENT_GUIDE.md
   ```

3. **Verify on Explorer**

   ```bash
   npx hardhat verify --network <network> <address> <constructor-args>
   ```

4. **Test Functionality**
   - Mint USDe with collateral
   - Stake USDe for sUSDe
   - Distribute rewards
   - (Optional) Cross-chain transfers

---

## 🔗 Related Documentation

- **[DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)** - Complete deployment guide
- **[QUICK_START_ARBITRUM_SEPOLIA.md](./QUICK_START_ARBITRUM_SEPOLIA.md)** - Fast start for Arbitrum Sepolia
- **[PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md)** - System overview
- **[OVAULT_INTEGRATION.md](./OVAULT_INTEGRATION.md)** - USDe details
- **[STAKED_USDE_INTEGRATION.md](./STAKED_USDE_INTEGRATION.md)** - Staking details

---

## ❓ FAQ

**Q: Which script should I use for mainnet?**  
A: Use the phased approach: `USDe.example.ts` then `StakedUSDe.example.ts`

**Q: Can I deploy on other networks?**  
A: Yes! All scripts work on any EVM network. Just configure `hardhat.config.ts`

**Q: Do I need to deploy cross-chain support?**  
A: No, it's optional. The core system works on a single chain.

**Q: Can I deploy StakedUSDe without USDe?**  
A: No, StakedUSDe requires an existing USDe contract.

**Q: What if deployment fails midway?**  
A: Hardhat Deploy tracks progress. Just run the command again, it will skip completed steps.

---

**Status**: ✅ All scripts ready  
**Last Updated**: 2025-10-20
