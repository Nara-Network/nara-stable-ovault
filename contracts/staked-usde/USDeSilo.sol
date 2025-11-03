// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IUSDeSiloDefinitions.sol";

/**
 * @title USDeSilo
 * @notice The Silo allows to store USDe during the stake cooldown process.
 */
contract USDeSilo is IUSDeSiloDefinitions {
    address immutable STAKING_VAULT;
    IERC20 immutable USDE;

    constructor(address stakingVault, address usde) {
        STAKING_VAULT = stakingVault;
        USDE = IERC20(usde);
    }

    modifier onlyStakingVault() {
        if (msg.sender != STAKING_VAULT) revert OnlyStakingVault();
        _;
    }

    function withdraw(address to, uint256 amount) external onlyStakingVault {
        USDE.transfer(to, amount);
    }
}

