// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SendParam, MessagingFee, MessagingReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title StakingSpokeHelper
 * @notice Helper contract on spoke chains to enable single-transaction cross-chain staking
 * @dev Allows users to stake USDe from any spoke chain without switching networks
 *
 * Flow:
 * 1. User calls stakeRemote() on Base Sepolia with USDe
 * 2. Helper bridges USDe to hub via LayerZero OFT
 * 3. Compose message triggers StakedUSDeComposer on hub
 * 4. Composer stakes USDe → sUSDe on hub
 * 5. Composer bridges sUSDe back to user on Base
 * 6. User receives sUSDe on Base after LayerZero settlement
 *
 * @notice This enables Ethena-style single-transaction cross-chain staking
 */
contract StakingSpokeHelper is Ownable {
    using SafeERC20 for IERC20;
    using OFTComposeMsgCodec for bytes;

    /* --------------- ERRORS --------------- */

    error InvalidZeroAddress();
    error InvalidAmount();
    error InsufficientFee();

    /* --------------- STATE VARIABLES --------------- */

    /// @notice The USDe OFT contract on this spoke chain
    address public immutable usdeOFT;

    /// @notice The hub chain endpoint ID
    uint32 public immutable hubEid;

    /// @notice The StakedUSDeComposer address on the hub chain
    address public immutable composerOnHub;

    /* --------------- EVENTS --------------- */

    event StakingInitiated(address indexed user, uint256 amount, uint32 dstEid, bytes32 to, uint256 nativeFee);

    /* --------------- CONSTRUCTOR --------------- */

    /**
     * @notice Creates a new StakingSpokeHelper
     * @param _usdeOFT The USDe OFT contract address on this spoke chain
     * @param _hubEid The LayerZero endpoint ID for the hub chain
     * @param _composerOnHub The StakedUSDeComposer address on the hub chain
     * @param _owner The owner address for this contract
     */
    constructor(address _usdeOFT, uint32 _hubEid, address _composerOnHub, address _owner) Ownable(_owner) {
        if (_usdeOFT == address(0) || _composerOnHub == address(0) || _owner == address(0)) {
            revert InvalidZeroAddress();
        }

        usdeOFT = _usdeOFT;
        hubEid = _hubEid;
        composerOnHub = _composerOnHub;
    }

    /* --------------- EXTERNAL FUNCTIONS --------------- */

    /**
     * @notice Stake USDe from this spoke chain and receive sUSDe on destination chain
     * @param amount The amount of USDe to stake
     * @param dstEid The destination chain ID where user wants to receive sUSDe
     * @param to The recipient address on the destination chain (usually msg.sender)
     * @param minSharesLD Minimum shares to receive (slippage protection)
     * @param extraOptions Extra LayerZero options for the return trip
     * @return receipt The messaging receipt from LayerZero
     *
     * @dev This function:
     * 1. Takes USDe from user
     * 2. Sends USDe to hub with compose message
     * 3. Compose message triggers StakedUSDeComposer on hub
     * 4. Composer stakes and sends sUSDe to destination
     */
    function stakeRemote(
        uint256 amount,
        uint32 dstEid,
        bytes32 to,
        uint256 minSharesLD,
        bytes calldata extraOptions
    ) external payable returns (MessagingReceipt memory receipt) {
        if (amount == 0) revert InvalidAmount();
        if (to == bytes32(0)) revert InvalidZeroAddress();

        // Transfer USDe from user to this contract
        IERC20(usdeOFT).safeTransferFrom(msg.sender, address(this), amount);

        // Approve USDe OFT to spend
        IERC20(usdeOFT).forceApprove(usdeOFT, amount);

        // Encode compose message for StakedUSDeComposer
        // Format: depositRemote(dstEid, minSharesLD, to, extraOptions)
        bytes memory composeMsg = abi.encode(
            dstEid, // Where to send sUSDe
            minSharesLD, // Minimum shares (slippage protection)
            to, // Recipient of sUSDe
            extraOptions // Options for sUSDe return transfer
        );

        // Prepare send parameters
        SendParam memory sendParam = SendParam({
            dstEid: hubEid,
            to: _addressToBytes32(composerOnHub), // Send to composer on hub
            amountLD: amount,
            minAmountLD: (amount * 99) / 100, // 1% slippage for bridge
            extraOptions: bytes(""), // Hub-side execution options
            composeMsg: composeMsg, // Trigger composer
            oftCmd: bytes("") // No OFT command needed
        });

        // Send via OFT with compose message
        // The native fee must cover:
        // 1. Bridging USDe to hub
        // 2. Executing compose message on hub
        // 3. Bridging sUSDe back to destination
        receipt = _sendOFT(sendParam, msg.value);

        emit StakingInitiated(msg.sender, amount, dstEid, to, msg.value);

        return receipt;
    }

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
    ) external view returns (MessagingFee memory fee) {
        bytes memory composeMsg = abi.encode(dstEid, minSharesLD, to, extraOptions);

        SendParam memory sendParam = SendParam({
            dstEid: hubEid,
            to: _addressToBytes32(composerOnHub),
            amountLD: amount,
            minAmountLD: (amount * 99) / 100,
            extraOptions: bytes(""),
            composeMsg: composeMsg,
            oftCmd: bytes("")
        });

        // Call quoteSend on the OFT
        (bool success, bytes memory result) = usdeOFT.staticcall(
            abi.encodeWithSignature(
                "quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)",
                sendParam,
                payInLzToken
            )
        );

        require(success, "Quote failed");
        fee = abi.decode(result, (MessagingFee));

        return fee;
    }

    /* --------------- INTERNAL FUNCTIONS --------------- */

    /**
     * @notice Internal function to send via OFT
     * @param sendParam The send parameters
     * @param nativeFee The native fee amount
     * @return receipt The messaging receipt
     */
    function _sendOFT(
        SendParam memory sendParam,
        uint256 nativeFee
    ) internal returns (MessagingReceipt memory receipt) {
        MessagingFee memory fee = MessagingFee({ nativeFee: nativeFee, lzTokenFee: 0 });

        (bool success, bytes memory result) = usdeOFT.call{ value: nativeFee }(
            abi.encodeWithSignature(
                "send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)",
                sendParam,
                fee,
                address(this) // refund address
            )
        );

        require(success, "OFT send failed");
        (receipt, ) = abi.decode(result, (MessagingReceipt, OFTReceipt));

        return receipt;
    }

    /**
     * @notice Convert address to bytes32
     * @param addr The address to convert
     * @return The bytes32 representation
     */
    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /* --------------- ADMIN FUNCTIONS --------------- */

    /**
     * @notice Rescue tokens accidentally sent to this contract
     * @param token The token address
     * @param to The recipient
     * @param amount The amount to rescue
     */
    function rescueToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Rescue native tokens
     * @param to The recipient
     * @param amount The amount
     */
    function rescueNative(address payable to, uint256 amount) external onlyOwner {
        (bool success, ) = to.call{ value: amount }("");
        require(success, "Native transfer failed");
    }

    /**
     * @notice Receive function to accept native tokens
     */
    receive() external payable {}
}

// Struct for OFT receipt (needed for decoding)
struct OFTReceipt {
    uint256 amountSentLD;
    uint256 amountReceivedLD;
}
