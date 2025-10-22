// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/**
 * @title IStakingSpokeHelper
 * @notice Interface for the StakingSpokeHelper contract
 */
interface IStakingSpokeHelper {
    /* --------------- ERRORS --------------- */

    error InvalidZeroAddress();
    error InvalidAmount();
    error InsufficientFee();

    /* --------------- EVENTS --------------- */

    event StakingInitiated(address indexed user, uint256 amount, uint32 dstEid, bytes32 to, uint256 nativeFee);

    /* --------------- FUNCTIONS --------------- */

    /**
     * @notice Stake USDe from this spoke chain and receive sUSDe on destination chain
     * @param amount The amount of USDe to stake
     * @param dstEid The destination chain ID where user wants to receive sUSDe
     * @param to The recipient address on the destination chain
     * @param minSharesLD Minimum shares to receive (slippage protection)
     * @param extraOptions Extra LayerZero options for the return trip
     * @return receipt The messaging receipt from LayerZero
     */
    function stakeRemote(
        uint256 amount,
        uint32 dstEid,
        bytes32 to,
        uint256 minSharesLD,
        bytes calldata extraOptions
    ) external payable returns (MessagingReceipt memory receipt);

    /**
     * @notice Quote the fee for cross-chain staking operation
     * @param amount The amount of USDe to stake
     * @param dstEid The destination chain ID where user wants sUSDe
     * @param to The recipient address
     * @param minSharesLD Minimum shares
     * @param extraOptions Extra options for return trip
     * @param payInLzToken Whether to pay in LZ token
     * @return fee The messaging fee required
     */
    function quoteStakeRemote(
        uint256 amount,
        uint32 dstEid,
        bytes32 to,
        uint256 minSharesLD,
        bytes calldata extraOptions,
        bool payInLzToken
    ) external view returns (MessagingFee memory fee);

    /**
     * @notice Rescue tokens accidentally sent to this contract
     * @param token The token address
     * @param to The recipient
     * @param amount The amount to rescue
     */
    function rescueToken(address token, address to, uint256 amount) external;

    /**
     * @notice Rescue native tokens
     * @param to The recipient
     * @param amount The amount
     */
    function rescueNative(address payable to, uint256 amount) external;

    /* --------------- VIEW FUNCTIONS --------------- */

    function usdeOFT() external view returns (address);
    function hubEid() external view returns (uint32);
    function composerOnHub() external view returns (address);
}
