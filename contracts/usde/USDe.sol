// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../mct/MultiCollateralToken.sol";

/**
 * @title USDe
 * @notice Omnichain vault version of USDe with integrated minting functionality
 * @dev This contract combines ERC4626 vault with direct collateral minting
 * - Underlying asset: MCT (MultiCollateralToken)
 * - Exchange rate: 1:1 with MCT
 * - Users can mint by depositing collateral (USDC, etc.)
 * - Collateral is converted to MCT, then USDe shares are minted
 */
contract USDe is ERC4626, ERC20Permit, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* --------------- CONSTANTS --------------- */

    /// @notice Role for emergency actions
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");

    /// @notice Role for managing collateral operations
    bytes32 public constant COLLATERAL_MANAGER_ROLE = keccak256("COLLATERAL_MANAGER_ROLE");

    /* --------------- STATE VARIABLES --------------- */

    /// @notice The MCT token (underlying asset)
    MultiCollateralToken public immutable mct;

    /// @notice USDe minted per block
    mapping(uint256 => uint256) public mintedPerBlock;

    /// @notice USDe redeemed per block
    mapping(uint256 => uint256) public redeemedPerBlock;

    /// @notice Max minted USDe allowed per block
    uint256 public maxMintPerBlock;

    /// @notice Max redeemed USDe allowed per block
    uint256 public maxRedeemPerBlock;

    /// @notice Delegated signer status for smart contracts
    mapping(address => mapping(address => DelegatedSignerStatus)) public delegatedSigner;

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

    /* --------------- CONSTRUCTOR --------------- */

    constructor(
        MultiCollateralToken _mct,
        address admin,
        uint256 _maxMintPerBlock,
        uint256 _maxRedeemPerBlock
    ) ERC20("USDe", "USDe") ERC4626(IERC20(address(_mct))) ERC20Permit("USDe") {
        if (address(_mct) == address(0)) revert ZeroAddressException();
        if (admin == address(0)) revert ZeroAddressException();

        mct = _mct;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GATEKEEPER_ROLE, admin);
        _grantRole(COLLATERAL_MANAGER_ROLE, admin);

        _setMaxMintPerBlock(_maxMintPerBlock);
        _setMaxRedeemPerBlock(_maxRedeemPerBlock);
    }

    /* --------------- EXTERNAL MINT/REDEEM --------------- */

    /**
     * @notice Mint USDe by depositing collateral
     * @param collateralAsset The collateral asset to deposit
     * @param collateralAmount The amount of collateral to deposit
     * @return usdeAmount The amount of USDe minted
     */
    function mintWithCollateral(
        address collateralAsset,
        uint256 collateralAmount
    ) external nonReentrant returns (uint256 usdeAmount) {
        return _mintWithCollateral(collateralAsset, collateralAmount, msg.sender);
    }

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
    ) external nonReentrant returns (uint256 usdeAmount) {
        if (delegatedSigner[msg.sender][beneficiary] != DelegatedSignerStatus.ACCEPTED) {
            revert InvalidSignature();
        }
        return _mintWithCollateral(collateralAsset, collateralAmount, beneficiary);
    }

    /**
     * @notice Redeem USDe for collateral
     * @param collateralAsset The collateral asset to receive
     * @param usdeAmount The amount of USDe to redeem
     * @return collateralAmount The amount of collateral received
     */
    function redeemForCollateral(
        address collateralAsset,
        uint256 usdeAmount
    ) external nonReentrant returns (uint256 collateralAmount) {
        return _redeemForCollateral(collateralAsset, usdeAmount, msg.sender);
    }

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
    ) external nonReentrant returns (uint256 collateralAmount) {
        if (delegatedSigner[msg.sender][beneficiary] != DelegatedSignerStatus.ACCEPTED) {
            revert InvalidSignature();
        }
        return _redeemForCollateral(collateralAsset, usdeAmount, beneficiary);
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
     * @notice Internal mint logic with collateral
     * @param collateralAsset The collateral asset
     * @param collateralAmount The amount of collateral
     * @param beneficiary The address to receive USDe
     * @return usdeAmount The amount of USDe minted
     */
    function _mintWithCollateral(
        address collateralAsset,
        uint256 collateralAmount,
        address beneficiary
    ) internal belowMaxMintPerBlock(collateralAmount) returns (uint256 usdeAmount) {
        if (collateralAmount == 0) revert InvalidAmount();
        if (!mct.isSupportedAsset(collateralAsset)) revert UnsupportedAsset();
        if (beneficiary == address(0)) revert ZeroAddressException();

        // Convert collateral to USDe amount (normalize decimals)
        usdeAmount = _convertToUsdeAmount(collateralAsset, collateralAmount);

        // Track minted amount
        mintedPerBlock[block.number] += usdeAmount;

        // Transfer collateral from user to this contract
        IERC20(collateralAsset).safeTransferFrom(beneficiary, address(this), collateralAmount);

        // Approve MCT to spend collateral
        IERC20(collateralAsset).safeIncreaseAllowance(address(mct), collateralAmount);

        // Mint MCT by depositing collateral
        uint256 mctAmount = mct.mint(collateralAsset, collateralAmount, address(this));

        // Mint USDe shares (1:1 with MCT due to ERC4626)
        // Since we control the exchange rate to be 1:1, we mint directly
        _mint(beneficiary, mctAmount);

        emit Mint(beneficiary, collateralAsset, collateralAmount, usdeAmount);
    }

    /**
     * @notice Internal redeem logic for collateral
     * @param collateralAsset The collateral asset to receive
     * @param usdeAmount The amount of USDe to burn
     * @param beneficiary The address to receive collateral
     * @return collateralAmount The amount of collateral received
     */
    function _redeemForCollateral(
        address collateralAsset,
        uint256 usdeAmount,
        address beneficiary
    ) internal belowMaxRedeemPerBlock(usdeAmount) returns (uint256 collateralAmount) {
        if (usdeAmount == 0) revert InvalidAmount();
        if (!mct.isSupportedAsset(collateralAsset)) revert UnsupportedAsset();
        if (beneficiary == address(0)) revert ZeroAddressException();

        // Convert USDe amount to collateral amount
        collateralAmount = _convertToCollateralAmount(collateralAsset, usdeAmount);

        // Track redeemed amount
        redeemedPerBlock[block.number] += usdeAmount;

        // Burn USDe from beneficiary (1:1 with MCT)
        _burn(beneficiary, usdeAmount);

        // Approve MCT to burn
        IERC20(address(mct)).safeIncreaseAllowance(address(mct), usdeAmount);

        // Redeem MCT for collateral
        uint256 receivedCollateral = mct.redeem(collateralAsset, usdeAmount, beneficiary);

        emit Redeem(beneficiary, collateralAsset, usdeAmount, receivedCollateral);
    }

    /**
     * @notice Convert collateral amount to USDe amount (normalize decimals to 18)
     * @param collateralAsset The collateral asset address
     * @param collateralAmount The amount of collateral
     * @return The equivalent USDe amount (18 decimals)
     */
    function _convertToUsdeAmount(address collateralAsset, uint256 collateralAmount) internal view returns (uint256) {
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
     * @notice Convert USDe amount to collateral amount (denormalize decimals)
     * @param collateralAsset The collateral asset address
     * @param usdeAmount The amount of USDe (18 decimals)
     * @return The equivalent collateral amount
     */
    function _convertToCollateralAmount(address collateralAsset, uint256 usdeAmount) internal view returns (uint256) {
        uint8 collateralDecimals = IERC20Metadata(collateralAsset).decimals();

        if (collateralDecimals == 18) {
            return usdeAmount;
        } else if (collateralDecimals < 18) {
            // Scale down (e.g., 18 decimals -> USDC 6 decimals)
            return usdeAmount / (10 ** (18 - collateralDecimals));
        } else {
            // Scale up (shouldn't happen with standard stablecoins)
            return usdeAmount * (10 ** (collateralDecimals - 18));
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

    /// @dev Override decimals to ensure 18 decimals
    function decimals() public pure override(ERC4626, ERC20) returns (uint8) {
        return 18;
    }

    /**
     * @notice Prevent renouncing ownership
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        if (role == DEFAULT_ADMIN_ROLE) revert CantRenounceOwnership();
        super.renounceRole(role, account);
    }
}
