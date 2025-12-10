// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title INaraUSDPlus
 * @notice Interface for the NaraUSDPlus contract with cooldown functionality
 */
interface INaraUSDPlus is IERC4626, IERC20Permit {
    /* --------------- STRUCTS --------------- */

    struct UserCooldown {
        uint104 cooldownEnd;
        uint152 sharesAmount; // Amount of NaraUSD+ shares locked in silo
    }

    /* --------------- EVENTS --------------- */

    event RewardsReceived(uint256 amount);
    event LockedAmountRedistributed(address indexed from, address indexed to, uint256 amount);
    event AssetsBurned(uint256 amount);
    /// @notice Event emitted when cooldown duration updates
    event CooldownDurationUpdated(uint24 previousDuration, uint24 newDuration);
    /// @notice Event emitted when vesting period updates
    event VestingPeriodUpdated(uint256 previousPeriod, uint256 newPeriod);

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
    /// @notice Error emitted when the shares amount to redeem is greater than the shares balance of the owner
    error ExcessiveRedeemAmount();
    /// @notice Error emitted when the shares amount to withdraw is greater than the shares balance of the owner
    error ExcessiveWithdrawAmount();
    /// @notice Error emitted when cooldown value is invalid
    error InvalidCooldown();

    /* --------------- FUNCTIONS --------------- */

    /**
     * @notice Transfer rewards from the rewarder into this contract
     * @param amount The amount of rewards to transfer
     */
    function transferInRewards(uint256 amount) external;

    /**
     * @notice Burn NaraUSD from the contract to decrease NaraUSD+ exchange rate
     * @param amount The amount of NaraUSD to burn
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
     * @notice Returns the amount of NaraUSD tokens that are unvested
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
     * @notice Get vesting period
     * @return uint256 The vesting period in seconds
     */
    function vestingPeriod() external view returns (uint256);

    /**
     * @notice Get minimum shares constant
     * @return uint256 The minimum shares
     */
    function MIN_SHARES() external view returns (uint256);

    /* --------------- COOLDOWN FUNCTIONS --------------- */

    /**
     * @notice Redeem assets and starts a cooldown to claim the converted underlying asset
     * @param assets assets to redeem
     * @return shares The amount of shares locked in cooldown
     */
    function cooldownAssets(uint256 assets) external returns (uint256 shares);

    /**
     * @notice Redeem shares into assets and starts a cooldown to claim the converted underlying asset
     * @param shares shares to redeem
     * @return assets The amount of assets that will be claimable after cooldown
     */
    function cooldownShares(uint256 shares) external returns (uint256 assets);

    /**
     * @notice Claim the staking amount after the cooldown has finished
     * @param receiver Address to receive the redeemed NaraUSD
     */
    function unstake(address receiver) external;

    /**
     * @notice Set cooldown duration
     * @param duration The cooldown duration in seconds
     */
    function setCooldownDuration(uint24 duration) external;

    /**
     * @notice Set vesting period for rewards
     * @param period The vesting period in seconds
     */
    function setVestingPeriod(uint256 period) external;

    /* --------------- COOLDOWN VIEW FUNCTIONS --------------- */

    /**
     * @notice Get cooldown duration
     * @return uint24 The cooldown duration in seconds
     */
    function cooldownDuration() external view returns (uint24);
}
