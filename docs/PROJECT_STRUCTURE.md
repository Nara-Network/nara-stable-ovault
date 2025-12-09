# 📁 Project Structure - naraUSD OVault System

Complete omnichain vault system for naraUSD and NaraUSDPlus with cross-chain functionality powered by LayerZero.

## 📊 Overview

This project contains three main modules:

1. **MCT (MultiCollateralToken)**: Multi-collateral backing for naraUSD
2. **naraUSD**: Omnichain stablecoin vault with minting/redeeming
3. **NaraUSDPlus**: Staking vault for earning rewards on naraUSD

---

## 🗂️ Folder Structure

```
contracts/
├── mct/                              # MultiCollateralToken Module
│   ├── MultiCollateralToken.sol     # ERC20 token accepting multiple collaterals
│   └── MCTOFTAdapter.sol             # Hub chain OFT adapter (validation only - NOT for cross-chain!)
│
├── narausd/                             # naraUSD Module
│   ├── naraUSD.sol                      # ERC4626 vault with minting
│   ├── NaraUSDOFTAdapter.sol            # Hub chain OFT adapter (lockbox)
│   ├── NaraUSDOFT.sol                   # Spoke chain OFT (mint/burn)
│   └── NaraUSDComposer.sol              # Cross-chain composer
│
├── narausd-plus/                        # NaraUSDPlus Module
│   ├── NaraUSDPlus.sol                  # ERC4626 staking vault
│   ├── StakingRewardsDistributor.sol     # Automated rewards distribution
│   ├── NaraUSDPlusOFTAdapter.sol        # Hub chain OFT adapter (lockbox)
│   └── NaraUSDPlusOFT.sol               # Spoke chain OFT (mint/burn)
│
└── interfaces/                       # Interfaces
    ├── mct/
    │   └── IMultiCollateralToken.sol
    ├── narausd/
    │   └── InaraUSD.sol
    └── narausd-plus/
        ├── INaraUSDPlus.sol
        └── IStakingRewardsDistributor.sol
```

---

## 📦 Module Details

### 1️⃣ MCT (MultiCollateralToken) Module

**Purpose**: Holds various stablecoins (USDC, USDT, DAI, etc.) as collateral for naraUSD.

**Contracts**:

- `MultiCollateralToken.sol`: Core token managing multiple collateral types
- `MCTOFTAdapter.sol`: Hub-only adapter for validation (NOT used for cross-chain transfers)

**Important**: MCT is HUB-ONLY and does NOT go cross-chain. See `MCT_ARCHITECTURE.md` for details.

**Key Features**:

- Multi-collateral support (USDC, USDT, DAI, etc.)
- Decimal normalization (all collateral → 18 decimals)
- Collateral management by team
- Role-based access control

**Roles**:

- `DEFAULT_ADMIN_ROLE`: Add/remove supported assets
- `MINTER_ROLE`: Mint/burn MCT tokens
- `COLLATERAL_MANAGER_ROLE`: Withdraw/deposit collateral

---

### 2️⃣ naraUSD Module

**Purpose**: Omnichain stablecoin with integrated minting/redeeming functionality.

**Contracts**:

- `naraUSD.sol`: Main ERC4626 vault (1:1 with MCT)
- `NaraUSDOFTAdapter.sol`: Hub chain bridge (lockbox model)
- `NaraUSDOFT.sol`: Spoke chain representation (mint/burn model)
- `NaraUSDComposer.sol`: Cross-chain operations orchestrator

**Key Features**:

- ERC4626 standard vault
- Direct collateral minting (USDC → MCT → naraUSD)
- Rate limiting (maxMintPerBlock, maxRedeemPerBlock)
- Delegated signers for smart contracts
- Cross-chain transfers

**Roles**:

- `DEFAULT_ADMIN_ROLE`: Configure limits, manage roles
- `GATEKEEPER_ROLE`: Emergency disable mint/redeem

**User Flow**:

```
Deposit USDC → Mint MCT → Receive naraUSD → Transfer cross-chain
```

---

### 3️⃣ NaraUSDPlus Module

**Purpose**: Staking vault for naraUSD to earn protocol rewards.

**Contracts**:

- `NaraUSDPlus.sol`: Main ERC4626 staking vault
- `StakingRewardsDistributor.sol`: Automated rewards helper
- `NaraUSDPlusOFTAdapter.sol`: Hub chain bridge (lockbox model)
- `NaraUSDPlusOFT.sol`: Spoke chain representation (mint/burn model)
- `NaraUSDPlusComposer.sol`: Cross-chain staking operations orchestrator ⭐ NEW

**Key Features**:

- ERC4626 standard vault
- 8-hour reward vesting (prevents MEV)
- Blacklist system (full restriction)
- Minimum shares protection (1 ether)
- Cross-chain naraUSD+ transfers
- **Cross-chain staking from any spoke chain** ⭐ NEW (mirrors Ethena)
- Automated rewards distribution

**Roles**:

- `DEFAULT_ADMIN_ROLE`: Manage all roles, rescue tokens
- `REWARDER_ROLE`: Transfer rewards to vault
- `BLACKLIST_MANAGER_ROLE`: Manage blacklist
- `FULL_RESTRICTED_STAKER_ROLE`: Cannot transfer/stake/unstake

**User Flow**:

```
Stake naraUSD → Receive naraUSD+ → Earn rewards → Transfer cross-chain
```

---

## 🔄 Complete User Flows

### Flow 1: Mint naraUSD with Collateral (Hub Chain)

```solidity
// 1. Approve USDC to naraUSD contract
usdc.approve(narausd, amount);

// 2. Mint naraUSD
narausd.mintWithCollateral(usdcAddress, amount);
// Result: USDC → MCT → naraUSD
```

### Flow 2: Stake naraUSD for naraUSD+ (Hub Chain)

```solidity
// 1. Approve naraUSD to NaraUSDPlus contract
narausd.approve(naraUSDPlus, amount);

// 2. Deposit to receive naraUSD+
naraUSDPlus.deposit(amount, userAddress);
// Result: naraUSD → naraUSD+ (earning rewards)
```

### Flow 3: Transfer naraUSD+ Cross-Chain

```solidity
// Transfer naraUSD+ from Hub to Spoke Chain
const sendParam = {
    dstEid: SPOKE_EID,
    to: addressToBytes32(receiver),
    amountLD: amount,
    minAmountLD: minAmount,
    extraOptions: '0x',
    composeMsg: '0x',
    oftCmd: '0x'
};

await naraUSDPlusOFTAdapter.send(sendParam, { value: nativeFee });
```

### Flow 4: Complete Omnichain Flow

```
User on Chain A (Spoke)
    ↓ Deposit USDC
Bridge to Hub Chain
    ↓ Mint naraUSD
    ↓ Stake for naraUSD+
Bridge naraUSD+ to Chain B (Spoke)
    ↓ Hold & Earn Rewards
Bridge back to Hub
    ↓ Unstake for naraUSD
    ↓ Redeem for USDC
```

---

## 🚀 Deployment Order

### Hub Chain Deployment

1. **Deploy MCT**

   ```solidity
   MultiCollateralToken mct = new MultiCollateralToken(admin, [usdc, usdt, dai]);
   ```

2. **Deploy naraUSD**

   ```solidity
   naraUSD narausd = new naraUSD(
       mct,
       admin,
       maxMintPerBlock,
       maxRedeemPerBlock
   );
   ```

3. **Grant MINTER_ROLE to naraUSD**

   ```solidity
   await mct.grantRole(MINTER_ROLE, narausd.address);
   ```

4. **Deploy NaraUSDPlus**

   ```solidity
   NaraUSDPlus naraUSDPlus = new NaraUSDPlus(
       narausd,
       rewarder,
       admin
   );
   ```

5. **Deploy StakingRewardsDistributor**

   ```solidity
   StakingRewardsDistributor distributor = new StakingRewardsDistributor(
       naraUSDPlus,
       narausd,
       admin,
       operator
   );
   ```

6. **Grant REWARDER_ROLE**

   ```solidity
   await naraUSDPlus.grantRole(REWARDER_ROLE, distributor.address);
   ```

7. **Deploy OFT Adapters (Lockbox)**

   ```solidity
   // MCTOFTAdapter (validation only - NOT wired to spoke chains!)
   MCTOFTAdapter mctAdapter = new MCTOFTAdapter(mct, lzEndpoint, admin);

   // Actual cross-chain adapters
   NaraUSDOFTAdapter narausdAdapter = new NaraUSDOFTAdapter(narausd, lzEndpoint, admin);
   NaraUSDPlusOFTAdapter naraUSDPlusAdapter = new NaraUSDPlusOFTAdapter(naraUSDPlus, lzEndpoint, admin);
   ```

8. **Deploy Composer**
   ```solidity
   NaraUSDComposer composer = new NaraUSDComposer(narausd, mctAdapter, narausdAdapter);
   ```

### Spoke Chain Deployment

For each spoke chain:

```solidity
// 1. Deploy OFTs (Mint/Burn) - NOTE: NO MCTOFT! MCT is hub-only
NaraUSDOFT narausdOFT = new NaraUSDOFT(lzEndpoint, admin);
NaraUSDPlusOFT naraUSDPlusOFT = new NaraUSDPlusOFT(lzEndpoint, admin);

// 2. Set peers to hub adapters
await mctOFT.setPeer(HUB_EID, addressToBytes32(mctAdapter.address));
await narausdOFT.setPeer(HUB_EID, addressToBytes32(narausdAdapter.address));
await naraUSDPlusOFT.setPeer(HUB_EID, addressToBytes32(naraUSDPlusAdapter.address));

// 3. Set peers on hub to spoke OFTs
await mctAdapter.setPeer(SPOKE_EID, addressToBytes32(mctOFT.address));
await narausdAdapter.setPeer(SPOKE_EID, addressToBytes32(narausdOFT.address));
await naraUSDPlusAdapter.setPeer(SPOKE_EID, addressToBytes32(naraUSDPlusOFT.address));
```

---

## 🔐 Security Features

### 1. Rate Limiting (naraUSD)

- `maxMintPerBlock`: Limits minting per block
- `maxRedeemPerBlock`: Limits redeeming per block
- Emergency disable via `GATEKEEPER_ROLE`

### 2. Reward Vesting (NaraUSDPlus)

- 8-hour vesting period prevents MEV attacks
- Cannot add new rewards while vesting
- Smooth reward distribution

### 3. Blacklist System

- **naraUSD**: Full restriction prevents all transfers, minting, and redemptions
- **NaraUSDPlus**: Full restriction prevents all transfers, staking, and unstaking
- **OFT Contracts**: Full restriction prevents transfers on spoke chains (NaraUSDOFT, NaraUSDPlusOFT)
- Admin can redistribute locked funds

### 4. Minimum Shares Protection

- naraUSD: Prevents donation attacks
- NaraUSDPlus: 1 ether minimum

### 5. Access Control

- Role-based permissions
- Cannot renounce critical roles
- Multi-signature recommended for admins

---

## 📊 Contract Sizes

All contracts compile successfully with Solidity ^0.8.22:

| Contract                  | Module        | Type                                   |
| ------------------------- | ------------- | -------------------------------------- |
| MultiCollateralToken      | MCT           | Core Token                             |
| MCTOFTAdapter             | MCT           | Hub Validation Only (NOT cross-chain!) |
| naraUSD                   | naraUSD       | Core Vault                             |
| NaraUSDOFTAdapter         | naraUSD       | Hub Bridge                             |
| NaraUSDOFT                | naraUSD       | Spoke Token                            |
| NaraUSDComposer           | naraUSD       | Composer                               |
| NaraUSDPlus             | NaraUSDPlus | Staking Vault                          |
| StakingRewardsDistributor | NaraUSDPlus | Helper                                 |
| NaraUSDPlusOFTAdapter   | NaraUSDPlus | Hub Bridge                             |
| NaraUSDPlusOFT          | NaraUSDPlus | Spoke Token                            |

---

## 📖 Documentation

- **naraUSD Integration**: See `OVAULT_INTEGRATION.md`
- **NaraUSDPlus Details**: See `STAKED_NARAUSD_INTEGRATION.md`
- **Deployment Summary**: See `DEPLOYMENT_SUMMARY.md`

---

## ✅ Key Improvements Over Original

| Feature      | Original                | OVault Version         |
| ------------ | ----------------------- | ---------------------- |
| Contracts    | naraUSD + EthenaMinting | naraUSD (merged)       |
| Cross-chain  | No                      | Full LayerZero support |
| Architecture | Single chain            | Hub-and-spoke          |
| Staking      | NaraUSDPlus only      | + Cross-chain naraUSD+ |
| Collateral   | Single in minting       | Multi-collateral (MCT) |
| Solidity     | 0.8.20                  | ^0.8.22                |
| OpenZeppelin | 4.x                     | 5.x                    |

---

## 🎯 Testing Checklist

- [ ] MCT: Add/remove supported assets
- [ ] MCT: Mint/burn with different collaterals
- [ ] MCT: Withdraw/deposit collateral
- [ ] naraUSD: Mint with collateral (USDC, USDT, DAI)
- [ ] naraUSD: Redeem for collateral
- [ ] naraUSD: Rate limiting
- [ ] naraUSD: Delegated signers
- [ ] naraUSD: Cross-chain transfers
- [ ] NaraUSDPlus: Stake/unstake
- [ ] NaraUSDPlus: Reward vesting
- [ ] NaraUSDPlus: Blacklist functionality
- [ ] NaraUSDPlus: Cross-chain naraUSD+
- [ ] StakingRewardsDistributor: Transfer rewards
- [ ] NaraUSDComposer: Cross-chain deposit
- [ ] All: Emergency functions

---

## 📝 License

GPL-3.0

---

**Status**: ✅ All contracts compiled successfully  
**Last Updated**: 2025-10-20  
**Solidity Version**: ^0.8.22  
**OpenZeppelin**: 5.x  
**LayerZero**: Latest
