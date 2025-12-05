// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title StakedNaraUSDSilo
 * @notice The Silo allows to store staking vault tokens (snaraUSD) during the stake cooldown process.
 */
contract StakedNaraUSDSilo {
    /// @notice Error emitted when the staking vault is not the caller
    error OnlyStakingVault();

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
