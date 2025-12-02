// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title IStakedNaraUSD
 * @notice Interface for the StakedNaraUSD contract
 */
interface IStakedNaraUSD is IERC4626, IERC20Permit {
    /* --------------- EVENTS --------------- */

    event RewardsReceived(uint256 amount);
    event LockedAmountRedistributed(address indexed from, address indexed to, uint256 amount);
    event AssetsBurned(uint256 amount);

    /* --------------- ERRORS --------------- */

    error InvalidZeroAddress();
    error InvalidAmount();
    error InvalidToken();
    error CantBlacklistOwner();
    error OperationNotAllowed();
    error MinSharesViolation();
    error StillVesting();
    error CantRenounceOwnership();
    error ReserveTooLowAfterBurn();

    /* --------------- FUNCTIONS --------------- */

    /**
     * @notice Transfer rewards from the rewarder into this contract
     * @param amount The amount of rewards to transfer
     */
    function transferInRewards(uint256 amount) external;

    /**
     * @notice Burn naraUSD from the contract to decrease snaraUSD exchange rate
     * @param amount The amount of naraUSD to burn
     */
    function burnAssets(uint256 amount) external;

    /**
     * @notice Add an address to blacklist
     * @param target The address to blacklist
     */
    function addToBlacklist(address target) external;

    /**
     * @notice Remove an address from blacklist
     * @param target The address to un-blacklist
     */
    function removeFromBlacklist(address target) external;

    /**
     * @notice Rescue tokens accidentally sent to the contract
     * @param token The token to be rescued
     * @param amount The amount of tokens to be rescued
     * @param to Where to send rescued tokens
     */
    function rescueTokens(address token, uint256 amount, address to) external;

    /**
     * @notice Redistribute locked amount from full restricted user
     * @param from The address to burn the entire balance from
     * @param to The address to mint the entire balance to
     */
    function redistributeLockedAmount(address from, address to) external;

    /* --------------- VIEW FUNCTIONS --------------- */

    /**
     * @notice Returns the amount of naraUSD tokens that are unvested
     * @return The unvested amount
     */
    function getUnvestedAmount() external view returns (uint256);

    /**
     * @notice Get vesting amount
     * @return uint256 The vesting amount
     */
    function vestingAmount() external view returns (uint256);

    /**
     * @notice Get last distribution timestamp
     * @return uint256 The last distribution timestamp
     */
    function lastDistributionTimestamp() external view returns (uint256);

    /**
     * @notice Get vesting period constant
     * @return uint256 The vesting period
     */
    function VESTING_PERIOD() external view returns (uint256);

    /**
     * @notice Get minimum shares constant
     * @return uint256 The minimum shares
     */
    function MIN_SHARES() external view returns (uint256);
}
