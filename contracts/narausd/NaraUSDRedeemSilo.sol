// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title NaraUSDRedeemSilo
 * @notice Holds locked NaraUSD tokens during redemption queue period
 */
contract NaraUSDRedeemSilo {
    /// @notice Error when caller is not the vault
    error OnlyVault();

    address immutable VAULT;
    IERC20 immutable naraUSD;

    constructor(address vault, address narausd) {
        VAULT = vault;
        naraUSD = IERC20(narausd);
    }

    modifier onlyVault() {
        if (msg.sender != VAULT) revert OnlyVault();
        _;
    }

    /// @notice Withdraw NaraUSD from silo (only callable by vault)
    function withdraw(address to, uint256 amount) external onlyVault {
        naraUSD.transfer(to, amount);
    }
}

