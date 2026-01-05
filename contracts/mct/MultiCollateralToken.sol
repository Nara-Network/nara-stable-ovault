// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/mct/IMultiCollateralToken.sol";

/**
 * @title MultiCollateralToken (MCT)
 * @notice Multi-collateral token that can accept various assets and mint MCT tokens
 * @dev This token serves as the underlying asset for NaraUSD OVault
 * @dev This contract is upgradeable using UUPS proxy pattern
 */
/**
 * @dev Privileged roles: COLLATERAL_MANAGER can move collateral, MINTER can mint unbacked.
 *      Roles can be renounced. redeem() may truncate decimals.
 */
contract MultiCollateralToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IMultiCollateralToken
{
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

    /// @dev Storage gap for future upgrades
    uint256[48] private __gap;

    /* --------------- INITIALIZER --------------- */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param admin Admin address
     * @param initialAssets Array of initial supported asset addresses
     */
    function initialize(address admin, address[] memory initialAssets) public initializer {
        if (admin == address(0)) revert ZeroAddressException();

        __ERC20_init("MultiCollateralToken", "MCT");
        __ERC20Burnable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(COLLATERAL_MANAGER_ROLE, admin);

        // Add initial supported assets
        for (uint256 i = 0; i < initialAssets.length; i++) {
            _addSupportedAsset(initialAssets[i]);
        }
    }

    /**
     * @notice Get the default admin role (for interface compatibility with NaraUSDComposer)
     * @return The DEFAULT_ADMIN_ROLE bytes32 value
     */
    function defaultAdminRole() external pure returns (bytes32) {
        return DEFAULT_ADMIN_ROLE;
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     * @dev Only DEFAULT_ADMIN_ROLE can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

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
        mctAmount = _convertToMctAmount(collateralAsset, collateralAmount);

        // Transfer collateral from caller to this contract
        IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Update collateral balance
        collateralBalance[collateralAsset] += collateralAmount;

        // Mint MCT to beneficiary
        _mint(beneficiary, mctAmount);

        emit Minted(beneficiary, collateralAsset, collateralAmount, mctAmount);
    }

    /**
     * @notice Mint MCT without depositing collateral (admin-controlled)
     * @param beneficiary The address to receive minted MCT
     * @param mctAmount The amount of MCT to mint
     */
    function mintWithoutCollateral(address beneficiary, uint256 mctAmount) external onlyRole(MINTER_ROLE) {
        if (mctAmount == 0) revert InvalidAmount();
        if (beneficiary == address(0)) revert ZeroAddressException();

        _mint(beneficiary, mctAmount);
        emit UnbackedMint(beneficiary, mctAmount);
    }

    /**
     * @notice Burn MCT tokens
     * @param amount The amount of MCT to burn
     */
    function burn(uint256 amount) public virtual override(ERC20BurnableUpgradeable, IMultiCollateralToken) {
        super.burn(amount);
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
     * @dev Reverts if asset has remaining collateral balance to prevent locking funds
     */
    function removeSupportedAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (collateralBalance[asset] > 0) revert AssetHasCollateral();
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
    function _convertToMctAmount(address collateralAsset, uint256 collateralAmount) internal view returns (uint256) {
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
            revert AssetAlreadySupported();
        }
        emit AssetAdded(asset);
    }

    /**
     * @dev Prevent renouncing DEFAULT_ADMIN_ROLE to avoid ungovernability
     */
    function renounceRole(bytes32 role, address account) public virtual override(AccessControlUpgradeable) {
        if (role == DEFAULT_ADMIN_ROLE) revert ZeroAddressException();
        super.renounceRole(role, account);
    }
}
