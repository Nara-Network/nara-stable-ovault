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

    address public vault;
    IERC20 public naraUsd;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _vault The vault address that can withdraw
     * @param _narausd The NaraUSD token address
     */
    function initialize(address _vault, address _narausd) public initializer {
        if (_vault == address(0) || _narausd == address(0)) revert InvalidZeroAddress();

        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        vault = _vault;
        naraUsd = IERC20(_narausd);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     * @dev Only owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Update vault address (only owner, for deployment flexibility)
     * @param _vault The new vault address
     */
    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert InvalidZeroAddress();
        vault = _vault;
    }

    /**
     * @notice Update naraUSD token address (only owner, for deployment flexibility)
     * @param narausd The new naraUSD token address
     */
    function setNaraUsd(address narausd) external onlyOwner {
        if (narausd == address(0)) revert InvalidZeroAddress();
        naraUsd = IERC20(narausd);
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    /// @notice Withdraw NaraUSD from silo (only callable by vault)
    function withdraw(address to, uint256 amount) external onlyVault {
        naraUsd.transfer(to, amount);
    }
}
