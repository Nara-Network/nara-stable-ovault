// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title InUSD
 * @notice Interface for the nUSD contract
 */
interface InUSD is IERC4626, IERC20Permit {
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
        uint256 nUSDAmount
    );
    event Redeem(
        address indexed beneficiary,
        address indexed collateralAsset,
        uint256 nUSDAmount,
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
        uint256 nUSDAmount,
        address indexed collateralAsset,
        uint256 cooldownEnd
    );
    event RedemptionCompleted(
        address indexed user,
        uint256 nUSDAmount,
        address indexed collateralAsset,
        uint256 collateralAmount
    );
    event RedemptionCancelled(address indexed user, uint256 nUSDAmount);
    event MintFeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event RedeemFeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event FeeTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event FeeCollected(address indexed treasury, uint256 feeAmount, bool isMintFee);
    event LockedAmountRedistributed(address indexed from, address indexed to, uint256 amount);
    event MinMintAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event MinRedeemAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event KeyringConfigUpdated(address indexed keyringAddress, uint256 policyId);
    event KeyringWhitelistUpdated(address indexed account, bool status);

    /* --------------- STRUCTS --------------- */

    struct RedemptionRequest {
        uint104 cooldownEnd;
        uint152 nUSDAmount;
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
    error InvalidFee();
    error OperationNotAllowed();
    error CantBlacklistOwner();
    error BelowMinimumAmount();
    error KeyringCredentialInvalid(address account);

    /* --------------- FUNCTIONS --------------- */

    /**
     * @notice Mint nUSD by depositing collateral
     * @param collateralAsset The collateral asset to deposit
     * @param collateralAmount The amount of collateral to deposit
     * @return nUSDAmount The amount of nUSD minted
     */
    function mintWithCollateral(
        address collateralAsset,
        uint256 collateralAmount
    ) external returns (uint256 nUSDAmount);

    /**
     * @notice Mint nUSD on behalf of a beneficiary
     * @param collateralAsset The collateral asset to deposit
     * @param collateralAmount The amount of collateral to deposit
     * @param beneficiary The address to receive minted nUSD
     * @return nUSDAmount The amount of nUSD minted
     */
    function mintWithCollateralFor(
        address collateralAsset,
        uint256 collateralAmount,
        address beneficiary
    ) external returns (uint256 nUSDAmount);

    /**
     * @notice Request redemption with cooldown - locks nUSD and starts cooldown timer
     * @param collateralAsset The collateral asset to receive after cooldown
     * @param nUSDAmount The amount of nUSD to lock for redemption
     */
    function cooldownRedeem(address collateralAsset, uint256 nUSDAmount) external;

    /**
     * @notice Complete redemption after cooldown period - redeems nUSD for collateral
     * @return collateralAmount The amount of collateral received
     */
    function completeRedeem() external returns (uint256 collateralAmount);

    /**
     * @notice Cancel redemption request and return locked nUSD to user
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
     * @notice Set mint fee
     * @param _mintFeeBps New mint fee in basis points (max 10%)
     */
    function setMintFee(uint16 _mintFeeBps) external;

    /**
     * @notice Set redeem fee
     * @param _redeemFeeBps New redeem fee in basis points (max 10%)
     */
    function setRedeemFee(uint16 _redeemFeeBps) external;

    /**
     * @notice Set fee treasury address
     * @param _feeTreasury New treasury address
     */
    function setFeeTreasury(address _feeTreasury) external;

    /**
     * @notice Set minimum mint amount
     * @param _minMintAmount New minimum mint amount (18 decimals)
     */
    function setMinMintAmount(uint256 _minMintAmount) external;

    /**
     * @notice Set minimum redeem amount
     * @param _minRedeemAmount New minimum redeem amount (18 decimals)
     */
    function setMinRedeemAmount(uint256 _minRedeemAmount) external;

    /**
     * @notice Set Keyring contract address and policy ID
     * @param _keyringAddress Address of the Keyring contract (set to address(0) to disable)
     * @param _policyId The policy ID to check credentials against
     */
    function setKeyringConfig(address _keyringAddress, uint256 _policyId) external;

    /**
     * @notice Add or remove an address from the Keyring whitelist
     * @param account The address to update whitelist status for
     * @param status True to whitelist, false to remove from whitelist
     */
    function setKeyringWhitelist(address account, bool status) external;

    /**
     * @notice Add an address to blacklist
     * @param target The address to blacklist
     */
    function addToBlacklist(address target) external;

    /**
     * @notice Remove an address from blacklist
     * @param target The address to un-blacklist
     */
    function removeFromBlacklist(address target) external;

    /**
     * @notice Redistribute locked amount from full restricted user
     * @param from The address to burn the entire balance from (must have FULL_RESTRICTED_ROLE)
     * @param to The address to mint the entire balance to (or address(0) to burn)
     */
    function redistributeLockedAmount(address from, address to) external;

    /**
     * @notice Mint nUSD without collateral backing (protocol controlled)
     * @param to The recipient of newly minted nUSD
     * @param amount The amount to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burn nUSD and underlying MCT without withdrawing collateral
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

    /**
     * @notice Get mint fee in basis points
     * @return uint16 The mint fee
     */
    function mintFeeBps() external view returns (uint16);

    /**
     * @notice Get redeem fee in basis points
     * @return uint16 The redeem fee
     */
    function redeemFeeBps() external view returns (uint16);

    /**
     * @notice Get fee treasury address
     * @return address The treasury address
     */
    function feeTreasury() external view returns (address);

    /**
     * @notice Get minimum mint amount
     * @return uint256 The minimum mint amount (18 decimals)
     */
    function minMintAmount() external view returns (uint256);

    /**
     * @notice Get minimum redeem amount
     * @return uint256 The minimum redeem amount (18 decimals)
     */
    function minRedeemAmount() external view returns (uint256);

    /**
     * @notice Get Keyring contract address
     * @return address The Keyring contract address
     */
    function keyringAddress() external view returns (address);

    /**
     * @notice Get Keyring policy ID
     * @return uint256 The policy ID
     */
    function keyringPolicyId() external view returns (uint256);

    /**
     * @notice Check if an address is whitelisted in Keyring
     * @param account The address to check
     * @return bool True if whitelisted
     */
    function keyringWhitelist(address account) external view returns (bool);

    /**
     * @notice Check if an address has valid Keyring credentials
     * @param account The address to check
     * @return bool True if account has credentials or Keyring is disabled
     */
    function hasValidCredentials(address account) external view returns (bool);
}
