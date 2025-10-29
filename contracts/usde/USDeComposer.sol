// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { VaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { IOFT, SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { IVaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/interfaces/IVaultComposerSync.sol";

interface IUSDe {
    function mintWithCollateral(
        address collateralAsset,
        uint256 collateralAmount
    ) external returns (uint256 usdeAmount);
}

/**
 * @title USDeComposer
 * @notice Composer that routes deposits through USDe.mintWithCollateral instead of ERC4626.deposit
 * @dev Collateral flows: user sends collateralAsset to composer → composer approves USDe →
 *      calls USDe.mintWithCollateralFor(collateralAsset, amount, address(this)) → sends shares cross-chain
 * @dev Cross-chain deposits of collateral require a collateral OFT and base composer support; this contract
 *      overrides local deposit flow via depositAndSend().
 */
contract USDeComposer is VaultComposerSync {
    using SafeERC20 for IERC20;
    using OFTComposeMsgCodec for bytes;

    /// @notice Collateral asset to use for minting (e.g., USDC)
    address public immutable collateralAsset;
    /// @notice OFT contract for the collateral asset (e.g., Stargate USDC OFT)
    address public immutable collateralAssetOFT;

    // Debug events
    event DebugLzComposeStart(address composeSender, bytes32 guid, uint256 msgValue);
    event DebugValidationPassed();
    event DebugMessageDecoded(bytes32 composeFrom, uint256 amount, uint256 composeMsgLength);
    event DebugHandleComposeStart(address oftIn, bytes32 composeFrom, uint256 amount);
    event DebugSendParamDecoded(uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD);
    event DebugMsgValueCheck(uint256 minMsgValue, uint256 actualMsgValue);
    event DebugProcessingAssetOFT();
    event DebugProcessingShareOFT();
    event DebugProcessingCollateralAsset();
    event DebugDepositCollateralAndSendStart(uint256 assetAmount);
    event DebugDepositCollateralAndSendComplete(uint256 shareAmount);
    event DebugHandleComposeComplete();
    event DebugLzComposeComplete();
    event DebugError(bytes errorData);
    event DepositedUSDe(
        address share,
        address recipient,
        uint32 dstEid,
        bytes32 to,
        uint256 amountLD,
        uint256 minAmountLD,
        bytes extraOptions,
        bytes composeMsg,
        bytes oftCmd
    );

    /**
     * @param _vault The USDe contract implementing ERC4626
     * @param _assetOFT The asset OFT address expected by base (must match vault.asset(), i.e., MCT)
     * @param _shareOFT The USDe OFT adapter contract for cross-chain share transfers
     * @param _collateralAsset The ERC20 collateral to mint with (e.g., USDC)
     */
    constructor(
        address _vault,
        address _assetOFT,
        address _shareOFT,
        address _collateralAsset,
        address _collateralAssetOFT
    ) VaultComposerSync(_vault, _assetOFT, _shareOFT) {
        collateralAsset = _collateralAsset;
        collateralAssetOFT = _collateralAssetOFT;
        // Approve collateral to its OFT for potential refunds
        IERC20(collateralAsset).approve(collateralAssetOFT, type(uint256).max);
    }

    /**
     * @dev Collateral deposit path: mints shares using USDe.mintWithCollateralFor and sends them
     */
    function _depositCollateralAndSend(
        bytes32 _depositor,
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress
    ) internal {
        emit DebugDepositCollateralAndSendStart(_assetAmount);

        // Approve USDe to pull collateral from this composer
        IERC20(collateralAsset).forceApprove(address(VAULT), _assetAmount);
        // Mint USDe to this contract
        uint256 shareAmount = IUSDe(address(VAULT)).mintWithCollateral(collateralAsset, _assetAmount);
        _assertSlippage(shareAmount, _sendParam.minAmountLD);

        _sendParam.amountLD = shareAmount;
        _sendParam.minAmountLD = 0;

        _send(SHARE_OFT, _sendParam, _refundAddress);
        emit DepositedUSDe(
            SHARE_OFT,
            _refundAddress,
            _sendParam.dstEid,
            _sendParam.to,
            _sendParam.amountLD,
            _sendParam.minAmountLD,
            _sendParam.extraOptions,
            _sendParam.composeMsg,
            _sendParam.oftCmd
        );

        emit DebugDepositCollateralAndSendComplete(shareAmount);
    }

    /**
     * @notice Override lzCompose to accept collateralAsset as a valid compose sender
     * @dev This allows the composer to handle cross-chain deposits of collateral assets (e.g., USDC)
     * @param _composeSender The OFT contract address used for refunds, can be ASSET_OFT, SHARE_OFT, or collateralAsset
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
        emit DebugLzComposeStart(_composeSender, _guid, msg.value);

        if (msg.sender != ENDPOINT) revert OnlyEndpoint(msg.sender);
        if (
            _composeSender != ASSET_OFT &&
            _composeSender != SHARE_OFT &&
            _composeSender != collateralAsset &&
            _composeSender != collateralAssetOFT
        ) {
            revert OnlyValidComposeCaller(_composeSender);
        }

        emit DebugValidationPassed();

        bytes32 composeFrom = _message.composeFrom();
        uint256 amount = _message.amountLD();
        bytes memory composeMsg = _message.composeMsg();

        emit DebugMessageDecoded(composeFrom, amount, composeMsg.length);

        /// @dev try...catch to handle the compose operation. if it fails we refund the user
        try this._handleComposeInternal{ value: msg.value }(_composeSender, composeFrom, composeMsg, amount) {
            emit Sent(_guid);
            emit DebugLzComposeComplete();
        } catch (bytes memory _err) {
            emit DebugError(_err);

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
        emit DebugHandleComposeStart(_oftIn, _composeFrom, _amount);

        /// @dev Can only be called by self
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);

        /// @dev SendParam defines how the composer will handle the user's funds
        /// @dev The minMsgValue is the minimum amount of msg.value that must be sent, failing to do so will revert and the transaction will be retained in the endpoint for future retries
        (SendParam memory sendParam, uint256 minMsgValue) = abi.decode(_composeMsg, (SendParam, uint256));

        emit DebugSendParamDecoded(sendParam.dstEid, sendParam.to, sendParam.amountLD, sendParam.minAmountLD);
        emit DebugMsgValueCheck(minMsgValue, msg.value);

        if (msg.value < minMsgValue) revert InsufficientMsgValue(minMsgValue, msg.value);

        if (_oftIn == ASSET_OFT) {
            emit DebugProcessingAssetOFT();
            super._depositAndSend(_composeFrom, _amount, sendParam, tx.origin);
        } else if (_oftIn == SHARE_OFT) {
            emit DebugProcessingShareOFT();
            super._redeemAndSend(_composeFrom, _amount, sendParam, tx.origin);
        } else if (_oftIn == collateralAssetOFT) {
            emit DebugProcessingCollateralAsset();
            _depositCollateralAndSend(_composeFrom, _amount, sendParam, tx.origin);
        } else {
            revert OnlyValidComposeCaller(_oftIn);
        }

        emit DebugHandleComposeComplete();
    }

    /**
     * @notice Override _refund to handle collateral asset via its OFT
     */
    function _refund(address _oft, bytes calldata _message, uint256 _amount, address _refundAddress) internal override {
        if (_oft == collateralAsset) {
            SendParam memory refundSendParam;
            refundSendParam.dstEid = OFTComposeMsgCodec.srcEid(_message);
            refundSendParam.to = OFTComposeMsgCodec.composeFrom(_message);
            refundSendParam.amountLD = _amount;

            IOFT(collateralAssetOFT).send{ value: msg.value }(
                refundSendParam,
                MessagingFee(msg.value, 0),
                _refundAddress
            );
        } else {
            super._refund(_oft, _message, _amount, _refundAddress);
        }
    }
}
