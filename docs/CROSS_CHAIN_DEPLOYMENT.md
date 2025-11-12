# 🌐 Cross-Chain Deployment Guide

Complete guide for deploying USDe and StakedUSDe OFT infrastructure for omnichain functionality.

## 📋 Overview

This guide covers deploying LayerZero OFT (Omnichain Fungible Token) infrastructure to enable:

- ✅ Cross-chain USDe transfers
- ✅ Cross-chain MCT transfers
- ✅ Cross-chain sUSDe transfers (optional)

## 🏗️ Architecture

```
Hub Chain (Sepolia)                    Spoke Chain (OP Sepolia, Base Sepolia)
┌──────────────────────┐              ┌──────────────────────┐
│ MultiCollateralToken │              │                      │
│ USDe (ERC4626)       │              │                      │
│ StakedUSDe (ERC4626) │              │                      │
└──────────────────────┘              └──────────────────────┘
         │                                      │
         ▼                                      ▼
┌──────────────────────┐              ┌──────────────────────┐
│ MCTOFTAdapter        │◄────peer────►│ MCTOFT               │
│ USDeOFTAdapter       │◄────peer────►│ USDeOFT              │
│ StakedUSDeOFTAdapter │◄────peer────►│ StakedUSDeOFT        │
│ USDeComposer         │              │                      │
└──────────────────────┘              └──────────────────────┘
```

## 📦 Deployment Scripts

| Script                        | Purpose                              | Command Tag       |
| ----------------------------- | ------------------------------------ | ----------------- |
| `deploy/OVault.ts`            | Deploy USDe OFT infrastructure       | `ovault`          |
| `deploy/OVault.StakedUSDe.ts` | Deploy StakedUSDe OFT infrastructure | `staked-usde-oft` |

## ⚙️ Prerequisites

### 1. Core Contracts Deployed

You must deploy core contracts on the hub chain first:

```bash
# Option A: Deploy everything
npx hardhat deploy --network arbitrum-sepolia --tags FullSystem

# Option B: Deploy step-by-step
npx hardhat deploy --network arbitrum-sepolia --tags USDe
npx hardhat deploy --network arbitrum-sepolia --tags StakedUSDe
```

### 2. Configuration

Update `devtools/deployConfig.ts`:

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

### 3. Network Configuration

Ensure networks are configured in `hardhat.config.ts`:

```typescript
networks: {
  sepolia: {
    url: process.env.SEPOLIA_RPC_URL,
    eid: EndpointId.SEPOLIA_V2_TESTNET,
    // ...
  },
  'optimism-sepolia': {
    url: process.env.OP_SEPOLIA_RPC_URL,
    eid: EndpointId.OPTSEP_V2_TESTNET,
    // ...
  },
  'base-sepolia': {
    url: process.env.BASE_SEPOLIA_RPC_URL,
    eid: EndpointId.BASESEP_V2_TESTNET,
    // ...
  },
}
```

---

## 🚀 Deployment Steps

### Step 1: Deploy USDe OFT Infrastructure

#### Hub Chain (Arbitrum Sepolia)

```bash
npx hardhat deploy --network arbitrum-sepolia --tags ovault
```

**Deploys:**

- ✅ `MCTOFTAdapter` - Lockbox for MCT on hub
- ✅ `USDeOFTAdapter` - Lockbox for USDe on hub
- ✅ `USDeComposer` - Cross-chain operations coordinator

**What it does:**

- Wraps existing MCT and USDe tokens
- Creates lockbox adapters (tokens stay on hub)
- Enables cross-chain messaging

#### Spoke Chains

```bash
# Optimism Sepolia
npx hardhat deploy --network optimism-sepolia --tags ovault

# Base Sepolia
npx hardhat deploy --network base-sepolia --tags ovault

# Sepolia
npx hardhat deploy --network sepolia --tags ovault

# Add more spoke chains as needed
```

**Deploys:**

- ✅ `MCTOFT` - Mint/burn OFT for MCT on spoke
- ✅ `USDeOFT` - Mint/burn OFT for USDe on spoke

**What it does:**

- Creates OFT contracts on spoke chains
- Mints tokens when received from hub
- Burns tokens when sent to hub

---

### Step 2: (Optional) Deploy StakedUSDe OFT Infrastructure

Only needed if you want cross-chain sUSDe transfers.

#### Hub Chain (Arbitrum Sepolia)

```bash
npx hardhat deploy --network arbitrum-sepolia --tags staked-usde-oft
```

**Deploys:**

- ✅ `StakedUSDeOFTAdapter` - Lockbox for sUSDe on hub

#### Spoke Chains

```bash
# Optimism Sepolia
npx hardhat deploy --network optimism-sepolia --tags staked-usde-oft

# Base Sepolia
npx hardhat deploy --network base-sepolia --tags staked-usde-oft

# Sepolia
npx hardhat deploy --network sepolia --tags staked-usde-oft
```

**Deploys:**

- ✅ `StakedUSDeOFT` - Mint/burn OFT for sUSDe on spoke

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
- Hub `USDeOFTAdapter` ↔ Spoke `USDeOFT` (each spoke)
- Hub `StakedUSDeOFTAdapter` ↔ Spoke `StakedUSDeOFT` (each spoke)

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

## 📊 Deployment Summary Example

After successful deployment, you should have:

### Hub Chain (Arbitrum Sepolia)

```
Core Contracts:
  MultiCollateralToken: 0xabc...
  USDe: 0xdef...
  StakedUSDe: 0xghi...
  StakingRewardsDistributor: 0xjkl...

OFT Infrastructure:
  MCTOFTAdapter: 0x123...
  USDeOFTAdapter: 0x456...
  USDeComposer: 0x789...
  StakedUSDeOFTAdapter: 0x012...
```

### Spoke Chain 1 (OP Sepolia)

```
OFT Contracts:
  MCTOFT: 0x345...
  USDeOFT: 0x678...
  StakedUSDeOFT: 0x901...
```

### Spoke Chain 2 (Base Sepolia)

```
OFT Contracts:
  MCTOFT: 0x234...
  USDeOFT: 0x567...
  StakedUSDeOFT: 0x890...
```

### Spoke Chain 3 (Sepolia)

```
OFT Contracts:
  MCTOFT: 0x345...
  USDeOFT: 0x678...
  StakedUSDeOFT: 0x901...
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

# 3. Deploy StakedUSDe OFTs (optional)
npx hardhat deploy --network arbitrum-sepolia --tags staked-usde-oft
npx hardhat deploy --network optimism-sepolia --tags staked-usde-oft
npx hardhat deploy --network base-sepolia --tags staked-usde-oft
npx hardhat deploy --network sepolia --tags staked-usde-oft

# 4. Wire everything
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts
```

### Pattern 2: Add New Spoke Chain Later

```bash
# Deploy OFTs on new chain (e.g., Polygon Sepolia)
npx hardhat deploy --network polygon-sepolia --tags ovault
npx hardhat deploy --network polygon-sepolia --tags staked-usde-oft

# Wire the new chain
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts
```

### Pattern 3: USDe Only (No StakedUSDe)

```bash
# Deploy core (MCT + USDe only)
npx hardhat deploy --network arbitrum-sepolia --tags USDe

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
- [QUICK_START_ARBITRUM_SEPOLIA.md](./QUICK_START_ARBITRUM_SEPOLIA.md) - Quick start for Arbitrum Sepolia
- [OVAULT_INTEGRATION.md](./OVAULT_INTEGRATION.md) - Technical OVault details
- [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md) - System architecture

---

## 🔗 Useful Commands Reference

```bash
# Deploy core contracts
npx hardhat deploy --network arbitrum-sepolia --tags FullSystem

# Deploy USDe OFT infrastructure
npx hardhat deploy --network arbitrum-sepolia --tags ovault

# Deploy StakedUSDe OFT infrastructure
npx hardhat deploy --network arbitrum-sepolia --tags staked-usde-oft

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
