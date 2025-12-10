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

    address public stakingVault;
    IERC20 public token;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _stakingVault The staking vault address that can withdraw
     * @param _token The token address (NaraUSD+)
     */
    function initialize(address _stakingVault, address _token) public initializer {
        if (_stakingVault == address(0) || _token == address(0)) revert InvalidZeroAddress();

        __Ownable_init(msg.sender);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        stakingVault = _stakingVault;
        token = IERC20(_token);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     * @dev Only owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Update staking vault address (only owner, for deployment flexibility)
     * @param _stakingVault The new staking vault address
     */
    function setStakingVault(address _stakingVault) external onlyOwner {
        if (_stakingVault == address(0)) revert InvalidZeroAddress();
        stakingVault = _stakingVault;
    }

    /**
     * @notice Update token address (only owner, for deployment flexibility)
     * @param _token The new token address
     */
    function setToken(address _token) external onlyOwner {
        if (_token == address(0)) revert InvalidZeroAddress();
        token = IERC20(_token);
    }

    modifier onlyStakingVault() {
        _onlyStakingVault();
        _;
    }

    function _onlyStakingVault() internal view {
        if (msg.sender != stakingVault) revert OnlyStakingVault();
    }

    function withdraw(address to, uint256 amount) external onlyStakingVault {
        token.transfer(to, amount);
    }
}
