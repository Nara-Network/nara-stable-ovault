// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

/**
 * @title IStakednUSDComposer
 * @notice Interface for the StakednUSDComposer contract
 * @dev Inherits from LayerZero's VaultComposerSync which provides the core cross-chain vault operations
 *
 * The VaultComposerSync provides:
 * - depositRemote(): Deposit assets on one chain, receive shares on another
 * - redeemRemote(): Redeem shares on one chain, receive assets on another
 * - Various quote functions for estimating cross-chain fees
 *
 * All LayerZero VaultComposerSync functions are available through this interface.
 */
interface IStakednUSDComposer {
    // The interface inherits all functions from VaultComposerSync
    // Key functions include:
    // - function depositRemote(...) external payable
    // - function redeemRemote(...) external payable
    // - function quoteDeposit(...) external view returns (MessagingFee memory)
    // - function quoteRedeem(...) external view returns (MessagingFee memory)
}
