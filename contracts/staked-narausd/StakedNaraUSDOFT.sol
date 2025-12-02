// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/**
 * @title StakedNaraUSDOFT
 * @notice OFT for snaraUSD vault shares on spoke chains
 * @dev This is deployed on spoke chains to represent snaraUSD shares cross-chain
 */
contract StakedNaraUSDOFT is OFT, AccessControl {
    /* --------------- CONSTANTS --------------- */

    /// @notice Role that can blacklist and un-blacklist addresses
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    /// @notice Role that prevents an address from transferring
    bytes32 public constant FULL_RESTRICTED_STAKER_ROLE = keccak256("FULL_RESTRICTED_STAKER_ROLE");

    /* --------------- ERRORS --------------- */

    error OperationNotAllowed();
    error CantBlacklistOwner();
    error CantRenounceOwnership();

    /* --------------- MODIFIERS --------------- */

    /// @notice Ensure blacklist target is not admin
    modifier notAdmin(address target) {
        if (hasRole(DEFAULT_ADMIN_ROLE, target)) revert CantBlacklistOwner();
        _;
    }

    /**
     * @notice Constructs the snaraUSD Share OFT contract for spoke chains
     * @param _lzEndpoint The address of the LayerZero endpoint on this chain
     * @param _delegate The address that will have owner privileges
     */
    constructor(
        address _lzEndpoint,
        address _delegate
    ) OFT("Staked naraUSD", "snaraUSD", _lzEndpoint, _delegate) Ownable(_delegate) {
        _grantRole(DEFAULT_ADMIN_ROLE, _delegate);
        _grantRole(BLACKLIST_MANAGER_ROLE, _delegate);
    }

    /**
     * @notice Add an address to blacklist
     * @param target The address to blacklist
     */
    function addToBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) notAdmin(target) {
        _grantRole(FULL_RESTRICTED_STAKER_ROLE, target);
    }

    /**
     * @notice Remove an address from blacklist
     * @param target The address to un-blacklist
     */
    function removeFromBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        _revokeRole(FULL_RESTRICTED_STAKER_ROLE, target);
    }

    /**
     * @dev Hook that is called before any transfer of tokens
     * @dev Disables transfers from or to addresses with FULL_RESTRICTED_STAKER_ROLE
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, from)) {
            revert OperationNotAllowed();
        }
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, to)) {
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
