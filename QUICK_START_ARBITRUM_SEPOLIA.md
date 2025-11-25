# ⚡ Quick Start - Deploy nUSD OVault System

Fast deployment guide for both testnet and mainnet with environment-based configuration.

## 🎯 One-Command Deployment

### Step 1: Set Your Addresses

Open `deploy/FullSystem.arbitrum-sepolia.ts` and update:

```typescript
const ADMIN_ADDRESS = "YOUR_ADMIN_ADDRESS_HERE";
const OPERATOR_ADDRESS = "YOUR_OPERATOR_ADDRESS_HERE";
```

### Step 2: Choose Your Environment

**For Testnet (Default):**
```bash
DEPLOY_ENV=testnet npx hardhat deploy --network arbitrum-sepolia --tags FullSystem
```

**For Mainnet:**
```bash
DEPLOY_ENV=mainnet npx hardhat deploy --network arbitrum --tags FullSystem
```

> **Note**: If `DEPLOY_ENV` is not set, it defaults to `testnet`.

That's it! ✅

---

## 📋 What Gets Deployed

| Contract                  | Description           | Address (after deployment) |
| ------------------------- | --------------------- | -------------------------- |
| MultiCollateralToken      | Holds USDC collateral | Check console output       |
| nUSD                      | Stablecoin vault      | Check console output       |
| StakednUSD                | Staking vault         | Check console output       |
| StakingRewardsDistributor | Automated rewards     | Check console output       |

---

## 🔧 Configuration

The deployment uses environment-based configuration. Settings are automatically selected based on `DEPLOY_ENV`:

### Testnet Configuration (Default)

- **Hub Chain**: Arbitrum Sepolia
  - **Chain ID**: 421614
  - **RPC**: https://sepolia-rollup.arbitrum.io/rpc
  - **LayerZero Endpoint ID**: 40231 (ARBSEP_V2_TESTNET)
- **USDC Address**: `0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773`
- **USDC OFT**: `0x543BdA7c6cA4384FE90B1F5929bb851F52888983`
- Bridge USDC: https://bridge.arbitrum.io/
- Faucet: https://faucet.quicknode.com/arbitrum/sepolia

### Mainnet Configuration

- **Hub Chain**: Arbitrum
  - **Chain ID**: 42161
  - **RPC**: Configured in `hardhat.config.ts`
  - **LayerZero Endpoint ID**: 30110 (ARBITRUM_V2_MAINNET)
- **USDC Address**: ⚠️ **Update in `devtools/deployConfig.mainnet.ts`**
- **USDC OFT**: ⚠️ **Update in `devtools/deployConfig.mainnet.ts`**

> **Important**: Before deploying to mainnet, update the USDC addresses in `devtools/deployConfig.mainnet.ts`

### Limits

- **Max Mint Per Block**: 1,000,000 nUSD
- **Max Redeem Per Block**: 1,000,000 nUSD

---

## 🧪 Quick Test

After deployment, test the system:

### 1. Get Network Native Token (ETH)

**Testnet:**
```
https://faucet.quicknode.com/arbitrum/sepolia
https://www.alchemy.com/faucets/arbitrum-sepolia
```

**Mainnet:**
- Use a DEX or bridge to get ETH on Arbitrum

### 2. Get USDC

**Testnet:**
```
Bridge from Sepolia: https://bridge.arbitrum.io/
Or use faucet: https://faucet.circle.com/ (then bridge)
```

**Mainnet:**
- Bridge USDC from Ethereum mainnet or use a DEX

### 3. Mint nUSD

```bash
# Testnet
npx hardhat console --network arbitrum-sepolia

# Mainnet
npx hardhat console --network arbitrum
```

```javascript
// Get contracts (replace with your deployed addresses)
// USDC address comes from deployConfig based on DEPLOY_ENV
const usdc = await ethers.getContractAt(
  "IERC20",
  "YOUR_USDC_ADDRESS", // Check deployConfig for the correct address
);
const nusd = await ethers.getContractAt("nusd/nUSD", "YOUR_NUSD_ADDRESS");

// Mint 100 nUSD with 100 USDC
const amount = ethers.utils.parseUnits("100", 6); // 100 USDC (6 decimals)
await usdc.approve(nusd.address, amount);
await nusd.mintWithCollateral(usdc.address, amount);

// Check balance
const [signer] = await ethers.getSigners();
const balance = await nusd.balanceOf(signer.address);
console.log("nUSD balance:", ethers.utils.formatEther(balance));
```

### 4. Stake nUSD

```javascript
const stakedNusd = await ethers.getContractAt(
  "staked-nusd/StakednUSD",
  "YOUR_STAKED_NUSD_ADDRESS",
);

// Stake 50 nUSD
const stakeAmount = ethers.utils.parseEther("50");
await nusd.approve(stakedNusd.address, stakeAmount);
await stakedNusd.deposit(stakeAmount, (await ethers.getSigners())[0].address);

// Check snUSD balance
const sBalance = await stakedNusd.balanceOf(
  (await ethers.getSigners())[0].address,
);
console.log("snUSD balance:", ethers.utils.formatEther(sBalance));
```

### 5. Distribute Rewards (as Operator)

```javascript
const distributor = await ethers.getContractAt(
  "staked-nusd/StakingRewardsDistributor",
  "YOUR_DISTRIBUTOR_ADDRESS",
);

// Transfer nUSD to distributor
const rewardsAmount = ethers.utils.parseEther("10");
await nusd.transfer(distributor.address, rewardsAmount);

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
   nUSD: 0x5678...
   StakednUSD: 0x9abc...
   StakingRewardsDistributor: 0xdef0...

⚙️  Configuration:
   Admin: 0xYourAdmin...
   Operator: 0xYourOperator...
   USDC (Sepolia): 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
   Max Mint/Block: 1000000000000000000000000
   Max Redeem/Block: 1000000000000000000000000

🔑 Granted Roles:
   MCT.MINTER_ROLE → nUSD
   StakednUSD.REWARDER_ROLE → StakingRewardsDistributor
   StakednUSD.BLACKLIST_MANAGER_ROLE → Admin
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

To enable cross-chain nUSD and snUSD:

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
# 1) Deploy nUSD OFT infra (deploys nUSDOFTAdapter and nUSDComposer on hub)
npx hardhat deploy --network arbitrum-sepolia --tags ovault

# 2) Deploy StakednUSD OFT adapter on hub (required for StakednUSDComposer)
npx hardhat deploy --network arbitrum-sepolia --tags staked-nusd-oft

# 3) Re-run ovault on hub to deploy StakednUSDComposer once the adapter exists
npx hardhat deploy --network arbitrum-sepolia --tags ovault

# On Base Sepolia (spoke)
npx hardhat deploy --network base-sepolia --tags ovault
npx hardhat deploy --network base-sepolia --tags staked-nusd-oft

# On Sepolia (spoke)
npx hardhat deploy --network sepolia --tags ovault
npx hardhat deploy --network sepolia --tags staked-nusd-oft
```

### 3. Wire LayerZero Peers

Update the contract addresses in respective config files. Then, run these commands:

```bash
# nUSD peers (hub adapter ↔ spoke OFT)
npx hardhat lz:oapp:wire --oapp-config layerzero.nusd.config.ts

# snUSD peers (hub adapter ↔ spoke OFT)
npx hardhat lz:oapp:wire --oapp-config layerzero.snusd.config.ts
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
const nusd = await ethers.getContractAt("nusd/nUSD", "NUSD_ADDRESS");
await nusd.setMaxMintPerBlock(ethers.utils.parseEther("2000000"));
await nusd.setMaxRedeemPerBlock(ethers.utils.parseEther("2000000"));
```

### Emergency Disable Mint/Redeem

```javascript
const GATEKEEPER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("GATEKEEPER_ROLE"),
);
await nusd.grantRole(GATEKEEPER_ROLE, "GATEKEEPER_ADDRESS");

// As gatekeeper
await nusd.disableMintRedeem();
```

### Change Rewards Operator

```javascript
const distributor = await ethers.getContractAt(
  "staked-nusd/StakingRewardsDistributor",
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
5. 📖 Read [STAKED_NUSD_INTEGRATION.md](./STAKED_NUSD_INTEGRATION.md) for details
6. 🌐 Deploy OFT infrastructure for cross-chain support

---

## 📞 Support

**Deployment Issues?**

- Check [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)
- Check [CROSS_CHAIN_DEPLOYMENT.md](./CROSS_CHAIN_DEPLOYMENT.md)
- Check [Troubleshooting](#common-issues) section above

**Understanding the System?**

- [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md) - Overview
- [OVAULT_INTEGRATION.md](./OVAULT_INTEGRATION.md) - nUSD details
- [STAKED_NUSD_INTEGRATION.md](./STAKED_NUSD_INTEGRATION.md) - Staking details

---

**Status**: ✅ Ready to deploy  
**Network**: Arbitrum Sepolia Testnet (Hub Chain)  
**Last Updated**: 2025-10-20

🚀 **Happy Deploying!**
