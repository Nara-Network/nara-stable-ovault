// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title StakedUSDe
 * @notice Staking contract for USDe tokens with OVault integration
 * @dev Users stake USDe tokens and earn rewards. The contract uses ERC4626 standard
 *      for vault operations and can be integrated with LayerZero's OVault for omnichain functionality.
 *
 *      Rewards are distributed by REWARDER_ROLE and vest over time to prevent MEV attacks.
 */
contract StakedUSDe is AccessControl, ReentrancyGuard, ERC20Permit, ERC4626 {
    using SafeERC20 for IERC20;

    /* --------------- CONSTANTS --------------- */

    /// @notice Role that can distribute rewards to this contract
    bytes32 public constant REWARDER_ROLE = keccak256("REWARDER_ROLE");

    /// @notice Role that can blacklist and un-blacklist addresses
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    /// @notice Role that prevents an address from staking
    bytes32 public constant SOFT_RESTRICTED_STAKER_ROLE = keccak256("SOFT_RESTRICTED_STAKER_ROLE");

    /// @notice Role that prevents an address from transferring, staking, or unstaking
    bytes32 public constant FULL_RESTRICTED_STAKER_ROLE = keccak256("FULL_RESTRICTED_STAKER_ROLE");

    /// @notice Vesting period for rewards (8 hours)
    uint256 public constant VESTING_PERIOD = 8 hours;

    /// @notice Minimum non-zero shares to prevent donation attack
    uint256 public constant MIN_SHARES = 1 ether;

    /* --------------- STATE VARIABLES --------------- */

    /// @notice Amount of the last asset distribution + unvested remainder
    uint256 public vestingAmount;

    /// @notice Timestamp of the last asset distribution
    uint256 public lastDistributionTimestamp;

    /* --------------- EVENTS --------------- */

    event RewardsReceived(uint256 amount);
    event LockedAmountRedistributed(address indexed from, address indexed to, uint256 amount);

    /* --------------- ERRORS --------------- */

    error InvalidZeroAddress();
    error InvalidAmount();
    error InvalidToken();
    error CantBlacklistOwner();
    error OperationNotAllowed();
    error MinSharesViolation();
    error StillVesting();
    error CantRenounceOwnership();

    /* --------------- MODIFIERS --------------- */

    /// @notice Ensure input amount is non-zero
    modifier notZero(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    /// @notice Ensure blacklist target is not admin
    modifier notAdmin(address target) {
        if (hasRole(DEFAULT_ADMIN_ROLE, target)) revert CantBlacklistOwner();
        _;
    }

    /* --------------- CONSTRUCTOR --------------- */

    /**
     * @notice Constructor for StakedUSDe contract
     * @param _asset The address of the USDe token
     * @param _initialRewarder The address of the initial rewarder
     * @param _admin The address of the admin role
     */
    constructor(
        IERC20 _asset,
        address _initialRewarder,
        address _admin
    ) ERC20("Staked USDe", "sUSDe") ERC4626(_asset) ERC20Permit("sUSDe") {
        if (_admin == address(0) || _initialRewarder == address(0) || address(_asset) == address(0)) {
            revert InvalidZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(REWARDER_ROLE, _initialRewarder);
        _grantRole(BLACKLIST_MANAGER_ROLE, _admin);
    }

    /* --------------- EXTERNAL --------------- */

    /**
     * @notice Transfer rewards from the rewarder into this contract
     * @param amount The amount of rewards to transfer
     */
    function transferInRewards(uint256 amount) external nonReentrant onlyRole(REWARDER_ROLE) notZero(amount) {
        _updateVestingAmount(amount);

        // Transfer assets from rewarder to this contract
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        emit RewardsReceived(amount);
    }

    /**
     * @notice Add an address to blacklist
     * @param target The address to blacklist
     * @param isFullBlacklisting Soft or full blacklisting level
     */
    function addToBlacklist(
        address target,
        bool isFullBlacklisting
    ) external onlyRole(BLACKLIST_MANAGER_ROLE) notAdmin(target) {
        bytes32 role = isFullBlacklisting ? FULL_RESTRICTED_STAKER_ROLE : SOFT_RESTRICTED_STAKER_ROLE;
        _grantRole(role, target);
    }

    /**
     * @notice Remove an address from blacklist
     * @param target The address to un-blacklist
     * @param isFullBlacklisting Soft or full blacklisting level
     */
    function removeFromBlacklist(address target, bool isFullBlacklisting) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        bytes32 role = isFullBlacklisting ? FULL_RESTRICTED_STAKER_ROLE : SOFT_RESTRICTED_STAKER_ROLE;
        _revokeRole(role, target);
    }

    /**
     * @notice Rescue tokens accidentally sent to the contract
     * @dev Cannot rescue the underlying asset (USDe)
     * @param token The token to be rescued
     * @param amount The amount of tokens to be rescued
     * @param to Where to send rescued tokens
     */
    function rescueTokens(
        address token,
        uint256 amount,
        address to
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(token) == asset()) revert InvalidToken();
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Redistribute locked amount from full restricted user
     * @param from The address to burn the entire balance from (must have FULL_RESTRICTED_STAKER_ROLE)
     * @param to The address to mint the entire balance to (or address(0) to burn)
     */
    function redistributeLockedAmount(address from, address to) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, from) && !hasRole(FULL_RESTRICTED_STAKER_ROLE, to)) {
            uint256 amountToDistribute = balanceOf(from);
            uint256 usdeToVest = previewRedeem(amountToDistribute);

            _burn(from, amountToDistribute);

            // to address of address(0) enables burning
            if (to == address(0)) {
                _updateVestingAmount(usdeToVest);
            } else {
                _mint(to, amountToDistribute);
            }

            emit LockedAmountRedistributed(from, to, amountToDistribute);
        } else {
            revert OperationNotAllowed();
        }
    }

    /* --------------- PUBLIC --------------- */

    /**
     * @notice Returns the amount of USDe tokens that are vested in the contract
     * @return The total vested assets
     */
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - getUnvestedAmount();
    }

    /**
     * @notice Returns the amount of USDe tokens that are unvested in the contract
     * @return The unvested amount
     */
    function getUnvestedAmount() public view returns (uint256) {
        uint256 timeSinceLastDistribution = block.timestamp - lastDistributionTimestamp;

        if (timeSinceLastDistribution >= VESTING_PERIOD) {
            return 0;
        }

        uint256 deltaT;
        unchecked {
            deltaT = (VESTING_PERIOD - timeSinceLastDistribution);
        }
        return (deltaT * vestingAmount) / VESTING_PERIOD;
    }

    /// @dev Necessary because both ERC20 (from ERC20Permit) and ERC4626 declare decimals()
    function decimals() public pure override(ERC4626, ERC20) returns (uint8) {
        return 18;
    }

    /* --------------- INTERNAL --------------- */

    /// @notice Ensure minimum shares to prevent donation attack
    function _checkMinShares() internal view {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0 && _totalSupply < MIN_SHARES) revert MinSharesViolation();
    }

    /**
     * @dev Deposit/mint common workflow with blacklist checks
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant notZero(assets) notZero(shares) {
        if (hasRole(SOFT_RESTRICTED_STAKER_ROLE, caller) || hasRole(SOFT_RESTRICTED_STAKER_ROLE, receiver)) {
            revert OperationNotAllowed();
        }
        super._deposit(caller, receiver, assets, shares);
        _checkMinShares();
    }

    /**
     * @dev Withdraw/redeem common workflow with blacklist checks
     */
    function _withdraw(
        address caller,
        address receiver,
        address _owner,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant notZero(assets) notZero(shares) {
        if (
            hasRole(FULL_RESTRICTED_STAKER_ROLE, caller) ||
            hasRole(FULL_RESTRICTED_STAKER_ROLE, receiver) ||
            hasRole(FULL_RESTRICTED_STAKER_ROLE, _owner)
        ) {
            revert OperationNotAllowed();
        }

        super._withdraw(caller, receiver, _owner, assets, shares);
        _checkMinShares();
    }

    /**
     * @notice Update vesting amount and timestamp
     * @param newVestingAmount The new vesting amount to add
     */
    function _updateVestingAmount(uint256 newVestingAmount) internal {
        if (getUnvestedAmount() > 0) revert StillVesting();

        vestingAmount = newVestingAmount;
        lastDistributionTimestamp = block.timestamp;
    }

    /**
     * @dev Hook that is called before any transfer of tokens
     * @dev Disables transfers from or to addresses with FULL_RESTRICTED_STAKER_ROLE
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, from) && to != address(0)) {
            revert OperationNotAllowed();
        }
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, to)) {
            revert OperationNotAllowed();
        }
        super._update(from, to, value);
    }

    /**
     * @dev Prevent renouncing roles to maintain contract security
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        if (role == DEFAULT_ADMIN_ROLE) revert CantRenounceOwnership();
        super.renounceRole(role, account);
    }
}
