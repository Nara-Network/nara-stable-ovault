// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/**
 * @title NaraUSDOFT
 * @notice OFT for NaraUSD vault shares on spoke chains
 * @dev This is deployed on spoke chains to represent NaraUSD shares cross-chain
 *
 * @dev Privileged roles:
 * - DEFAULT_ADMIN_ROLE: Full administrative control. Can:
 *   - Grant/revoke all other roles
 *   - Manage contract ownership (via Ownable)
 * - BLACKLIST_MANAGER_ROLE: Can add/remove addresses from blacklist (FULL_RESTRICTED_ROLE)
 * - FULL_RESTRICTED_ROLE: Restriction status (not a role to grant). Addresses with this role:
 *   - Cannot transfer tokens (including via transferFrom)
 *   - Cannot receive tokens
 */
contract NaraUSDOFT is OFT, AccessControl {
    /* --------------- CONSTANTS --------------- */

    /// @notice Role that can blacklist and un-blacklist addresses
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    /// @notice Role that prevents an address from transferring
    bytes32 public constant FULL_RESTRICTED_ROLE = keccak256("FULL_RESTRICTED_ROLE");

    /* --------------- ERRORS --------------- */

    error OperationNotAllowed();
    error CantBlacklistOwner();
    error CantRenounceOwnership();
    error ZeroAddressException();
    error ValueUnchanged();

    /* --------------- MODIFIERS --------------- */

    /// @notice Ensure blacklist target is not admin
    modifier notAdmin(address target) {
        _notAdmin(target);
        _;
    }

    function _notAdmin(address target) internal view {
        if (hasRole(DEFAULT_ADMIN_ROLE, target)) revert CantBlacklistOwner();
    }

    /**
     * @notice Constructs the NaraUSD Share OFT contract for spoke chains
     * @param _lzEndpoint The address of the LayerZero endpoint on this chain
     * @param _delegate The address that will have owner privileges
     */
    constructor(
        address _lzEndpoint,
        address _delegate
    ) OFT("Nara USD", "NaraUSD", _lzEndpoint, _delegate) Ownable(_delegate) {
        _grantRole(DEFAULT_ADMIN_ROLE, _delegate);
        _grantRole(BLACKLIST_MANAGER_ROLE, _delegate);
    }

    /**
     * @notice Add an address to blacklist
     * @param target The address to blacklist
     */
    function addToBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) notAdmin(target) {
        if (target == address(0)) revert ZeroAddressException();
        if (hasRole(FULL_RESTRICTED_ROLE, target)) revert ValueUnchanged();
        _grantRole(FULL_RESTRICTED_ROLE, target);
    }

    /**
     * @notice Remove an address from blacklist
     * @param target The address to un-blacklist
     */
    function removeFromBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        if (target == address(0)) revert ZeroAddressException();
        if (!hasRole(FULL_RESTRICTED_ROLE, target)) revert ValueUnchanged();
        _revokeRole(FULL_RESTRICTED_ROLE, target);
    }

    /**
     * @dev Hook that is called before any transfer of tokens
     * @dev Disables transfers from or to addresses with FULL_RESTRICTED_ROLE
     * @dev Also prevents blacklisted msg.sender from initiating transfers via transferFrom
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (hasRole(FULL_RESTRICTED_ROLE, from)) {
            revert OperationNotAllowed();
        }
        if (hasRole(FULL_RESTRICTED_ROLE, to)) {
            revert OperationNotAllowed();
        }
        // Prevent blacklisted operators from moving tokens via transferFrom
        // msg.sender == address(0) during initialization, skip check in that case
        if (msg.sender != address(0) && hasRole(FULL_RESTRICTED_ROLE, msg.sender)) {
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
