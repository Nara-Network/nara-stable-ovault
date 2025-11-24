// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/**
 * @title StakednUSDOFT
 * @notice OFT for snUSD vault shares on spoke chains
 * @dev This is deployed on spoke chains to represent snUSD shares cross-chain
 */
contract StakednUSDOFT is OFT {
    /**
     * @notice Constructs the snUSD Share OFT contract for spoke chains
     * @param _lzEndpoint The address of the LayerZero endpoint on this chain
     * @param _delegate The address that will have owner privileges
     */
    constructor(
        address _lzEndpoint,
        address _delegate
    ) OFT("Staked nUSD", "snUSD", _lzEndpoint, _delegate) Ownable(_delegate) {}
}
