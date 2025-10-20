// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";

/**
 * @title MCTOFTAdapter
 * @notice OFT adapter for MultiCollateralToken on hub chain (lockbox model)
 * @dev This wraps the MCT token on the hub chain for cross-chain transfers
 */
contract MCTOFTAdapter is OFTAdapter {
    /**
     * @notice Creates a new OFT adapter for MCT
     * @param _token The MCT token address
     * @param _lzEndpoint The LayerZero endpoint for this chain
     * @param _delegate The account with administrative privileges
     */
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OFTAdapter(_token, _lzEndpoint, _delegate) Ownable(_delegate) {}
}
