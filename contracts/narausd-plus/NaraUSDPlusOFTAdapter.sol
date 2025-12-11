// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OFTAdapterUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";

/**
 * @title NaraUSDPlusOFTAdapter
 * @notice OFT adapter for NaraUSD+ vault shares on hub chain (lockbox model)
 * @dev The share token MUST be an OFT adapter (lockbox) to maintain proper vault accounting
 * @dev A mint-burn adapter would not work since it transforms totalSupply()
 * @dev This contract is upgradeable using UUPS proxy pattern
 */
contract NaraUSDPlusOFTAdapter is Initializable, OFTAdapterUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the NaraUSD+ OFT adapter
     * @param _delegate The account with administrative privileges
     */
    function initialize(address _delegate) public initializer {
        __OFTAdapter_init(_delegate);
        __Ownable_init(_delegate);
        __UUPSUpgradeable_init();
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     * @dev Only owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
