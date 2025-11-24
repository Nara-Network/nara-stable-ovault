// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title nUSDRedeemSilo
 * @notice Holds locked nUSD tokens during redemption cooldown period
 */
contract nUSDRedeemSilo {
    /// @notice Error when caller is not the vault
    error OnlyVault();

    address immutable VAULT;
    IERC20 immutable nUSD;

    constructor(address vault, address nusd) {
        VAULT = vault;
        nUSD = IERC20(nusd);
    }

    modifier onlyVault() {
        if (msg.sender != VAULT) revert OnlyVault();
        _;
    }

    /// @notice Withdraw nUSD from silo (only callable by vault)
    function withdraw(address to, uint256 amount) external onlyVault {
        nUSD.transfer(to, amount);
    }
}

