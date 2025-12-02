// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

/**
 * @title IStakingRewardsDistributor
 * @notice Interface for the StakingRewardsDistributor contract
 */
interface IStakingRewardsDistributor {
    /* --------------- EVENTS --------------- */

    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event OperatorUpdated(address indexed newOperator, address indexed previousOperator);

    /* --------------- ERRORS --------------- */

    error InvalidZeroAddress();
    error InvalidAmount();
    error TransferFailed();
    error CantRenounceOwnership();
    error OnlyOperator();
    error InsufficientFunds();

    /* --------------- FUNCTIONS --------------- */

    /**
     * @notice Transfer naraUSD rewards to the staking contract
     * @param _rewardsAmount The amount of naraUSD to send
     */
    function transferInRewards(uint256 _rewardsAmount) external;

    /**
     * @notice Rescue tokens accidentally sent to the contract
     * @param _token The token to rescue
     * @param _to The address to send rescued tokens to
     * @param _amount The amount to rescue
     */
    function rescueTokens(address _token, address _to, uint256 _amount) external;

    /**
     * @notice Set a new operator
     * @param _newOperator The new operator address
     */
    function setOperator(address _newOperator) external;

    /* --------------- VIEW FUNCTIONS --------------- */

    /**
     * @notice Get the operator address
     * @return address The operator address
     */
    function operator() external view returns (address);
}
