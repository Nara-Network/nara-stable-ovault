// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { VaultComposerSync } from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";

/**
 * @title StakedNaraUSDComposer
 * @notice Cross-chain vault composer enabling omnichain StakedNaraUSD operations via LayerZero
 * @dev This composer allows users to:
 *      - Deposit naraUSD from any chain and receive snaraUSD on any destination chain
 *      - Redeem snaraUSD from any chain and receive naraUSD on any destination chain
 *      - All operations happen in a single transaction from the user's perspective
 *
 * @notice Mirrors Ethena's production cross-chain staking implementation
 *
 * Example Flow (User on Base Sepolia):
 * 1. User calls depositRemote() with naraUSD on Base
 * 2. Composer bridges naraUSD to hub (Arbitrum) via LayerZero
 * 3. Hub stakes naraUSD → receives snaraUSD
 * 4. Composer bridges snaraUSD back to Base via LayerZero
 * 5. User receives snaraUSD on Base after LayerZero settlement (~1-5 mins)
 */
contract StakedNaraUSDComposer is VaultComposerSync {
    /**
     * @notice Creates a new cross-chain vault composer for StakedNaraUSD
     * @param _vault The StakedNaraUSD contract implementing ERC4626
     * @param _assetOFT The naraUSD OFT adapter contract for cross-chain naraUSD transfers
     * @param _shareOFT The snaraUSD OFT adapter contract for cross-chain snaraUSD transfers
     */
    constructor(address _vault, address _assetOFT, address _shareOFT) VaultComposerSync(_vault, _assetOFT, _shareOFT) {}
}
