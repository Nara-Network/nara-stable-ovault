// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OFTUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";

/**
 * @title NaraUSDOFT
 * @notice OFT for NaraUSD vault shares on spoke chains
 * @dev This is deployed on spoke chains to represent NaraUSD shares cross-chain
 * @dev This contract is upgradeable using UUPS proxy pattern
 */
contract NaraUSDOFT is Initializable, OFTUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    /* --------------- CONSTANTS --------------- */

    /// @notice Role that can blacklist and un-blacklist addresses
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    /// @notice Role that prevents an address from transferring
    bytes32 public constant FULL_RESTRICTED_ROLE = keccak256("FULL_RESTRICTED_ROLE");

    /* --------------- ERRORS --------------- */

    error OperationNotAllowed();
    error CantBlacklistOwner();
    error CantRenounceOwnership();

    /* --------------- MODIFIERS --------------- */

    /// @notice Ensure blacklist target is not admin
    modifier notAdmin(address target) {
        _notAdmin(target);
        _;
    }

    function _notAdmin(address target) internal view {
        if (hasRole(DEFAULT_ADMIN_ROLE, target)) revert CantBlacklistOwner();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the NaraUSD Share OFT contract for spoke chains
     * @param _delegate The address that will have owner privileges
     */
    function initialize(address _delegate) public initializer {
        __OFT_init("Nara USD", "NaraUSD", _delegate);
        __Ownable_init(_delegate);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _delegate);
        _grantRole(BLACKLIST_MANAGER_ROLE, _delegate);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     * @dev Only owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Add an address to blacklist
     * @param target The address to blacklist
     */
    function addToBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) notAdmin(target) {
        _grantRole(FULL_RESTRICTED_ROLE, target);
    }

    /**
     * @notice Remove an address from blacklist
     * @param target The address to un-blacklist
     */
    function removeFromBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        _revokeRole(FULL_RESTRICTED_ROLE, target);
    }

    /**
     * @dev Hook that is called before any transfer of tokens
     * @dev Disables transfers from or to addresses with FULL_RESTRICTED_ROLE
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (hasRole(FULL_RESTRICTED_ROLE, from)) {
            revert OperationNotAllowed();
        }
        if (hasRole(FULL_RESTRICTED_ROLE, to)) {
            revert OperationNotAllowed();
        }

        super._update(from, to, value);
    }

    /**
     * @notice Prevent renouncing ownership
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        if (role == DEFAULT_ADMIN_ROLE) revert CantRenounceOwnership();
        super.renounceRole(role, account);
    }
}
