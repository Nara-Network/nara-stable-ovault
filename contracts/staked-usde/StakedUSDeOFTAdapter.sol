// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";

/**
 * @title StakedUSDeOFTAdapter
 * @notice OFT adapter for sUSDe vault shares on hub chain (lockbox model)
 * @dev The share token MUST be an OFT adapter (lockbox) to maintain proper vault accounting
 * @dev A mint-burn adapter would not work since it transforms totalSupply()
 */
contract StakedUSDeOFTAdapter is OFTAdapter {
    /**
     * @notice Creates a new OFT adapter for sUSDe vault shares
     * @param _token The StakedUSDe token address
     * @param _lzEndpoint The LayerZero endpoint for this chain
     * @param _delegate The account with administrative privileges
     */
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OFTAdapter(_token, _lzEndpoint, _delegate) Ownable(_delegate) {}
}
