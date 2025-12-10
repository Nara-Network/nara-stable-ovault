// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/**
 * @title NaraUSDRedeemSilo
 * @notice Holds locked NaraUSD tokens during redemption queue period
 * @dev This contract is upgradeable using UUPS proxy pattern
 */
contract NaraUSDRedeemSilo is Initializable, UUPSUpgradeable, Ownable2StepUpgradeable {
    /// @notice Error when caller is not the vault
    error OnlyVault();
    error InvalidZeroAddress();

    address public VAULT;
    IERC20 public naraUSD;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param vault The vault address that can withdraw
     * @param narausd The NaraUSD token address
     */
    function initialize(address vault, address narausd) public initializer {
        if (vault == address(0) || narausd == address(0)) revert InvalidZeroAddress();

        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        VAULT = vault;
        naraUSD = IERC20(narausd);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     * @dev Only owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Update vault address (only owner, for deployment flexibility)
     * @param vault The new vault address
     */
    function setVault(address vault) external onlyOwner {
        if (vault == address(0)) revert InvalidZeroAddress();
        VAULT = vault;
    }

    /**
     * @notice Update naraUSD token address (only owner, for deployment flexibility)
     * @param narausd The new naraUSD token address
     */
    function setNaraUSD(address narausd) external onlyOwner {
        if (narausd == address(0)) revert InvalidZeroAddress();
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

