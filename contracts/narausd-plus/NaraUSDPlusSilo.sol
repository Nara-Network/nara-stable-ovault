// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/**
 * @title NaraUSDPlusSilo
 * @notice The Silo allows to store staking vault tokens (NaraUSD+) during the stake cooldown process.
 * @dev This contract is upgradeable using UUPS proxy pattern
 */
contract NaraUSDPlusSilo is Initializable, UUPSUpgradeable, Ownable2StepUpgradeable {
    /// @notice Error emitted when the staking vault is not the caller
    error OnlyStakingVault();
    error InvalidZeroAddress();

    address public STAKING_VAULT;
    IERC20 public TOKEN;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param stakingVault The staking vault address that can withdraw
     * @param token The token address (NaraUSD+)
     */
    function initialize(address stakingVault, address token) public initializer {
        if (stakingVault == address(0) || token == address(0)) revert InvalidZeroAddress();

        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        STAKING_VAULT = stakingVault;
        TOKEN = IERC20(token);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     * @dev Only owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Update staking vault address (only owner, for deployment flexibility)
     * @param stakingVault The new staking vault address
     */
    function setStakingVault(address stakingVault) external onlyOwner {
        if (stakingVault == address(0)) revert InvalidZeroAddress();
        STAKING_VAULT = stakingVault;
    }

    /**
     * @notice Update token address (only owner, for deployment flexibility)
     * @param token The new token address
     */
    function setToken(address token) external onlyOwner {
        if (token == address(0)) revert InvalidZeroAddress();
        TOKEN = IERC20(token);
    }

    modifier onlyStakingVault() {
        if (msg.sender != STAKING_VAULT) revert OnlyStakingVault();
        _;
    }

    function withdraw(address to, uint256 amount) external onlyStakingVault {
        TOKEN.transfer(to, amount);
    }
}
