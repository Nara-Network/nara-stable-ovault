// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/**
 * @title nUSDOFT
 * @notice OFT for nUSD vault shares on spoke chains
 * @dev This is deployed on spoke chains to represent nUSD shares cross-chain
 */
contract nUSDOFT is OFT {
    /**
     * @notice Constructs the nUSD Share OFT contract for spoke chains
     * @param _lzEndpoint The address of the LayerZero endpoint on this chain
     * @param _delegate The address that will have owner privileges
     */
    constructor(
        address _lzEndpoint,
        address _delegate
    ) OFT("nUSD", "nUSD", _lzEndpoint, _delegate) Ownable(_delegate) {}
}
