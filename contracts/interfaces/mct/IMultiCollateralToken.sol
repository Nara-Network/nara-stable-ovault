// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IMultiCollateralToken
 * @notice Interface for the MultiCollateralToken contract
 */
interface IMultiCollateralToken is IERC20 {
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
    event UnbackedMint(address indexed beneficiary, uint256 mctAmount);

    /* --------------- ERRORS --------------- */

    error ZeroAddressException();
    error InvalidAmount();
    error UnsupportedAsset();
    error InvalidAssetAddress();
    error InsufficientCollateral();

    /* --------------- FUNCTIONS --------------- */

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
    ) external returns (uint256 mctAmount);

    /**
     * @notice Mint MCT without depositing collateral (admin-controlled)
     * @param beneficiary The address to receive minted MCT
     * @param mctAmount The amount of MCT to mint
     */
    function mintWithoutCollateral(address beneficiary, uint256 mctAmount) external;

    /**
     * @notice Burn MCT tokens
     * @param amount The amount of MCT to burn
     */
    function burn(uint256 amount) external;

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
    ) external returns (uint256 collateralAmount);

    /**
     * @notice Withdraw collateral for team management
     * @param asset The asset to withdraw
     * @param amount The amount to withdraw
     * @param to The address to send the collateral to
     */
    function withdrawCollateral(address asset, uint256 amount, address to) external;

    /**
     * @notice Deposit collateral back from team management
     * @param asset The asset to deposit
     * @param amount The amount to deposit
     */
    function depositCollateral(address asset, uint256 amount) external;

    /**
     * @notice Add a new supported asset
     * @param asset The asset address to add
     */
    function addSupportedAsset(address asset) external;

    /**
     * @notice Remove a supported asset
     * @param asset The asset address to remove
     */
    function removeSupportedAsset(address asset) external;

    /**
     * @notice Check if an asset is supported
     * @param asset The asset address to check
     * @return bool True if asset is supported
     */
    function isSupportedAsset(address asset) external view returns (bool);

    /**
     * @notice Get all supported assets
     * @return address[] Array of supported asset addresses
     */
    function getSupportedAssets() external view returns (address[] memory);

    /**
     * @notice Get collateral balance for an asset
     * @param asset The asset address
     * @return uint256 The collateral balance
     */
    function collateralBalance(address asset) external view returns (uint256);
}
