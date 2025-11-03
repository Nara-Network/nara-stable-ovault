// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title USDeRedeemSilo
 * @notice Holds locked USDe tokens during redemption cooldown period
 */
contract USDeRedeemSilo {
    /// @notice Error when caller is not the vault
    error OnlyVault();

    address immutable VAULT;
    IERC20 immutable USDE;

    constructor(address vault, address usde) {
        VAULT = vault;
        USDE = IERC20(usde);
    }

    modifier onlyVault() {
        if (msg.sender != VAULT) revert OnlyVault();
        _;
    }

    /// @notice Withdraw USDe from silo (only callable by vault)
    function withdraw(address to, uint256 amount) external onlyVault {
        USDE.transfer(to, amount);
    }
}

