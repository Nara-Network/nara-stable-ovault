# ⚡ Quick Start - Deploy on Arbitrum Sepolia

Fast deployment guide for Arbitrum Sepolia testnet with pre-configured settings.

## 🎯 One-Command Deployment

### Step 1: Set Your Addresses

Open `deploy/FullSystem.arbitrum-sepolia.ts` and update:

```typescript
const ADMIN_ADDRESS = "YOUR_ADMIN_ADDRESS_HERE";
const OPERATOR_ADDRESS = "YOUR_OPERATOR_ADDRESS_HERE";
```

### Step 2: Deploy Everything

```bash
npx hardhat deploy --network arbitrum-sepolia --tags FullSystem
```

That's it! ✅

---

## 📋 What Gets Deployed

| Contract                  | Description           | Address (after deployment) |
| ------------------------- | --------------------- | -------------------------- |
| MultiCollateralToken      | Holds USDC collateral | Check console output       |
| USDe                      | Stablecoin vault      | Check console output       |
| StakedUSDe                | Staking vault         | Check console output       |
| StakingRewardsDistributor | Automated rewards     | Check console output       |

---

## 🔧 Pre-Configured Settings

### Network: Arbitrum Sepolia Testnet (Hub Chain)

- **Chain ID**: 421614
- **RPC**: https://sepolia-rollup.arbitrum.io/rpc
- **LayerZero Endpoint ID**: 40231 (ARBSEP_V2_TESTNET)

### Collateral Asset

- **USDC (Arbitrum Sepolia)**: `0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773`
- Bridge USDC: https://bridge.arbitrum.io/
- Faucet: https://faucet.quicknode.com/arbitrum/sepolia

### Limits

- **Max Mint Per Block**: 1,000,000 USDe
- **Max Redeem Per Block**: 1,000,000 USDe

---

## 🧪 Quick Test

After deployment, test the system:

### 1. Get Arbitrum Sepolia ETH

```
https://faucet.quicknode.com/arbitrum/sepolia
https://www.alchemy.com/faucets/arbitrum-sepolia
```

### 2. Get Arbitrum Sepolia USDC

```
Bridge from Sepolia: https://bridge.arbitrum.io/
Or use faucet: https://faucet.circle.com/ (then bridge)
```

### 3. Mint USDe

```bash
npx hardhat console --network arbitrum-sepolia
```

```javascript
// Get contracts (replace with your deployed addresses)
const usdc = await ethers.getContractAt(
  "IERC20",
  "0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773",
);
const usde = await ethers.getContractAt("usde/USDe", "YOUR_USDE_ADDRESS");

// Mint 100 USDe with 100 USDC
const amount = ethers.utils.parseUnits("100", 6); // 100 USDC (6 decimals)
await usdc.approve(usde.address, amount);
await usde.mintWithCollateral(usdc.address, amount);

// Check balance
const [signer] = await ethers.getSigners();
const balance = await usde.balanceOf(signer.address);
console.log("USDe balance:", ethers.utils.formatEther(balance));
```

### 4. Stake USDe

```javascript
const stakedUsde = await ethers.getContractAt(
  "staked-usde/StakedUSDe",
  "YOUR_STAKED_USDE_ADDRESS",
);

// Stake 50 USDe
const stakeAmount = ethers.utils.parseEther("50");
await usde.approve(stakedUsde.address, stakeAmount);
await stakedUsde.deposit(stakeAmount, (await ethers.getSigners())[0].address);

// Check sUSDe balance
const sBalance = await stakedUsde.balanceOf(
  (await ethers.getSigners())[0].address,
);
console.log("sUSDe balance:", ethers.utils.formatEther(sBalance));
```

### 5. Distribute Rewards (as Operator)

```javascript
const distributor = await ethers.getContractAt(
  "staked-usde/StakingRewardsDistributor",
  "YOUR_DISTRIBUTOR_ADDRESS",
);

// Transfer USDe to distributor
const rewardsAmount = ethers.utils.parseEther("10");
await usde.transfer(distributor.address, rewardsAmount);

// Distribute rewards (must be called by OPERATOR_ADDRESS)
await distributor.transferInRewards(rewardsAmount);

console.log("✓ Rewards distributed!");
```

---

## 📝 Deployment Output Example

After running the deployment, you'll see:

```
========================================
DEPLOYMENT COMPLETE ✅
========================================

📦 Deployed Contracts:
   MultiCollateralToken: 0x1234...
   USDe: 0x5678...
   StakedUSDe: 0x9abc...
   StakingRewardsDistributor: 0xdef0...

⚙️  Configuration:
   Admin: 0xYourAdmin...
   Operator: 0xYourOperator...
   USDC (Sepolia): 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
   Max Mint/Block: 1000000000000000000000000
   Max Redeem/Block: 1000000000000000000000000

🔑 Granted Roles:
   MCT.MINTER_ROLE → USDe
   StakedUSDe.REWARDER_ROLE → StakingRewardsDistributor
   StakedUSDe.BLACKLIST_MANAGER_ROLE → Admin
```

---

## ✅ Verify on Arbiscan

The deployment script will print verification commands. Example:

```bash
npx hardhat verify --network arbitrum-sepolia 0x1234... \
  "0xAdminAddress..." \
  "[\"0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773\"]"
```

Run these commands to verify each contract on Arbiscan.

---

## 🌐 Add Cross-Chain Support (Optional)

To enable cross-chain USDe and sUSDe:

### 1. Update LayerZero Config

Already configured for Arbitrum Sepolia hub in `devtools/deployConfig.ts`:

```typescript
const _hubEid = EndpointId.ARBSEP_V2_TESTNET;
const _spokeEids = [
  EndpointId.OPTSEP_V2_TESTNET,
  EndpointId.BASESEP_V2_TESTNET,
  EndpointId.SEPOLIA_V2_TESTNET,
];
```

### 2. Deploy OFT Infrastructure (Includes Hub Composers)

```bash
# On Arbitrum Sepolia (hub)
# 1) Deploy USDe OFT infra (deploys USDeOFTAdapter and USDeComposer on hub)
npx hardhat deploy --network arbitrum-sepolia --tags ovault

# 2) Deploy StakedUSDe OFT adapter on hub (required for StakedUSDeComposer)
npx hardhat deploy --network arbitrum-sepolia --tags staked-usde-oft

# 3) Re-run ovault on hub to deploy StakedUSDeComposer once the adapter exists
npx hardhat deploy --network arbitrum-sepolia --tags ovault

# On Optimism Sepolia (spoke)
npx hardhat deploy --network optimism-sepolia --tags ovault
npx hardhat deploy --network optimism-sepolia --tags staked-usde-oft

# On Base Sepolia (spoke)
npx hardhat deploy --network base-sepolia --tags ovault
npx hardhat deploy --network base-sepolia --tags staked-usde-oft

# On Sepolia (spoke)
npx hardhat deploy --network sepolia --tags ovault
npx hardhat deploy --network sepolia --tags staked-usde-oft
```

### 3. Wire LayerZero Peers

Update the contract addresses in respective config files. Then, run these commands:

```bash
# USDe peers (hub adapter ↔ spoke OFT)
npx hardhat lz:oapp:wire --oapp-config layerzero.usde.config.ts

# sUSDe peers (hub adapter ↔ spoke OFT)
npx hardhat lz:oapp:wire --oapp-config layerzero.susde.config.ts
```

---

## 🎛️ Admin Functions

### Add More Collateral Assets

```javascript
const mct = await ethers.getContractAt(
  "mct/MultiCollateralToken",
  "MCT_ADDRESS",
);
await mct.addSupportedAsset("0xNewAssetAddress...");
```

### Update Rate Limits

```javascript
const usde = await ethers.getContractAt("usde/USDe", "USDE_ADDRESS");
await usde.setMaxMintPerBlock(ethers.utils.parseEther("2000000"));
await usde.setMaxRedeemPerBlock(ethers.utils.parseEther("2000000"));
```

### Emergency Disable Mint/Redeem

```javascript
const GATEKEEPER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("GATEKEEPER_ROLE"),
);
await usde.grantRole(GATEKEEPER_ROLE, "GATEKEEPER_ADDRESS");

// As gatekeeper
await usde.disableMintRedeem();
```

### Change Rewards Operator

```javascript
const distributor = await ethers.getContractAt(
  "staked-usde/StakingRewardsDistributor",
  "DISTRIBUTOR_ADDRESS",
);
await distributor.setOperator("NEW_OPERATOR_ADDRESS");
```

---

## 🐛 Common Issues

### "Could not find MNEMONIC or PRIVATE_KEY"

Create a `.env` file:

```bash
MNEMONIC="your twelve word seed phrase here"
# OR
PRIVATE_KEY="0x..."
```

### "Transaction reverted: InvalidZeroAddress"

Make sure you set `ADMIN_ADDRESS` and `OPERATOR_ADDRESS` in the deployment script.

### "Insufficient funds"

Get Arbitrum Sepolia ETH from a faucet:

- https://faucet.quicknode.com/arbitrum/sepolia
- https://www.alchemy.com/faucets/arbitrum-sepolia

### Deployment Hangs

Check your RPC endpoint for Arbitrum Sepolia. Try:

```bash
npx hardhat deploy --network arbitrum-sepolia --reset
```

---

## 📚 Next Steps

1. ✅ Deploy contracts
2. ✅ Verify on Arbiscan
3. ✅ Test minting and staking
4. 📖 Read [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for production deployment
5. 📖 Read [STAKED_USDE_INTEGRATION.md](./STAKED_USDE_INTEGRATION.md) for details
6. 🌐 Deploy OFT infrastructure for cross-chain support

---

## 📞 Support

**Deployment Issues?**

- Check [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)
- Check [CROSS_CHAIN_DEPLOYMENT.md](./CROSS_CHAIN_DEPLOYMENT.md)
- Check [Troubleshooting](#common-issues) section above

**Understanding the System?**

- [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md) - Overview
- [OVAULT_INTEGRATION.md](./OVAULT_INTEGRATION.md) - USDe details
- [STAKED_USDE_INTEGRATION.md](./STAKED_USDE_INTEGRATION.md) - Staking details

---

**Status**: ✅ Ready to deploy  
**Network**: Arbitrum Sepolia Testnet (Hub Chain)  
**Last Updated**: 2025-10-20

🚀 **Happy Deploying!**
