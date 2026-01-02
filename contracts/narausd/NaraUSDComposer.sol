// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { VaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { IOFT, SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

interface INaraUSD {
    function mintWithCollateral(
        address collateralAsset,
        uint256 collateralAmount
    ) external returns (uint256 naraUsdAmount);

    function redeem(
        address collateralAsset,
        uint256 naraUsdAmount,
        bool allowQueue
    ) external returns (uint256 collateralAmount, bool wasQueued);

    function hasValidCredentials(address account) external view returns (bool);

    function isBlacklisted(address account) external view returns (bool);

    function asset() external view returns (address);
}

interface IMCT {
    function hasRole(bytes32 role, address account) external view returns (bool);

    function defaultAdminRole() external view returns (bytes32);

    function collateralBalance(address asset) external view returns (uint256);

    function isSupportedAsset(address asset) external view returns (bool);
}

/// @notice Error thrown when sender does not have valid Keyring credentials
error UnauthorizedSender(address sender);

/// @notice Error thrown when caller is not authorized
error Unauthorized();

/// @notice Error thrown when collateral is already whitelisted
error CollateralAlreadyWhitelisted(address collateral);

/// @notice Error thrown when collateral is not whitelisted
error CollateralNotWhitelisted(address collateral);

/// @notice Error thrown when collateral OFT is not whitelisted for compose
error CollateralOFTNotWhitelisted(address oft);

/// @notice Error thrown when msg.value is sent for a local transfer that doesn't require fees
error NoMsgValueExpected();

/// @notice Error thrown when address(0) is provided as parameter
error ZeroAddressException();

/// @notice Error thrown when OFT is already mapped to a different collateral asset
error OFTAlreadyMapped(address oft, address existingAsset);

/// @notice Error thrown when asset is not supported by MCT
error AssetNotSupportedByMCT(address asset);

/// @notice Error thrown when ASSET_OFT is used in compose (it's validation-only, not for operations)
error AssetOFTNotAllowedInCompose();

/**
 * @title NaraUSDComposer
 * @notice Composer that enables cross-chain NaraUSD minting and redemption via collateral deposits
 *
 * @dev Overview:
 * This composer allows users to:
 * - Deposit collateral (USDC/USDT) on any chain and receive NaraUSD shares on any destination chain
 * - Redeem NaraUSD shares on any chain and receive collateral on any destination chain (if liquidity available)
 *
 * Deposit Flow:
 * 1. User sends collateral (USDC) from spoke chain via Stargate/collateral OFT
 * 2. NaraUSDComposer receives collateral on hub chain via lzCompose
 * 3. Composer calls NaraUSD.mintWithCollateral(collateralAsset, amount)
 * 4. NaraUSD internally manages MCT (MultiCollateralToken) - user never sees it
 * 5. Composer sends NaraUSD shares cross-chain via SHARE_OFT (NaraUSDOFTAdapter)
 * 6. User receives NaraUSD on destination chain
 *
 * Redeem Flow:
 * 1. User sends NaraUSD shares from spoke chain via SHARE_OFT
 * 2. NaraUSDComposer receives shares on hub chain via lzCompose
 * 3. Composer checks liquidity for requested collateral asset
 * 4. If liquidity available: Composer calls NaraUSD.redeem(collateralAsset, amount, false)
 *    - This burns NaraUSD shares and transfers collateral to composer
 * 5. Composer sends collateral cross-chain via collateral OFT
 * 6. User receives collateral on destination chain
 * 7. If no liquidity: Transaction reverts and NaraUSD shares are refunded via SHARE_OFT
 *
 * @dev IMPORTANT - ASSET_OFT Parameter (Validation Only):
 *
 * This contract inherits from VaultComposerSync which requires an ASSET_OFT parameter
 * that must satisfy: ASSET_OFT.token() == VAULT.asset()
 *
 * For NaraUSD vault:
 * - VAULT.asset() = MCT (MultiCollateralToken)
 * - Therefore ASSET_OFT must be MCTOFTAdapter
 * - BUT: MCT NEVER goes cross-chain! It's hub-only and invisible to users.
 *
 * The ASSET_OFT (MCTOFTAdapter) exists ONLY to pass constructor validation.
 * It is NEVER used in the actual compose flow!
 * ASSET_OFT compose operations are explicitly blocked at runtime with AssetOFTNotAllowedInCompose().
 *
 * Actual Flow Uses:
 * ✅ collateralAsset - What users actually deposit (USDC/USDT)
 * ✅ collateralAssetOFT - For cross-chain collateral (Stargate USDC OFT)
 * ✅ SHARE_OFT - For sending NaraUSD cross-chain (NaraUSDOFTAdapter)
 * ❌ ASSET_OFT - Only for validation, explicitly blocked in compose operations
 *
 * See _depositCollateralAndSend() for the actual deposit logic that uses
 * collateralAsset, not ASSET_OFT.
 *
 * @custom:security MCT stays on hub chain only, ASSET_OFT is not used for cross-chain
 * @custom:note See MCTOFTAdapter.sol and WHY_MCTOFT_ADAPTER_EXISTS.md for details
 */
contract NaraUSDComposer is VaultComposerSync {
    using SafeERC20 for IERC20;
    using OFTComposeMsgCodec for bytes;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Set of whitelisted collateral assets
    EnumerableSet.AddressSet private _whitelistedCollaterals;

    /// @notice Mapping from collateral OFT address to collateral asset address
    mapping(address => address) public oftToCollateral;

    /// @notice Mapping from collateral asset address to its OFT address
    mapping(address => address) public collateralToOft;

    event Error(bytes errorData);
    event CollateralWhitelisted(address indexed collateral, address indexed oft);
    event CollateralRemoved(address indexed collateral, address indexed oft);

    /**
     * @notice Creates a new NaraUSDComposer for cross-chain NaraUSD minting
     *
     * @param _vault The NaraUSD vault contract implementing ERC4626
     *
     * @param _assetOft VALIDATION ONLY - MCTOFTAdapter that satisfies vault.asset() check
     *                  This is NEVER used for actual cross-chain operations!
     *                  MCT (vault's underlying asset) stays on hub chain only.
     *                  Passed only to satisfy VaultComposerSync constructor validation.
     *                  See contract-level documentation for detailed explanation.
     *
     * @param _shareOft The NaraUSD OFT adapter for cross-chain share transfers (ACTUALLY USED)
     *                  This is what sends NaraUSD cross-chain to users.
     *
     * @dev Key Point: _assetOft (MCT) is required by base class but never used.
     *      The actual flow uses whitelisted collateral assets and _shareOft.
     * @dev Admin must whitelist collateral assets after deployment using addWhitelistedCollateral()
     */
    constructor(address _vault, address _assetOft, address _shareOft) VaultComposerSync(_vault, _assetOft, _shareOft) {}

    /**
     * @notice Add a collateral asset and its OFT to the whitelist
     * @param asset The collateral token address (e.g., USDC, USDT)
     * @param assetOft The OFT contract for the collateral asset
     * @dev Only callable by MCT admin (same role that manages MCT's supported assets)
     */
    function addWhitelistedCollateral(address asset, address assetOft) external {
        address mct = INaraUSD(address(VAULT)).asset();
        bytes32 adminRole = IMCT(mct).defaultAdminRole();
        if (!IMCT(mct).hasRole(adminRole, msg.sender)) {
            revert Unauthorized();
        }

        if (asset == address(0) || assetOft == address(0)) {
            revert ZeroAddressException();
        }

        // Verify asset is supported by MCT (composer whitelist must be subset of MCT supported assets)
        if (!IMCT(mct).isSupportedAsset(asset)) {
            revert AssetNotSupportedByMCT(asset);
        }

        // Check if OFT is already mapped to a different asset
        address existingAsset = oftToCollateral[assetOft];
        if (existingAsset != address(0) && existingAsset != asset) {
            revert OFTAlreadyMapped(assetOft, existingAsset);
        }

        if (!_whitelistedCollaterals.add(asset)) {
            revert CollateralAlreadyWhitelisted(asset);
        }

        oftToCollateral[assetOft] = asset;
        collateralToOft[asset] = assetOft;

        // Approve collateral to its OFT for potential refunds
        IERC20(asset).approve(assetOft, type(uint256).max);

        emit CollateralWhitelisted(asset, assetOft);
    }

    /**
     * @notice Remove a collateral asset from the whitelist
     * @param asset The collateral token address to remove
     * @dev Only callable by MCT admin (same role that manages MCT's supported assets)
     */
    function removeWhitelistedCollateral(address asset) external {
        address mct = INaraUSD(address(VAULT)).asset();
        bytes32 adminRole = IMCT(mct).defaultAdminRole();
        if (!IMCT(mct).hasRole(adminRole, msg.sender)) {
            revert Unauthorized();
        }

        if (!_whitelistedCollaterals.remove(asset)) {
            revert CollateralNotWhitelisted(asset);
        }

        address assetOft = collateralToOft[asset];
        delete oftToCollateral[assetOft];
        delete collateralToOft[asset];

        // Revoke approval
        IERC20(asset).approve(assetOft, 0);

        emit CollateralRemoved(asset, assetOft);
    }

    /**
     * @notice Get all whitelisted collateral assets
     * @return Array of whitelisted collateral asset addresses
     */
    function getWhitelistedCollaterals() external view returns (address[] memory) {
        return _whitelistedCollaterals.values();
    }

    /**
     * @notice Get the number of whitelisted collateral assets
     * @return Count of whitelisted collaterals
     */
    function getWhitelistedCollateralsCount() external view returns (uint256) {
        return _whitelistedCollaterals.length();
    }

    /**
     * @notice Check if a collateral asset is whitelisted
     * @param asset The collateral asset address to check
     * @return True if whitelisted, false otherwise
     */
    function isCollateralWhitelisted(address asset) external view returns (bool) {
        return _whitelistedCollaterals.contains(asset);
    }

    /**
     * @notice Internal function to handle collateral deposits and cross-chain share sending
     * @dev This is the ACTUAL deposit flow used by this composer.
     *      Note: Does NOT use ASSET_OFT (MCT). Uses whitelisted collateral assets instead.
     *
     * Flow:
     * 1. Determine which collateral asset was sent via its OFT
     * 2. Approve NaraUSD to pull collateral
     * 3. Call NaraUSD.mintWithCollateral(collateralAsset, amount) - MCT handled internally
     * 4. Receive NaraUSD shares
     * 5. Send shares cross-chain via SHARE_OFT (not ASSET_OFT!)
     *
     * @param _depositor The address requesting the deposit
     * @param _assetAmount The amount of collateral to deposit
     * @param _sendParam Parameters for sending shares cross-chain
     * @param _refundAddress Address to refund excess msg.value
     * @param _collateralOft The OFT contract that sent the collateral
     */
    function _depositCollateralAndSend(
        bytes32 _depositor,
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress,
        address _collateralOft
    ) internal {
        // Check if original sender has valid Keyring credentials
        address originalSender = address(uint160(uint256(_depositor)));
        if (!INaraUSD(address(VAULT)).hasValidCredentials(originalSender)) {
            revert UnauthorizedSender(originalSender);
        }
        if (INaraUSD(address(VAULT)).isBlacklisted(originalSender)) {
            revert UnauthorizedSender(originalSender);
        }

        // Get the actual collateral asset from the OFT
        address collateralAsset = oftToCollateral[_collateralOft];

        // Approve NaraUSD to pull collateral from this composer
        IERC20(collateralAsset).forceApprove(address(VAULT), _assetAmount);
        // Mint NaraUSD to this contract
        uint256 shareAmount = INaraUSD(address(VAULT)).mintWithCollateral(collateralAsset, _assetAmount);
        _assertSlippage(shareAmount, _sendParam.minAmountLD);

        _sendParam.amountLD = shareAmount;
        _sendParam.minAmountLD = 0;

        _send(SHARE_OFT, _sendParam, _refundAddress);
    }

    /**
     * @notice Internal function to handle NaraUSD redemption and cross-chain collateral sending
     * @dev This implements cross-chain redeem with instant redemption if liquidity is available.
     *      If no liquidity, it reverts and triggers refund of NaraUSD via SHARE_OFT.
     *
     * Flow:
     * 1. Check if original sender has valid credentials
     * 2. Verify collateral asset is whitelisted (NaraUSD shares already in this contract via SHARE_OFT compose)
     * 3. Call NaraUSD.redeem(collateralAsset, amount, false) - reverts if no liquidity
     *    - This burns NaraUSD shares from this contract and transfers collateral to this contract
     * 4. Send collateral cross-chain via collateral OFT
     *
     * @param _redeemer The address requesting the redemption
     * @param _shareAmount The amount of NaraUSD shares to redeem
     * @param _sendParam Parameters for sending collateral cross-chain
     * @param _refundAddress Address to refund excess msg.value
     * @param _collateralAsset The collateral asset to receive
     */
    function _redeemCollateralAndSend(
        bytes32 _redeemer,
        uint256 _shareAmount,
        SendParam memory _sendParam,
        address _refundAddress,
        address _collateralAsset
    ) internal {
        // Check if original sender has valid Keyring credentials
        address originalSender = address(uint160(uint256(_redeemer)));
        if (!INaraUSD(address(VAULT)).hasValidCredentials(originalSender)) {
            revert UnauthorizedSender(originalSender);
        }
        if (INaraUSD(address(VAULT)).isBlacklisted(originalSender)) {
            revert UnauthorizedSender(originalSender);
        }

        // Verify collateral asset is whitelisted
        if (!_whitelistedCollaterals.contains(_collateralAsset)) {
            revert CollateralNotWhitelisted(_collateralAsset);
        }

        // Get collateral OFT for sending cross-chain
        address collateralOft = collateralToOft[_collateralAsset];
        if (collateralOft == address(0)) {
            revert CollateralNotWhitelisted(_collateralAsset);
        }

        // Redeem NaraUSD for collateral - this will revert if no liquidity (allowQueue=false)
        // The NaraUSD contract checks liquidity internally and reverts with InsufficientCollateral if insufficient
        // This burns NaraUSD shares from this contract (shares arrived via SHARE_OFT compose)
        // and transfers collateral to this contract
        // Redeem NaraUSD for collateral - returns the exact collateral amount received (after fees)
        // Since allowQueue=false, this will revert with InsufficientCollateral if no liquidity
        (uint256 collateralAmount, ) = INaraUSD(address(VAULT)).redeem(_collateralAsset, _shareAmount, false);

        _assertSlippage(collateralAmount, _sendParam.minAmountLD);

        // Handle local sends differently to avoid base VaultComposerSync._send limitation
        // Base _send only handles ASSET_OFT and SHARE_OFT for local sends, not collateral OFTs
        if (_sendParam.dstEid == VAULT_EID) {
            // Local send (same chain as vault) - transfer collateral ERC20 directly to recipient
            if (msg.value > 0) revert NoMsgValueExpected();
            SafeERC20.safeTransfer(
                IERC20(_collateralAsset),
                OFTComposeMsgCodec.bytes32ToAddress(_sendParam.to),
                collateralAmount
            );
        } else {
            // Cross-chain send - use OFT
            _sendParam.amountLD = collateralAmount;
            _sendParam.minAmountLD = 0;
            _send(collateralOft, _sendParam, _refundAddress);
        }
    }

    /**
     * @notice Override lzCompose to accept whitelisted collateral assets as valid compose senders
     * @dev This allows the composer to handle cross-chain deposits and redemptions
     * @param _composeSender The OFT contract address used for refunds, can be ASSET_OFT, SHARE_OFT, or any whitelisted collateral OFT
     * @param _guid LayerZero's unique tx id (created on the source tx)
     * @param _message Decomposable bytes object into [composeHeader][composeMessage]
     *                  For SHARE_OFT: composeMessage = abi.encode(SendParam, uint256 minMsgValue, address collateralAsset)
     *                  For others: composeMessage = abi.encode(SendParam, uint256 minMsgValue)
     */
    function lzCompose(
        address _composeSender, // The OFT used on refund, also the vaultIn token.
        bytes32 _guid,
        bytes calldata _message, // expected to contain a composeMessage = abi.encode(SendParam hopSendParam,uint256 minMsgValue)
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) external payable override {
        if (msg.sender != ENDPOINT) revert OnlyEndpoint(msg.sender);

        // ASSET_OFT is validation-only and not allowed in compose operations
        if (_composeSender == ASSET_OFT) {
            revert AssetOFTNotAllowedInCompose();
        }

        // Validate compose sender is either SHARE_OFT or a whitelisted collateral OFT
        bool isValidOft = _composeSender == SHARE_OFT;
        bool isWhitelistedCollateral = oftToCollateral[_composeSender] != address(0);

        if (!isValidOft && !isWhitelistedCollateral) {
            revert CollateralOFTNotWhitelisted(_composeSender);
        }

        bytes32 composeFrom = _message.composeFrom();
        uint256 amount = _message.amountLD();
        bytes memory composeMsg = _message.composeMsg();

        /// @dev try...catch to handle the compose operation. if it fails we refund the user
        try this._handleComposeInternal{ value: msg.value }(_composeSender, composeFrom, composeMsg, amount) {
            emit Sent(_guid);
        } catch (bytes memory _err) {
            emit Error(_err);

            /// @dev A revert where the msg.value passed is lower than the min expected msg.value is handled separately
            /// This is because it is possible to re-trigger from the endpoint the compose operation with the right msg.value
            if (bytes4(_err) == InsufficientMsgValue.selector) {
                assembly {
                    revert(add(32, _err), mload(_err))
                }
            }

            _refund(_composeSender, _message, amount, tx.origin);
            emit Refunded(_guid);
        }
    }

    /**
     * @notice Internal function to handle compose operations
     * @dev This function can only be called by self (self-call restriction)
     * @dev For SHARE_OFT compose messages, expects: abi.encode(SendParam, uint256 minMsgValue, address collateralAsset)
     * @dev For other OFTs, expects: abi.encode(SendParam, uint256 minMsgValue)
     */
    function _handleComposeInternal(
        address _oftIn,
        bytes32 _composeFrom,
        bytes memory _composeMsg,
        uint256 _amount
    ) external payable {
        /// @dev Can only be called by self
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);

        // ASSET_OFT is validation-only and not allowed in compose operations
        if (_oftIn == ASSET_OFT) {
            revert AssetOFTNotAllowedInCompose();
        }

        if (_oftIn == SHARE_OFT) {
            /// @dev For SHARE_OFT, compose message includes collateral asset address
            /// @dev Format: abi.encode(SendParam, uint256 minMsgValue, address collateralAsset)
            (SendParam memory sendParam, uint256 minMsgValue, address collateralAsset) = abi.decode(
                _composeMsg,
                (SendParam, uint256, address)
            );

            if (msg.value < minMsgValue) revert InsufficientMsgValue(minMsgValue, msg.value);

            // Custom redeem flow: redeem NaraUSD for collateral and send cross-chain
            _redeemCollateralAndSend(_composeFrom, _amount, sendParam, tx.origin, collateralAsset);
        } else if (oftToCollateral[_oftIn] != address(0)) {
            // It's a whitelisted collateral OFT
            /// @dev SendParam defines how the composer will handle the user's funds
            /// @dev The minMsgValue is the minimum amount of msg.value that must be sent
            (SendParam memory sendParam, uint256 minMsgValue) = abi.decode(_composeMsg, (SendParam, uint256));

            if (msg.value < minMsgValue) revert InsufficientMsgValue(minMsgValue, msg.value);

            _depositCollateralAndSend(_composeFrom, _amount, sendParam, tx.origin, _oftIn);
        } else {
            revert OnlyValidComposeCaller(_oftIn);
        }
    }
}
