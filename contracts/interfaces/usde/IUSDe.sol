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
    event CooldownDurationUpdated(uint24 previousDuration, uint24 newDuration);
    event RedemptionRequested(
        address indexed user,
        uint256 usdeAmount,
        address indexed collateralAsset,
        uint256 cooldownEnd
    );
    event RedemptionCompleted(
        address indexed user,
        uint256 usdeAmount,
        address indexed collateralAsset,
        uint256 collateralAmount
    );
    event RedemptionCancelled(address indexed user, uint256 usdeAmount);

    /* --------------- STRUCTS --------------- */

    struct RedemptionRequest {
        uint104 cooldownEnd;
        uint152 usdeAmount;
        address collateralAsset;
    }

    /* --------------- ERRORS --------------- */

    error ZeroAddressException();
    error InvalidAmount();
    error UnsupportedAsset();
    error MaxMintPerBlockExceeded();
    error MaxRedeemPerBlockExceeded();
    error InvalidSignature();
    error DelegationNotInitiated();
    error CantRenounceOwnership();
    error InvalidCooldown();
    error NoRedemptionRequest();
    error CooldownNotFinished();
    error ExistingRedemptionRequest();

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
     * @notice Request redemption with cooldown - locks USDe and starts cooldown timer
     * @param collateralAsset The collateral asset to receive after cooldown
     * @param usdeAmount The amount of USDe to lock for redemption
     */
    function cooldownRedeem(address collateralAsset, uint256 usdeAmount) external;

    /**
     * @notice Complete redemption after cooldown period - redeems USDe for collateral
     * @return collateralAmount The amount of collateral received
     */
    function completeRedeem() external returns (uint256 collateralAmount);

    /**
     * @notice Cancel redemption request and return locked USDe to user
     */
    function cancelRedeem() external;

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
     * @notice Set cooldown duration for redemptions
     * @param duration New cooldown duration (max 90 days)
     */
    function setCooldownDuration(uint24 duration) external;

    /**
     * @notice Pause all mint and redeem operations
     */
    function pause() external;

    /**
     * @notice Unpause all mint and redeem operations
     */
    function unpause() external;

    /**
     * @notice Mint USDe without collateral backing (protocol controlled)
     * @param to The recipient of newly minted USDe
     * @param amount The amount to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burn USDe and underlying MCT without withdrawing collateral
     * @param amount The amount to burn (from msg.sender)
     */
    function burn(uint256 amount) external;

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

    /**
     * @notice Get cooldown duration
     * @return uint24 The cooldown duration in seconds
     */
    function cooldownDuration() external view returns (uint24);

    /**
     * @notice Get redemption request for a user
     * @param user The user address
     * @return RedemptionRequest The redemption request
     */
    function redemptionRequests(address user) external view returns (RedemptionRequest memory);

    /**
     * @notice Get the redeem silo address
     * @return address The silo contract address
     */
    function redeemSilo() external view returns (address);
}
