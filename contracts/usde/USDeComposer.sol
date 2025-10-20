// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { VaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";

/**
 * @title USDeComposer
 * @notice Cross-chain vault composer enabling omnichain USDe vault operations via LayerZero
 * @dev This composer allows users to:
 *      - Deposit MCT from any chain and receive USDe on any destination chain
 *      - Redeem USDe from any chain and receive MCT on any destination chain
 *      - All operations happen in a single transaction from the user's perspective
 */
contract USDeComposer is VaultComposerSync {
    /**
     * @notice Creates a new cross-chain vault composer for USDe
     * @param _vault The USDe contract implementing ERC4626
     * @param _assetOFT The MCT OFT adapter contract for cross-chain MCT transfers
     * @param _shareOFT The USDe OFT adapter contract for cross-chain share transfers
     */
    constructor(address _vault, address _assetOFT, address _shareOFT) VaultComposerSync(_vault, _assetOFT, _shareOFT) {}
}
