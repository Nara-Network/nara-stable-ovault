// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title MultiCollateralToken (MCT)
 * @notice Multi-collateral token that can accept various assets and mint MCT tokens
 * @dev This token serves as the underlying asset for USDe OVault
 */
contract MultiCollateralToken is ERC20, ERC20Burnable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* --------------- CONSTANTS --------------- */

    /// @notice Role for managing collateral
    bytes32 public constant COLLATERAL_MANAGER_ROLE = keccak256("COLLATERAL_MANAGER_ROLE");

    /// @notice Role for minting MCT
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /* --------------- STATE VARIABLES --------------- */

    /// @notice Supported collateral assets
    EnumerableSet.AddressSet private _supportedAssets;

    /// @notice Total collateral value tracked per asset
    mapping(address => uint256) public collateralBalance;

    /* --------------- EVENTS --------------- */

    event AssetAdded(address indexed asset);
    event AssetRemoved(address indexed asset);
    event Minted(
        address indexed beneficiary,
        address indexed collateralAsset,
        uint256 collateralAmount,
        uint256 mctAmount
    );
    event Redeemed(
        address indexed beneficiary,
        address indexed collateralAsset,
        uint256 mctAmount,
        uint256 collateralAmount
    );
    event CollateralWithdrawn(address indexed asset, uint256 amount, address indexed to);

    /* --------------- ERRORS --------------- */

    error ZeroAddressException();
    error InvalidAmount();
    error UnsupportedAsset();
    error InvalidAssetAddress();
    error InsufficientCollateral();

    /* --------------- CONSTRUCTOR --------------- */

    constructor(address admin, address[] memory initialAssets) ERC20("MultiCollateralToken", "MCT") {
        if (admin == address(0)) revert ZeroAddressException();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(COLLATERAL_MANAGER_ROLE, admin);

        // Add initial supported assets
        for (uint256 i = 0; i < initialAssets.length; i++) {
            _addSupportedAsset(initialAssets[i]);
        }
    }

    /* --------------- EXTERNAL --------------- */

    /**
     * @notice Mint MCT by depositing collateral
     * @param collateralAsset The asset to deposit as collateral
     * @param collateralAmount The amount of collateral to deposit
     * @param beneficiary The address to receive minted MCT
     * @return mctAmount The amount of MCT minted
     */
    function mint(
        address collateralAsset,
        uint256 collateralAmount,
        address beneficiary
    ) external nonReentrant onlyRole(MINTER_ROLE) returns (uint256 mctAmount) {
        if (collateralAmount == 0) revert InvalidAmount();
        if (!_supportedAssets.contains(collateralAsset)) revert UnsupportedAsset();
        if (beneficiary == address(0)) revert ZeroAddressException();

        // Convert collateral to MCT amount (normalize decimals to 18)
        mctAmount = _convertToMCTAmount(collateralAsset, collateralAmount);

        // Transfer collateral from caller to this contract
        IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Update collateral balance
        collateralBalance[collateralAsset] += collateralAmount;

        // Mint MCT to beneficiary
        _mint(beneficiary, mctAmount);

        emit Minted(beneficiary, collateralAsset, collateralAmount, mctAmount);
    }

    /**
     * @notice Redeem MCT for collateral
     * @param collateralAsset The asset to receive
     * @param mctAmount The amount of MCT to burn
     * @param beneficiary The address to receive collateral
     * @return collateralAmount The amount of collateral returned
     */
    function redeem(
        address collateralAsset,
        uint256 mctAmount,
        address beneficiary
    ) external nonReentrant onlyRole(MINTER_ROLE) returns (uint256 collateralAmount) {
        if (mctAmount == 0) revert InvalidAmount();
        if (!_supportedAssets.contains(collateralAsset)) revert UnsupportedAsset();
        if (beneficiary == address(0)) revert ZeroAddressException();

        // Convert MCT amount to collateral amount
        collateralAmount = _convertToCollateralAmount(collateralAsset, mctAmount);

        // Check if sufficient collateral is available
        if (collateralBalance[collateralAsset] < collateralAmount) {
            revert InsufficientCollateral();
        }

        // Burn MCT from caller
        _burn(msg.sender, mctAmount);

        // Update collateral balance
        collateralBalance[collateralAsset] -= collateralAmount;

        // Transfer collateral to beneficiary
        IERC20(collateralAsset).safeTransfer(beneficiary, collateralAmount);

        emit Redeemed(beneficiary, collateralAsset, mctAmount, collateralAmount);
    }

    /**
     * @notice Withdraw collateral for team management
     * @param asset The asset to withdraw
     * @param amount The amount to withdraw
     * @param to The address to send the collateral to
     */
    function withdrawCollateral(
        address asset,
        uint256 amount,
        address to
    ) external nonReentrant onlyRole(COLLATERAL_MANAGER_ROLE) {
        if (amount == 0) revert InvalidAmount();
        if (!_supportedAssets.contains(asset)) revert UnsupportedAsset();
        if (to == address(0)) revert ZeroAddressException();
        if (collateralBalance[asset] < amount) revert InsufficientCollateral();

        collateralBalance[asset] -= amount;
        IERC20(asset).safeTransfer(to, amount);

        emit CollateralWithdrawn(asset, amount, to);
    }

    /**
     * @notice Deposit collateral back from team management
     * @param asset The asset to deposit
     * @param amount The amount to deposit
     */
    function depositCollateral(address asset, uint256 amount) external nonReentrant onlyRole(COLLATERAL_MANAGER_ROLE) {
        if (amount == 0) revert InvalidAmount();
        if (!_supportedAssets.contains(asset)) revert UnsupportedAsset();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        collateralBalance[asset] += amount;
    }

    /**
     * @notice Add a new supported asset
     * @param asset The asset address to add
     */
    function addSupportedAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addSupportedAsset(asset);
    }

    /**
     * @notice Remove a supported asset
     * @param asset The asset address to remove
     */
    function removeSupportedAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_supportedAssets.remove(asset)) revert InvalidAssetAddress();
        emit AssetRemoved(asset);
    }

    /**
     * @notice Check if an asset is supported
     * @param asset The asset address to check
     * @return bool True if asset is supported
     */
    function isSupportedAsset(address asset) external view returns (bool) {
        return _supportedAssets.contains(asset);
    }

    /**
     * @notice Get all supported assets
     * @return address[] Array of supported asset addresses
     */
    function getSupportedAssets() external view returns (address[] memory) {
        uint256 length = _supportedAssets.length();
        address[] memory assets = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            assets[i] = _supportedAssets.at(i);
        }
        return assets;
    }

    /* --------------- INTERNAL --------------- */

    /**
     * @notice Convert collateral amount to MCT amount (normalize decimals to 18)
     * @param collateralAsset The collateral asset address
     * @param collateralAmount The amount of collateral
     * @return The equivalent MCT amount (18 decimals)
     */
    function _convertToMCTAmount(address collateralAsset, uint256 collateralAmount) internal view returns (uint256) {
        uint8 collateralDecimals = IERC20Metadata(collateralAsset).decimals();

        if (collateralDecimals == 18) {
            return collateralAmount;
        } else if (collateralDecimals < 18) {
            // Scale up (e.g., USDC 6 decimals -> 18 decimals)
            return collateralAmount * (10 ** (18 - collateralDecimals));
        } else {
            // Scale down (shouldn't happen with standard stablecoins)
            return collateralAmount / (10 ** (collateralDecimals - 18));
        }
    }

    /**
     * @notice Convert MCT amount to collateral amount (denormalize decimals)
     * @param collateralAsset The collateral asset address
     * @param mctAmount The amount of MCT (18 decimals)
     * @return The equivalent collateral amount
     */
    function _convertToCollateralAmount(address collateralAsset, uint256 mctAmount) internal view returns (uint256) {
        uint8 collateralDecimals = IERC20Metadata(collateralAsset).decimals();

        if (collateralDecimals == 18) {
            return mctAmount;
        } else if (collateralDecimals < 18) {
            // Scale down (e.g., 18 decimals -> USDC 6 decimals)
            return mctAmount / (10 ** (18 - collateralDecimals));
        } else {
            // Scale up (shouldn't happen with standard stablecoins)
            return mctAmount * (10 ** (collateralDecimals - 18));
        }
    }

    /**
     * @notice Internal function to add supported asset
     * @param asset The asset address to add
     */
    function _addSupportedAsset(address asset) internal {
        if (asset == address(0) || asset == address(this)) {
            revert InvalidAssetAddress();
        }
        if (!_supportedAssets.add(asset)) {
            revert InvalidAssetAddress();
        }
        emit AssetAdded(asset);
    }
}
