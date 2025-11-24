// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { VaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";

/**
 * @title StakednUSDComposer
 * @notice Cross-chain vault composer enabling omnichain StakednUSD operations via LayerZero
 * @dev This composer allows users to:
 *      - Deposit nUSD from any chain and receive snUSD on any destination chain
 *      - Redeem snUSD from any chain and receive nUSD on any destination chain
 *      - All operations happen in a single transaction from the user's perspective
 *
 * @notice Mirrors Ethena's production cross-chain staking implementation
 *
 * Example Flow (User on Base Sepolia):
 * 1. User calls depositRemote() with nUSD on Base
 * 2. Composer bridges nUSD to hub (Arbitrum) via LayerZero
 * 3. Hub stakes nUSD → receives snUSD
 * 4. Composer bridges snUSD back to Base via LayerZero
 * 5. User receives snUSD on Base after LayerZero settlement (~1-5 mins)
 */
contract StakednUSDComposer is VaultComposerSync {
    /**
     * @notice Creates a new cross-chain vault composer for StakednUSD
     * @param _vault The StakednUSD contract implementing ERC4626
     * @param _assetOFT The nUSD OFT adapter contract for cross-chain nUSD transfers
     * @param _shareOFT The snUSD OFT adapter contract for cross-chain snUSD transfers
     */
    constructor(address _vault, address _assetOFT, address _shareOFT) VaultComposerSync(_vault, _assetOFT, _shareOFT) {}
}
