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
 * @dev This contract is upgradeable using UUPS proxy pattern
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
     * @notice Update queued redemption request amount
     * @param newAmount The new amount of NaraUSD to redeem
     * @dev If liquidity is now available, automatically executes instant redemption instead of keeping queued
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

        // Check if instant redemption is now possible
        uint256 collateralNeeded = _convertToCollateralAmount(collateralAsset, newAmount);
        uint256 availableCollateral = mct.collateralBalance(collateralAsset);

        if (availableCollateral >= collateralNeeded) {
            // Liquidity available - execute instant redemption
            _checkBelowMaxRedeemPerBlock(newAmount);

            redeemedPerBlock[block.number] += newAmount;

            // Clear the queued request first
            delete _redemptionRequests[msg.sender];

            // Withdraw currently escrowed NaraUSD from silo to this contract
            redeemSilo.withdraw(address(this), currentAmount);

            // Adjust balance: if newAmount > currentAmount, need more from user
            if (newAmount > currentAmount) {
                uint256 additionalAmount = newAmount - currentAmount;
                _transfer(msg.sender, address(this), additionalAmount);
            } else if (newAmount < currentAmount) {
                // Return excess to user
                uint256 excessAmount = currentAmount - newAmount;
                _transfer(address(this), msg.sender, excessAmount);
            }

            // Now execute instant redemption from this contract's balance
            _burn(address(this), newAmount);

            // Execute redemption and transfer to user
            uint256 collateralReceived = _executeRedemption(msg.sender, collateralAsset, newAmount);

            // Emit RedemptionCompleted because this was a queued request that is being fulfilled
            emit RedemptionCompleted(msg.sender, newAmount, collateralAsset, collateralReceived);
        } else {
            // Still no liquidity - update queued amount
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
    }

    /**
     * @notice Cancel redemption request and return locked NaraUSD to user
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
        address oldTreasury = feeTreasury;
        feeTreasury = _feeTreasury;
        emit FeeTreasuryUpdated(oldTreasury, _feeTreasury);
    }

    /**
     * @notice Set minimum mint amount
     * @param _minMintAmount New minimum mint amount (18 decimals)
     */
    function setMinMintAmount(uint256 _minMintAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
     */
    function setMinRedeemAmount(uint256 _minRedeemAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
        keyringWhitelist[account] = status;
        emit KeyringWhitelistUpdated(account, status);
    }

    /**
     * @notice Add an address to blacklist
     * @param target The address to blacklist
     */
    function addToBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) notAdmin(target) {
        if (target == address(0)) revert ZeroAddressException();
        _grantRole(FULL_RESTRICTED_ROLE, target);
    }

    /**
     * @notice Remove an address from blacklist
     * @param target The address to un-blacklist
     */
    function removeFromBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        if (target == address(0)) revert ZeroAddressException();
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
     * @notice Override ERC4626 withdraw - disabled in favor of custom redeem flow
     * @dev Use redeem() with instant/queue logic instead
     */
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert("Use redeem()");
    }

    /**
     * @notice Override ERC4626 redeem - disabled in favor of custom redeem flow
     * @dev The ERC4626 redeem(shares, receiver, owner) is replaced by our custom
     *      redeem(collateralAsset, naraUsdAmount, allowQueue) function
     */
    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert("Use redeem(collateralAsset, naraUsdAmount, allowQueue)");
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
     */
    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        // First get base conversion using ERC4626 formula
        uint256 baseShares = convertToShares(assets);

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

        // Convert sharesBeforeFee to assets using base conversion
        assets = convertToAssets(sharesBeforeFee);

        return assets;
    }

    /**
     * @notice Override previewRedeem to account for redeem fees
     * @param shares The amount of shares (NaraUSD) to redeem
     * @return assets The amount of assets (MCT) that would be received after fees
     * @dev MUST be inclusive of withdrawal fees per ERC4626 standard
     * @dev Note: Actual redeem fee is on collateral, but for ERC4626 we apply it to MCT (1:1 equivalent)
     */
    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        // First get base conversion using ERC4626 formula
        uint256 baseAssets = convertToAssets(shares);

        // Apply redeem fee if configured
        uint256 feeAmount = _calculateRedeemFee(baseAssets);
        assets = baseAssets > feeAmount ? baseAssets - feeAmount : 0;

        return assets;
    }

    /**
     * @notice Override previewWithdraw to account for redeem fees
     * @param assets The amount of assets (MCT) to withdraw
     * @return shares The amount of shares (NaraUSD) needed to withdraw assets (inclusive of fees)
     * @dev MUST be inclusive of withdrawal fees per ERC4626 standard
     * @dev To get 'assets' after fee, we need to redeem more shares
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        // Calculate how many assets we need before fee to get 'assets' after fee
        uint256 assetsBeforeFee = assets;
        if (feeTreasury != address(0)) {
            if (redeemFeeBps > 0) {
                // Calculate assuming percentage fee only
                uint256 denominator = BPS_DENOMINATOR - redeemFeeBps;
                assetsBeforeFee = Math.ceilDiv(assets * BPS_DENOMINATOR, denominator);

                // Check if minimum fee would apply
                uint256 estimatedFee = _calculateRedeemFee(assetsBeforeFee);
                uint256 estimatedPercentageFee = (assetsBeforeFee * redeemFeeBps) / BPS_DENOMINATOR;
                if (estimatedFee > estimatedPercentageFee) {
                    // Minimum fee applies, so: assets = assetsBeforeFee - minRedeemFeeAmount
                    assetsBeforeFee = assets + minRedeemFeeAmount;
                }
            } else if (minRedeemFeeAmount > 0) {
                // Only minimum fee applies (no percentage)
                assetsBeforeFee = assets + minRedeemFeeAmount;
            }
        }

        // Convert assetsBeforeFee to shares using base conversion
        shares = convertToShares(assetsBeforeFee);

        return shares;
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
