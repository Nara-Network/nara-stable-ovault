// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

/**
 * @title MockKeyring
 * @notice Mock implementation of the Keyring credential checking system for testing
 */
contract MockKeyring {
    // Mapping of policyId => address => hasCredential
    mapping(uint256 => mapping(address => bool)) private credentials;

    /**
     * @notice Check if an entity has a valid credential for a specific policy
     * @param policyId The ID of the policy to check against
     * @param entity The address of the entity to check
     * @return bool indicating whether the entity has valid credentials
     */
    function checkCredential(uint256 policyId, address entity) external view returns (bool) {
        return credentials[policyId][entity];
    }

    /**
     * @notice Set credential status for an address (for testing purposes)
     * @param policyId The policy ID
     * @param entity The address to set credential for
     * @param hasCredential Whether the address has credentials
     */
    function setCredential(uint256 policyId, address entity, bool hasCredential) external {
        credentials[policyId][entity] = hasCredential;
    }

    /**
     * @notice Batch set credentials for multiple addresses
     * @param policyId The policy ID
     * @param entities Array of addresses
     * @param hasCredentials Array of credential statuses
     */
    function batchSetCredentials(
        uint256 policyId,
        address[] calldata entities,
        bool[] calldata hasCredentials
    ) external {
        require(entities.length == hasCredentials.length, "Length mismatch");
        for (uint256 i = 0; i < entities.length; i++) {
            credentials[policyId][entities[i]] = hasCredentials[i];
        }
    }
}

