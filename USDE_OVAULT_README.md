# USDe OVault Implementation

This document describes the OVault (Omnichain Vault) version of the USDe and EthenaMinting contracts.

## Overview

The USDe OVault implementation combines the functionality of USDe and EthenaMinting into a single ERC4626-compliant vault with integrated minting capabilities. The architecture uses a multi-collateral approach with a two-token system:

1. **MultiCollateralToken (MCT)**: The underlying asset that accepts multiple collateral types
2. **USDe**: The ERC4626 vault that issues USDe shares backed by MCT at a 1:1 ratio

## Architecture

### MultiCollateralToken (MCT)

The MCT contract serves as the underlying asset for the USDe vault. It has the following characteristics:

- **Multi-Collateral Support**: Can accept various stablecoins (USDC, USDT, DAI, etc.)
- **Team Management**: Collateral can be withdrawn by authorized team members for management and redeposited
- **Decimal Normalization**: All collateral is normalized to 18 decimals when converting to MCT
- **Access Control**: Uses OpenZeppelin's AccessControl for role-based permissions

#### Key Functions

```solidity
// Mint MCT by depositing collateral (called by USDe)
function mint(address collateralAsset, uint256 collateralAmount, address beneficiary)
    external returns (uint256 mctAmount)

// Redeem MCT for collateral (called by USDe)
function redeem(address collateralAsset, uint256 mctAmount, address beneficiary)
    external returns (uint256 collateralAmount)

// Withdraw collateral for team management
function withdrawCollateral(address asset, uint256 amount, address to) external

// Deposit collateral back from team management
function depositCollateral(address asset, uint256 amount) external

// Add/remove supported assets
function addSupportedAsset(address asset) external
function removeSupportedAsset(address asset) external
```

#### Roles

- `DEFAULT_ADMIN_ROLE`: Can add/remove supported assets and manage other roles
- `COLLATERAL_MANAGER_ROLE`: Can withdraw and deposit collateral
- `MINTER_ROLE`: Can mint and redeem MCT (assigned to USDe contract)

### USDe

The USDe contract is an ERC4626 vault that:

- Uses MCT as the underlying asset
- Maintains a 1:1 exchange rate between USDe and MCT
- Accepts collateral directly from users (no need to pre-mint MCT)
- Includes rate limiting (max mint/redeem per block)
- Supports delegated signers for smart contract integration

#### Key Functions

```solidity
// Mint USDe by depositing collateral
function mintWithCollateral(address collateralAsset, uint256 collateralAmount)
    external returns (uint256 usdeAmount)

// Mint USDe for a beneficiary (delegated signer)
function mintWithCollateralFor(address collateralAsset, uint256 collateralAmount, address beneficiary)
    external returns (uint256 usdeAmount)

// Redeem USDe for collateral
function redeemForCollateral(address collateralAsset, uint256 usdeAmount)
    external returns (uint256 collateralAmount)

// Redeem USDe for a beneficiary (delegated signer)
function redeemForCollateralFor(address collateralAsset, uint256 usdeAmount, address beneficiary)
    external returns (uint256 collateralAmount)

// Standard ERC4626 functions also available:
// - deposit(assets, receiver)
// - mint(shares, receiver)
// - withdraw(assets, receiver, owner)
// - redeem(shares, receiver, owner)
```

#### Roles

- `DEFAULT_ADMIN_ROLE`: Can set rate limits and manage other roles
- `GATEKEEPER_ROLE`: Can disable mint/redeem in emergencies
- `COLLATERAL_MANAGER_ROLE`: Future use for collateral management

## User Flow

### Minting USDe

The flow for a user to mint USDe with USDC:

```
1. User approves USDe to spend USDC
2. User calls mintWithCollateral(USDC, 1000e6) // 1000 USDC
3. USDe transfers USDC from user
4. USDe approves MCT to spend USDC
5. USDe calls MCT.mint(USDC, 1000e6, address(this))
   - MCT transfers USDC to itself
   - MCT mints 1000e18 MCT to USDe
6. USDe mints 1000e18 USDe to user (1:1 with MCT)
7. User receives 1000 USDe
```

### Redeeming USDe

The flow for a user to redeem USDe for USDC:

```
1. User calls redeemForCollateral(USDC, 1000e18) // 1000 USDe
2. USDe burns 1000e18 USDe from user
3. USDe approves MCT to spend MCT
4. USDe calls MCT.redeem(USDC, 1000e18, user)
   - MCT burns 1000e18 MCT from USDe
   - MCT transfers 1000e6 USDC to user
5. User receives 1000 USDC
```

## Deployment Guide

### 1. Deploy MultiCollateralToken

```solidity
address[] memory initialAssets = new address[](1);
initialAssets[0] = USDC_ADDRESS; // Add USDC as initial supported asset

MultiCollateralToken mct = new MultiCollateralToken(
    admin,           // Admin address
    initialAssets    // Initial supported assets
);
```

### 2. Deploy USDe

```solidity
USDe usde = new USDe(
    mct,                    // MCT contract
    admin,                  // Admin address
    1000000 * 1e18,        // Max mint per block (1M USDe)
    1000000 * 1e18         // Max redeem per block (1M USDe)
);
```

### 3. Grant USDe the MINTER_ROLE on MCT

```solidity
mct.grantRole(keccak256("MINTER_ROLE"), address(usde));
```

### 4. (Optional) Add more supported assets

```solidity
mct.addSupportedAsset(USDT_ADDRESS);
mct.addSupportedAsset(DAI_ADDRESS);
```

### 5. (Optional) Grant COLLATERAL_MANAGER_ROLE to team members

```solidity
mct.grantRole(keccak256("COLLATERAL_MANAGER_ROLE"), teamMember);
```

## Security Considerations

### Rate Limiting

Both contracts implement per-block rate limiting to prevent:

- Flash loan attacks
- Market manipulation
- Excessive minting/redeeming

### Access Control

- All privileged operations are protected by role-based access control
- Admin role cannot be renounced to prevent loss of control
- Delegated signers must be confirmed by both parties

### Collateral Management

- MCT tracks collateral balance separately from actual token balance
- Withdrawals check against tracked collateral balance to prevent over-withdrawal
- Only COLLATERAL_MANAGER_ROLE can withdraw/deposit collateral

### ERC4626 Security

- Uses OpenZeppelin's ERC4626 implementation with built-in protections
- Decimal normalization prevents precision loss
- ReentrancyGuard protects all state-changing functions

## Differences from Original Contracts

### Combined Functionality

The original implementation had:

- `USDe.sol`: Simple ERC20 with minting
- `EthenaMinting.sol`: Separate minting contract with collateral handling

The new implementation combines both into:

- `USDe.sol`: ERC4626 vault with integrated minting
- `MultiCollateralToken.sol`: Underlying collateral management

### Key Improvements

1. **ERC4626 Standard**: Users can interact with USDe as a standard vault
2. **Direct Collateral Minting**: Users don't need to pre-convert collateral to MCT
3. **Multi-Collateral Foundation**: MCT provides a flexible foundation for multiple assets
4. **Team Collateral Management**: MCT allows team to manage collateral without affecting USDe supply
5. **Omnichain Ready**: Can be integrated with LayerZero's OVault system for cross-chain operations

## Integration with OVault

To make this omnichain, you would:

1. Deploy `USDe` on the hub chain
2. Deploy `MyShareOFTAdapter` wrapping the USDe token
3. Deploy `MyOVaultComposer` for cross-chain operations
4. Deploy `MyShareOFT` on spoke chains
5. Configure LayerZero messaging between chains

Users can then:

- Deposit collateral on Chain A to receive USDe on Chain B
- Redeem USDe on Chain B to receive collateral on Chain A
- Transfer USDe between any supported chains

## Testing

Run the tests with:

```bash
pnpm test
```

## License

GPL-3.0
