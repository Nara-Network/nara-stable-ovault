// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "../mct/IMultiCollateralToken.sol";

interface INaraUSDRedeemSilo {
    function withdraw(address to, uint256 amount) external;
}

/**
 * @title INaraUSD
 * @notice Interface for the NaraUSD contract
 */
interface INaraUSD {
    /* --------------- EVENTS --------------- */

    event Mint(
        address indexed beneficiary,
        address indexed collateralAsset,
        uint256 collateralAmount,
        uint256 naraUsdAmount
    );
    event Redeem(
        address indexed beneficiary,
        address indexed collateralAsset,
        uint256 naraUsdAmount,
        uint256 collateralAmount
    );
    event MaxMintPerBlockChanged(uint256 oldMax, uint256 newMax);
    event MaxRedeemPerBlockChanged(uint256 oldMax, uint256 newMax);
    event RedemptionRequested(address indexed user, uint256 naraUsdAmount, address indexed collateralAsset);
    event RedemptionCompleted(
        address indexed user,
        uint256 naraUsdAmount,
        address indexed collateralAsset,
        uint256 collateralAmount
    );
    event RedemptionCancelled(address indexed user, uint256 naraUsdAmount);
    event MintFeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event RedeemFeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event FeeTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event FeeCollected(address indexed treasury, uint256 feeAmount, bool isMintFee);
    event LockedAmountRedistributed(
        address indexed from,
        address indexed to,
        uint256 walletAmount,
        uint256 escrowedAmount
    );
    event MinMintAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event MinRedeemAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event MinMintFeeAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event MinRedeemFeeAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event KeyringConfigUpdated(address indexed keyringAddress, uint256 policyId);
    event KeyringWhitelistUpdated(address indexed account, bool status);

    /* --------------- STRUCTS --------------- */

    struct RedemptionRequest {
        uint152 naraUsdAmount;
        address collateralAsset;
    }

    /* --------------- ERRORS --------------- */

    error ZeroAddressException();
    error InvalidAmount();
    error UnsupportedAsset();
    error MaxMintPerBlockExceeded();
    error MaxRedeemPerBlockExceeded();
    error CantRenounceOwnership();
    error NoRedemptionRequest();
    error ExistingRedemptionRequest();
    error InvalidFee();
    error OperationNotAllowed();
    error CantBlacklistOwner();
    error BelowMinimumAmount();
    error KeyringCredentialInvalid(address account);
    error InsufficientCollateral();
    error ValueUnchanged();

    /* --------------- FUNCTIONS --------------- */

    /**
     * @notice Mint NaraUSD by depositing collateral
     * @param collateralAsset The collateral asset to deposit
     * @param collateralAmount The amount of collateral to deposit
     * @return naraUsdAmount The amount of NaraUSD minted
     */
    function mintWithCollateral(
        address collateralAsset,
        uint256 collateralAmount
    ) external returns (uint256 naraUsdAmount);

    /**
     * @notice Redeem NaraUSD for collateral - instant if liquidity available, otherwise queued
     * @param collateralAsset The collateral asset to receive
     * @param naraUsdAmount The amount of NaraUSD to redeem
     * @param allowQueue If false, reverts when insufficient liquidity; if true, queues the request
     * @return collateralAmount The amount of collateral received (0 if queued)
     * @return wasQueued True if request was queued, false if executed instantly
     * @dev Note: The "redemption queue" is NOT an ordered FIFO queue. It is a per-user mapping (one request per user).
     *      Completion order is discretionary by the collateral manager/solver.
     */
    function redeem(
        address collateralAsset,
        uint256 naraUsdAmount,
        bool allowQueue
    ) external returns (uint256 collateralAmount, bool wasQueued);

    /**
     * @notice Complete queued redemption for a specific user - redeems NaraUSD for collateral
     * @param user The address whose redemption request should be completed
     * @return collateralAmount The amount of collateral received
     * @dev Completion order is discretionary - there is no FIFO ordering. The solver can complete any
     *      user's request opportunistically when liquidity is available.
     */
    function completeRedeem(address user) external returns (uint256 collateralAmount);

    /**
     * @notice Bulk-complete redemptions for multiple users
     * @param users Array of user addresses whose redemptions should be completed
     * @dev Completion order is discretionary - there is no FIFO ordering. The solver can choose which
     *      users to complete in any order when liquidity is available.
     */
    function bulkCompleteRedeem(address[] calldata users) external;

    /**
     * @notice Attempt to complete own queued redemption if liquidity is available
     * @dev Allows users to complete their own redemption request if sufficient collateral is available
     * @dev Reverts if insufficient collateral or other validation fails
     * @return collateralAmount The amount of collateral received
     */
    function tryCompleteRedeem() external returns (uint256 collateralAmount);

    /**
     * @notice Update queued redemption request amount
     * @param newAmount The new amount of NaraUSD to redeem
     * @dev Only updates the queued amount, never executes instant redemption. Use tryCompleteRedeem() to attempt completion.
     */
    function updateRedemptionRequest(uint256 newAmount) external;

    /**
     * @notice Cancel queued redemption request and return locked NaraUSD to user
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
     * @notice Set minimum mint fee amount
     * @param _minMintFeeAmount New minimum mint fee amount (18 decimals)
     */
    function setMinMintFeeAmount(uint256 _minMintFeeAmount) external;

    /**
     * @notice Set minimum redeem fee amount
     * @param _minRedeemFeeAmount New minimum redeem fee amount (18 decimals)
     */
    function setMinRedeemFeeAmount(uint256 _minRedeemFeeAmount) external;

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
     * @notice Redistribute locked amount from blacklisted user (both wallet and escrowed)
     * @param from The address to redistribute from (must have FULL_RESTRICTED_ROLE)
     * @param to The address to mint the balance to (or address(0) to burn)
     */
    function redistributeLockedAmount(address from, address to) external;

    /**
     * @notice Mint NaraUSD without collateral backing (protocol controlled)
     * @param to The recipient of newly minted NaraUSD
     * @param amount The amount to mint
     */
    function mintWithoutCollateral(address to, uint256 amount) external;

    /**
     * @notice Burn NaraUSD and underlying MCT without withdrawing collateral
     * @param amount The amount to burn (from msg.sender)
     */
    function burn(uint256 amount) external;

    /* --------------- VIEW FUNCTIONS --------------- */

    /**
     * @notice Get the MCT token
     * @return The MCT token contract
     */
    function mct() external view returns (IMultiCollateralToken);

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
     * @notice Get max instant redeem for a collateral asset
     * @param collateralAsset The collateral asset to redeem
     * @return uint256 The max instant redeem
     */
    function maxInstantRedeem(address owner, address collateralAsset) external view returns (uint256);

    /**
     * @notice Get redemption request for a user
     * @param user The user address
     * @return RedemptionRequest The redemption request
     */
    function redemptionRequests(address user) external view returns (RedemptionRequest memory);

    /**
     * @notice Get the redeem silo contract
     * @return The silo contract
     */
    function redeemSilo() external view returns (INaraUSDRedeemSilo);

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
     * @notice Get minimum mint fee amount
     * @return uint256 The minimum mint fee amount (18 decimals)
     */
    function minMintFeeAmount() external view returns (uint256);

    /**
     * @notice Get minimum redeem fee amount
     * @return uint256 The minimum redeem fee amount (18 decimals)
     */
    function minRedeemFeeAmount() external view returns (uint256);

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
