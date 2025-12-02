// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";

/**
 * @title MCTOFTAdapter
 * @notice OFT adapter for MultiCollateralToken on hub chain
 *
 * ============================================================================
 * IMPORTANT: VALIDATION ONLY - NOT USED FOR ACTUAL CROSS-CHAIN OPERATIONS
 * ============================================================================
 *
 * This contract exists ONLY to satisfy VaultComposerSync constructor validation.
 * MCT (MultiCollateralToken) does NOT go cross-chain and is invisible to users.
 *
 * @dev Architecture Explanation:
 *
 * User Flow:
 * - Users deposit collateral (USDC/USDT) via naraUSD.mintWithCollateral()
 * - MCT is created internally by naraUSD contract (users never see it)
 * - Users receive naraUSD shares
 * - MCT NEVER leaves the hub chain
 *
 * Why This Contract Exists:
 * - NaraUSDComposer inherits from LayerZero's VaultComposerSync
 * - VaultComposerSync validates: ASSET_OFT.token() == VAULT.asset()
 * - naraUSD vault's underlying asset is MCT
 * - Therefore, we need an adapter that returns token() = MCT
 * - BUT MCT never actually goes cross-chain!
 *
 * What This Contract Does:
 * ✅ Exists on hub chain
 * ✅ Returns token() = MCT to pass validation
 * ✅ Satisfies VaultComposerSync constructor check
 *
 * What This Contract Does NOT Do:
 * ❌ NOT wired to spoke chains (no peer configuration)
 * ❌ NOT used for cross-chain MCT transfers
 * ❌ NOT used in NaraUSDComposer's actual deposit flow
 * ❌ NOT visible to end users
 * ❌ NOT part of the collateral deposit flow
 *
 * Actual Cross-Chain Flow (without using this adapter):
 * 1. User sends USDC via Stargate/collateral OFT
 * 2. NaraUSDComposer receives USDC on hub
 * 3. Composer calls naraUSD.mintWithCollateral(USDC, amount)
 * 4. naraUSD internally manages MCT (user never sees it)
 * 5. Composer sends naraUSD shares cross-chain via NaraUSDOFTAdapter
 * 6. User receives naraUSD on destination chain
 *
 * Notice: MCTOFTAdapter is never used in steps 1-6!
 *
 * Alternative Approach:
 * A custom VaultComposer that doesn't inherit from VaultComposerSync would
 * eliminate the need for this validation-only contract. However, using the
 * standard VaultComposerSync is simpler and requires less custom code.
 *
 * @custom:security This contract is deployed but never configured for cross-chain use
 * @custom:note See WHY_MCTOFT_ADAPTER_EXISTS.md for detailed explanation
 */
contract MCTOFTAdapter is OFTAdapter {
    /**
     * @notice Creates a new OFT adapter for MCT (validation only)
     * @dev This adapter is deployed on hub chain but is NEVER used for cross-chain operations.
     *      It exists solely to satisfy VaultComposerSync constructor validation.
     *      Do NOT configure peers or wire this to spoke chains.
     *
     * @param _token The MCT token address
     * @param _lzEndpoint The LayerZero endpoint for this chain (hub chain only)
     * @param _delegate The account with administrative privileges
     */
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OFTAdapter(_token, _lzEndpoint, _delegate) Ownable(_delegate) {}
}
