// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./NaraUSDPlus.sol";
import "../interfaces/narausd/INaraUSD.sol";

/**
 * @title StakingRewardsDistributor
 * @notice Helper contract to automate staking rewards distribution
 * @dev This contract allows automated reward distribution without multisig transactions,
 *      increasing distribution frequency and reducing arbitrage opportunities.
 *
 *      Roles:
 *      - Owner (multisig): Configuration calls only
 *      - Operator (delegated signer): Can transfer rewards to staking contract
 * @dev This contract is upgradeable using UUPS proxy pattern
 */
contract StakingRewardsDistributor is
    Initializable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /* --------------- CONSTANTS --------------- */

    /// @notice Placeholder address for native ETH
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* --------------- STATE VARIABLES --------------- */

    /// @notice Staking vault contract
    NaraUSDPlus public stakingVault;

    /// @notice NaraUSD token
    IERC20 public narausdToken;

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

    /* --------------- INITIALIZER --------------- */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _stakingVault The staking vault contract
     * @param _narausd The NaraUSD token contract
     * @param _admin The admin address (multisig)
     * @param _operator The operator address (delegated signer)
     */
    function initialize(
        NaraUSDPlus _stakingVault,
        IERC20 _narausd,
        address _admin,
        address _operator
    ) public initializer {
        if (address(_stakingVault) == address(0)) revert InvalidZeroAddress();
        if (address(_narausd) == address(0)) revert InvalidZeroAddress();
        if (_admin == address(0)) revert InvalidZeroAddress();
        if (_operator == address(0)) revert InvalidZeroAddress();

        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        stakingVault = _stakingVault;
        narausdToken = _narausd;

        _transferOwnership(_admin);

        // Set the operator
        setOperator(_operator);

        // Approve NaraUSD to the staking contract
        narausdToken.safeIncreaseAllowance(address(stakingVault), type(uint256).max);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     * @dev Only owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* --------------- EXTERNAL --------------- */

    /**
     * @notice Transfer NaraUSD rewards to the staking contract
     * @param _rewardsAmount The amount of NaraUSD to send
     * @dev Only the operator can call this function
     * @dev This contract must have REWARDER_ROLE in the staking contract
     */
    function transferInRewards(uint256 _rewardsAmount) external nonReentrant {
        if (msg.sender != operator) revert OnlyOperator();

        // Check that this contract holds enough NaraUSD balance
        if (narausdToken.balanceOf(address(this)) < _rewardsAmount) revert InsufficientFunds();

        stakingVault.transferInRewards(_rewardsAmount);
    }

    /**
     * @notice Burn NaraUSD assets from the staking contract to decrease NaraUSD+ exchange rate
     * @param _amount The amount of NaraUSD to burn from staking vault
     * @dev Only the operator can call this function
     * @dev This contract must have REWARDER_ROLE in the staking contract
     */
    function burnAssets(uint256 _amount) external nonReentrant {
        if (msg.sender != operator) revert OnlyOperator();

        stakingVault.burnAssets(_amount);
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
