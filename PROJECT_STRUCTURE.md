# 📁 Project Structure - USDe OVault System

Complete omnichain vault system for USDe and StakedUSDe with cross-chain functionality powered by LayerZero.

## 📊 Overview

This project contains three main modules:

1. **MCT (MultiCollateralToken)**: Multi-collateral backing for USDe
2. **USDe**: Omnichain stablecoin vault with minting/redeeming
3. **StakedUSDe**: Staking vault for earning rewards on USDe

---

## 🗂️ Folder Structure

```
contracts/
├── mct/                              # MultiCollateralToken Module
│   ├── MultiCollateralToken.sol     # ERC20 token accepting multiple collaterals
│   └── (no adapter)                  # MCT is hub-only; no OFT adapter
│
├── usde/                             # USDe Module
│   ├── USDe.sol                      # ERC4626 vault with minting
│   ├── USDeOFTAdapter.sol            # Hub chain OFT adapter (lockbox)
│   ├── USDeOFT.sol                   # Spoke chain OFT (mint/burn)
│   └── USDeComposer.sol              # Cross-chain composer
│
├── staked-usde/                      # StakedUSDe Module
│   ├── StakedUSDe.sol                # ERC4626 staking vault
│   ├── StakingRewardsDistributor.sol # Automated rewards distribution
│   ├── StakedUSDeOFTAdapter.sol      # Hub chain OFT adapter (lockbox)
│   └── StakedUSDeOFT.sol             # Spoke chain OFT (mint/burn)
│
└── interfaces/                       # Interfaces
    ├── mct/
    │   └── IMultiCollateralToken.sol
    ├── usde/
    │   └── IUSDe.sol
    └── staked-usde/
        ├── IStakedUSDe.sol
        └── IStakingRewardsDistributor.sol
```

---

## 📦 Module Details

### 1️⃣ MCT (MultiCollateralToken) Module

**Purpose**: Holds various stablecoins (USDC, USDT, DAI, etc.) as collateral for USDe.

**Contracts**:

- `MultiCollateralToken.sol`: Core token managing multiple collateral types
  // Note: MCT is hub-only in this setup. Cross-chain MCT is disabled.

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

### 2️⃣ USDe Module

**Purpose**: Omnichain stablecoin with integrated minting/redeeming functionality.

**Contracts**:

- `USDe.sol`: Main ERC4626 vault (1:1 with MCT)
- `USDeOFTAdapter.sol`: Hub chain bridge (lockbox model)
- `USDeOFT.sol`: Spoke chain representation (mint/burn model)
- `USDeComposer.sol`: Cross-chain operations orchestrator

**Key Features**:

- ERC4626 standard vault
- Direct collateral minting (USDC → MCT → USDe)
- Rate limiting (maxMintPerBlock, maxRedeemPerBlock)
- Delegated signers for smart contracts
- Cross-chain transfers

**Roles**:

- `DEFAULT_ADMIN_ROLE`: Configure limits, manage roles
- `GATEKEEPER_ROLE`: Emergency disable mint/redeem

**User Flow**:

```
Deposit USDC → Mint MCT → Receive USDe → Transfer cross-chain
```

---

### 3️⃣ StakedUSDe Module

**Purpose**: Staking vault for USDe to earn protocol rewards.

**Contracts**:

- `StakedUSDe.sol`: Main ERC4626 staking vault
- `StakingRewardsDistributor.sol`: Automated rewards helper
- `StakedUSDeOFTAdapter.sol`: Hub chain bridge (lockbox model)
- `StakedUSDeOFT.sol`: Spoke chain representation (mint/burn model)
- `StakedUSDeComposer.sol`: Cross-chain staking operations orchestrator ⭐ NEW

**Key Features**:

- ERC4626 standard vault
- 8-hour reward vesting (prevents MEV)
- Blacklist system (soft & full restrictions)
- Minimum shares protection (1 ether)
- Cross-chain sUSDe transfers
- **Cross-chain staking from any spoke chain** ⭐ NEW (mirrors Ethena)
- Automated rewards distribution

**Roles**:

- `DEFAULT_ADMIN_ROLE`: Manage all roles, rescue tokens
- `REWARDER_ROLE`: Transfer rewards to vault
- `BLACKLIST_MANAGER_ROLE`: Manage blacklist
- `SOFT_RESTRICTED_STAKER_ROLE`: Cannot stake
- `FULL_RESTRICTED_STAKER_ROLE`: Cannot transfer/stake/unstake

**User Flow**:

```
Stake USDe → Receive sUSDe → Earn rewards → Transfer cross-chain
```

---

## 🔄 Complete User Flows

### Flow 1: Mint USDe with Collateral (Hub Chain)

```solidity
// 1. Approve USDC to USDe contract
usdc.approve(usde, amount);

// 2. Mint USDe
usde.mintWithCollateral(usdcAddress, amount);
// Result: USDC → MCT → USDe
```

### Flow 2: Stake USDe for sUSDe (Hub Chain)

```solidity
// 1. Approve USDe to StakedUSDe contract
usde.approve(stakedUSDe, amount);

// 2. Deposit to receive sUSDe
stakedUSDe.deposit(amount, userAddress);
// Result: USDe → sUSDe (earning rewards)
```

### Flow 3: Transfer sUSDe Cross-Chain

```solidity
// Transfer sUSDe from Hub to Spoke Chain
const sendParam = {
    dstEid: SPOKE_EID,
    to: addressToBytes32(receiver),
    amountLD: amount,
    minAmountLD: minAmount,
    extraOptions: '0x',
    composeMsg: '0x',
    oftCmd: '0x'
};

await sUsdeOFTAdapter.send(sendParam, { value: nativeFee });
```

### Flow 4: Complete Omnichain Flow

```
User on Chain A (Spoke)
    ↓ Deposit USDC
Bridge to Hub Chain
    ↓ Mint USDe
    ↓ Stake for sUSDe
Bridge sUSDe to Chain B (Spoke)
    ↓ Hold & Earn Rewards
Bridge back to Hub
    ↓ Unstake for USDe
    ↓ Redeem for USDC
```

---

## 🚀 Deployment Order

### Hub Chain Deployment

1. **Deploy MCT**

   ```solidity
   MultiCollateralToken mct = new MultiCollateralToken(admin, [usdc, usdt, dai]);
   ```

2. **Deploy USDe**

   ```solidity
   USDe usde = new USDe(
       mct,
       admin,
       maxMintPerBlock,
       maxRedeemPerBlock
   );
   ```

3. **Grant MINTER_ROLE to USDe**

   ```solidity
   await mct.grantRole(MINTER_ROLE, usde.address);
   ```

4. **Deploy StakedUSDe**

   ```solidity
   StakedUSDe stakedUSDe = new StakedUSDe(
       usde,
       rewarder,
       admin
   );
   ```

5. **Deploy StakingRewardsDistributor**

   ```solidity
   StakingRewardsDistributor distributor = new StakingRewardsDistributor(
       stakedUSDe,
       usde,
       admin,
       operator
   );
   ```

6. **Grant REWARDER_ROLE**

   ```solidity
   await stakedUSDe.grantRole(REWARDER_ROLE, distributor.address);
   ```

7. **Deploy OFT Adapters (Lockbox)**

   ```solidity
   MCTOFTAdapter mctAdapter = new MCTOFTAdapter(mct, lzEndpoint, admin);
   USDeOFTAdapter usdeAdapter = new USDeOFTAdapter(usde, lzEndpoint, admin);
   StakedUSDeOFTAdapter sUsdeAdapter = new StakedUSDeOFTAdapter(stakedUSDe, lzEndpoint, admin);
   ```

8. **Deploy Composer**
   ```solidity
   USDeComposer composer = new USDeComposer(usde, mctAdapter, usdeAdapter);
   ```

### Spoke Chain Deployment

For each spoke chain:

```solidity
// 1. Deploy OFTs (Mint/Burn)
MCTOFT mctOFT = new MCTOFT(lzEndpoint, admin);
USDeOFT usdeOFT = new USDeOFT(lzEndpoint, admin);
StakedUSDeOFT sUsdeOFT = new StakedUSDeOFT(lzEndpoint, admin);

// 2. Set peers to hub adapters
await mctOFT.setPeer(HUB_EID, addressToBytes32(mctAdapter.address));
await usdeOFT.setPeer(HUB_EID, addressToBytes32(usdeAdapter.address));
await sUsdeOFT.setPeer(HUB_EID, addressToBytes32(sUsdeAdapter.address));

// 3. Set peers on hub to spoke OFTs
await mctAdapter.setPeer(SPOKE_EID, addressToBytes32(mctOFT.address));
await usdeAdapter.setPeer(SPOKE_EID, addressToBytes32(usdeOFT.address));
await sUsdeAdapter.setPeer(SPOKE_EID, addressToBytes32(sUsdeOFT.address));
```

---

## 🔐 Security Features

### 1. Rate Limiting (USDe)

- `maxMintPerBlock`: Limits minting per block
- `maxRedeemPerBlock`: Limits redeeming per block
- Emergency disable via `GATEKEEPER_ROLE`

### 2. Reward Vesting (StakedUSDe)

- 8-hour vesting period prevents MEV attacks
- Cannot add new rewards while vesting
- Smooth reward distribution

### 3. Blacklist System (StakedUSDe)

- **Soft**: Cannot stake new funds
- **Full**: Cannot transfer/stake/unstake
- Admin can redistribute locked funds

### 4. Minimum Shares Protection

- USDe: Prevents donation attacks
- StakedUSDe: 1 ether minimum

### 5. Access Control

- Role-based permissions
- Cannot renounce critical roles
- Multi-signature recommended for admins

---

## 📊 Contract Sizes

All contracts compile successfully with Solidity ^0.8.22:

| Contract                  | Module     | Type          |
| ------------------------- | ---------- | ------------- |
| MultiCollateralToken      | MCT        | Core Token    |
| MCTOFTAdapter             | MCT        | Hub Bridge    |
| MCTOFT                    | MCT        | Spoke Token   |
| USDe                      | USDe       | Core Vault    |
| USDeOFTAdapter            | USDe       | Hub Bridge    |
| USDeOFT                   | USDe       | Spoke Token   |
| USDeComposer              | USDe       | Composer      |
| StakedUSDe                | StakedUSDe | Staking Vault |
| StakingRewardsDistributor | StakedUSDe | Helper        |
| StakedUSDeOFTAdapter      | StakedUSDe | Hub Bridge    |
| StakedUSDeOFT             | StakedUSDe | Spoke Token   |

---

## 📖 Documentation

- **USDe Integration**: See `OVAULT_INTEGRATION.md`
- **StakedUSDe Details**: See `STAKED_USDE_INTEGRATION.md`
- **Deployment Summary**: See `DEPLOYMENT_SUMMARY.md`
- **Example Usage**: See `examples/USDe.usage.ts`
- **Example Deploy**: See `deploy/USDe.example.ts`

---

## ✅ Key Improvements Over Original

| Feature      | Original             | OVault Version         |
| ------------ | -------------------- | ---------------------- |
| Contracts    | USDe + EthenaMinting | USDe (merged)          |
| Cross-chain  | No                   | Full LayerZero support |
| Architecture | Single chain         | Hub-and-spoke          |
| Staking      | StakedUSDe only      | + Cross-chain sUSDe    |
| Collateral   | Single in minting    | Multi-collateral (MCT) |
| Solidity     | 0.8.20               | ^0.8.22                |
| OpenZeppelin | 4.x                  | 5.x                    |

---

## 🎯 Testing Checklist

- [ ] MCT: Add/remove supported assets
- [ ] MCT: Mint/burn with different collaterals
- [ ] MCT: Withdraw/deposit collateral
- [ ] USDe: Mint with collateral (USDC, USDT, DAI)
- [ ] USDe: Redeem for collateral
- [ ] USDe: Rate limiting
- [ ] USDe: Delegated signers
- [ ] USDe: Cross-chain transfers
- [ ] StakedUSDe: Stake/unstake
- [ ] StakedUSDe: Reward vesting
- [ ] StakedUSDe: Blacklist functionality
- [ ] StakedUSDe: Cross-chain sUSDe
- [ ] StakingRewardsDistributor: Transfer rewards
- [ ] USDeComposer: Cross-chain deposit
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
