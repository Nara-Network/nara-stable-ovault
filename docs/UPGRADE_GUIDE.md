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

The upgrade script (`deploy/UpgradeNaraUSD.example.ts`) uses tags to ensure it only runs when explicitly requested. This prevents accidental upgrades during regular deployments.

**Usage Options:**

- **Recommended**: `npx hardhat deploy --tags UpgradeNaraUSD` (uses hardhat-deploy tags)
- **Alternative**: `npx hardhat run deploy/UpgradeNaraUSD.example.ts` (direct script execution)

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
# Using hardhat-deploy (recommended):
npx hardhat deploy --network arbitrum-sepolia --tags UpgradeNaraUSD

# Or using hardhat run:
npx hardhat run deploy/UpgradeNaraUSD.example.ts --network arbitrum-sepolia
```

#### Step 4: Validate the Upgrade (Dry Run)

The upgrade script automatically validates storage compatibility. If validation fails, you'll see an error like:

```
Error: New storage layout is incompatible
```

#### Step 5: Execute the Upgrade

```bash
# For mainnet (be careful!)
# Using hardhat-deploy (recommended):
npx hardhat deploy --network arbitrum --tags UpgradeNaraUSD

# Or using hardhat run:
npx hardhat run deploy/UpgradeNaraUSD.example.ts --network arbitrum
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
const { upgrades } = await import("hardhat");
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
import { type HardhatRuntimeEnvironment } from "hardhat/types";
import { type DeployFunction } from "hardhat-deploy/types";
import { upgradeContract } from "../devtools/utils";

const upgradeNaraUSDV2: DeployFunction = async (
  hre: HardhatRuntimeEnvironment,
) => {
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
};

export default upgradeNaraUSDV2;
upgradeNaraUSDV2.tags = ["UpgradeNaraUSD", "Upgrade"];
```

Run it:

```bash
# Using hardhat-deploy (recommended):
npx hardhat deploy --network arbitrum-sepolia --tags UpgradeNaraUSD

# Or using hardhat run:
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
const { upgrades } = await import("hardhat");
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
const naraUsd = await ethers.getContractAt("NaraUSD", proxyAddress);
const name = await naraUsd.name();
const symbol = await naraUsd.symbol();
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
const naraUsd = await ethers.getContractAt("NaraUSD", proxyAddress);
const ADMIN_ROLE = await naraUsd.DEFAULT_ADMIN_ROLE();
const hasRole = await naraUsd.hasRole(ADMIN_ROLE, deployerAddress);
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

## Managing Multiple Upgrades Over Time

For projects that will have multiple upgrades, it's important to maintain a clear history and be able to run specific upgrades when needed.

### Recommended Approach: Versioned Upgrade Scripts

**Structure:**

```
deploy/
└── upgrades/
    ├── templates/
    │   ├── UpgradeNaraUSD.example.ts          # Template (never run directly)
    │   └── UpgradeNaraUSD.v2.example.ts       # Example of versioned script
    ├── UpgradeNaraUSD.v2.ts                   # Actual V2 upgrade (when needed)
    ├── UpgradeNaraUSD.v3.ts                   # Actual V3 upgrade (when needed)
    └── ...
```

**Key Principles:**

1. **Keep the example as a template** - `UpgradeNaraUSD.example.ts` is for reference only
2. **Create versioned files for each upgrade** - `UpgradeNaraUSD.v2.ts`, `UpgradeNaraUSD.v3.ts`, etc.
3. **Use versioned tags** - `UpgradeNaraUSD-V2`, `UpgradeNaraUSD-V3`, etc.
4. **Document what changed** - Each upgrade script should clearly document what it does
5. **Test before mainnet** - Always test on testnet first

### Creating a New Upgrade Script

#### Step 1: Copy the Template

```bash
cp deploy/upgrades/templates/UpgradeNaraUSD.v2.example.ts deploy/upgrades/UpgradeNaraUSD.v2.ts
```

#### Step 2: Update the Header

Document what this upgrade does:

```typescript
/**
 * Upgrade NaraUSD Contract to V2
 *
 * Upgrade V2 Changes:
 * - Added new function: setMaxDailyMint(uint256 amount)
 * - Fixed bug: Fee calculation overflow issue
 * - Migration: Call migrateToV2() to initialize new state variables
 *
 * Date: 2024-01-15
 * Author: Your Name
 */
```

#### Step 3: Uncomment and Update Tags

⚠️ **IMPORTANT**: The example files have tags commented out. You MUST uncomment and update them:

```typescript
// ⚠️ IMPORTANT: Uncomment and update the tags below!
// Change 'UpgradeNaraUSD-V2' to match your version (V3, V4, etc.)
upgradeNaraUSDV2.tags = ["UpgradeNaraUSD-V2", "Upgrade", "NaraUSD"];
```

#### Step 4: Add Migration Logic (if needed)

If your upgrade requires migration:

```typescript
const result = await upgradeContract(hre, proxyAddress, "NaraUSD", {
  call: {
    fn: "migrateToV2",
    args: [],
  },
  log: true,
});
```

#### Step 5: Test on Testnet

```bash
npx hardhat deploy --network arbitrum-sepolia --tags UpgradeNaraUSD-V2
```

#### Step 6: Deploy to Mainnet

```bash
npx hardhat deploy --network arbitrum --tags UpgradeNaraUSD-V2
```

### Tag Strategy

**Recommended: Versioned Tags**

Use versioned tags for clarity and safety:

```typescript
upgradeNaraUSDV2.tags = ["UpgradeNaraUSD-V2", "Upgrade", "NaraUSD"];
```

**Usage:**

```bash
# Run specific version
npx hardhat deploy --tags UpgradeNaraUSD-V2

# Run all upgrades (rare)
npx hardhat deploy --tags Upgrade
```

**Why versioned tags?**

- Clear versioning
- Can run specific upgrades
- Easy to track which upgrade ran
- Prevents accidental execution of wrong upgrade

### Upgrade History Tracking

Document upgrades in each script header:

```typescript
/**
 * Upgrade History:
 * - V1: Initial deployment (2024-01-01)
 * - V2: Added maxDailyMint (2024-01-15) <- Current
 * - V3: Fixed fee calculation (planned)
 */
```

Or maintain a separate `docs/UPGRADE_HISTORY.md` file with all upgrade records.

### Example Workflow

**First Upgrade (V2):**

1. Make contract changes
2. Compile: `pnpm compile:hardhat`
3. Create script: `cp deploy/upgrades/templates/UpgradeNaraUSD.v2.example.ts deploy/upgrades/UpgradeNaraUSD.v2.ts`
4. Update script header with changes
5. **Uncomment and update tags** (change V2 to your version)
6. Test: `npx hardhat deploy --network arbitrum-sepolia --tags UpgradeNaraUSD-V2`
7. Deploy: `npx hardhat deploy --network arbitrum --tags UpgradeNaraUSD-V2`

**Second Upgrade (V3):**

1. Make contract changes
2. Compile: `pnpm compile:hardhat`
3. Create script: `cp deploy/upgrades/templates/UpgradeNaraUSD.v2.example.ts deploy/upgrades/UpgradeNaraUSD.v3.ts`
4. Update script (change V2 → V3, update tags, document changes)
5. Test: `npx hardhat deploy --network arbitrum-sepolia --tags UpgradeNaraUSD-V3`
6. Deploy: `npx hardhat deploy --network arbitrum --tags UpgradeNaraUSD-V3`

### Best Practices Summary

1. ✅ **Never run the example script directly** - It's a template only
2. ✅ **Create versioned files** - `UpgradeNaraUSD.v2.ts`, `UpgradeNaraUSD.v3.ts`, etc.
3. ✅ **Use versioned tags** - `UpgradeNaraUSD-V2`, `UpgradeNaraUSD-V3`
4. ✅ **Uncomment tags in your actual upgrade scripts** - Example files have tags commented out
5. ✅ **Document changes** - Clear header comments explaining what changed
6. ✅ **Test on testnet first** - Always validate before mainnet
7. ✅ **Keep upgrade history** - Track all upgrades in documentation
8. ✅ **One script per upgrade** - Don't modify old upgrade scripts

## Additional Resources

- [OpenZeppelin Upgrades Plugin Docs](https://docs.openzeppelin.com/upgrades-plugins/1.x/)
- [UUPS Pattern Explanation](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable)
- [Storage Layout Guide](https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable)
