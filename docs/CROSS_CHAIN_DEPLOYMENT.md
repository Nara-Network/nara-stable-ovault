# 🌐 Cross-Chain Deployment Guide

Complete guide for deploying naraUSD and StakedNaraUSD OFT infrastructure for omnichain functionality.

## 📋 Overview

This guide covers deploying LayerZero OFT (Omnichain Fungible Token) infrastructure to enable:

- ✅ Cross-chain naraUSD transfers
- ✅ Cross-chain MCT transfers
- ✅ Cross-chain snaraUSD transfers (optional)

## 🏗️ Architecture

```
Hub Chain (Sepolia)                    Spoke Chain (OP Sepolia, Base Sepolia)
┌──────────────────────┐              ┌──────────────────────┐
│ MultiCollateralToken │              │                      │
│ naraUSD (ERC4626)       │              │                      │
│ StakedNaraUSD (ERC4626) │              │                      │
└──────────────────────┘              └──────────────────────┘
         │                                      │
         ▼                                      ▼
┌──────────────────────┐              ┌──────────────────────┐
│ MCTOFTAdapter        │◄────peer────►│ MCTOFT               │
│ NaraUSDOFTAdapter       │◄────peer────►│ NaraUSDOFT              │
│ StakedNaraUSDOFTAdapter │◄────peer────►│ StakedNaraUSDOFT        │
│ NaraUSDComposer         │              │                      │
└──────────────────────┘              └──────────────────────┘
```

## 📦 Deployment Scripts

| Script                        | Purpose                              | Command Tag       |
| ----------------------------- | ------------------------------------ | ----------------- |
| `deploy/OVault.ts`            | Deploy naraUSD OFT infrastructure       | `ovault`          |
| `deploy/OVault.StakedNaraUSD.ts` | Deploy StakedNaraUSD OFT infrastructure | `staked-narausd-oft` |

## ⚙️ Prerequisites

### 1. Core Contracts Deployed

You must deploy core contracts on the hub chain first:

```bash
# Option A: Deploy everything
npx hardhat deploy --network arbitrum-sepolia --tags FullSystem

# Option B: Deploy step-by-step
npx hardhat deploy --network arbitrum-sepolia --tags naraUSD
npx hardhat deploy --network arbitrum-sepolia --tags StakedNaraUSD
```

### 2. Configuration

Update `devtools/deployConfig.ts` (or `deployConfig.testnet.ts` / `deployConfig.mainnet.ts`):

**Testnet:**

```typescript
// Hub chain (where core contracts live)
const _hubEid = EndpointId.ARBSEP_V2_TESTNET;

// Spoke chains (where OFTs will be deployed)
const _spokeEids = [
  EndpointId.OPTSEP_V2_TESTNET,
  EndpointId.BASESEP_V2_TESTNET,
  EndpointId.SEPOLIA_V2_TESTNET,
];
```

**Mainnet:**

```typescript
// Hub chain (where core contracts live)
const _hubEid = EndpointId.ARBITRUM_V2_MAINNET;

// Spoke chains (where OFTs will be deployed)
const _spokeEids = [EndpointId.BASE_V2_MAINNET, EndpointId.ETHEREUM_V2_MAINNET];
```

### 3. Network Configuration

Ensure networks are configured in `hardhat.config.ts`:

**Testnet:**

```typescript
networks: {
  sepolia: {
    url: process.env.RPC_URL_SEPOLIA_TESTNET,
    eid: EndpointId.SEPOLIA_V2_TESTNET,
    // ...
  },
  'optimism-sepolia': {
    url: process.env.RPC_URL_OPTIMISM_TESTNET,
    eid: EndpointId.OPTSEP_V2_TESTNET,
    // ...
  },
  'base-sepolia': {
    url: process.env.RPC_URL_BASE_TESTNET,
    eid: EndpointId.BASESEP_V2_TESTNET,
    // ...
  },
  'arbitrum-sepolia': {
    url: process.env.RPC_URL_ARBITRUM_TESTNET,
    eid: EndpointId.ARBSEP_V2_TESTNET,
    // ...
  },
}
```

**Mainnet:**

```typescript
networks: {
  arbitrum: {
    url: process.env.RPC_URL_ARBITRUM_MAINNET,
    eid: EndpointId.ARBITRUM_V2_MAINNET,
    // ...
  },
  base: {
    url: process.env.RPC_URL_BASE_MAINNET,
    eid: EndpointId.BASE_V2_MAINNET,
    // ...
  },
  ethereum: {
    url: process.env.RPC_URL_ETHEREUM_MAINNET,
    eid: EndpointId.ETHEREUM_V2_MAINNET,
    // ...
  },
}
```

---

## 🚀 Deployment Steps

### Step 1: Deploy naraUSD OFT Infrastructure

#### Hub Chain (Arbitrum Sepolia)

```bash
npx hardhat deploy --network arbitrum-sepolia --tags ovault
```

**Deploys:**

- ✅ `MCTOFTAdapter` - Lockbox for MCT on hub
- ✅ `NaraUSDOFTAdapter` - Lockbox for naraUSD on hub
- ✅ `NaraUSDComposer` - Cross-chain operations coordinator

**What it does:**

- Wraps existing MCT and naraUSD tokens
- Creates lockbox adapters (tokens stay on hub)
- Enables cross-chain messaging

#### Spoke Chains

**Testnet:**

```bash
# Optimism Sepolia
DEPLOY_ENV=testnet npx hardhat deploy --network optimism-sepolia --tags ovault

# Base Sepolia
DEPLOY_ENV=testnet npx hardhat deploy --network base-sepolia --tags ovault

# Sepolia
DEPLOY_ENV=testnet npx hardhat deploy --network sepolia --tags ovault
```

**Mainnet:**

```bash
# Base
DEPLOY_ENV=mainnet npx hardhat deploy --network base --tags ovault

# Ethereum
DEPLOY_ENV=mainnet npx hardhat deploy --network ethereum --tags ovault
```

**Deploys:**

- ✅ `MCTOFT` - Mint/burn OFT for MCT on spoke
- ✅ `NaraUSDOFT` - Mint/burn OFT for naraUSD on spoke

**What it does:**

- Creates OFT contracts on spoke chains
- Mints tokens when received from hub
- Burns tokens when sent to hub

---

### Step 2: (Optional) Deploy StakedNaraUSD OFT Infrastructure

Only needed if you want cross-chain snaraUSD transfers.

#### Hub Chain

**Testnet:**

```bash
DEPLOY_ENV=testnet npx hardhat deploy --network arbitrum-sepolia --tags staked-narausd-oft
```

**Mainnet:**

```bash
DEPLOY_ENV=mainnet npx hardhat deploy --network arbitrum --tags staked-narausd-oft
```

**Deploys:**

- ✅ `StakedNaraUSDOFTAdapter` - Lockbox for snaraUSD on hub

#### Spoke Chains

**Testnet:**

```bash
# Optimism Sepolia
DEPLOY_ENV=testnet npx hardhat deploy --network optimism-sepolia --tags staked-narausd-oft

# Base Sepolia
DEPLOY_ENV=testnet npx hardhat deploy --network base-sepolia --tags staked-narausd-oft

# Sepolia
DEPLOY_ENV=testnet npx hardhat deploy --network sepolia --tags staked-narausd-oft
```

**Mainnet:**

```bash
# Base
DEPLOY_ENV=mainnet npx hardhat deploy --network base --tags staked-narausd-oft

# Ethereum
DEPLOY_ENV=mainnet npx hardhat deploy --network ethereum --tags staked-narausd-oft
```

**Deploys:**

- ✅ `StakedNaraUSDOFT` - Mint/burn OFT for snaraUSD on spoke (includes blacklist functionality) (includes blacklist functionality)

---

### Step 3: Wire LayerZero Peers

After deploying on all chains, connect them:

```bash
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts
```

**What this does:**

- Sets peer relationships between hub and spoke OFTs
- Configures trusted paths for cross-chain messages
- Enables bidirectional communication

**Peers that get connected:**

- Hub `MCTOFTAdapter` ↔ Spoke `MCTOFT` (each spoke)
- Hub `NaraUSDOFTAdapter` ↔ Spoke `NaraUSDOFT` (each spoke)
- Hub `StakedNaraUSDOFTAdapter` ↔ Spoke `StakedNaraUSDOFT` (each spoke)

---

## ✅ Verification

### 1. Check Deployed Contracts

```bash
# List all deployments on Arbitrum Sepolia (hub)
ls -la deployments/arbitrum-sepolia/

# List all deployments on OP Sepolia (spoke)
ls -la deployments/optimism-sepolia/

# List all deployments on Sepolia (spoke)
ls -la deployments/sepolia/
```

### 2. Verify Peers Are Set

```bash
npx hardhat console --network arbitrum-sepolia
```

```javascript
// Get contracts
const mctAdapter = await ethers.getContractAt(
  "mct/MCTOFTAdapter",
  "<MCTOFTAdapter_ADDRESS>",
);

// Check peer on OP Sepolia (EID: 40232)
const OP_SEPOLIA_EID = 40232;
const peer = await mctAdapter.peers(OP_SEPOLIA_EID);
console.log("Peer on OP Sepolia:", peer);

// Peer should be the addressToBytes32 of MCTOFT on OP Sepolia
```

### 3. Test Cross-Chain Transfer

```javascript
// On Arbitrum Sepolia (hub)
const mctAdapter = await ethers.getContractAt("mct/MCTOFTAdapter", "<ADDRESS>");

// Prepare cross-chain transfer
const sendParam = {
  dstEid: 40232, // OP Sepolia
  to: ethers.utils.zeroPad(recipientAddress, 32),
  amountLD: ethers.utils.parseEther("100"),
  minAmountLD: ethers.utils.parseEther("99"),
  extraOptions: "0x",
  composeMsg: "0x",
  oftCmd: "0x",
};

// Get quote for gas
const quote = await mctAdapter.quoteSend(sendParam, false);
console.log("Gas fee:", ethers.utils.formatEther(quote.nativeFee));

// Send tokens
await mctAdapter.send(sendParam, { value: quote.nativeFee });
```

---

## 🛡️ OFT Blacklist Functionality

The OFT contracts on spoke chains (`NaraUSDOFT` and `StakedNaraUSDOFT`) include blacklist functionality to prevent transfers from or to restricted addresses.

### Features

- **Full Restriction**: Blacklisted addresses cannot send or receive tokens
- **Consistent with Hub**: Same blacklist system as naraUSD and StakedNaraUSD on hub chain
- **Admin Protection**: Cannot blacklist addresses with `DEFAULT_ADMIN_ROLE`
- **Access Control**: Only `BLACKLIST_MANAGER_ROLE` can manage blacklist

### Usage

```solidity
// On spoke chain (e.g., Optimism Sepolia)
const narausdOFT = await ethers.getContractAt("NaraUSDOFT", "<NaraUSDOFT_ADDRESS>");

// Add address to blacklist (requires BLACKLIST_MANAGER_ROLE)
await narausdOFT.addToBlacklist(restrictedAddress);

// Remove from blacklist
await narausdOFT.removeFromBlacklist(restrictedAddress);

// Check if address is blacklisted
const isBlacklisted = await narausdOFT.hasRole(
  await narausdOFT.FULL_RESTRICTED_ROLE(),
  restrictedAddress
);
```

### Roles

| Role                     | Description                             |
| ------------------------ | --------------------------------------- |
| `DEFAULT_ADMIN_ROLE`     | Full admin access, can manage all roles |
| `BLACKLIST_MANAGER_ROLE` | Can add/remove addresses from blacklist |
| `FULL_RESTRICTED_ROLE`   | Prevents all transfers (blacklisted)    |

**Note**: The deployer address automatically receives `DEFAULT_ADMIN_ROLE` and `BLACKLIST_MANAGER_ROLE` during deployment.

---

## 📊 Deployment Summary Example

After successful deployment, you should have:

### Testnet Deployment

#### Hub Chain (Arbitrum Sepolia)

```
Core Contracts:
  MultiCollateralToken: 0xabc...
  naraUSD: 0xdef...
  StakedNaraUSD: 0xghi...
  StakingRewardsDistributor: 0xjkl...

OFT Infrastructure:
  MCTOFTAdapter: 0x123...
  NaraUSDOFTAdapter: 0x456...
  NaraUSDComposer: 0x789...
  StakedNaraUSDOFTAdapter: 0x012...
```

#### Spoke Chain 1 (Base Sepolia)

```
OFT Contracts:
  MCTOFT: 0x234...
  NaraUSDOFT: 0x567...
  StakedNaraUSDOFT: 0x890...
```

#### Spoke Chain 2 (Sepolia)

```
OFT Contracts:
  MCTOFT: 0x345...
  NaraUSDOFT: 0x678...
  StakedNaraUSDOFT: 0x901...
```

### Mainnet Deployment

#### Hub Chain (Arbitrum)

```
Core Contracts:
  MultiCollateralToken: 0xabc...
  naraUSD: 0xdef...
  StakedNaraUSD: 0xghi...
  StakingRewardsDistributor: 0xjkl...

OFT Infrastructure:
  MCTOFTAdapter: 0x123...
  NaraUSDOFTAdapter: 0x456...
  NaraUSDComposer: 0x789...
  StakedNaraUSDOFTAdapter: 0x012...
```

#### Spoke Chain 1 (Base)

```
OFT Contracts:
  MCTOFT: 0x234...
  NaraUSDOFT: 0x567...
  StakedNaraUSDOFT: 0x890...
```

#### Spoke Chain 2 (Ethereum)

```
OFT Contracts:
  MCTOFT: 0x345...
  NaraUSDOFT: 0x678...
  StakedNaraUSDOFT: 0x901...
```

---

## 🔧 Troubleshooting

### Issue: "EndpointV2 not found"

**Solution:** LayerZero endpoint needs to be deployed first. The OVault template includes this.

```bash
# This should already be deployed as part of the project setup
npx hardhat deploy --network arbitrum-sepolia --tags EndpointV2
```

### Issue: "Core contract not found"

**Solution:** Deploy core contracts first:

```bash
npx hardhat deploy --network arbitrum-sepolia --tags FullSystem
```

### Issue: "Peers not set after wiring"

**Solution:** Check your `layerzero.config.ts` file and ensure all contract addresses are correct.

### Issue: "Wrong chain type"

**Error:** Script deploys wrong contract type (adapter instead of OFT or vice versa)

**Solution:** Check that your `_hubEid` in `devtools/deployConfig.ts` matches your hub chain.

---

## 🎯 Common Deployment Patterns

### Pattern 1: Full Multi-Chain Deployment

```bash
# 1. Deploy core on hub
npx hardhat deploy --network arbitrum-sepolia --tags FullSystem

# 2. Deploy OFTs on all chains
npx hardhat deploy --network arbitrum-sepolia --tags ovault
npx hardhat deploy --network optimism-sepolia --tags ovault
npx hardhat deploy --network base-sepolia --tags ovault
npx hardhat deploy --network sepolia --tags ovault

# 3. Deploy StakedNaraUSD OFTs (optional)
npx hardhat deploy --network arbitrum-sepolia --tags staked-narausd-oft
npx hardhat deploy --network optimism-sepolia --tags staked-narausd-oft
npx hardhat deploy --network base-sepolia --tags staked-narausd-oft
npx hardhat deploy --network sepolia --tags staked-narausd-oft

# 4. Wire everything
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts
```

### Pattern 2: Add New Spoke Chain Later

```bash
# Deploy OFTs on new chain (e.g., Polygon Sepolia)
npx hardhat deploy --network polygon-sepolia --tags ovault
npx hardhat deploy --network polygon-sepolia --tags staked-narausd-oft

# Wire the new chain
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts
```

### Pattern 3: naraUSD Only (No StakedNaraUSD)

```bash
# Deploy core (MCT + naraUSD only)
npx hardhat deploy --network arbitrum-sepolia --tags naraUSD

# Deploy OFTs
npx hardhat deploy --network arbitrum-sepolia --tags ovault
npx hardhat deploy --network optimism-sepolia --tags ovault
npx hardhat deploy --network base-sepolia --tags ovault
npx hardhat deploy --network sepolia --tags ovault

# Wire
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts
```

---

## 📚 Related Documentation

- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - General deployment guide
- [DEPLOYMENT_QUICK_START.md](../DEPLOYMENT_QUICK_START.md) - Quick start deployment guide
- [OVAULT_INTEGRATION.md](./OVAULT_INTEGRATION.md) - Technical OVault details
- [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md) - System architecture

---

## 🔗 Useful Commands Reference

```bash
# Deploy core contracts
npx hardhat deploy --network arbitrum-sepolia --tags FullSystem

# Deploy naraUSD OFT infrastructure
npx hardhat deploy --network arbitrum-sepolia --tags ovault

# Deploy StakedNaraUSD OFT infrastructure
npx hardhat deploy --network arbitrum-sepolia --tags staked-narausd-oft

# Wire LayerZero peers
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts

# Verify contract
npx hardhat verify --network arbitrum-sepolia <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>

# Check deployment status
ls -la deployments/<network>/
```

---

**Status**: ✅ Ready for cross-chain deployment  
**Last Updated**: 2025-10-20
