// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../mct/MultiCollateralToken.sol";
import "./NaraUSDRedeemSilo.sol";
import "../interfaces/narausd/INaraUSD.sol";

/**
 * @title IKeyring
 * @notice Interface for Keyring credential checking
 */
interface IKeyring {
    /**
     * @notice Checks the credential of an entity against a specific policy
     * @param policyId The ID of the policy to check against
     * @param entity The address of the entity to check
     * @return bool indicating whether the entity's credentials pass the policy check
     */
    function checkCredential(uint256 policyId, address entity) external view returns (bool);
}

/**
 * @title NaraUSD
 * @notice Omnichain vault version of NaraUSD with integrated minting functionality and redemption queue
 * @dev This contract combines ERC4626 vault with direct collateral minting
 * - Underlying asset: MCT (MultiCollateralToken)
 * - Exchange rate: 1:1 with MCT
 * - Users can mint by depositing collateral (USDC, etc.)
 * - Collateral is converted to MCT, then NaraUSD shares are minted
 * - Redemptions: instant if liquidity available, otherwise queued for solver execution
 * - Users can cancel queued redemption requests anytime
 * @dev IMPORTANT - ERC4626 Limitations: This contract partially implements ERC4626.
 *      - ERC4626 deposit() and mint() are DISABLED - use mintWithCollateral() instead
 *      - ERC4626 withdraw() and redeem() are DISABLED - use redeem(collateralAsset, naraUsdAmount, allowQueue) instead
 *      - maxDeposit() and maxMint() reflect per-block limits and paused state
 *      - maxWithdraw() and maxRedeem() return 0 (ERC4626 withdraw/redeem are unsupported)
 *      - preview* functions account for fees but the corresponding actions may be disabled
 * @dev IMPORTANT - Redemption Mechanism: The "redemption queue" is NOT an ordered FIFO queue.
 *      It is implemented as a per-user mapping (one active request per user). There is no global
 *      ordering, no "next in line" concept, and no automatic FIFO processing. Completion order is
 *      discretionary by the COLLATERAL_MANAGER_ROLE (solver), who can complete requests opportunistically
 *      via completeRedeem() or bulkCompleteRedeem() when liquidity becomes available.
 * @dev This contract is upgradeable using UUPS proxy pattern
 *
 * @dev Privileged roles:
 * - DEFAULT_ADMIN_ROLE: Full administrative control. Can:
 *   - Upgrade contract implementation (UUPS)
 *   - Set all configuration parameters (fees, limits, minimums, treasury, Keyring config)
 *   - Redistribute locked amounts from blacklisted users
 *   - Grant/revoke all other roles
 * - GATEKEEPER_ROLE: Emergency controls. Can:
 *   - Pause/unpause all operations
 *   - Disable mint and redeem (set max per block to 0)
 * - COLLATERAL_MANAGER_ROLE: Manages redemption queue execution. Can:
 *   - Complete queued redemptions (completeRedeem, bulkCompleteRedeem)
 *   - Acts as "solver" to process escrowed redemption requests when liquidity becomes available
 *   - Completion order is discretionary (not FIFO) - can complete any user's request opportunistically
 * - MINTER_ROLE: Can mint NaraUSD without collateral backing (for incentives, etc.)
 * - BLACKLIST_MANAGER_ROLE: Can add/remove addresses from blacklist (FULL_RESTRICTED_ROLE)
 * - FULL_RESTRICTED_ROLE: Restriction status (not a role to grant). Addresses with this role:
 *   - Cannot transfer tokens (including via transferFrom)
 *   - Cannot mint or redeem
 *   - Can have their locked balances redistributed by admin
 */
contract NaraUSD is
    Initializable,
    ERC4626Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    INaraUSD
{
    using SafeERC20 for IERC20;

    /* --------------- CONSTANTS --------------- */

    /// @notice Role for emergency actions
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");

    /// @notice Role for managing collateral operations
    bytes32 public constant COLLATERAL_MANAGER_ROLE = keccak256("COLLATERAL_MANAGER_ROLE");

    /// @notice Role allowed to mint NaraUSD without collateral backing
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role that can blacklist and un-blacklist addresses
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    /// @notice Role that prevents an address from transferring, minting, or redeeming
    bytes32 public constant FULL_RESTRICTED_ROLE = keccak256("FULL_RESTRICTED_ROLE");

    /// @notice Maximum fee in basis points (10% = 1000 bps)
    uint16 public constant MAX_FEE_BPS = 1000;

    /// @notice Basis points denominator (100% = 10000 bps)
    uint16 public constant BPS_DENOMINATOR = 10000;

    /* --------------- STATE VARIABLES --------------- */

    /// @notice The MCT token (underlying asset)
    IMultiCollateralToken public mct;

    /// @notice NaraUSD minted per block
    mapping(uint256 => uint256) public mintedPerBlock;

    /// @notice NaraUSD redeemed per block
    mapping(uint256 => uint256) public redeemedPerBlock;

    /// @notice Max minted NaraUSD allowed per block
    uint256 public maxMintPerBlock;

    /// @notice Max redeemed NaraUSD allowed per block
    uint256 public maxRedeemPerBlock;

    /// @notice Minimum NaraUSD amount required for minting (18 decimals)
    uint256 public minMintAmount;

    /// @notice Minimum NaraUSD amount required for redemption (18 decimals)
    uint256 public minRedeemAmount;

    /// @notice Mapping of user addresses to their redemption requests
    /// @dev This is NOT an ordered queue - each user can have one active request. There is no FIFO ordering.
    ///      Completion order is discretionary by COLLATERAL_MANAGER_ROLE (solver).
    mapping(address => RedemptionRequest) private _redemptionRequests;

    /// @notice Get redemption request for a user
    function redemptionRequests(address user) public view returns (RedemptionRequest memory) {
        return _redemptionRequests[user];
    }

    /// @notice Silo contract for holding locked NaraUSD during redemption queue
    INaraUSDRedeemSilo public redeemSilo;

    /// @notice Mint fee in basis points (e.g., 10 = 0.1%)
    uint16 public mintFeeBps;

    /// @notice Redeem fee in basis points (e.g., 10 = 0.1%)
    uint16 public redeemFeeBps;

    /// @notice Minimum mint fee amount (18 decimals)
    uint256 public minMintFeeAmount;

    /// @notice Minimum redeem fee amount (18 decimals)
    uint256 public minRedeemFeeAmount;

    /// @notice Treasury address to receive fees
    address public feeTreasury;

    /// @notice Address of the Keyring contract for credential checking
    address public keyringAddress;

    /// @notice ID of the Keyring policy to check against
    uint256 public keyringPolicyId;

    /// @notice Mapping to track whitelist status of addresses (for contracts like AMM pools)
    mapping(address => bool) public keyringWhitelist;

    /**
     * @dev Storage gap to allow for new storage variables in future upgrades
     * @dev Reserves 50 storage slots for future versions
     */
    uint256[50] private __gap;

    /* --------------- MODIFIERS --------------- */

    /// @notice Ensure minted amount doesn't exceed max per block
    modifier belowMaxMintPerBlock(uint256 mintAmount) {
        _checkBelowMaxMintPerBlock(mintAmount);
        _;
    }

    /// @notice Ensure redeemed amount doesn't exceed max per block
    modifier belowMaxRedeemPerBlock(uint256 redeemAmount) {
        _checkBelowMaxRedeemPerBlock(redeemAmount);
        _;
    }

    /// @notice Ensure blacklist target is not admin
    modifier notAdmin(address target) {
        _checkNotAdmin(target);
        _;
    }

    /* --------------- INTERNAL HELPERS --------------- */

    function _checkBelowMaxMintPerBlock(uint256 mintAmount) internal view {
        if (mintedPerBlock[block.number] + mintAmount > maxMintPerBlock) {
            revert MaxMintPerBlockExceeded();
        }
    }

    function _checkBelowMaxRedeemPerBlock(uint256 redeemAmount) internal view {
        if (redeemedPerBlock[block.number] + redeemAmount > maxRedeemPerBlock) {
            revert MaxRedeemPerBlockExceeded();
        }
    }

    function _checkNotAdmin(address target) internal view {
        if (hasRole(DEFAULT_ADMIN_ROLE, target)) revert CantBlacklistOwner();
    }

    /**
     * @notice Check if an address has valid Keyring credentials (public view)
     * @param account The address to check
     * @return bool True if account has credentials or Keyring is disabled
     * @dev Returns true if:
     *      - Keyring is not configured (keyringAddress == address(0))
     *      - Account is whitelisted
     *      - Account has valid credentials in Keyring
     */
    function hasValidCredentials(address account) public view returns (bool) {
        // If Keyring not configured, everyone is valid
        if (keyringAddress == address(0)) {
            return true;
        }

        // If whitelisted, skip check
        if (keyringWhitelist[account]) {
            return true;
        }

        // Check Keyring credentials
        IKeyring keyring = IKeyring(keyringAddress);
        return keyring.checkCredential(keyringPolicyId, account);
    }

    /**
     * @notice Check if an address has valid Keyring credentials (internal with revert)
     * @param account The address to check
     * @dev Reverts if account does not have valid credentials
     *      Uses hasValidCredentials() for the actual check
     */
    function _checkKeyringCredential(address account) internal view {
        // Skip check for zero address (shouldn't happen but defensive)
        if (account == address(0)) {
            return;
        }

        // Use the public function for consistency
        if (!hasValidCredentials(account)) {
            revert KeyringCredentialInvalid(account);
        }
    }

    /* --------------- INITIALIZER --------------- */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _mct The MCT token (underlying asset)
     * @param admin Admin address
     * @param _maxMintPerBlock Max mint per block
     * @param _maxRedeemPerBlock Max redeem per block
     * @param _redeemSilo The redeem silo address (must be deployed separately as upgradeable proxy)
     */
    function initialize(
        MultiCollateralToken _mct,
        address admin,
        uint256 _maxMintPerBlock,
        uint256 _maxRedeemPerBlock,
        NaraUSDRedeemSilo _redeemSilo
    ) public initializer {
        if (address(_mct) == address(0)) revert ZeroAddressException();
        if (admin == address(0)) revert ZeroAddressException();
        if (address(_redeemSilo) == address(0)) revert ZeroAddressException();

        __ERC20_init("Nara USD", "NaraUSD");
        __ERC4626_init(IERC20(address(_mct)));
        __ERC20Permit_init("NaraUSD");
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        mct = IMultiCollateralToken(address(_mct));
        redeemSilo = INaraUSDRedeemSilo(address(_redeemSilo));

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GATEKEEPER_ROLE, admin);
        _grantRole(COLLATERAL_MANAGER_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(BLACKLIST_MANAGER_ROLE, admin);

        _setMaxMintPerBlock(_maxMintPerBlock);
        _setMaxRedeemPerBlock(_maxRedeemPerBlock);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     * @dev Only DEFAULT_ADMIN_ROLE can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /* --------------- EXTERNAL MINT/REDEEM --------------- */

    /**
     * @notice Mint NaraUSD by depositing collateral
     * @param collateralAsset The collateral asset to deposit
     * @param collateralAmount The amount of collateral to deposit
     * @return naraUsdAmount The amount of NaraUSD minted
     */
    function mintWithCollateral(
        address collateralAsset,
        uint256 collateralAmount
    ) external nonReentrant whenNotPaused returns (uint256 naraUsdAmount) {
        return _mintWithCollateral(collateralAsset, collateralAmount);
    }

    /**
     * @notice Mint NaraUSD without collateral backing (admin-controlled)
     * @param to The address to receive freshly minted NaraUSD
     * @param amount The amount of NaraUSD to mint
     * @dev Intended for protocol-controlled operations such as incentive programs
     */
    function mintWithoutCollateral(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert ZeroAddressException();
        if (amount == 0) revert InvalidAmount();
        _mint(to, amount);

        // Mint corresponding MCT to maintain 1:1 backing
        mct.mintWithoutCollateral(address(this), amount);
    }

    /**
     * @notice Mint NaraUSD without collateral backing for a specific beneficiary (admin-controlled)
     * @param beneficiary The address to receive freshly minted NaraUSD
     * @param amount The amount of NaraUSD to mint
     * @dev Alias for mint() with more explicit naming to clarify this is unbacked minting
     * @dev Intended for protocol-controlled operations such as incentive programs
     */
    function mintWithoutCollateralFor(
        address beneficiary,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (beneficiary == address(0)) revert ZeroAddressException();
        if (amount == 0) revert InvalidAmount();
        _mint(beneficiary, amount);

        // Mint corresponding MCT to maintain 1:1 backing
        mct.mintWithoutCollateral(address(this), amount);
    }

    /* --------------- REDEMPTION (INSTANT OR QUEUED) --------------- */

    /**
     * @notice Redeem NaraUSD for collateral - instant if liquidity available, otherwise queued
     * @param collateralAsset The collateral asset to receive
     * @param naraUsdAmount The amount of NaraUSD to redeem
     * @param allowQueue If false, reverts when insufficient liquidity; if true, queues the request
     * @return collateralAmount The amount of collateral received (0 if queued)
     * @return wasQueued True if request was queued, false if executed instantly
     * @dev IMPORTANT - Redemption Queue Mechanism: This is NOT an ordered FIFO queue. Each user can have
     *      one active redemption request stored in a mapping. There is no global ordering, no "next in line",
     *      and completion order is discretionary by COLLATERAL_MANAGER_ROLE (solver). The solver can complete
     *      any user's request opportunistically when liquidity becomes available.
     * @dev Note: Users can repeatedly create and cancel requests (spam is possible but costs gas).
     * @dev The minRedeemAmount check is enforced only at request creation time.
     *      Queued requests are "grandfathered" and will complete even if minRedeemAmount is increased later.
     * @dev IMPORTANT - Asset Removal Risk: If governance removes a collateral asset from MCT's supported
     *      assets list while redemption requests are queued for that asset, those queued requests will
     *      become non-completable (completion requires asset to be supported in MCT). However, users can
     *      ALWAYS call cancelRedeem() to recover their escrowed NaraUSD regardless of asset support status.
     *      Users should monitor asset support changes for queued requests. Governance should ensure queued
     *      requests are completed or users are notified before removing asset support.
     */
    function redeem(
        address collateralAsset,
        uint256 naraUsdAmount,
        bool allowQueue
    ) external nonReentrant whenNotPaused returns (uint256 collateralAmount, bool wasQueued) {
        if (naraUsdAmount == 0) revert InvalidAmount();
        if (!mct.isSupportedAsset(collateralAsset)) revert UnsupportedAsset();

        // Check minimum redeem amount
        if (minRedeemAmount > 0 && naraUsdAmount < minRedeemAmount) {
            revert BelowMinimumAmount();
        }

        // Check blacklist restrictions
        if (_isBlacklisted(msg.sender)) {
            revert OperationNotAllowed();
        }

        // Check Keyring credentials
        _checkKeyringCredential(msg.sender);

        // Calculate collateral needed
        uint256 collateralNeeded = _convertToCollateralAmount(collateralAsset, naraUsdAmount);

        // Check if MCT has sufficient collateral for instant redemption
        uint256 availableCollateral = mct.collateralBalance(collateralAsset);

        if (availableCollateral >= collateralNeeded) {
            // Instant redemption path
            collateralAmount = _instantRedeem(msg.sender, collateralAsset, naraUsdAmount);
            return (collateralAmount, false);
        } else {
            // Queue path
            if (!allowQueue) revert InsufficientCollateral();
            _queueRedeem(msg.sender, collateralAsset, naraUsdAmount);
            return (0, true);
        }
    }

    /**
     * @notice Complete redemption for a specific user - redeems NaraUSD for collateral from queued request
     * @param user The address whose redemption request should be completed
     * @dev Only callable by collateral manager
     */
    function completeRedeem(
        address user
    ) external nonReentrant whenNotPaused onlyRole(COLLATERAL_MANAGER_ROLE) returns (uint256 collateralAmount) {
        return _completeRedemption(user);
    }

    /**
     * @notice Bulk-complete redemptions for multiple users
     * @dev Callable by collateral manager to act as a "bulk solver" for escrowed redemption requests
     * @param users Array of user addresses whose redemptions should be completed
     */
    function bulkCompleteRedeem(
        address[] calldata users
    ) external nonReentrant whenNotPaused onlyRole(COLLATERAL_MANAGER_ROLE) {
        uint256 length = users.length;
        for (uint256 i = 0; i < length; ) {
            _completeRedemption(users[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Attempt to complete own queued redemption if liquidity is available
     * @dev Allows users to complete their own redemption request if sufficient collateral is available
     * @dev Reverts if insufficient collateral or other validation fails
     * @return collateralAmount The amount of collateral received
     */
    function tryCompleteRedeem() external nonReentrant whenNotPaused returns (uint256 collateralAmount) {
        return _completeRedemption(msg.sender);
    }

    /**
     * @notice Preview redemption amount for a specific collateral asset
     * @param collateralAsset The collateral asset to receive
     * @param naraUsdAmount The amount of NaraUSD to redeem
     * @return collateralAmount The amount of collateral that would be received after fees (0 if instant redemption not possible)
     * @dev This preview reflects the actual redemption flow and accounts for fees and liquidity availability
     * @dev Returns 0 if insufficient liquidity, asset not supported, or below minRedeemAmount
     */
    function previewRedeem(
        address collateralAsset,
        uint256 naraUsdAmount
    ) public view returns (uint256 collateralAmount) {
        if (naraUsdAmount == 0 || !mct.isSupportedAsset(collateralAsset)) {
            return 0;
        }

        // Check minimum redeem amount
        if (minRedeemAmount > 0 && naraUsdAmount < minRedeemAmount) {
            return 0;
        }

        // Calculate collateral needed
        uint256 collateralNeeded = _convertToCollateralAmount(collateralAsset, naraUsdAmount);
        uint256 availableCollateral = mct.collateralBalance(collateralAsset);

        // Check if instant redemption is possible
        if (availableCollateral < collateralNeeded) {
            return 0;
        }

        // Calculate collateral amount after fees
        // Fee is calculated on NaraUSD amount (18 decimals), then converted to collateral decimals
        uint256 feeAmount18 = _calculateRedeemFee(naraUsdAmount);

        if (feeAmount18 > 0) {
            // Convert fee from 18 decimals to collateral decimals
            uint256 feeAmountCollateral = _convertToCollateralAmount(collateralAsset, feeAmount18);
            collateralAmount = collateralNeeded > feeAmountCollateral ? collateralNeeded - feeAmountCollateral : 0;
        } else {
            collateralAmount = collateralNeeded;
        }

        return collateralAmount;
    }

    /**
     * @notice Update queued redemption request amount
     * @param newAmount The new amount of NaraUSD to redeem
     * @dev Only updates the queued amount. Use tryCompleteRedeem() to attempt completion.
     */
    function updateRedemptionRequest(uint256 newAmount) external nonReentrant whenNotPaused {
        RedemptionRequest memory request = _redemptionRequests[msg.sender];

        if (request.naraUsdAmount == 0) revert NoRedemptionRequest();
        if (newAmount == 0) revert InvalidAmount();

        // Check minimum redeem amount
        if (minRedeemAmount > 0 && newAmount < minRedeemAmount) {
            revert BelowMinimumAmount();
        }

        // Check blacklist and Keyring compliance (required for all redemption operations)
        if (_isBlacklisted(msg.sender)) {
            revert OperationNotAllowed();
        }
        _checkKeyringCredential(msg.sender);

        address collateralAsset = request.collateralAsset;
        uint256 currentAmount = request.naraUsdAmount;

        // Update queued amount only (no automatic instant redemption)
        if (newAmount > currentAmount) {
            // Increasing - transfer additional NaraUSD to silo
            uint256 additionalAmount = newAmount - currentAmount;
            _transfer(msg.sender, address(redeemSilo), additionalAmount);
        } else if (newAmount < currentAmount) {
            // Decreasing - return excess NaraUSD from silo to user
            uint256 excessAmount = currentAmount - newAmount;
            redeemSilo.withdraw(msg.sender, excessAmount);
        }

        // Update stored amount
        _redemptionRequests[msg.sender].naraUsdAmount = uint152(newAmount);

        emit RedemptionRequested(msg.sender, newAmount, collateralAsset);
    }

    /**
     * @notice Cancel redemption request and return locked NaraUSD to user
     * @dev This function always works regardless of asset support status, providing an escape hatch
     *      for users if their requested collateral asset is removed from MCT's supported assets.
     * @dev Note: Users can cancel at any time. This is by design.
     *      If a solver attempts to complete a cancelled request, the call will revert with NoRedemptionRequest.
     * @dev Note: Users can repeatedly create and cancel requests (spam is possible but costs gas).
     */
    function cancelRedeem() external nonReentrant whenNotPaused {
        if (_isBlacklisted(msg.sender)) {
            revert OperationNotAllowed();
        }

        RedemptionRequest memory request = _redemptionRequests[msg.sender];

        if (request.naraUsdAmount == 0) revert NoRedemptionRequest();

        uint256 naraUsdAmount = request.naraUsdAmount;

        // Clear redemption request
        delete _redemptionRequests[msg.sender];

        // Return NaraUSD from silo to user
        redeemSilo.withdraw(msg.sender, naraUsdAmount);

        emit RedemptionCancelled(msg.sender, naraUsdAmount);
    }

    /* --------------- ADMIN FUNCTIONS --------------- */

    /**
     * @notice Set max mint per block
     * @param _maxMintPerBlock New max mint per block
     */
    function setMaxMintPerBlock(uint256 _maxMintPerBlock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxMintPerBlock(_maxMintPerBlock);
    }

    /**
     * @notice Set max redeem per block
     * @param _maxRedeemPerBlock New max redeem per block
     */
    function setMaxRedeemPerBlock(uint256 _maxRedeemPerBlock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxRedeemPerBlock(_maxRedeemPerBlock);
    }

    /**
     * @notice Disable mint and redeem in emergency
     */
    function disableMintRedeem() external onlyRole(GATEKEEPER_ROLE) {
        _setMaxMintPerBlock(0);
        _setMaxRedeemPerBlock(0);
    }

    /**
     * @notice Pause all mint and redeem operations
     */
    function pause() external onlyRole(GATEKEEPER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause all mint and redeem operations
     */
    function unpause() external onlyRole(GATEKEEPER_ROLE) {
        _unpause();
    }

    /**
     * @notice Set mint fee
     * @param _mintFeeBps New mint fee in basis points (max 10%)
     */
    function setMintFee(uint16 _mintFeeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_mintFeeBps > MAX_FEE_BPS) revert InvalidFee();
        if (_mintFeeBps == mintFeeBps) revert ValueUnchanged();
        uint16 oldFee = mintFeeBps;
        mintFeeBps = _mintFeeBps;
        emit MintFeeUpdated(oldFee, _mintFeeBps);
    }

    /**
     * @notice Set redeem fee
     * @param _redeemFeeBps New redeem fee in basis points (max 10%)
     */
    function setRedeemFee(uint16 _redeemFeeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_redeemFeeBps > MAX_FEE_BPS) revert InvalidFee();
        if (_redeemFeeBps == redeemFeeBps) revert ValueUnchanged();
        uint16 oldFee = redeemFeeBps;
        redeemFeeBps = _redeemFeeBps;
        emit RedeemFeeUpdated(oldFee, _redeemFeeBps);
    }

    /**
     * @notice Set fee treasury address
     * @param _feeTreasury New treasury address
     */
    function setFeeTreasury(address _feeTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_feeTreasury == address(0)) revert ZeroAddressException();
        if (_feeTreasury == feeTreasury) revert ValueUnchanged();
        address oldTreasury = feeTreasury;
        feeTreasury = _feeTreasury;
        emit FeeTreasuryUpdated(oldTreasury, _feeTreasury);
    }

    /**
     * @notice Set minimum mint amount
     * @param _minMintAmount New minimum mint amount (18 decimals)
     */
    function setMinMintAmount(uint256 _minMintAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minMintAmount == minMintAmount) revert ValueUnchanged();
        // Ensure minimum fee doesn't exceed minimum amount (if both are non-zero)
        if (_minMintAmount > 0 && minMintFeeAmount > 0 && minMintFeeAmount >= _minMintAmount) {
            revert InvalidFee();
        }
        uint256 oldAmount = minMintAmount;
        minMintAmount = _minMintAmount;
        emit MinMintAmountUpdated(oldAmount, _minMintAmount);
    }

    /**
     * @notice Set minimum redeem amount
     * @param _minRedeemAmount New minimum redeem amount (18 decimals)
     * @dev Note: Increasing this value will NOT invalidate existing queued redemption requests.
     *      Queued requests below the new minimum will remain valid and can still be completed.
     */
    function setMinRedeemAmount(uint256 _minRedeemAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minRedeemAmount == minRedeemAmount) revert ValueUnchanged();
        // Ensure minimum fee doesn't exceed minimum amount (if both are non-zero)
        if (_minRedeemAmount > 0 && minRedeemFeeAmount > 0 && minRedeemFeeAmount >= _minRedeemAmount) {
            revert InvalidFee();
        }
        uint256 oldAmount = minRedeemAmount;
        minRedeemAmount = _minRedeemAmount;
        emit MinRedeemAmountUpdated(oldAmount, _minRedeemAmount);
    }

    /**
     * @notice Set minimum mint fee amount
     * @param _minMintFeeAmount New minimum mint fee amount (18 decimals)
     */
    function setMinMintFeeAmount(uint256 _minMintFeeAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minMintFeeAmount == minMintFeeAmount) revert ValueUnchanged();
        // Ensure minimum fee doesn't exceed minimum amount (if both are non-zero)
        if (minMintAmount > 0 && _minMintFeeAmount > 0 && _minMintFeeAmount >= minMintAmount) {
            revert InvalidFee();
        }
        uint256 oldAmount = minMintFeeAmount;
        minMintFeeAmount = _minMintFeeAmount;
        emit MinMintFeeAmountUpdated(oldAmount, _minMintFeeAmount);
    }

    /**
     * @notice Set minimum redeem fee amount
     * @param _minRedeemFeeAmount New minimum redeem fee amount (18 decimals)
     */
    function setMinRedeemFeeAmount(uint256 _minRedeemFeeAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minRedeemFeeAmount == minRedeemFeeAmount) revert ValueUnchanged();
        // Ensure minimum fee doesn't exceed minimum amount (if both are non-zero)
        if (minRedeemAmount > 0 && _minRedeemFeeAmount > 0 && _minRedeemFeeAmount >= minRedeemAmount) {
            revert InvalidFee();
        }
        uint256 oldAmount = minRedeemFeeAmount;
        minRedeemFeeAmount = _minRedeemFeeAmount;
        emit MinRedeemFeeAmountUpdated(oldAmount, _minRedeemFeeAmount);
    }

    /**
     * @notice Set Keyring contract address and policy ID
     * @param _keyringAddress Address of the Keyring contract (set to address(0) to disable)
     * @param _policyId The policy ID to check credentials against
     */
    function setKeyringConfig(address _keyringAddress, uint256 _policyId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_keyringAddress == keyringAddress && _policyId == keyringPolicyId) revert ValueUnchanged();
        keyringAddress = _keyringAddress;
        keyringPolicyId = _policyId;
        emit KeyringConfigUpdated(_keyringAddress, _policyId);
    }

    /**
     * @notice Add or remove an address from the Keyring whitelist
     * @param account The address to update whitelist status for
     * @param status True to whitelist, false to remove from whitelist
     * @dev Whitelisted addresses bypass Keyring checks (useful for AMM pools, smart contracts)
     */
    function setKeyringWhitelist(address account, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddressException();
        if (keyringWhitelist[account] == status) revert ValueUnchanged();
        keyringWhitelist[account] = status;
        emit KeyringWhitelistUpdated(account, status);
    }

    /**
     * @notice Add an address to blacklist
     * @param target The address to blacklist
     */
    function addToBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) notAdmin(target) {
        if (target == address(0)) revert ZeroAddressException();
        if (hasRole(FULL_RESTRICTED_ROLE, target)) revert ValueUnchanged();
        _grantRole(FULL_RESTRICTED_ROLE, target);
    }

    /**
     * @notice Remove an address from blacklist
     * @param target The address to un-blacklist
     */
    function removeFromBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        if (target == address(0)) revert ZeroAddressException();
        if (!hasRole(FULL_RESTRICTED_ROLE, target)) revert ValueUnchanged();
        _revokeRole(FULL_RESTRICTED_ROLE, target);
    }

    /**
     * @notice Redistribute locked amount from blacklisted user (both wallet and escrowed)
     * @param from The address to redistribute from (must have FULL_RESTRICTED_ROLE)
     * @param to The address to mint the balance to (or address(0) to burn)
     * @dev Handles both:
     *      1. Wallet balance - regular balanceOf(from)
     *      2. Escrowed balance - NaraUSD locked in redeemSilo from queued redemptions
     *      This ensures all funds from a blacklisted user can be recovered/redistributed
     */
    function redistributeLockedAmount(address from, address to) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (from == address(0)) revert ZeroAddressException();
        if (!_isBlacklisted(from)) {
            revert OperationNotAllowed();
        }
        // Allow to = address(0) for burning, but otherwise check blacklist
        if (to != address(0) && _isBlacklisted(to)) {
            revert OperationNotAllowed();
        }

        uint256 walletAmount = balanceOf(from);
        uint256 escrowedAmount = 0;

        // Handle wallet balance
        if (walletAmount > 0) {
            // Bypass blacklist check by calling super._update directly for the burn
            // This is safe because it's admin-only and explicitly for moving frozen funds
            super._update(from, address(0), walletAmount);
        }

        // Handle escrowed balance in redemption queue
        RedemptionRequest memory request = _redemptionRequests[from];
        if (request.naraUsdAmount > 0) {
            escrowedAmount = request.naraUsdAmount;

            // Clear the redemption request
            delete _redemptionRequests[from];

            // Withdraw escrowed NaraUSD from silo to this contract
            redeemSilo.withdraw(address(this), escrowedAmount);

            // Burn the escrowed tokens
            _burn(address(this), escrowedAmount);
        }

        uint256 totalAmount = walletAmount + escrowedAmount;

        // Mint total amount to recipient (or burn if to == address(0))
        if (to != address(0) && totalAmount > 0) {
            _mint(to, totalAmount);
        }

        emit LockedAmountRedistributed(from, to, walletAmount, escrowedAmount);
    }

    /**
     * @notice Internal helper to check if an address is fully restricted (blacklisted)
     * @param account The address to check
     * @return bool True if account has FULL_RESTRICTED_ROLE
     */
    function _isBlacklisted(address account) internal view returns (bool) {
        return hasRole(FULL_RESTRICTED_ROLE, account);
    }

    /**
     * @notice Public view helper to check if an address is blacklisted
     * @param account The address to check
     * @return bool True if account has FULL_RESTRICTED_ROLE
     */
    function isBlacklisted(address account) external view returns (bool) {
        return _isBlacklisted(account);
    }

    /**
     * @notice Burn NaraUSD tokens and underlying MCT without withdrawing collateral
     * @dev This creates a deflationary effect: burns both NaraUSD and MCT while keeping collateral in MCT
     * @dev Burns tokens from msg.sender only (caller must own the tokens)
     * @param amount The amount of NaraUSD to burn
     */
    function burn(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        // Burn NaraUSD from caller (1:1 with MCT)
        _burn(msg.sender, amount);

        // Burn the equivalent MCT tokens held by this contract
        // This keeps the collateral in MCT but reduces MCT supply
        // Making remaining MCT more valuable (since same collateral backs fewer tokens)
        mct.burn(amount);
    }

    /* --------------- INTERNAL --------------- */

    /**
     * @notice Calculate mint fee amount
     * @param amount The amount to calculate fee on (18 decimals)
     * @return feeAmount The fee amount (18 decimals)
     */
    function _calculateMintFee(uint256 amount) internal view returns (uint256 feeAmount) {
        if (feeTreasury == address(0)) {
            return 0;
        }

        uint256 percentageFee = 0;
        if (mintFeeBps > 0) {
            percentageFee = (amount * mintFeeBps) / BPS_DENOMINATOR;
        }
        feeAmount = percentageFee > minMintFeeAmount ? percentageFee : minMintFeeAmount;
    }

    /**
     * @notice Calculate redeem fee amount
     * @param amount The amount to calculate fee on (18 decimals)
     * @return feeAmount The fee amount (18 decimals)
     */
    function _calculateRedeemFee(uint256 amount) internal view returns (uint256 feeAmount) {
        if (feeTreasury == address(0)) {
            return 0;
        }

        uint256 percentageFee = 0;
        if (redeemFeeBps > 0) {
            percentageFee = (amount * redeemFeeBps) / BPS_DENOMINATOR;
        }
        feeAmount = percentageFee > minRedeemFeeAmount ? percentageFee : minRedeemFeeAmount;
    }

    /**
     * @notice Internal mint logic with collateral
     * @param collateralAsset The collateral asset
     * @param collateralAmount The amount of collateral
     * @return The amount of NaraUSD minted (after fees)
     */
    function _mintWithCollateral(address collateralAsset, uint256 collateralAmount) internal returns (uint256) {
        if (collateralAmount == 0) revert InvalidAmount();
        if (!mct.isSupportedAsset(collateralAsset)) revert UnsupportedAsset();

        // Check blacklist restrictions (full restriction prevents minting)
        if (_isBlacklisted(msg.sender)) {
            revert OperationNotAllowed();
        }

        // Check Keyring credentials
        _checkKeyringCredential(msg.sender);

        // Convert collateral to NaraUSD amount (normalize decimals)
        uint256 naraUsdAmount = _convertToNaraUsdAmount(collateralAsset, collateralAmount);

        // Calculate mint fee to determine actual mint amount
        uint256 feeAmount18 = _calculateMintFee(naraUsdAmount);
        uint256 expectedMintAmount = naraUsdAmount - feeAmount18;

        // Check per-block mint limit using post-fee amount (actual amount that will be minted)
        _checkBelowMaxMintPerBlock(expectedMintAmount);

        // Track minted amount using post-fee amount (actual circulating supply increase)
        mintedPerBlock[block.number] += expectedMintAmount;

        // Transfer collateral from caller to this contract
        IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Calculate collateral for minting (after deducting fee)
        uint256 collateralForMinting = collateralAmount;

        if (feeAmount18 > 0) {
            // Convert fee from 18 decimals back to collateral decimals
            uint256 feeAmountCollateral = _convertToCollateralAmount(collateralAsset, feeAmount18);
            collateralForMinting = collateralAmount - feeAmountCollateral;

            // Transfer fee in collateral to treasury
            IERC20(collateralAsset).safeTransfer(feeTreasury, feeAmountCollateral);
            emit FeeCollected(feeTreasury, feeAmountCollateral, true);
        }

        // Approve MCT to spend remaining collateral
        IERC20(collateralAsset).safeIncreaseAllowance(address(mct), collateralForMinting);

        // Mint MCT by depositing remaining collateral
        uint256 mctAmount = mct.mint(collateralAsset, collateralForMinting, address(this));

        // Check minimum mint amount (after fees)
        if (minMintAmount > 0 && mctAmount < minMintAmount) {
            revert BelowMinimumAmount();
        }

        // Mint NaraUSD shares to msg.sender (1:1 with MCT)
        _mint(msg.sender, mctAmount);

        emit Mint(msg.sender, collateralAsset, collateralAmount, mctAmount);

        return mctAmount;
    }

    /**
     * @notice Convert collateral amount to NaraUSD amount (normalize decimals to 18)
     * @param collateralAsset The collateral asset address
     * @param collateralAmount The amount of collateral
     * @return The equivalent NaraUSD amount (18 decimals)
     */
    function _convertToNaraUsdAmount(
        address collateralAsset,
        uint256 collateralAmount
    ) internal view returns (uint256) {
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
     * @notice Convert NaraUSD amount to collateral amount (denormalize decimals)
     * @param collateralAsset The collateral asset address
     * @param naraUsdAmount The amount of NaraUSD (18 decimals)
     * @return The equivalent collateral amount
     */
    function _convertToCollateralAmount(
        address collateralAsset,
        uint256 naraUsdAmount
    ) internal view returns (uint256) {
        uint8 collateralDecimals = IERC20Metadata(collateralAsset).decimals();

        if (collateralDecimals == 18) {
            return naraUsdAmount;
        } else if (collateralDecimals < 18) {
            // Scale down (e.g., 18 decimals -> USDC 6 decimals)
            return naraUsdAmount / (10 ** (18 - collateralDecimals));
        } else {
            // Scale up (shouldn't happen with standard stablecoins)
            return naraUsdAmount * (10 ** (collateralDecimals - 18));
        }
    }

    /**
     * @notice Set max mint per block (internal)
     * @param _maxMintPerBlock New max mint per block
     */
    function _setMaxMintPerBlock(uint256 _maxMintPerBlock) internal {
        uint256 oldMax = maxMintPerBlock;
        maxMintPerBlock = _maxMintPerBlock;
        emit MaxMintPerBlockChanged(oldMax, _maxMintPerBlock);
    }

    /**
     * @notice Set max redeem per block (internal)
     * @param _maxRedeemPerBlock New max redeem per block
     */
    function _setMaxRedeemPerBlock(uint256 _maxRedeemPerBlock) internal {
        uint256 oldMax = maxRedeemPerBlock;
        maxRedeemPerBlock = _maxRedeemPerBlock;
        emit MaxRedeemPerBlockChanged(oldMax, _maxRedeemPerBlock);
    }

    /* --------------- OVERRIDES --------------- */

    /**
     * @notice Override ERC4626 withdraw - intentionally disabled
     * @dev ERC4626 withdraw() is unsupported. Use redeem(collateralAsset, naraUsdAmount, allowQueue) instead.
     *      This ensures all redemptions go through the proper flow with compliance checks and queue handling.
     */
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert("ERC4626 withdraw() is disabled. Use redeem(collateralAsset, naraUsdAmount, allowQueue)");
    }

    /**
     * @notice Override ERC4626 redeem - intentionally disabled
     * @dev ERC4626 redeem() is unsupported. Use redeem(collateralAsset, naraUsdAmount, allowQueue) instead.
     *      This ensures all redemptions go through the proper flow with compliance checks and queue handling.
     */
    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert("ERC4626 redeem() is disabled. Use redeem(collateralAsset, naraUsdAmount, allowQueue)");
    }

    /**
     * @notice Override ERC4626 deposit - disabled in favor of mintWithCollateral flow
     * @dev ERC4626 deposit() is intentionally disabled. Use mintWithCollateral() instead.
     *      This prevents direct MCT deposits that bypass compliance checks and per-block limits.
     */
    function deposit(uint256, address) public pure override returns (uint256) {
        revert("Use mintWithCollateral()");
    }

    /**
     * @notice Override ERC4626 mint - disabled in favor of mintWithCollateral flow
     * @dev ERC4626 mint() is intentionally disabled. Use mintWithCollateral() instead.
     *      This prevents direct MCT deposits that bypass compliance checks and per-block limits.
     */
    function mint(uint256, address) public pure override returns (uint256) {
        revert("Use mintWithCollateral()");
    }

    /**
     * @notice Override maxDeposit to reflect actual constraints
     * @return The maximum amount of assets that can be deposited
     * @dev Returns 0 when paused or when maxMintPerBlock is 0 (disabled)
     * @dev ERC4626 deposit is disabled, but this override ensures integrations see accurate limits
     */
    function maxDeposit(address) public view override returns (uint256) {
        if (paused() || maxMintPerBlock == 0) {
            return 0;
        }
        // Return remaining capacity for this block
        uint256 remaining = maxMintPerBlock > mintedPerBlock[block.number]
            ? maxMintPerBlock - mintedPerBlock[block.number]
            : 0;
        return remaining;
    }

    /**
     * @notice Override maxMint to reflect actual constraints
     * @return The maximum amount of shares that can be minted
     * @dev Returns 0 when paused or when maxMintPerBlock is 0 (disabled)
     * @dev ERC4626 mint is disabled, but this override ensures integrations see accurate limits
     */
    function maxMint(address) public view override returns (uint256) {
        if (paused() || maxMintPerBlock == 0) {
            return 0;
        }
        // Return remaining capacity for this block
        uint256 remaining = maxMintPerBlock > mintedPerBlock[block.number]
            ? maxMintPerBlock - mintedPerBlock[block.number]
            : 0;
        return remaining;
    }

    /**
     * @notice Override maxWithdraw to reflect that ERC4626 withdraw is disabled
     * @return The maximum amount of assets that can be withdrawn
     * @dev Returns 0 because ERC4626 withdraw() is disabled. Use redeem(collateralAsset, naraUsdAmount, allowQueue) instead.
     */
    function maxWithdraw(address) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Override maxRedeem to reflect that ERC4626 redeem is disabled
     * @return The maximum amount of shares that can be redeemed
     * @dev Returns 0 because ERC4626 redeem() is disabled. Use redeem(collateralAsset, naraUsdAmount, allowQueue) instead.
     */
    function maxRedeem(address) public pure override returns (uint256) {
        return 0;
    }

    /// @dev Override decimals to ensure 18 decimals
    function decimals() public pure override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        return 18;
    }

    /**
     * @notice Override previewDeposit to account for mint fees
     * @param assets The amount of assets (MCT) to deposit
     * @return shares The amount of shares (NaraUSD) that would be minted to the receiver after fees
     * @dev MUST be inclusive of deposit fees per ERC4626 standard
     * @dev Fee is calculated on MCT amount, then shares are minted 1:1 with remaining MCT
     * @dev Note: Since MCT is 1:1 with supported stablecoins (normalized to 18 decimals),
     *      this preview reflects the ratio between supported stablecoins (in 18 decimals) and NaraUSD.
     *      For example, 1000e18 USDC (normalized) = 1000e18 MCT = 1000e18 NaraUSD (minus fees).
     */
    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        uint256 baseShares = super.previewDeposit(assets);

        // Apply mint fee if configured
        uint256 feeAmount = _calculateMintFee(baseShares);
        shares = baseShares > feeAmount ? baseShares - feeAmount : 0;

        return shares;
    }

    /**
     * @notice Override previewMint to account for mint fees
     * @param shares The amount of shares (NaraUSD) to mint
     * @return assets The amount of assets (MCT) needed to mint shares (inclusive of fees)
     * @dev MUST be inclusive of deposit fees per ERC4626 standard
     * @dev To get 'shares' after fee, we need more MCT assets
     * @dev Note: Since MCT is 1:1 with supported stablecoins (normalized to 18 decimals),
     *      this preview reflects the ratio between NaraUSD and supported stablecoins (in 18 decimals).
     *      For example, to mint 1000e18 NaraUSD, you need 1000e18+ MCT (normalized stablecoins, plus fees).
     */
    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        // Calculate how many shares we need before fee to get 'shares' after fee
        uint256 sharesBeforeFee = shares;
        if (feeTreasury != address(0)) {
            if (mintFeeBps > 0) {
                // Calculate assuming percentage fee only
                uint256 denominator = BPS_DENOMINATOR - mintFeeBps;
                sharesBeforeFee = Math.ceilDiv(shares * BPS_DENOMINATOR, denominator);

                // Check if minimum fee would apply
                uint256 estimatedFee = _calculateMintFee(sharesBeforeFee);
                uint256 estimatedPercentageFee = (sharesBeforeFee * mintFeeBps) / BPS_DENOMINATOR;
                if (estimatedFee > estimatedPercentageFee) {
                    // Minimum fee applies, so: shares = sharesBeforeFee - minMintFeeAmount
                    sharesBeforeFee = shares + minMintFeeAmount;
                }
            } else if (minMintFeeAmount > 0) {
                // Only minimum fee applies (no percentage)
                sharesBeforeFee = shares + minMintFeeAmount;
            }
        }

        assets = super.previewMint(sharesBeforeFee);

        return assets;
    }

    /**
     * @notice Override previewRedeem to reflect that ERC4626 redeem is disabled
     * @return assets The amount of assets (MCT) that would be received
     * @dev Returns 0 because ERC4626 redeem() is disabled. Use previewRedeem(collateralAsset, naraUsdAmount) instead.
     */
    function previewRedeem(uint256) public pure override returns (uint256 assets) {
        return 0;
    }

    /**
     * @notice Override previewWithdraw to reflect that ERC4626 withdraw is disabled
     * @return shares The amount of shares (NaraUSD) needed to withdraw assets
     * @dev Returns 0 because ERC4626 withdraw() is disabled. Use previewRedeem(collateralAsset, naraUsdAmount) instead.
     */
    function previewWithdraw(uint256) public pure override returns (uint256 shares) {
        return 0;
    }

    /**
     * @notice Internal function to execute instant redemption
     * @param user The user redeeming
     * @param collateralAsset The collateral asset to receive
     * @param naraUsdAmount The amount of NaraUSD to redeem
     * @return collateralAmount The amount of collateral sent to user (after fees)
     */
    function _instantRedeem(
        address user,
        address collateralAsset,
        uint256 naraUsdAmount
    ) internal belowMaxRedeemPerBlock(naraUsdAmount) returns (uint256 collateralAmount) {
        // Track redeemed amount for per-block limit
        redeemedPerBlock[block.number] += naraUsdAmount;

        // Burn NaraUSD from user
        _burn(user, naraUsdAmount);

        // Execute redemption and transfer to user
        collateralAmount = _executeRedemption(user, collateralAsset, naraUsdAmount);

        emit Redeem(user, collateralAsset, naraUsdAmount, collateralAmount);

        return collateralAmount;
    }

    /**
     * @notice Internal function to queue a redemption request
     * @param user The user requesting redemption
     * @param collateralAsset The collateral asset to receive
     * @param naraUsdAmount The amount of NaraUSD to lock
     */
    function _queueRedeem(address user, address collateralAsset, uint256 naraUsdAmount) internal {
        if (_redemptionRequests[user].naraUsdAmount > 0) revert ExistingRedemptionRequest();

        // Transfer NaraUSD from user to silo (escrow)
        _transfer(user, address(redeemSilo), naraUsdAmount);

        // Record redemption request (valid until completed or cancelled)
        _redemptionRequests[user] = RedemptionRequest({
            naraUsdAmount: uint152(naraUsdAmount),
            collateralAsset: collateralAsset
        });

        emit RedemptionRequested(user, naraUsdAmount, collateralAsset);
    }

    /**
     * @notice Internal helper to complete a single redemption
     * @dev Reverts if the request does not exist
     * @dev Note: Queued redemption requests are NOT re-validated against the current minRedeemAmount.
     *      The minimum amount check is enforced only at request creation time in redeem().
     *      This means if governance increases minRedeemAmount after requests are queued,
     *      those legacy requests below the new minimum can still be completed ("grandfathered").
     * @dev IMPORTANT: This function depends on the collateral asset being supported in MCT at completion
     *      time, as MCT's redeem() function requires asset support. If governance removes the asset from
     *      MCT's supported assets after a request is queued, this function will revert. Users must use
     *      cancelRedeem() to recover their escrowed NaraUSD in such cases.
     * @param user The address whose redemption request should be completed
     * @return collateralAmount The amount of collateral sent to the user (after fees)
     */
    function _completeRedemption(address user) internal returns (uint256 collateralAmount) {
        RedemptionRequest memory request = _redemptionRequests[user];

        if (request.naraUsdAmount == 0) revert NoRedemptionRequest();

        // Check blacklist restrictions (full restriction prevents redeeming)
        if (_isBlacklisted(user)) {
            revert OperationNotAllowed();
        }

        // Check Keyring credentials
        _checkKeyringCredential(user);

        uint256 naraUsdAmount = request.naraUsdAmount;
        address collateralAsset = request.collateralAsset;

        // Check if sufficient collateral is available before attempting completion
        uint256 requiredCollateral = _convertToCollateralAmount(collateralAsset, naraUsdAmount);
        if (mct.collateralBalance(collateralAsset) < requiredCollateral) {
            revert InsufficientCollateral();
        }

        // Check per-block redemption limit
        _checkBelowMaxRedeemPerBlock(naraUsdAmount);

        // Track redeemed amount for per-block limit
        redeemedPerBlock[block.number] += naraUsdAmount;

        // Clear redemption request
        delete _redemptionRequests[user];

        // Withdraw NaraUSD from silo back to this contract
        redeemSilo.withdraw(address(this), naraUsdAmount);

        // Burn NaraUSD
        _burn(address(this), naraUsdAmount);

        // Execute redemption and transfer to user
        collateralAmount = _executeRedemption(user, collateralAsset, naraUsdAmount);

        emit RedemptionCompleted(user, naraUsdAmount, collateralAsset, collateralAmount);

        return collateralAmount;
    }

    /**
     * @notice Internal function to execute MCT redemption with fee handling
     * @param user The user receiving collateral
     * @param collateralAsset The collateral asset to receive
     * @param naraUsdAmount The amount of NaraUSD being redeemed
     * @return The amount of collateral sent to user (after fees)
     */
    function _executeRedemption(
        address user,
        address collateralAsset,
        uint256 naraUsdAmount
    ) internal returns (uint256) {
        // Redeem MCT for collateral to this contract
        uint256 receivedCollateral = mct.redeem(collateralAsset, naraUsdAmount, address(this));

        // Calculate redeem fee (convert collateral to 18 decimals for fee calculation)
        uint256 receivedCollateral18 = _convertToNaraUsdAmount(collateralAsset, receivedCollateral);
        uint256 feeAmount18 = _calculateRedeemFee(receivedCollateral18);
        uint256 collateralAmount = receivedCollateral;

        if (feeAmount18 > 0) {
            // Convert fee from 18 decimals back to collateral decimals
            uint256 feeAmountCollateral = _convertToCollateralAmount(collateralAsset, feeAmount18);
            collateralAmount = receivedCollateral - feeAmountCollateral;

            // Transfer fee in collateral to treasury
            IERC20(collateralAsset).safeTransfer(feeTreasury, feeAmountCollateral);
            emit FeeCollected(feeTreasury, feeAmountCollateral, false);
        }

        // Transfer remaining collateral to user
        IERC20(collateralAsset).safeTransfer(user, collateralAmount);

        return collateralAmount;
    }

    /**
     * @dev Hook that is called before any transfer of tokens
     * @dev Completely freezes blacklisted addresses - they cannot transfer, burn, or receive
     * @dev Only admin can move their tokens via redistributeLockedAmount
     * @dev Note: Keyring checks are NOT applied to transfers - NaraUSD is freely transferrable
     */
    function _update(address from, address to, uint256 value) internal virtual override(ERC20Upgradeable) {
        // Blacklisted addresses are completely frozen - they cannot send, receive, or operate transfers
        if (_isBlacklisted(from)) {
            revert OperationNotAllowed();
        }
        if (_isBlacklisted(to)) {
            revert OperationNotAllowed();
        }
        // Check msg.sender to prevent blacklisted operators from moving tokens via transferFrom
        // Note: from == msg.sender in direct transfers, but differs in transferFrom calls
        if (msg.sender != from && _isBlacklisted(msg.sender)) {
            revert OperationNotAllowed();
        }

        super._update(from, to, value);
    }

    /**
     * @notice Prevent renouncing ownership
     */
    function renounceRole(bytes32 role, address account) public virtual override(AccessControlUpgradeable) {
        if (role == DEFAULT_ADMIN_ROLE) revert CantRenounceOwnership();
        super.renounceRole(role, account);
    }
}
