// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { VaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";
import { IOFT, SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

interface IUSDe {
    function mintWithCollateralFor(
        address collateralAsset,
        uint256 collateralAmount,
        address beneficiary
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

    /// @notice Collateral asset to use for minting (e.g., USDC)
    address public immutable collateralAsset;

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
        address _collateralAsset
    ) VaultComposerSync(_vault, _assetOFT, _shareOFT) {
        collateralAsset = _collateralAsset;
    }

    /**
     * @notice Pull collateral from sender and send shares per SendParam
     * @dev Overrides base to transfer collateralAsset rather than VAULT.asset()
     */
    function depositAndSend(
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress
    ) external payable override {
        // Pull collateral from user into composer
        IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), _assetAmount);
        // Route through the standard internal flow
        _depositAndSend(bytes32(uint256(uint160(msg.sender))), _assetAmount, _sendParam, _refundAddress);
    }

    /**
     * @dev Deposit override: use USDe.mintWithCollateralFor with configured collateralAsset
     * @return shareAmount Amount of USDe shares minted
     */
    function _deposit(bytes32 /*_depositor*/, uint256 _assetAmount) internal override returns (uint256 shareAmount) {
        // Approve USDe to pull collateral from this composer
        IERC20(collateralAsset).forceApprove(address(VAULT), _assetAmount);
        // Mint USDe to this contract, then shares are sent by parent logic
        shareAmount = IUSDe(address(VAULT)).mintWithCollateralFor(collateralAsset, _assetAmount, address(this));
    }
}
