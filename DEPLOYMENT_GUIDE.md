# 🚀 Deployment Guide - USDe OVault System

Complete deployment guide for the USDe OVault system on Sepolia testnet and other networks.

## 📋 Prerequisites

### Required Setup

1. **Environment Variables**

   ```bash
   # .env file
   MNEMONIC="your twelve word mnemonic phrase here"
   # OR
   PRIVATE_KEY="0x..."

   # Optional: Etherscan API key for verification
   ETHERSCAN_API_KEY="your-api-key"
   ```

2. **Dependencies**

   ```bash
   pnpm install
   ```

3. **Compile Contracts**
   ```bash
   pnpm compile
   ```

### Network Information

**Sepolia Testnet**

- Chain ID: 11155111
- RPC: https://rpc.sepolia.org
- USDC (Testnet): `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
- LayerZero Endpoint: Check [LayerZero docs](https://docs.layerzero.network/)

## 🎯 Deployment Options

You have three deployment options:

### Option 1: Full System Deployment (Recommended for Testing)

Deploy everything at once on Sepolia testnet.

```bash
npx hardhat deploy --network sepolia --tags FullSystem
```

This deploys:

- ✅ MultiCollateralToken (MCT)
- ✅ USDe vault
- ✅ StakedUSDe vault
- ✅ StakingRewardsDistributor

**Before running:**

1. Open `deploy/FullSystem.sepolia.ts`
2. Set `ADMIN_ADDRESS` (your multisig or admin EOA)
3. Set `OPERATOR_ADDRESS` (bot/EOA for rewards distribution)

### Option 2: Phased Deployment

Deploy step-by-step for production environments.

#### Phase 1: Deploy MCT + USDe

```bash
# 1. Update deploy/USDe.example.ts
#    - Set ADMIN_ADDRESS
#    - Set INITIAL_SUPPORTED_ASSETS (e.g., USDC address)
#    - Set MAX_MINT_PER_BLOCK and MAX_REDEEM_PER_BLOCK

# 2. Rename file
cp deploy/USDe.example.ts deploy/USDe.ts

# 3. Deploy
npx hardhat deploy --network sepolia --tags USDe
```

#### Phase 2: Deploy StakedUSDe

```bash
# 1. Update deploy/StakedUSDe.example.ts
#    - Set ADMIN_ADDRESS
#    - Set USDE_ADDRESS (from Phase 1)
#    - Set OPERATOR_ADDRESS
#    - Set INITIAL_REWARDER (optional)

# 2. Rename file
cp deploy/StakedUSDe.example.ts deploy/StakedUSDe.ts

# 3. Deploy
npx hardhat deploy --network sepolia --tags StakedUSDe
```

### Option 3: Manual Deployment via Console

Use Hardhat console for interactive deployment.

```bash
npx hardhat console --network sepolia
```

See [Console Deployment](#console-deployment) section below.

---

## 📝 Configuration Files

### 1. Full System Deployment (`deploy/FullSystem.sepolia.ts`)

**Edit these values:**

```typescript
const ADMIN_ADDRESS = "0x..."; // Your admin address
const OPERATOR_ADDRESS = "0x..."; // Rewards operator address
const SEPOLIA_USDC = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238";
const MAX_MINT_PER_BLOCK = "1000000000000000000000000"; // 1M USDe
const MAX_REDEEM_PER_BLOCK = "1000000000000000000000000"; // 1M USDe
```

### 2. USDe Only (`deploy/USDe.example.ts`)

```typescript
const ADMIN_ADDRESS = "0x...";
const INITIAL_SUPPORTED_ASSETS = [
  "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", // USDC
];
const MAX_MINT_PER_BLOCK = "1000000000000000000000000";
const MAX_REDEEM_PER_BLOCK = "1000000000000000000000000";
```

### 3. StakedUSDe Only (`deploy/StakedUSDe.example.ts`)

```typescript
const ADMIN_ADDRESS = "0x...";
const OPERATOR_ADDRESS = "0x...";
const USDE_ADDRESS = "0x..."; // From previous deployment
const INITIAL_REWARDER = "0x..."; // Optional, uses deployer if not set
```

### 4. LayerZero OVault Config (`devtools/deployConfig.ts`)

```typescript
const _hubEid = EndpointId.ARBSEP_V2_TESTNET;
const _spokeEids = [
  EndpointId.OPTSEP_V2_TESTNET,
  EndpointId.BASESEP_V2_TESTNET,
  EndpointId.SEPOLIA_V2_TESTNET,
];
```

---

## 🔍 Post-Deployment Steps

### 1. Verify Contracts on Etherscan

After deployment, verify each contract:

```bash
# MultiCollateralToken
npx hardhat verify --network sepolia <MCT_ADDRESS> \
  "<ADMIN_ADDRESS>" \
  "[\"0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238\"]"

# USDe
npx hardhat verify --network sepolia <USDE_ADDRESS> \
  "<MCT_ADDRESS>" \
  "<ADMIN_ADDRESS>" \
  "<MAX_MINT_PER_BLOCK>" \
  "<MAX_REDEEM_PER_BLOCK>"

# StakedUSDe
npx hardhat verify --network sepolia <STAKED_USDE_ADDRESS> \
  "<USDE_ADDRESS>" \
  "<INITIAL_REWARDER>" \
  "<ADMIN_ADDRESS>"

# StakingRewardsDistributor
npx hardhat verify --network sepolia <DISTRIBUTOR_ADDRESS> \
  "<STAKED_USDE_ADDRESS>" \
  "<USDE_ADDRESS>" \
  "<ADMIN_ADDRESS>" \
  "<OPERATOR_ADDRESS>"
```

### 2. Verify Roles

Check that roles were granted correctly:

```bash
npx hardhat console --network sepolia
```

```javascript
// Get contracts
const mct = await ethers.getContractAt(
  "mct/MultiCollateralToken",
  "<MCT_ADDRESS>",
);
const usde = await ethers.getContractAt("usde/USDe", "<USDE_ADDRESS>");
const stakedUsde = await ethers.getContractAt(
  "staked-usde/StakedUSDe",
  "<STAKED_USDE_ADDRESS>",
);

// Check roles
const MINTER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("MINTER_ROLE"),
);
const REWARDER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("REWARDER_ROLE"),
);
const BLACKLIST_MANAGER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("BLACKLIST_MANAGER_ROLE"),
);

// Verify MCT roles
console.log(
  "USDe has MINTER_ROLE:",
  await mct.hasRole(MINTER_ROLE, usde.address),
);

// Verify StakedUSDe roles
console.log(
  "Distributor has REWARDER_ROLE:",
  await stakedUsde.hasRole(REWARDER_ROLE, "<DISTRIBUTOR_ADDRESS>"),
);
console.log(
  "Admin has BLACKLIST_MANAGER_ROLE:",
  await stakedUsde.hasRole(BLACKLIST_MANAGER_ROLE, "<ADMIN_ADDRESS>"),
);
```

### 3. Test Minting USDe

Get testnet USDC and mint USDe:

```javascript
// Get Sepolia USDC from faucet
// https://faucet.circle.com/ or other USDC faucets

const usdc = await ethers.getContractAt(
  "IERC20",
  "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
);
const amount = ethers.utils.parseUnits("100", 6); // 100 USDC (6 decimals)

// Approve USDC to USDe
await usdc.approve(usde.address, amount);

// Mint USDe
await usde.mintWithCollateral(usdc.address, amount);

// Check balance
const balance = await usde.balanceOf(
  await ethers.provider.getSigner().getAddress(),
);
console.log("USDe balance:", ethers.utils.formatEther(balance));
```

### 4. Test Staking

Stake USDe for sUSDe:

```javascript
const stakeAmount = ethers.utils.parseEther("50"); // 50 USDe

// Approve USDe to StakedUSDe
await usde.approve(stakedUsde.address, stakeAmount);

// Deposit to receive sUSDe
const signer = await ethers.provider.getSigner();
await stakedUsde.deposit(stakeAmount, await signer.getAddress());

// Check sUSDe balance
const sUsdeBalance = await stakedUsde.balanceOf(await signer.getAddress());
console.log("sUSDe balance:", ethers.utils.formatEther(sUsdeBalance));
```

### 5. Test Rewards Distribution

Fund and test the rewards distributor:

```javascript
const distributor = await ethers.getContractAt(
  "staked-usde/StakingRewardsDistributor",
  "<DISTRIBUTOR_ADDRESS>",
);

// Transfer USDe to distributor for rewards
const rewardsAmount = ethers.utils.parseEther("10"); // 10 USDe
await usde.transfer(distributor.address, rewardsAmount);

// Check distributor balance
const distBalance = await usde.balanceOf(distributor.address);
console.log("Distributor USDe balance:", ethers.utils.formatEther(distBalance));

// As operator, transfer rewards to StakedUSDe
// NOTE: This must be called by the OPERATOR_ADDRESS
await distributor.transferInRewards(rewardsAmount);

// Wait 8 hours for rewards to vest
// Check increased sUSDe value
const totalAssets = await stakedUsde.totalAssets();
console.log(
  "Total assets after rewards:",
  ethers.utils.formatEther(totalAssets),
);
```

---

## 🔧 Console Deployment

For manual control, deploy via Hardhat console:

```bash
npx hardhat console --network sepolia
```

### Deploy MCT + USDe

```javascript
// Get deployer
const [deployer] = await ethers.getSigners();
console.log("Deployer:", deployer.address);

// Configuration
const ADMIN = "0x..."; // Set your admin address
const USDC = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238";
const MAX_MINT = ethers.utils.parseEther("1000000");
const MAX_REDEEM = ethers.utils.parseEther("1000000");

// Deploy MCT
const MCT = await ethers.getContractFactory("mct/MultiCollateralToken");
const mct = await MCT.deploy(ADMIN, [USDC]);
await mct.deployed();
console.log("MCT deployed at:", mct.address);

// Deploy USDe
const USDe = await ethers.getContractFactory("usde/USDe");
const usde = await USDe.deploy(mct.address, ADMIN, MAX_MINT, MAX_REDEEM);
await usde.deployed();
console.log("USDe deployed at:", usde.address);

// Grant MINTER_ROLE
const MINTER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("MINTER_ROLE"),
);
await mct.grantRole(MINTER_ROLE, usde.address);
console.log("MINTER_ROLE granted");
```

### Deploy StakedUSDe + Distributor

```javascript
// Configuration
const OPERATOR = "0x..."; // Set operator address
const USDE_ADDRESS = "0x..."; // From previous deployment

// Deploy StakedUSDe
const StakedUSDe = await ethers.getContractFactory("staked-usde/StakedUSDe");
const stakedUsde = await StakedUSDe.deploy(
  USDE_ADDRESS,
  deployer.address,
  ADMIN,
);
await stakedUsde.deployed();
console.log("StakedUSDe deployed at:", stakedUsde.address);

// Deploy StakingRewardsDistributor
const Distributor = await ethers.getContractFactory(
  "staked-usde/StakingRewardsDistributor",
);
const distributor = await Distributor.deploy(
  stakedUsde.address,
  USDE_ADDRESS,
  ADMIN,
  OPERATOR,
);
await distributor.deployed();
console.log("StakingRewardsDistributor deployed at:", distributor.address);

// Grant roles
const REWARDER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("REWARDER_ROLE"),
);
const BLACKLIST_MANAGER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("BLACKLIST_MANAGER_ROLE"),
);

await stakedUsde.grantRole(REWARDER_ROLE, distributor.address);
await stakedUsde.grantRole(BLACKLIST_MANAGER_ROLE, ADMIN);
console.log("Roles granted");
```

---

## 🌐 Cross-Chain Deployment (OVault)

To enable cross-chain functionality, deploy OFT adapters and configure LayerZero.

### Prerequisites

- Core contracts must be deployed first (MCT, USDe, StakedUSDe)
- Use `FullSystem.sepolia.ts` or phased deployment
- Configure `devtools/deployConfig.ts` with your hub and spoke chain EIDs

### 1. Deploy USDe OFT Infrastructure on All Chains

**Hub Chain (Arbitrum Sepolia):**

```bash
npx hardhat deploy --network arbitrum-sepolia --tags ovault
```

This deploys on hub:

- `USDeOFTAdapter` (lockbox for USDe)

**Spoke Chains:**

```bash
# Deploy on Optimism Sepolia
npx hardhat deploy --network optimism-sepolia --tags ovault

# Deploy on Base Sepolia
npx hardhat deploy --network base-sepolia --tags ovault

# Deploy on Sepolia
npx hardhat deploy --network sepolia --tags ovault
```

This deploys on spokes:

- `USDeOFT` (mint/burn for USDe)

### 2. (Optional) Deploy StakedUSDe OFT Infrastructure

**Hub Chain (Arbitrum Sepolia):**

```bash
npx hardhat deploy --network arbitrum-sepolia --tags staked-usde-oft
```

This deploys on hub:

- `StakedUSDeOFTAdapter` (lockbox for sUSDe)

**Spoke Chains:**

```bash
# Deploy on Optimism Sepolia
npx hardhat deploy --network optimism-sepolia --tags staked-usde-oft

# Deploy on Base Sepolia
npx hardhat deploy --network base-sepolia --tags staked-usde-oft

# Deploy on Sepolia
npx hardhat deploy --network sepolia --tags staked-usde-oft
```

This deploys on spokes:

- `StakedUSDeOFT` (mint/burn for sUSDe)

### 3. Configure LayerZero Peers

```bash
# Wire up the connections between all chains
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts
```

This connects:

- Hub USDeOFTAdapter ↔ Spoke USDeOFT (all chains)
- Hub StakedUSDeOFTAdapter ↔ Spoke StakedUSDeOFT (all chains)

### 4. Verify Cross-Chain Setup

After wiring, verify the peers are set correctly:

```javascript
// On hub chain
const mctAdapter = await ethers.getContractAt(
  "mct/MCTOFTAdapter",
  "<ADAPTER_ADDRESS>",
);
const peerAddress = await mctAdapter.peers(SPOKE_EID);
console.log("Peer on spoke:", peerAddress);

// On spoke chain
const mctOFT = await ethers.getContractAt("mct/MCTOFT", "<OFT_ADDRESS>");
const peerAddress = await mctOFT.peers(HUB_EID);
console.log("Peer on hub:", peerAddress);
```

---

## 🐛 Troubleshooting

### Role Granting Fails

If automatic role granting fails during deployment:

```bash
npx hardhat console --network sepolia
```

```javascript
const mct = await ethers.getContractAt(
  "mct/MultiCollateralToken",
  "<MCT_ADDRESS>",
);
const MINTER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("MINTER_ROLE"),
);
await mct.grantRole(MINTER_ROLE, "<USDE_ADDRESS>");
```

### Deployment Fails Midway

Hardhat Deploy tracks deployments. To redeploy:

```bash
# Remove deployment file
rm deployments/sepolia/<ContractName>.json

# Redeploy
npx hardhat deploy --network sepolia --tags <TagName>
```

### Gas Estimation Issues

If gas estimation fails, set explicit gas limit:

```javascript
await contract.function({ gasLimit: 500000 });
```

---

## 📊 Deployment Costs (Estimate)

Approximate gas costs on Sepolia (gas price varies):

| Contract                  | Gas Used   | Estimated Cost (15 gwei) |
| ------------------------- | ---------- | ------------------------ |
| MultiCollateralToken      | ~2.5M      | ~0.0375 ETH              |
| USDe                      | ~3.5M      | ~0.0525 ETH              |
| StakedUSDe                | ~3.0M      | ~0.045 ETH               |
| StakingRewardsDistributor | ~1.5M      | ~0.0225 ETH              |
| **Total**                 | **~10.5M** | **~0.1575 ETH**          |

---

## ✅ Deployment Checklist

Before going to production:

- [ ] Set `ADMIN_ADDRESS` to multisig
- [ ] Set `OPERATOR_ADDRESS` to secure bot/EOA
- [ ] Configure appropriate `MAX_MINT_PER_BLOCK`
- [ ] Configure appropriate `MAX_REDEEM_PER_BLOCK`
- [ ] Verify all contracts on Etherscan
- [ ] Test minting with small amounts
- [ ] Test staking with small amounts
- [ ] Test rewards distribution
- [ ] Grant `GATEKEEPER_ROLE` for emergency actions
- [ ] Grant `COLLATERAL_MANAGER_ROLE` to treasury
- [ ] Set up monitoring and alerts
- [ ] Test emergency pause functionality
- [ ] Document all deployed addresses
- [ ] Transfer admin roles to multisig

---

## 📚 Additional Resources

- [USDe Integration Guide](./OVAULT_INTEGRATION.md)
- [StakedUSDe Guide](./STAKED_USDE_INTEGRATION.md)
- [Project Structure](./PROJECT_STRUCTURE.md)
- [Usage Examples](./examples/USDe.usage.ts)

---

**Questions or Issues?**  
Check the documentation or reach out to the team.

**Status**: ✅ Ready for deployment  
**Last Updated**: 2025-10-20
