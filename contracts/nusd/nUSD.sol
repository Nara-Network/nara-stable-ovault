// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../mct/MultiCollateralToken.sol";
import "./nUSDRedeemSilo.sol";

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
 * @title nUSD
 * @notice Omnichain vault version of nUSD with integrated minting functionality and redemption cooldown
 * @dev This contract combines ERC4626 vault with direct collateral minting
 * - Underlying asset: MCT (MultiCollateralToken)
 * - Exchange rate: 1:1 with MCT
 * - Users can mint by depositing collateral (USDC, etc.)
 * - Collateral is converted to MCT, then nUSD shares are minted
 * - Redemptions require cooldown: lock nUSD → wait X days → redeem to collateral → release
 * - Users can cancel redemption requests during cooldown period
 */
contract nUSD is ERC4626, ERC20Permit, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* --------------- CONSTANTS --------------- */

    /// @notice Role for emergency actions
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");

    /// @notice Role for managing collateral operations
    bytes32 public constant COLLATERAL_MANAGER_ROLE = keccak256("COLLATERAL_MANAGER_ROLE");

    /// @notice Role allowed to mint nUSD without collateral backing
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role that can blacklist and un-blacklist addresses
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    /// @notice Role that prevents an address from transferring, minting, or redeeming
    bytes32 public constant FULL_RESTRICTED_ROLE = keccak256("FULL_RESTRICTED_ROLE");

    /// @notice Maximum cooldown duration (90 days)
    uint24 public constant MAX_COOLDOWN_DURATION = 90 days;

    /// @notice Maximum fee in basis points (10% = 1000 bps)
    uint16 public constant MAX_FEE_BPS = 1000;

    /// @notice Basis points denominator (100% = 10000 bps)
    uint16 public constant BPS_DENOMINATOR = 10000;

    /* --------------- STRUCTS --------------- */

    /// @notice Redemption request structure
    struct RedemptionRequest {
        uint104 cooldownEnd; // Timestamp when cooldown ends
        uint152 nUSDAmount; // Amount of nUSD locked for redemption
        address collateralAsset; // Collateral asset to receive
    }

    /* --------------- STATE VARIABLES --------------- */

    /// @notice The MCT token (underlying asset)
    MultiCollateralToken public immutable mct;

    /// @notice nUSD minted per block
    mapping(uint256 => uint256) public mintedPerBlock;

    /// @notice nUSD redeemed per block
    mapping(uint256 => uint256) public redeemedPerBlock;

    /// @notice Max minted nUSD allowed per block
    uint256 public maxMintPerBlock;

    /// @notice Max redeemed nUSD allowed per block
    uint256 public maxRedeemPerBlock;

    /// @notice Minimum nUSD amount required for minting (18 decimals)
    uint256 public minMintAmount;

    /// @notice Minimum nUSD amount required for redemption (18 decimals)
    uint256 public minRedeemAmount;

    /// @notice Delegated signer status for smart contracts
    mapping(address => mapping(address => DelegatedSignerStatus)) public delegatedSigner;

    /// @notice Cooldown duration in seconds for redemptions
    uint24 public cooldownDuration;

    /// @notice Mapping of user addresses to their redemption requests
    mapping(address => RedemptionRequest) public redemptionRequests;

    /// @notice Silo contract for holding locked nUSD during cooldown
    nUSDRedeemSilo public immutable redeemSilo;

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
    event MinMintFeeAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event MinRedeemFeeAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event KeyringConfigUpdated(address indexed keyringAddress, uint256 policyId);
    event KeyringWhitelistUpdated(address indexed account, bool status);

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

    /* --------------- MODIFIERS --------------- */

    /// @notice Ensure minted amount doesn't exceed max per block
    modifier belowMaxMintPerBlock(uint256 mintAmount) {
        if (mintedPerBlock[block.number] + mintAmount > maxMintPerBlock) {
            revert MaxMintPerBlockExceeded();
        }
        _;
    }

    /// @notice Ensure redeemed amount doesn't exceed max per block
    modifier belowMaxRedeemPerBlock(uint256 redeemAmount) {
        if (redeemedPerBlock[block.number] + redeemAmount > maxRedeemPerBlock) {
            revert MaxRedeemPerBlockExceeded();
        }
        _;
    }

    /// @notice Ensure blacklist target is not admin
    modifier notAdmin(address target) {
        if (hasRole(DEFAULT_ADMIN_ROLE, target)) revert CantBlacklistOwner();
        _;
    }

    /* --------------- INTERNAL HELPERS --------------- */

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

    /* --------------- CONSTRUCTOR --------------- */

    constructor(
        MultiCollateralToken _mct,
        address admin,
        uint256 _maxMintPerBlock,
        uint256 _maxRedeemPerBlock
    ) ERC20("nUSD", "nUSD") ERC4626(IERC20(address(_mct))) ERC20Permit("nUSD") {
        if (address(_mct) == address(0)) revert ZeroAddressException();
        if (admin == address(0)) revert ZeroAddressException();

        mct = _mct;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GATEKEEPER_ROLE, admin);
        _grantRole(COLLATERAL_MANAGER_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(BLACKLIST_MANAGER_ROLE, admin);

        _setMaxMintPerBlock(_maxMintPerBlock);
        _setMaxRedeemPerBlock(_maxRedeemPerBlock);

        // Create silo for holding locked nUSD during redemption cooldown
        redeemSilo = new nUSDRedeemSilo(address(this), address(this));

        // Default cooldown to 7 days
        cooldownDuration = 7 days;
    }

    /* --------------- EXTERNAL MINT/REDEEM --------------- */

    /**
     * @notice Mint nUSD by depositing collateral
     * @param collateralAsset The collateral asset to deposit
     * @param collateralAmount The amount of collateral to deposit
     * @return nUSDAmount The amount of nUSD minted
     */
    function mintWithCollateral(
        address collateralAsset,
        uint256 collateralAmount
    ) external nonReentrant whenNotPaused returns (uint256 nUSDAmount) {
        return _mintWithCollateral(collateralAsset, collateralAmount, msg.sender);
    }

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
    ) external nonReentrant whenNotPaused returns (uint256 nUSDAmount) {
        if (delegatedSigner[msg.sender][beneficiary] != DelegatedSignerStatus.ACCEPTED) {
            revert InvalidSignature();
        }
        return _mintWithCollateral(collateralAsset, collateralAmount, beneficiary);
    }

    /**
     * @notice Mint nUSD without collateral backing (admin-controlled)
     * @param to The address to receive freshly minted nUSD
     * @param amount The amount of nUSD to mint
     * @dev Intended for protocol-controlled operations such as incentive programs
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert ZeroAddressException();
        if (amount == 0) revert InvalidAmount();
        _mint(to, amount);

        // Mint corresponding MCT to maintain 1:1 backing
        mct.mintWithoutCollateral(address(this), amount);
    }

    /* --------------- COOLDOWN REDEMPTION --------------- */

    /**
     * @notice Request redemption with cooldown - locks nUSD and starts cooldown timer
     * @param collateralAsset The collateral asset to receive after cooldown
     * @param nUSDAmount The amount of nUSD to lock for redemption
     */
    function cooldownRedeem(address collateralAsset, uint256 nUSDAmount) external nonReentrant whenNotPaused {
        if (nUSDAmount == 0) revert InvalidAmount();
        if (!mct.isSupportedAsset(collateralAsset)) revert UnsupportedAsset();
        if (redemptionRequests[msg.sender].nUSDAmount > 0) revert ExistingRedemptionRequest();

        // Check minimum redeem amount
        if (minRedeemAmount > 0 && nUSDAmount < minRedeemAmount) {
            revert BelowMinimumAmount();
        }

        // Check blacklist restrictions (full restriction prevents redeeming)
        if (hasRole(FULL_RESTRICTED_ROLE, msg.sender)) {
            revert OperationNotAllowed();
        }

        // Check Keyring credentials
        _checkKeyringCredential(msg.sender);

        // Transfer nUSD from user to silo (locks it)
        _transfer(msg.sender, address(redeemSilo), nUSDAmount);

        // Record redemption request
        redemptionRequests[msg.sender] = RedemptionRequest({
            cooldownEnd: uint104(block.timestamp + cooldownDuration),
            nUSDAmount: uint152(nUSDAmount),
            collateralAsset: collateralAsset
        });

        emit RedemptionRequested(msg.sender, nUSDAmount, collateralAsset, block.timestamp + cooldownDuration);
    }

    /**
     * @notice Complete redemption after cooldown period - redeems nUSD for collateral
     */
    function completeRedeem() external nonReentrant whenNotPaused returns (uint256 collateralAmount) {
        RedemptionRequest memory request = redemptionRequests[msg.sender];

        if (request.nUSDAmount == 0) revert NoRedemptionRequest();
        if (block.timestamp < request.cooldownEnd) revert CooldownNotFinished();

        // Check blacklist restrictions (full restriction prevents redeeming)
        if (hasRole(FULL_RESTRICTED_ROLE, msg.sender)) {
            revert OperationNotAllowed();
        }

        // Check Keyring credentials
        _checkKeyringCredential(msg.sender);

        uint256 nUSDAmount = request.nUSDAmount;
        address collateralAsset = request.collateralAsset;

        // Clear redemption request
        delete redemptionRequests[msg.sender];

        // Withdraw nUSD from silo back to this contract
        redeemSilo.withdraw(address(this), nUSDAmount);

        // Burn nUSD
        _burn(address(this), nUSDAmount);

        // Redeem MCT for collateral - first to this contract
        uint256 receivedCollateral = mct.redeem(collateralAsset, nUSDAmount, address(this));

        // Calculate redeem fee (convert collateral to 18 decimals for fee calculation)
        uint256 receivedCollateral18 = _convertToNUSDAmount(collateralAsset, receivedCollateral);
        uint256 feeAmount18 = _calculateRedeemFee(receivedCollateral18);
        uint256 collateralAfterFee = receivedCollateral;

        if (feeAmount18 > 0) {
            // Convert fee from 18 decimals back to collateral decimals
            uint256 feeAmountCollateral = _convertToCollateralAmount(collateralAsset, feeAmount18);
            collateralAfterFee = receivedCollateral - feeAmountCollateral;

            // Transfer fee in collateral to treasury
            IERC20(collateralAsset).safeTransfer(feeTreasury, feeAmountCollateral);
            emit FeeCollected(feeTreasury, feeAmountCollateral, false);
        }

        // Transfer remaining collateral to user
        IERC20(collateralAsset).safeTransfer(msg.sender, collateralAfterFee);

        emit RedemptionCompleted(msg.sender, nUSDAmount, collateralAsset, collateralAfterFee);

        // Return the actual collateral amount received by user (after fees)
        return collateralAfterFee;
    }

    /**
     * @notice Cancel redemption request and return locked nUSD to user
     */
    function cancelRedeem() external nonReentrant {
        RedemptionRequest memory request = redemptionRequests[msg.sender];

        if (request.nUSDAmount == 0) revert NoRedemptionRequest();

        uint256 nUSDAmount = request.nUSDAmount;

        // Clear redemption request
        delete redemptionRequests[msg.sender];

        // Return nUSD from silo to user
        redeemSilo.withdraw(msg.sender, nUSDAmount);

        emit RedemptionCancelled(msg.sender, nUSDAmount);
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
     * @notice Set cooldown duration for redemptions
     * @param duration New cooldown duration (max 90 days)
     */
    function setCooldownDuration(uint24 duration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (duration > MAX_COOLDOWN_DURATION) {
            revert InvalidCooldown();
        }

        uint24 previousDuration = cooldownDuration;
        cooldownDuration = duration;
        emit CooldownDurationUpdated(previousDuration, cooldownDuration);
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
        uint256 oldAmount = minMintAmount;
        minMintAmount = _minMintAmount;
        emit MinMintAmountUpdated(oldAmount, _minMintAmount);
    }

    /**
     * @notice Set minimum redeem amount
     * @param _minRedeemAmount New minimum redeem amount (18 decimals)
     */
    function setMinRedeemAmount(uint256 _minRedeemAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldAmount = minRedeemAmount;
        minRedeemAmount = _minRedeemAmount;
        emit MinRedeemAmountUpdated(oldAmount, _minRedeemAmount);
    }

    /**
     * @notice Set minimum mint fee amount
     * @param _minMintFeeAmount New minimum mint fee amount (18 decimals)
     */
    function setMinMintFeeAmount(uint256 _minMintFeeAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldAmount = minMintFeeAmount;
        minMintFeeAmount = _minMintFeeAmount;
        emit MinMintFeeAmountUpdated(oldAmount, _minMintFeeAmount);
    }

    /**
     * @notice Set minimum redeem fee amount
     * @param _minRedeemFeeAmount New minimum redeem fee amount (18 decimals)
     */
    function setMinRedeemFeeAmount(uint256 _minRedeemFeeAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
        keyringWhitelist[account] = status;
        emit KeyringWhitelistUpdated(account, status);
    }

    /**
     * @notice Add an address to blacklist
     * @param target The address to blacklist
     */
    function addToBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) notAdmin(target) {
        _grantRole(FULL_RESTRICTED_ROLE, target);
    }

    /**
     * @notice Remove an address from blacklist
     * @param target The address to un-blacklist
     */
    function removeFromBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        _revokeRole(FULL_RESTRICTED_ROLE, target);
    }

    /**
     * @notice Redistribute locked amount from full restricted user
     * @param from The address to burn the entire balance from (must have FULL_RESTRICTED_ROLE)
     * @param to The address to mint the entire balance to (or address(0) to burn)
     */
    function redistributeLockedAmount(address from, address to) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (hasRole(FULL_RESTRICTED_ROLE, from) && !hasRole(FULL_RESTRICTED_ROLE, to)) {
            uint256 amountToDistribute = balanceOf(from);

            _burn(from, amountToDistribute);

            // to address of address(0) enables burning
            if (to != address(0)) {
                _mint(to, amountToDistribute);
            }

            emit LockedAmountRedistributed(from, to, amountToDistribute);
        } else {
            revert OperationNotAllowed();
        }
    }

    /**
     * @notice Burn nUSD tokens and underlying MCT without withdrawing collateral
     * @dev This creates a deflationary effect: burns both nUSD and MCT while keeping collateral in MCT
     * @dev Burns tokens from msg.sender only (caller must own the tokens)
     * @param amount The amount of nUSD to burn
     */
    function burn(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        // Burn nUSD from caller (1:1 with MCT)
        _burn(msg.sender, amount);

        // Burn the equivalent MCT tokens held by this contract
        // This keeps the collateral in MCT but reduces MCT supply
        // Making remaining MCT more valuable (since same collateral backs fewer tokens)
        mct.burn(amount);
    }

    /* --------------- DELEGATED SIGNER FUNCTIONS --------------- */

    /**
     * @notice Enable smart contracts to delegate signing
     * @param _delegateTo The address to delegate to
     */
    function setDelegatedSigner(address _delegateTo) external {
        delegatedSigner[_delegateTo][msg.sender] = DelegatedSignerStatus.PENDING;
        emit DelegatedSignerInitiated(_delegateTo, msg.sender);
    }

    /**
     * @notice Confirm delegation
     * @param _delegatedBy The address that initiated delegation
     */
    function confirmDelegatedSigner(address _delegatedBy) external {
        if (delegatedSigner[msg.sender][_delegatedBy] != DelegatedSignerStatus.PENDING) {
            revert DelegationNotInitiated();
        }
        delegatedSigner[msg.sender][_delegatedBy] = DelegatedSignerStatus.ACCEPTED;
        emit DelegatedSignerAdded(msg.sender, _delegatedBy);
    }

    /**
     * @notice Remove delegated signer
     * @param _removedSigner The address to remove
     */
    function removeDelegatedSigner(address _removedSigner) external {
        delegatedSigner[_removedSigner][msg.sender] = DelegatedSignerStatus.REJECTED;
        emit DelegatedSignerRemoved(_removedSigner, msg.sender);
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
     * @param beneficiary The address to receive nUSD
     * @return nUSDAmount The amount of nUSD minted
     */
    function _mintWithCollateral(
        address collateralAsset,
        uint256 collateralAmount,
        address beneficiary
    ) internal belowMaxMintPerBlock(collateralAmount) returns (uint256 nUSDAmount) {
        if (collateralAmount == 0) revert InvalidAmount();
        if (!mct.isSupportedAsset(collateralAsset)) revert UnsupportedAsset();
        if (beneficiary == address(0)) revert ZeroAddressException();

        // Check blacklist restrictions (full restriction prevents minting)
        if (hasRole(FULL_RESTRICTED_ROLE, msg.sender) || hasRole(FULL_RESTRICTED_ROLE, beneficiary)) {
            revert OperationNotAllowed();
        }

        // Check Keyring credentials for sender only
        _checkKeyringCredential(msg.sender);

        // Convert collateral to nUSD amount (normalize decimals)
        nUSDAmount = _convertToNUSDAmount(collateralAsset, collateralAmount);

        // Check minimum mint amount
        if (minMintAmount > 0 && nUSDAmount < minMintAmount) {
            revert BelowMinimumAmount();
        }

        // Track minted amount
        mintedPerBlock[block.number] += nUSDAmount;

        // Transfer collateral from user to this contract
        IERC20(collateralAsset).safeTransferFrom(beneficiary, address(this), collateralAmount);

        // Calculate mint fee on collateral amount (convert to 18 decimals for fee calculation)
        uint256 collateralAmount18 = _convertToNUSDAmount(collateralAsset, collateralAmount);
        uint256 feeAmount18 = _calculateMintFee(collateralAmount18);
        uint256 collateralAfterFee = collateralAmount;
        uint256 collateralForMinting = collateralAmount;

        if (feeAmount18 > 0) {
            // Convert fee from 18 decimals back to collateral decimals
            uint256 feeAmountCollateral = _convertToCollateralAmount(collateralAsset, feeAmount18);
            collateralAfterFee = collateralAmount - feeAmountCollateral;
            collateralForMinting = collateralAfterFee;

            // Transfer fee in collateral to treasury
            IERC20(collateralAsset).safeTransfer(feeTreasury, feeAmountCollateral);
            emit FeeCollected(feeTreasury, feeAmountCollateral, true);
        }

        // Approve MCT to spend remaining collateral
        IERC20(collateralAsset).safeIncreaseAllowance(address(mct), collateralForMinting);

        // Mint MCT by depositing remaining collateral
        uint256 mctAmount = mct.mint(collateralAsset, collateralForMinting, address(this));

        // Mint nUSD shares to beneficiary (1:1 with MCT)
        _mint(beneficiary, mctAmount);

        emit Mint(beneficiary, collateralAsset, collateralAmount, mctAmount);

        // Return the actual amount minted to beneficiary (after fees)
        return mctAmount;
    }

    /**
     * @notice Convert collateral amount to nUSD amount (normalize decimals to 18)
     * @param collateralAsset The collateral asset address
     * @param collateralAmount The amount of collateral
     * @return The equivalent nUSD amount (18 decimals)
     */
    function _convertToNUSDAmount(address collateralAsset, uint256 collateralAmount) internal view returns (uint256) {
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
     * @notice Convert nUSD amount to collateral amount (denormalize decimals)
     * @param collateralAsset The collateral asset address
     * @param nUSDAmount The amount of nUSD (18 decimals)
     * @return The equivalent collateral amount
     */
    function _convertToCollateralAmount(address collateralAsset, uint256 nUSDAmount) internal view returns (uint256) {
        uint8 collateralDecimals = IERC20Metadata(collateralAsset).decimals();

        if (collateralDecimals == 18) {
            return nUSDAmount;
        } else if (collateralDecimals < 18) {
            // Scale down (e.g., 18 decimals -> USDC 6 decimals)
            return nUSDAmount / (10 ** (18 - collateralDecimals));
        } else {
            // Scale up (shouldn't happen with standard stablecoins)
            return nUSDAmount * (10 ** (collateralDecimals - 18));
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
     * @notice Override ERC4626 withdraw to enforce cooldown - disabled
     * @dev Use cooldownRedeem/completeRedeem instead
     */
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert("Use cooldownRedeem");
    }

    /**
     * @notice Override ERC4626 redeem to enforce cooldown - disabled
     * @dev Use cooldownRedeem/completeRedeem instead
     */
    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert("Use cooldownRedeem");
    }

    /// @dev Override decimals to ensure 18 decimals
    function decimals() public pure override(ERC4626, ERC20) returns (uint8) {
        return 18;
    }

    /**
     * @notice Override previewDeposit to account for mint fees
     * @param assets The amount of assets (MCT) to deposit
     * @return shares The amount of shares (nUSD) that would be minted to the receiver after fees
     * @dev MUST be inclusive of deposit fees per ERC4626 standard
     * @dev Fee is calculated on MCT amount, then shares are minted 1:1 with remaining MCT
     */
    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        // First get base conversion using ERC4626 formula
        uint256 baseShares = _convertToShares(assets, Math.Rounding.Floor);

        // Apply mint fee if configured
        uint256 feeAmount = _calculateMintFee(baseShares);
        shares = baseShares > feeAmount ? baseShares - feeAmount : 0;

        return shares;
    }

    /**
     * @notice Override previewMint to account for mint fees
     * @param shares The amount of shares (nUSD) to mint
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
        assets = _convertToAssets(sharesBeforeFee, Math.Rounding.Ceil);

        return assets;
    }

    /**
     * @notice Override previewRedeem to account for redeem fees
     * @param shares The amount of shares (nUSD) to redeem
     * @return assets The amount of assets (MCT) that would be received after fees
     * @dev MUST be inclusive of withdrawal fees per ERC4626 standard
     * @dev Note: Actual redeem fee is on collateral, but for ERC4626 we apply it to MCT (1:1 equivalent)
     */
    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        // First get base conversion using ERC4626 formula
        uint256 baseAssets = _convertToAssets(shares, Math.Rounding.Floor);

        // Apply redeem fee if configured
        uint256 feeAmount = _calculateRedeemFee(baseAssets);
        assets = baseAssets > feeAmount ? baseAssets - feeAmount : 0;

        return assets;
    }

    /**
     * @notice Override previewWithdraw to account for redeem fees
     * @param assets The amount of assets (MCT) to withdraw
     * @return shares The amount of shares (nUSD) needed to withdraw assets (inclusive of fees)
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
        shares = _convertToShares(assetsBeforeFee, Math.Rounding.Ceil);

        return shares;
    }

    /**
     * @dev Hook that is called before any transfer of tokens
     * @dev Disables transfers from or to addresses with FULL_RESTRICTED_ROLE
     * @dev Note: Keyring checks are NOT applied to transfers - nUSD is freely transferrable
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        // Check blacklist restrictions only
        if (hasRole(FULL_RESTRICTED_ROLE, from)) {
            revert OperationNotAllowed();
        }
        if (hasRole(FULL_RESTRICTED_ROLE, to)) {
            revert OperationNotAllowed();
        }

        super._update(from, to, value);
    }

    /**
     * @notice Prevent renouncing ownership
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        if (role == DEFAULT_ADMIN_ROLE) revert CantRenounceOwnership();
        super.renounceRole(role, account);
    }
}
