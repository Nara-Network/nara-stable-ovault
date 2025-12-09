// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { VaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";

/**
 * @title NaraUSDPlusComposer
 * @notice Cross-chain vault composer enabling omnichain NaraUSDPlus operations via LayerZero
 * @dev This composer allows users to:
 *      - Deposit naraUSD from any chain and receive naraUSD+ on any destination chain
 *      - Redeem naraUSD+ from any chain and receive naraUSD on any destination chain
 *      - All operations happen in a single transaction from the user's perspective
 *
 * @notice Mirrors Ethena's production cross-chain staking implementation
 *
 * Example Flow (User on Base Sepolia):
 * 1. User calls depositRemote() with naraUSD on Base
 * 2. Composer bridges naraUSD to hub (Arbitrum) via LayerZero
 * 3. Hub stakes naraUSD → receives naraUSD+
 * 4. Composer bridges naraUSD+ back to Base via LayerZero
 * 5. User receives naraUSD+ on Base after LayerZero settlement (~1-5 mins)
 */
contract NaraUSDPlusComposer is VaultComposerSync {
    /**
     * @notice Creates a new cross-chain vault composer for NaraUSDPlus
     * @param _vault The NaraUSDPlus contract implementing ERC4626
     * @param _assetOFT The naraUSD OFT adapter contract for cross-chain naraUSD transfers
     * @param _shareOFT The naraUSD+ OFT adapter contract for cross-chain naraUSD+ transfers
     */
    constructor(address _vault, address _assetOFT, address _shareOFT) VaultComposerSync(_vault, _assetOFT, _shareOFT) {}
}
