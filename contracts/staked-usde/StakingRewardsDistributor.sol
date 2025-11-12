// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./StakedUSDe.sol";
import "../interfaces/usde/IUSDe.sol";

/**
 * @title StakingRewardsDistributor
 * @notice Helper contract to automate staking rewards distribution
 * @dev This contract allows automated reward distribution without multisig transactions,
 *      increasing distribution frequency and reducing arbitrage opportunities.
 *
 *      Roles:
 *      - Owner (multisig): Configuration calls only
 *      - Operator (delegated signer): Can transfer rewards to staking contract
 */
contract StakingRewardsDistributor is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* --------------- CONSTANTS --------------- */

    /// @notice Placeholder address for native ETH
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* --------------- IMMUTABLES --------------- */

    /// @notice Staking vault contract
    StakedUSDe public immutable STAKING_VAULT;

    /// @notice USDe token
    IERC20 public immutable USDE_TOKEN;

    /* --------------- STATE VARIABLES --------------- */

    /// @notice Operator address authorized to invoke transferInRewards
    address public operator;

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

    /* --------------- CONSTRUCTOR --------------- */

    /**
     * @notice Constructor for StakingRewardsDistributor
     * @param _stakingVault The staking vault contract
     * @param _usde The USDe token contract
     * @param _admin The admin address (multisig)
     * @param _operator The operator address (delegated signer)
     */
    constructor(StakedUSDe _stakingVault, IERC20 _usde, address _admin, address _operator) Ownable(msg.sender) {
        if (address(_stakingVault) == address(0)) revert InvalidZeroAddress();
        if (address(_usde) == address(0)) revert InvalidZeroAddress();
        if (_admin == address(0)) revert InvalidZeroAddress();
        if (_operator == address(0)) revert InvalidZeroAddress();

        STAKING_VAULT = _stakingVault;
        USDE_TOKEN = _usde;

        _transferOwnership(msg.sender);

        // Set the operator
        setOperator(_operator);

        // Approve USDe to the staking contract
        USDE_TOKEN.safeIncreaseAllowance(address(STAKING_VAULT), type(uint256).max);

        if (msg.sender != _admin) {
            _transferOwnership(_admin);
        }
    }

    /* --------------- EXTERNAL --------------- */

    /**
     * @notice Transfer USDe rewards to the staking contract
     * @param _rewardsAmount The amount of USDe to send
     * @dev Only the operator can call this function
     * @dev This contract must have REWARDER_ROLE in the staking contract
     */
    function transferInRewards(uint256 _rewardsAmount) external nonReentrant {
        if (msg.sender != operator) revert OnlyOperator();

        // Check that this contract holds enough USDe balance
        if (USDE_TOKEN.balanceOf(address(this)) < _rewardsAmount) revert InsufficientFunds();

        STAKING_VAULT.transferInRewards(_rewardsAmount);
    }

    /**
     * @notice Remove USDe assets from the staking contract to decrease sUSDe exchange rate
     * @param _amount The amount of USDe to remove from staking vault
     * @param _to The address to send the removed USDe to
     * @dev Only the operator can call this function
     * @dev This contract must have REWARDER_ROLE in the staking contract
     */
    function removeAssets(uint256 _amount, address _to) external nonReentrant {
        if (msg.sender != operator) revert OnlyOperator();
        if (_to == address(0)) revert InvalidZeroAddress();

        STAKING_VAULT.removeAssets(_amount, _to);
    }

    /**
     * @notice Rescue tokens accidentally sent to the contract
     * @param _token The token to rescue (or ETH_ADDRESS for native ETH)
     * @param _to The address to send rescued tokens to
     * @param _amount The amount to rescue
     */
    function rescueTokens(address _token, address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert InvalidZeroAddress();
        if (_amount == 0) revert InvalidAmount();

        if (_token == ETH_ADDRESS) {
            (bool success, ) = _to.call{ value: _amount }("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }

        emit TokensRescued(_token, _to, _amount);
    }

    /**
     * @notice Set a new operator
     * @param _newOperator The new operator address
     */
    function setOperator(address _newOperator) public onlyOwner {
        if (_newOperator == address(0)) revert InvalidZeroAddress();

        address previousOperator = operator;
        operator = _newOperator;

        emit OperatorUpdated(_newOperator, previousOperator);
    }

    /**
     * @notice Prevent renouncing ownership
     */
    function renounceOwnership() public view override onlyOwner {
        revert CantRenounceOwnership();
    }

    /**
     * @notice Receive native ETH
     */
    receive() external payable {}
}
