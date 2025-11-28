// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/InUSDSiloDefinitions.sol";

/**
 * @title StakednUSDSilo
 * @notice The Silo allows to store staking vault tokens (snUSD) during the stake cooldown process.
 */
contract StakednUSDSilo is InUSDSiloDefinitions {
    address immutable STAKING_VAULT;
    IERC20 immutable TOKEN;

    constructor(address stakingVault, address token) {
        STAKING_VAULT = stakingVault;
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
