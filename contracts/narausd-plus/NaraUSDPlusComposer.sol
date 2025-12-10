// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { VaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";

/**
 * @title NaraUSDPlusComposer
 * @notice Cross-chain vault composer enabling omnichain NaraUSDPlus operations via LayerZero
 * @dev This composer allows users to:
 *      - Deposit NaraUSD from any chain and receive NaraUSD+ on any destination chain
 *      - Redeem NaraUSD+ from any chain and receive NaraUSD on any destination chain
 *      - All operations happen in a single transaction from the user's perspective
 *
 * @notice Mirrors Ethena's production cross-chain staking implementation
 *
 * Example Flow (User on Base Sepolia):
 * 1. User calls depositRemote() with NaraUSD on Base
 * 2. Composer bridges NaraUSD to hub (Arbitrum) via LayerZero
 * 3. Hub stakes NaraUSD → receives NaraUSD+
 * 4. Composer bridges NaraUSD+ back to Base via LayerZero
 * 5. User receives NaraUSD+ on Base after LayerZero settlement (~1-5 mins)
 */
contract NaraUSDPlusComposer is VaultComposerSync {
    /**
     * @notice Creates a new cross-chain vault composer for NaraUSDPlus
     * @param _vault The NaraUSDPlus contract implementing ERC4626
     * @param _assetOFT The NaraUSD OFT adapter contract for cross-chain NaraUSD transfers
     * @param _shareOFT The NaraUSD+ OFT adapter contract for cross-chain NaraUSD+ transfers
     */
    constructor(address _vault, address _assetOFT, address _shareOFT) VaultComposerSync(_vault, _assetOFT, _shareOFT) {}
}
