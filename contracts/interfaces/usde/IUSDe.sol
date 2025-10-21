// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title IUSDe
 * @notice Interface for the USDe contract
 */
interface IUSDe is IERC4626, IERC20Permit {
    /* --------------- ENUMS --------------- */

    enum DelegatedSignerStatus {
        REJECTED,
        PENDING,
        ACCEPTED
    }

    /* --------------- EVENTS --------------- */

    event Mint(
        address indexed beneficiary,
        address indexed collateralAsset,
        uint256 collateralAmount,
        uint256 usdeAmount
    );
    event Redeem(
        address indexed beneficiary,
        address indexed collateralAsset,
        uint256 usdeAmount,
        uint256 collateralAmount
    );
    event MaxMintPerBlockChanged(uint256 oldMax, uint256 newMax);
    event MaxRedeemPerBlockChanged(uint256 oldMax, uint256 newMax);
    event DelegatedSignerInitiated(address indexed delegateTo, address indexed delegatedBy);
    event DelegatedSignerAdded(address indexed signer, address indexed delegatedBy);
    event DelegatedSignerRemoved(address indexed signer, address indexed delegatedBy);

    /* --------------- ERRORS --------------- */

    error ZeroAddressException();
    error InvalidAmount();
    error UnsupportedAsset();
    error MaxMintPerBlockExceeded();
    error MaxRedeemPerBlockExceeded();
    error InvalidSignature();
    error DelegationNotInitiated();
    error CantRenounceOwnership();

    /* --------------- FUNCTIONS --------------- */

    /**
     * @notice Mint USDe by depositing collateral
     * @param collateralAsset The collateral asset to deposit
     * @param collateralAmount The amount of collateral to deposit
     * @return usdeAmount The amount of USDe minted
     */
    function mintWithCollateral(
        address collateralAsset,
        uint256 collateralAmount
    ) external returns (uint256 usdeAmount);

    /**
     * @notice Mint USDe on behalf of a beneficiary
     * @param collateralAsset The collateral asset to deposit
     * @param collateralAmount The amount of collateral to deposit
     * @param beneficiary The address to receive minted USDe
     * @return usdeAmount The amount of USDe minted
     */
    function mintWithCollateralFor(
        address collateralAsset,
        uint256 collateralAmount,
        address beneficiary
    ) external returns (uint256 usdeAmount);

    /**
     * @notice Redeem USDe for collateral
     * @param collateralAsset The collateral asset to receive
     * @param usdeAmount The amount of USDe to redeem
     * @return collateralAmount The amount of collateral received
     */
    function redeemForCollateral(
        address collateralAsset,
        uint256 usdeAmount
    ) external returns (uint256 collateralAmount);

    /**
     * @notice Redeem USDe on behalf of a beneficiary
     * @param collateralAsset The collateral asset to receive
     * @param usdeAmount The amount of USDe to redeem
     * @param beneficiary The address to burn USDe from and receive collateral
     * @return collateralAmount The amount of collateral received
     */
    function redeemForCollateralFor(
        address collateralAsset,
        uint256 usdeAmount,
        address beneficiary
    ) external returns (uint256 collateralAmount);

    /**
     * @notice Set max mint per block
     * @param _maxMintPerBlock New max mint per block
     */
    function setMaxMintPerBlock(uint256 _maxMintPerBlock) external;

    /**
     * @notice Set max redeem per block
     * @param _maxRedeemPerBlock New max redeem per block
     */
    function setMaxRedeemPerBlock(uint256 _maxRedeemPerBlock) external;

    /**
     * @notice Disable mint and redeem in emergency
     */
    function disableMintRedeem() external;

    /**
     * @notice Enable smart contracts to delegate signing
     * @param _delegateTo The address to delegate to
     */
    function setDelegatedSigner(address _delegateTo) external;

    /**
     * @notice Confirm delegation
     * @param _delegatedBy The address that initiated delegation
     */
    function confirmDelegatedSigner(address _delegatedBy) external;

    /**
     * @notice Remove delegated signer
     * @param _removedSigner The address to remove
     */
    function removeDelegatedSigner(address _removedSigner) external;

    /* --------------- VIEW FUNCTIONS --------------- */

    /**
     * @notice Get the MCT token address
     * @return address The MCT token address
     */
    function mct() external view returns (address);

    /**
     * @notice Get minted amount per block
     * @param blockNumber The block number
     * @return uint256 The minted amount
     */
    function mintedPerBlock(uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Get redeemed amount per block
     * @param blockNumber The block number
     * @return uint256 The redeemed amount
     */
    function redeemedPerBlock(uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Get max mint per block
     * @return uint256 The max mint per block
     */
    function maxMintPerBlock() external view returns (uint256);

    /**
     * @notice Get max redeem per block
     * @return uint256 The max redeem per block
     */
    function maxRedeemPerBlock() external view returns (uint256);

    /**
     * @notice Get delegated signer status
     * @param signer The signer address
     * @param delegatedBy The address that delegated
     * @return DelegatedSignerStatus The status
     */
    function delegatedSigner(address signer, address delegatedBy) external view returns (DelegatedSignerStatus);

    function safeIncreaseAllowance(address spender, uint256 amount) external;
}
