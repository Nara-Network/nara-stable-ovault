// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/InUSDSiloDefinitions.sol";

/**
 * @title NUSDSilo
 * @notice The Silo allows to store nUSD during the stake cooldown process.
 */
contract nUSDSilo is InUSDSiloDefinitions {
    address immutable STAKING_VAULT;
    IERC20 immutable NUSD;

    constructor(address stakingVault, address nusd) {
        STAKING_VAULT = stakingVault;
        nUSD = IERC20(nusd);
    }

    modifier onlyStakingVault() {
        if (msg.sender != STAKING_VAULT) revert OnlyStakingVault();
        _;
    }

    function withdraw(address to, uint256 amount) external onlyStakingVault {
        nUSD.transfer(to, amount);
    }
}

