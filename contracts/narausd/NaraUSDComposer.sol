// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { VaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { IOFT, SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { IVaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/interfaces/IVaultComposerSync.sol";

interface INaraUSD {
    function mintWithCollateral(
        address collateralAsset,
        uint256 collateralAmount
    ) external returns (uint256 naraUSDAmount);

    function hasValidCredentials(address account) external view returns (bool);

    function isBlacklisted(address account) external view returns (bool);

    function asset() external view returns (address);
}

interface IMCT {
    function hasRole(bytes32 role, address account) external view returns (bool);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
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

/**
 * @title NaraUSDComposer
 * @notice Composer that enables cross-chain naraUSD minting via collateral deposits
 *
 * @dev Overview:
 * This composer allows users to deposit collateral (USDC/USDT) on any chain and receive
 * naraUSD shares on any destination chain in a single transaction.
 *
 * User Flow:
 * 1. User sends collateral (USDC) from spoke chain via Stargate/collateral OFT
 * 2. NaraUSDComposer receives collateral on hub chain via lzCompose
 * 3. Composer calls naraUSD.mintWithCollateral(collateralAsset, amount)
 * 4. naraUSD internally manages MCT (MultiCollateralToken) - user never sees it
 * 5. Composer sends naraUSD shares cross-chain via SHARE_OFT (NaraUSDOFTAdapter)
 * 6. User receives naraUSD on destination chain
 *
 * @dev IMPORTANT - ASSET_OFT Parameter (Validation Only):
 *
 * This contract inherits from VaultComposerSync which requires an ASSET_OFT parameter
 * that must satisfy: ASSET_OFT.token() == VAULT.asset()
 *
 * For naraUSD vault:
 * - VAULT.asset() = MCT (MultiCollateralToken)
 * - Therefore ASSET_OFT must be MCTOFTAdapter
 * - BUT: MCT NEVER goes cross-chain! It's hub-only and invisible to users.
 *
 * The ASSET_OFT (MCTOFTAdapter) exists ONLY to pass constructor validation.
 * It is NEVER used in the actual compose flow!
 *
 * Actual Flow Uses:
 * ✅ collateralAsset - What users actually deposit (USDC/USDT)
 * ✅ collateralAssetOFT - For cross-chain collateral (Stargate USDC OFT)
 * ✅ SHARE_OFT - For sending naraUSD cross-chain (NaraUSDOFTAdapter)
 * ❌ ASSET_OFT - Only for validation, never used in operations
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
     * @notice Creates a new NaraUSDComposer for cross-chain naraUSD minting
     *
     * @param _vault The naraUSD vault contract implementing ERC4626
     *
     * @param _assetOFT VALIDATION ONLY - MCTOFTAdapter that satisfies vault.asset() check
     *                  This is NEVER used for actual cross-chain operations!
     *                  MCT (vault's underlying asset) stays on hub chain only.
     *                  Passed only to satisfy VaultComposerSync constructor validation.
     *                  See contract-level documentation for detailed explanation.
     *
     * @param _shareOFT The naraUSD OFT adapter for cross-chain share transfers (ACTUALLY USED)
     *                  This is what sends naraUSD cross-chain to users.
     *
     * @dev Key Point: _assetOFT (MCT) is required by base class but never used.
     *      The actual flow uses whitelisted collateral assets and _shareOFT.
     * @dev Admin must whitelist collateral assets after deployment using addWhitelistedCollateral()
     */
    constructor(address _vault, address _assetOFT, address _shareOFT) VaultComposerSync(_vault, _assetOFT, _shareOFT) {}

    /**
     * @notice Add a collateral asset and its OFT to the whitelist
     * @param asset The collateral token address (e.g., USDC, USDT)
     * @param assetOFT The OFT contract for the collateral asset
     * @dev Only callable by MCT admin (same role that manages MCT's supported assets)
     */
    function addWhitelistedCollateral(address asset, address assetOFT) external {
        address mct = INaraUSD(address(VAULT)).asset();
        bytes32 adminRole = IMCT(mct).DEFAULT_ADMIN_ROLE();
        if (!IMCT(mct).hasRole(adminRole, msg.sender)) {
            revert Unauthorized();
        }

        if (!_whitelistedCollaterals.add(asset)) {
            revert CollateralAlreadyWhitelisted(asset);
        }

        oftToCollateral[assetOFT] = asset;
        collateralToOft[asset] = assetOFT;

        // Approve collateral to its OFT for potential refunds
        IERC20(asset).approve(assetOFT, type(uint256).max);

        emit CollateralWhitelisted(asset, assetOFT);
    }

    /**
     * @notice Remove a collateral asset from the whitelist
     * @param asset The collateral token address to remove
     * @dev Only callable by MCT admin (same role that manages MCT's supported assets)
     */
    function removeWhitelistedCollateral(address asset) external {
        address mct = INaraUSD(address(VAULT)).asset();
        bytes32 adminRole = IMCT(mct).DEFAULT_ADMIN_ROLE();
        if (!IMCT(mct).hasRole(adminRole, msg.sender)) {
            revert Unauthorized();
        }

        if (!_whitelistedCollaterals.remove(asset)) {
            revert CollateralNotWhitelisted(asset);
        }

        address assetOFT = collateralToOft[asset];
        delete oftToCollateral[assetOFT];
        delete collateralToOft[asset];

        // Revoke approval
        IERC20(asset).approve(assetOFT, 0);

        emit CollateralRemoved(asset, assetOFT);
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
     * 2. Approve naraUSD to pull collateral
     * 3. Call naraUSD.mintWithCollateral(collateralAsset, amount) - MCT handled internally
     * 4. Receive naraUSD shares
     * 5. Send shares cross-chain via SHARE_OFT (not ASSET_OFT!)
     *
     * @param _depositor The address requesting the deposit
     * @param _assetAmount The amount of collateral to deposit
     * @param _sendParam Parameters for sending shares cross-chain
     * @param _refundAddress Address to refund excess msg.value
     * @param _collateralOFT The OFT contract that sent the collateral
     */
    function _depositCollateralAndSend(
        bytes32 _depositor,
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress,
        address _collateralOFT
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
        address collateralAsset = oftToCollateral[_collateralOFT];

        // Approve naraUSD to pull collateral from this composer
        IERC20(collateralAsset).forceApprove(address(VAULT), _assetAmount);
        // Mint naraUSD to this contract
        uint256 shareAmount = INaraUSD(address(VAULT)).mintWithCollateral(collateralAsset, _assetAmount);
        _assertSlippage(shareAmount, _sendParam.minAmountLD);

        _sendParam.amountLD = shareAmount;
        _sendParam.minAmountLD = 0;

        _send(SHARE_OFT, _sendParam, _refundAddress);
    }

    /**
     * @notice Override lzCompose to accept whitelisted collateral assets as valid compose senders
     * @dev This allows the composer to handle cross-chain deposits of any whitelisted collateral asset
     * @param _composeSender The OFT contract address used for refunds, can be ASSET_OFT, SHARE_OFT, or any whitelisted collateral OFT
     * @param _guid LayerZero's unique tx id (created on the source tx)
     * @param _message Decomposable bytes object into [composeHeader][composeMessage]
     */
    function lzCompose(
        address _composeSender, // The OFT used on refund, also the vaultIn token.
        bytes32 _guid,
        bytes calldata _message, // expected to contain a composeMessage = abi.encode(SendParam hopSendParam,uint256 minMsgValue)
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) external payable override {
        if (msg.sender != ENDPOINT) revert OnlyEndpoint(msg.sender);

        // Validate compose sender is either ASSET_OFT, SHARE_OFT, or a whitelisted collateral OFT
        bool isValidOFT = _composeSender == ASSET_OFT || _composeSender == SHARE_OFT;
        bool isWhitelistedCollateral = oftToCollateral[_composeSender] != address(0);

        if (!isValidOFT && !isWhitelistedCollateral) {
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
     */
    function _handleComposeInternal(
        address _oftIn,
        bytes32 _composeFrom,
        bytes memory _composeMsg,
        uint256 _amount
    ) external payable {
        /// @dev Can only be called by self
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);

        /// @dev SendParam defines how the composer will handle the user's funds
        /// @dev The minMsgValue is the minimum amount of msg.value that must be sent, failing to do so will revert and the transaction will be retained in the endpoint for future retries
        (SendParam memory sendParam, uint256 minMsgValue) = abi.decode(_composeMsg, (SendParam, uint256));

        if (msg.value < minMsgValue) revert InsufficientMsgValue(minMsgValue, msg.value);

        if (_oftIn == ASSET_OFT) {
            super._depositAndSend(_composeFrom, _amount, sendParam, tx.origin);
        } else if (_oftIn == SHARE_OFT) {
            super._redeemAndSend(_composeFrom, _amount, sendParam, tx.origin);
        } else if (oftToCollateral[_oftIn] != address(0)) {
            // It's a whitelisted collateral OFT
            _depositCollateralAndSend(_composeFrom, _amount, sendParam, tx.origin, _oftIn);
        } else {
            revert OnlyValidComposeCaller(_oftIn);
        }
    }

    /**
     * @notice Override _refund to handle any whitelisted collateral asset via its OFT
     */
    function _refund(address _oft, bytes calldata _message, uint256 _amount, address _refundAddress) internal override {
        if (oftToCollateral[_oft] != address(0)) {
            // It's a whitelisted collateral OFT - handle refund
            SendParam memory refundSendParam;
            refundSendParam.dstEid = OFTComposeMsgCodec.srcEid(_message);
            refundSendParam.to = OFTComposeMsgCodec.composeFrom(_message);
            refundSendParam.amountLD = _amount;

            IOFT(_oft).send{ value: msg.value }(refundSendParam, MessagingFee(msg.value, 0), _refundAddress);
        } else {
            super._refund(_oft, _message, _amount, _refundAddress);
        }
    }
}
