# 📁 Project Structure - nUSD OVault System

Complete omnichain vault system for nUSD and StakednUSD with cross-chain functionality powered by LayerZero.

## 📊 Overview

This project contains three main modules:

1. **MCT (MultiCollateralToken)**: Multi-collateral backing for nUSD
2. **nUSD**: Omnichain stablecoin vault with minting/redeeming
3. **StakednUSD**: Staking vault for earning rewards on nUSD

---

## 🗂️ Folder Structure

```
contracts/
├── mct/                              # MultiCollateralToken Module
│   ├── MultiCollateralToken.sol     # ERC20 token accepting multiple collaterals
│   ├── MCTOFTAdapter.sol             # Hub chain OFT adapter (lockbox)
│   └── MCTOFT.sol                    # Spoke chain OFT (mint/burn)
│
├── usde/                             # nUSD Module
│   ├── nUSD.sol                      # ERC4626 vault with minting
│   ├── nUSDOFTAdapter.sol            # Hub chain OFT adapter (lockbox)
│   ├── nUSDOFT.sol                   # Spoke chain OFT (mint/burn)
│   └── nUSDComposer.sol              # Cross-chain composer
│
├── staked-usde/                      # StakednUSD Module
│   ├── StakednUSD.sol                # ERC4626 staking vault
│   ├── StakingRewardsDistributor.sol # Automated rewards distribution
│   ├── StakednUSDOFTAdapter.sol      # Hub chain OFT adapter (lockbox)
│   └── StakednUSDOFT.sol             # Spoke chain OFT (mint/burn)
│
└── interfaces/                       # Interfaces
    ├── mct/
    │   └── IMultiCollateralToken.sol
    ├── usde/
    │   └── InUSD.sol
    └── staked-usde/
        ├── IStakednUSD.sol
        └── IStakingRewardsDistributor.sol
```

---

## 📦 Module Details

### 1️⃣ MCT (MultiCollateralToken) Module

**Purpose**: Holds various stablecoins (USDC, USDT, DAI, etc.) as collateral for nUSD.

**Contracts**:

- `MultiCollateralToken.sol`: Core token managing multiple collateral types
- `MCTOFTAdapter.sol`: Hub chain bridge (lockbox model)
- `MCTOFT.sol`: Spoke chain representation (mint/burn model)

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

### 2️⃣ nUSD Module

**Purpose**: Omnichain stablecoin with integrated minting/redeeming functionality.

**Contracts**:

- `nUSD.sol`: Main ERC4626 vault (1:1 with MCT)
- `nUSDOFTAdapter.sol`: Hub chain bridge (lockbox model)
- `nUSDOFT.sol`: Spoke chain representation (mint/burn model)
- `nUSDComposer.sol`: Cross-chain operations orchestrator

**Key Features**:

- ERC4626 standard vault
- Direct collateral minting (USDC → MCT → nUSD)
- Rate limiting (maxMintPerBlock, maxRedeemPerBlock)
- Delegated signers for smart contracts
- Cross-chain transfers

**Roles**:

- `DEFAULT_ADMIN_ROLE`: Configure limits, manage roles
- `GATEKEEPER_ROLE`: Emergency disable mint/redeem

**User Flow**:

```
Deposit USDC → Mint MCT → Receive nUSD → Transfer cross-chain
```

---

### 3️⃣ StakednUSD Module

**Purpose**: Staking vault for nUSD to earn protocol rewards.

**Contracts**:

- `StakednUSD.sol`: Main ERC4626 staking vault
- `StakingRewardsDistributor.sol`: Automated rewards helper
- `StakednUSDOFTAdapter.sol`: Hub chain bridge (lockbox model)
- `StakednUSDOFT.sol`: Spoke chain representation (mint/burn model)
- `StakednUSDComposer.sol`: Cross-chain staking operations orchestrator ⭐ NEW

**Key Features**:

- ERC4626 standard vault
- 8-hour reward vesting (prevents MEV)
- Blacklist system (soft & full restrictions)
- Minimum shares protection (1 ether)
- Cross-chain snUSD transfers
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
Stake nUSD → Receive snUSD → Earn rewards → Transfer cross-chain
```

---

## 🔄 Complete User Flows

### Flow 1: Mint nUSD with Collateral (Hub Chain)

```solidity
// 1. Approve USDC to nUSD contract
usdc.approve(nusd, amount);

// 2. Mint nUSD
nusd.mintWithCollateral(usdcAddress, amount);
// Result: USDC → MCT → nUSD
```

### Flow 2: Stake nUSD for snUSD (Hub Chain)

```solidity
// 1. Approve nUSD to StakednUSD contract
nusd.approve(stakednUSD, amount);

// 2. Deposit to receive snUSD
stakednUSD.deposit(amount, userAddress);
// Result: nUSD → snUSD (earning rewards)
```

### Flow 3: Transfer snUSD Cross-Chain

```solidity
// Transfer snUSD from Hub to Spoke Chain
const sendParam = {
    dstEid: SPOKE_EID,
    to: addressToBytes32(receiver),
    amountLD: amount,
    minAmountLD: minAmount,
    extraOptions: '0x',
    composeMsg: '0x',
    oftCmd: '0x'
};

await stakedNusdOFTAdapter.send(sendParam, { value: nativeFee });
```

### Flow 4: Complete Omnichain Flow

```
User on Chain A (Spoke)
    ↓ Deposit USDC
Bridge to Hub Chain
    ↓ Mint nUSD
    ↓ Stake for snUSD
Bridge snUSD to Chain B (Spoke)
    ↓ Hold & Earn Rewards
Bridge back to Hub
    ↓ Unstake for nUSD
    ↓ Redeem for USDC
```

---

## 🚀 Deployment Order

### Hub Chain Deployment

1. **Deploy MCT**

   ```solidity
   MultiCollateralToken mct = new MultiCollateralToken(admin, [usdc, usdt, dai]);
   ```

2. **Deploy nUSD**

   ```solidity
   nUSD nusd = new nUSD(
       mct,
       admin,
       maxMintPerBlock,
       maxRedeemPerBlock
   );
   ```

3. **Grant MINTER_ROLE to nUSD**

   ```solidity
   await mct.grantRole(MINTER_ROLE, nusd.address);
   ```

4. **Deploy StakednUSD**

   ```solidity
   StakednUSD stakednUSD = new StakednUSD(
       nusd,
       rewarder,
       admin
   );
   ```

5. **Deploy StakingRewardsDistributor**

   ```solidity
   StakingRewardsDistributor distributor = new StakingRewardsDistributor(
       stakednUSD,
       nusd,
       admin,
       operator
   );
   ```

6. **Grant REWARDER_ROLE**

   ```solidity
   await stakednUSD.grantRole(REWARDER_ROLE, distributor.address);
   ```

7. **Deploy OFT Adapters (Lockbox)**

   ```solidity
   MCTOFTAdapter mctAdapter = new MCTOFTAdapter(mct, lzEndpoint, admin);
   nUSDOFTAdapter usdeAdapter = new nUSDOFTAdapter(nusd, lzEndpoint, admin);
   StakednUSDOFTAdapter stakedNusdAdapter = new StakednUSDOFTAdapter(stakednUSD, lzEndpoint, admin);
   ```

8. **Deploy Composer**
   ```solidity
   nUSDComposer composer = new nUSDComposer(nusd, mctAdapter, usdeAdapter);
   ```

### Spoke Chain Deployment

For each spoke chain:

```solidity
// 1. Deploy OFTs (Mint/Burn)
MCTOFT mctOFT = new MCTOFT(lzEndpoint, admin);
nUSDOFT nusdOFT = new nUSDOFT(lzEndpoint, admin);
StakednUSDOFT stakedNusdOFT = new StakednUSDOFT(lzEndpoint, admin);

// 2. Set peers to hub adapters
await mctOFT.setPeer(HUB_EID, addressToBytes32(mctAdapter.address));
await nusdOFT.setPeer(HUB_EID, addressToBytes32(usdeAdapter.address));
await stakedNusdOFT.setPeer(HUB_EID, addressToBytes32(stakedNusdAdapter.address));

// 3. Set peers on hub to spoke OFTs
await mctAdapter.setPeer(SPOKE_EID, addressToBytes32(mctOFT.address));
await usdeAdapter.setPeer(SPOKE_EID, addressToBytes32(nusdOFT.address));
await stakedNusdAdapter.setPeer(SPOKE_EID, addressToBytes32(stakedNusdOFT.address));
```

---

## 🔐 Security Features

### 1. Rate Limiting (nUSD)

- `maxMintPerBlock`: Limits minting per block
- `maxRedeemPerBlock`: Limits redeeming per block
- Emergency disable via `GATEKEEPER_ROLE`

### 2. Reward Vesting (StakednUSD)

- 8-hour vesting period prevents MEV attacks
- Cannot add new rewards while vesting
- Smooth reward distribution

### 3. Blacklist System (StakednUSD)

- **Soft**: Cannot stake new funds
- **Full**: Cannot transfer/stake/unstake
- Admin can redistribute locked funds

### 4. Minimum Shares Protection

- nUSD: Prevents donation attacks
- StakednUSD: 1 ether minimum

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
| nUSD                      | nUSD       | Core Vault    |
| nUSDOFTAdapter            | nUSD       | Hub Bridge    |
| nUSDOFT                   | nUSD       | Spoke Token   |
| nUSDComposer              | nUSD       | Composer      |
| StakednUSD                | StakednUSD | Staking Vault |
| StakingRewardsDistributor | StakednUSD | Helper        |
| StakednUSDOFTAdapter      | StakednUSD | Hub Bridge    |
| StakednUSDOFT             | StakednUSD | Spoke Token   |

---

## 📖 Documentation

- **nUSD Integration**: See `OVAULT_INTEGRATION.md`
- **StakednUSD Details**: See `STAKED_NUSD_INTEGRATION.md`
- **Deployment Summary**: See `DEPLOYMENT_SUMMARY.md`
- **Example Usage**: See `examples/nUSD.usage.ts`
- **Example Deploy**: See `deploy/nUSD.example.ts`

---

## ✅ Key Improvements Over Original

| Feature      | Original             | OVault Version         |
| ------------ | -------------------- | ---------------------- |
| Contracts    | nUSD + EthenaMinting | nUSD (merged)          |
| Cross-chain  | No                   | Full LayerZero support |
| Architecture | Single chain         | Hub-and-spoke          |
| Staking      | StakednUSD only      | + Cross-chain snUSD    |
| Collateral   | Single in minting    | Multi-collateral (MCT) |
| Solidity     | 0.8.20               | ^0.8.22                |
| OpenZeppelin | 4.x                  | 5.x                    |

---

## 🎯 Testing Checklist

- [ ] MCT: Add/remove supported assets
- [ ] MCT: Mint/burn with different collaterals
- [ ] MCT: Withdraw/deposit collateral
- [ ] nUSD: Mint with collateral (USDC, USDT, DAI)
- [ ] nUSD: Redeem for collateral
- [ ] nUSD: Rate limiting
- [ ] nUSD: Delegated signers
- [ ] nUSD: Cross-chain transfers
- [ ] StakednUSD: Stake/unstake
- [ ] StakednUSD: Reward vesting
- [ ] StakednUSD: Blacklist functionality
- [ ] StakednUSD: Cross-chain snUSD
- [ ] StakingRewardsDistributor: Transfer rewards
- [ ] nUSDComposer: Cross-chain deposit
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
