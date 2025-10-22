// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { VaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";

/**
 * @title StakedUSDeComposer
 * @notice Cross-chain vault composer enabling omnichain StakedUSDe operations via LayerZero
 * @dev This composer allows users to:
 *      - Deposit USDe from any chain and receive sUSDe on any destination chain
 *      - Redeem sUSDe from any chain and receive USDe on any destination chain
 *      - All operations happen in a single transaction from the user's perspective
 *
 * @notice Mirrors Ethena's production cross-chain staking implementation
 *
 * Example Flow (User on Base Sepolia):
 * 1. User calls depositRemote() with USDe on Base
 * 2. Composer bridges USDe to hub (Arbitrum) via LayerZero
 * 3. Hub stakes USDe → receives sUSDe
 * 4. Composer bridges sUSDe back to Base via LayerZero
 * 5. User receives sUSDe on Base after LayerZero settlement (~1-5 mins)
 */
contract StakedUSDeComposer is VaultComposerSync {
    /**
     * @notice Creates a new cross-chain vault composer for StakedUSDe
     * @param _vault The StakedUSDe contract implementing ERC4626
     * @param _assetOFT The USDe OFT adapter contract for cross-chain USDe transfers
     * @param _shareOFT The sUSDe OFT adapter contract for cross-chain sUSDe transfers
     */
    constructor(address _vault, address _assetOFT, address _shareOFT) VaultComposerSync(_vault, _assetOFT, _shareOFT) {}
}
