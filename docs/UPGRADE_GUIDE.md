# Upgrade Guide for Upgradeable Contracts

This guide explains how to upgrade your UUPS upgradeable contracts (NaraUSD, NaraUSDPlus, MultiCollateralToken, etc.).

## Overview

All core contracts use the **UUPS (Universal Upgradeable Proxy Standard)** pattern:

- **Proxy Contract**: The address users interact with (never changes)
- **Implementation Contract**: The actual logic (can be upgraded)

When you upgrade, you deploy a new implementation and point the proxy to it. User addresses and storage remain unchanged.

## Prerequisites

1. ✅ You have `DEFAULT_ADMIN_ROLE` on the contract (for NaraUSD, NaraUSDPlus, MCT)
2. ✅ You have tested the new implementation on testnet
3. ✅ Storage layout is compatible (OpenZeppelin plugin validates this automatically)

## Step-by-Step Upgrade Process

### Method 1: Using the Upgrade Helper Script (Recommended)

#### Step 1: Prepare Your New Implementation

Make your changes to the contract (e.g., `contracts/narausd/NaraUSD.sol`). Ensure:

- Storage variables are **never removed or reordered**
- New variables are **only added at the end**
- No changes to `initialize()` function signature (unless you add a migration function)

#### Step 2: Compile the New Implementation

```bash
pnpm compile:hardhat
```

#### Step 3: Test the Upgrade on Testnet First

```bash
# Deploy to testnet
DEPLOY_ENV=testnet npx hardhat run deploy/UpgradeNaraUSD.example.ts --network arbitrum-sepolia
```

#### Step 4: Validate the Upgrade (Dry Run)

The upgrade script automatically validates storage compatibility. If validation fails, you'll see an error like:

```
Error: New storage layout is incompatible
```

#### Step 5: Execute the Upgrade

```bash
# For mainnet (be careful!)
DEPLOY_ENV=mainnet npx hardhat run deploy/UpgradeNaraUSD.example.ts --network arbitrum
```

### Method 2: Using Hardhat Console (Manual)

#### Step 1: Get the Proxy Address

```bash
npx hardhat console --network arbitrum-sepolia
```

```javascript
const deployment = await hre.deployments.get("NaraUSD");
const proxyAddress = deployment.address;
console.log("Proxy:", proxyAddress);
```

#### Step 2: Prepare Upgrade (Validate)

```javascript
const { upgrades } = require("@openzeppelin/hardhat-upgrades");
const ContractFactory = await ethers.getContractFactory("NaraUSD");
const newImpl = await upgrades.prepareUpgrade(proxyAddress, ContractFactory);
console.log("New implementation:", newImpl);
```

#### Step 3: Execute Upgrade

```javascript
const upgraded = await upgrades.upgradeProxy(proxyAddress, ContractFactory);
await upgraded.deployed();
console.log("Upgrade complete!");
```

#### Step 4: Verify

```javascript
const currentImpl =
  await upgrades.erc1967.getImplementationAddress(proxyAddress);
console.log("Current implementation:", currentImpl);
```

### Method 3: Using a Custom Upgrade Script

Create a new file `deploy/UpgradeNaraUSD.v2.ts`:

```typescript
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { upgradeContract } from "../devtools/utils";

async function main(hre: HardhatRuntimeEnvironment) {
  const { getNamedAccounts } = hre;
  const { deployer } = await getNamedAccounts();

  // Get proxy address
  const deployment = await hre.deployments.get("NaraUSD");
  const proxyAddress = deployment.address;

  // Upgrade to new implementation
  const result = await upgradeContract(hre, proxyAddress, "NaraUSD", {
    // Optional: Call a migration function after upgrade
    // call: {
    //     fn: 'migrateToV2',
    //     args: [],
    // },
    log: true,
  });

  console.log("Upgrade complete!");
  console.log("New implementation:", result.implementationAddress);
}

main(require("hardhat").hre).catch(console.error);
```

Run it:

```bash
npx hardhat run deploy/UpgradeNaraUSD.v2.ts --network arbitrum-sepolia
```

## Storage Layout Compatibility Rules

⚠️ **CRITICAL**: When upgrading, you MUST follow these rules:

### ✅ Allowed Changes:

- Add new state variables at the end
- Add new functions
- Modify function logic
- Add new events

### ❌ NOT Allowed:

- Remove state variables
- Reorder state variables
- Change variable types
- Change variable names (if they affect storage layout)
- Remove functions that are called externally

### Example: Safe Storage Change

```solidity
// V1
contract NaraUSD {
  uint256 public maxMintPerBlock; // slot 0
  uint256 public maxRedeemPerBlock; // slot 1
}

// V2 - SAFE ✅
contract NaraUSD {
  uint256 public maxMintPerBlock; // slot 0 (same)
  uint256 public maxRedeemPerBlock; // slot 1 (same)
  uint256 public newFeature; // slot 2 (added at end)
}
```

### Example: Unsafe Storage Change

```solidity
// V1
contract NaraUSD {
  uint256 public maxMintPerBlock; // slot 0
  uint256 public maxRedeemPerBlock; // slot 1
}

// V2 - UNSAFE ❌
contract NaraUSD {
  uint256 public maxRedeemPerBlock; // slot 0 (moved!)
  uint256 public maxMintPerBlock; // slot 1 (moved!)
  // This will corrupt storage!
}
```

## Adding Migration Logic

If you need to migrate data or perform setup after upgrade:

### Step 1: Add a Migration Function to Your Contract

```solidity
contract NaraUSD {
  // ... existing code ...

  bool private _migrated;

  /**
   * @notice Migrate to V2 (can only be called once)
   */
  function migrateToV2() external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(!_migrated, "Already migrated");
    _migrated = true;

    // Perform migration logic here
    // e.g., update mappings, set new defaults, etc.
  }
}
```

### Step 2: Call Migration During Upgrade

```typescript
const result = await upgradeContract(hre, proxyAddress, "NaraUSD", {
  call: {
    fn: "migrateToV2",
    args: [],
  },
  log: true,
});
```

## Verifying Upgrades

### 1. Check Implementation Address

```bash
npx hardhat console --network arbitrum-sepolia
```

```javascript
const { upgrades } = require("@openzeppelin/hardhat-upgrades");
const deployment = await hre.deployments.get("NaraUSD");
const impl = await upgrades.erc1967.getImplementationAddress(
  deployment.address,
);
console.log("Implementation:", impl);
```

### 2. Verify on Block Explorer

1. Go to your proxy address on Etherscan/Arbiscan
2. Click "Contract" → "Read as Proxy"
3. Check "Implementation" address matches your new implementation

### 3. Test Contract Functions

```javascript
const naraUSD = await ethers.getContractAt("NaraUSD", proxyAddress);
const name = await naraUSD.name();
const symbol = await naraUSD.symbol();
console.log(`${name} (${symbol})`);
```

## Safety Checklist

Before upgrading on mainnet:

- [ ] ✅ Tested on testnet
- [ ] ✅ Storage layout validated (automatic via OpenZeppelin plugin)
- [ ] ✅ New implementation verified on block explorer
- [ ] ✅ All critical functions tested after upgrade
- [ ] ✅ Backup plan ready (can deploy another upgrade if needed)
- [ ] ✅ Team notified of upgrade window
- [ ] ✅ Consider pausing contract before upgrade (optional)

## Common Issues and Solutions

### Issue: "Storage layout incompatible"

**Solution**: You've changed storage layout incorrectly. Review the rules above and ensure you're only adding variables at the end.

### Issue: "Unauthorized" or "Access denied"

**Solution**: Ensure your account has `DEFAULT_ADMIN_ROLE`. Check:

```javascript
const naraUSD = await ethers.getContractAt("NaraUSD", proxyAddress);
const ADMIN_ROLE = await naraUSD.DEFAULT_ADMIN_ROLE();
const hasRole = await naraUSD.hasRole(ADMIN_ROLE, deployerAddress);
console.log("Has admin role:", hasRole);
```

### Issue: Upgrade succeeds but contract doesn't work

**Solution**:

1. Check if you need to call a migration function
2. Verify the new implementation was deployed correctly
3. Check event logs for errors

## Upgrading Other Contracts

The same process applies to all upgradeable contracts:

- `NaraUSD` → Use `upgradeContract(hre, proxyAddress, 'NaraUSD', ...)`
- `NaraUSDPlus` → Use `upgradeContract(hre, proxyAddress, 'NaraUSDPlus', ...)`
- `MultiCollateralToken` → Use `upgradeContract(hre, proxyAddress, 'MultiCollateralToken', ...)`
- `StakingRewardsDistributor` → Use `upgradeContract(hre, proxyAddress, 'StakingRewardsDistributor', ...)`
- `NaraUSDRedeemSilo` → Use `upgradeContract(hre, proxyAddress, 'NaraUSDRedeemSilo', ...)`
- `NaraUSDPlusSilo` → Use `upgradeContract(hre, proxyAddress, 'NaraUSDPlusSilo', ...)`

## Additional Resources

- [OpenZeppelin Upgrades Plugin Docs](https://docs.openzeppelin.com/upgrades-plugins/1.x/)
- [UUPS Pattern Explanation](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable)
- [Storage Layout Guide](https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable)
