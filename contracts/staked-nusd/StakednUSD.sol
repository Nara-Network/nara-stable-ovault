// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IStakednUSDCooldown.sol";
import "./nUSDSilo.sol";
import "../interfaces/nusd/InUSD.sol";

/**
 * @title StakednUSD
 * @notice Staking contract for nUSD tokens with OVault integration and cooldown functionality (V2)
 * @dev Users stake nUSD tokens and earn rewards. The contract uses ERC4626 standard
 *      for vault operations and can be integrated with LayerZero's OVault for omnichain functionality.
 *
 *      Rewards are distributed by REWARDER_ROLE and vest over time to prevent MEV attacks.
 *
 * @dev If cooldown duration is set to zero, the StakednUSD behavior follows ERC4626 standard
 *      and disables cooldownShares and cooldownAssets methods. If cooldown duration is greater
 *      than zero, the ERC4626 withdrawal and redeem functions are disabled, breaking the ERC4626
 *      standard, and enabling the cooldownShares and the cooldownAssets functions.
 */
contract StakednUSD is AccessControl, ReentrancyGuard, ERC20Permit, ERC4626, IStakednUSDCooldown, Pausable {
    using SafeERC20 for IERC20;

    /* --------------- CONSTANTS --------------- */

    /// @notice Role that can distribute rewards to this contract
    bytes32 public constant REWARDER_ROLE = keccak256("REWARDER_ROLE");

    /// @notice Role that can blacklist and un-blacklist addresses
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    /// @notice Role that prevents an address from transferring, staking, or unstaking
    bytes32 public constant FULL_RESTRICTED_STAKER_ROLE = keccak256("FULL_RESTRICTED_STAKER_ROLE");

    /// @notice Vesting period for rewards (8 hours)
    uint256 public constant VESTING_PERIOD = 8 hours;

    /// @notice Minimum non-zero shares to prevent donation attack
    uint256 public constant MIN_SHARES = 1 ether;

    /// @notice Maximum cooldown duration (90 days)
    uint24 public constant MAX_COOLDOWN_DURATION = 90 days;

    /* --------------- STATE VARIABLES --------------- */

    /// @notice Amount of the last asset distribution + unvested remainder
    uint256 public vestingAmount;

    /// @notice Timestamp of the last asset distribution
    uint256 public lastDistributionTimestamp;

    /// @notice Cooldown duration in seconds
    uint24 public cooldownDuration;

    /// @notice Mapping of user addresses to their cooldown data
    mapping(address => UserCooldown) public cooldowns;

    /// @notice Silo contract for holding assets during cooldown
    nUSDSilo public immutable silo;

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

    /// @notice Ensure cooldownDuration is zero
    modifier ensureCooldownOff() {
        if (cooldownDuration != 0) revert OperationNotAllowed();
        _;
    }

    /// @notice Ensure cooldownDuration is gt 0
    modifier ensureCooldownOn() {
        if (cooldownDuration == 0) revert OperationNotAllowed();
        _;
    }

    /* --------------- CONSTRUCTOR --------------- */

    /**
     * @notice Constructor for StakednUSD contract
     * @param _asset The address of the nUSD token
     * @param _initialRewarder The address of the initial rewarder
     * @param _admin The address of the admin role
     */
    constructor(
        IERC20 _asset,
        address _initialRewarder,
        address _admin
    ) ERC20("Staked nUSD", "snUSD") ERC4626(_asset) ERC20Permit("snUSD") {
        if (_admin == address(0) || _initialRewarder == address(0) || address(_asset) == address(0)) {
            revert InvalidZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(REWARDER_ROLE, _initialRewarder);
        _grantRole(BLACKLIST_MANAGER_ROLE, _admin);

        silo = new nUSDSilo(address(this), address(_asset));
        cooldownDuration = MAX_COOLDOWN_DURATION;
    }

    /* --------------- EXTERNAL --------------- */

    /**
     * @notice Transfer rewards from the rewarder into this contract
     * @param amount The amount of rewards to transfer
     */
    function transferInRewards(
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(REWARDER_ROLE) notZero(amount) {
        _updateVestingAmount(amount);

        // Transfer assets from rewarder to this contract
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        emit RewardsReceived(amount);
    }

    /**
     * @notice Burn nUSD from the contract to decrease snUSD exchange rate
     * @dev This calls nUSD's burn function which burns both nUSD and underlying MCT
     * @dev Collateral stays in MCT, making remaining tokens more valuable (deflationary)
     * @dev Unlike transferInRewards, this happens instantly without vesting
     * @param amount The amount of nUSD to burn
     */
    function burnAssets(uint256 amount) external nonReentrant onlyRole(REWARDER_ROLE) notZero(amount) {
        // Verify contract has enough nUSD balance
        uint256 contractBalance = IERC20(asset()).balanceOf(address(this));
        if (contractBalance < amount) revert InvalidAmount();
        if (contractBalance - amount < 1 ether) revert ReserveTooLowAfterBurn();

        // Call nUSD's burn function to properly burn nUSD and MCT
        // nUSD.burn() burns from msg.sender (this contract), so StakednUSD must own the tokens
        InUSD nusd = InUSD(asset());
        nusd.burn(amount);

        emit AssetsBurned(amount);

        // Auto-pause after deflationary burn so admin can review balances before resuming
        _pause();
    }

    /**
     * @notice Add an address to blacklist
     * @param target The address to blacklist
     */
    function addToBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) notAdmin(target) {
        _grantRole(FULL_RESTRICTED_STAKER_ROLE, target);
    }

    /**
     * @notice Remove an address from blacklist
     * @param target The address to un-blacklist
     */
    function removeFromBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        _revokeRole(FULL_RESTRICTED_STAKER_ROLE, target);
    }

    /**
     * @notice Rescue tokens accidentally sent to the contract
     * @dev Cannot rescue the underlying asset (nUSD)
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
            uint256 nusdToVest = previewRedeem(amountToDistribute);

            _burn(from, amountToDistribute);

            // to address of address(0) enables burning
            if (to == address(0)) {
                _updateVestingAmount(nusdToVest);
            } else {
                _mint(to, amountToDistribute);
            }

            emit LockedAmountRedistributed(from, to, amountToDistribute);
        } else {
            revert OperationNotAllowed();
        }
    }

    /**
     * @dev See {IERC4626-withdraw}.
     * @notice Only enabled when cooldown is off
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override(ERC4626, IERC4626) whenNotPaused ensureCooldownOff returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @dev See {IERC4626-redeem}.
     * @notice Only enabled when cooldown is off
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override(ERC4626, IERC4626) whenNotPaused ensureCooldownOff returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }

    /**
     * @notice Claim the staking amount after the cooldown has finished
     * @dev unstake can be called after cooldown have been set to 0, to let accounts claim remaining assets locked at Silo
     * @param receiver Address to send the assets by the staker
     */
    function unstake(address receiver) external {
        UserCooldown storage userCooldown = cooldowns[msg.sender];
        uint256 assets = userCooldown.underlyingAmount;

        if (block.timestamp >= userCooldown.cooldownEnd || cooldownDuration == 0) {
            userCooldown.cooldownEnd = 0;
            userCooldown.underlyingAmount = 0;

            silo.withdraw(receiver, assets);
        } else {
            revert InvalidCooldown();
        }
    }

    /**
     * @notice Redeem assets and starts a cooldown to claim the converted underlying asset
     * @param assets assets to redeem
     */
    function cooldownAssets(uint256 assets) external whenNotPaused ensureCooldownOn returns (uint256 shares) {
        if (assets > maxWithdraw(msg.sender)) revert ExcessiveWithdrawAmount();

        shares = previewWithdraw(assets);

        cooldowns[msg.sender].cooldownEnd = uint104(block.timestamp) + cooldownDuration;
        cooldowns[msg.sender].underlyingAmount += uint152(assets);

        _withdraw(msg.sender, address(silo), msg.sender, assets, shares);
    }

    /**
     * @notice Redeem shares into assets and starts a cooldown to claim the converted underlying asset
     * @param shares shares to redeem
     */
    function cooldownShares(uint256 shares) external whenNotPaused ensureCooldownOn returns (uint256 assets) {
        if (shares > maxRedeem(msg.sender)) revert ExcessiveRedeemAmount();

        assets = previewRedeem(shares);

        cooldowns[msg.sender].cooldownEnd = uint104(block.timestamp) + cooldownDuration;
        cooldowns[msg.sender].underlyingAmount += uint152(assets);

        _withdraw(msg.sender, address(silo), msg.sender, assets, shares);
    }

    /**
     * @notice Set cooldown duration
     * @dev If cooldown duration is set to zero, the behavior follows ERC4626 standard and disables
     *      cooldownShares and cooldownAssets methods. If cooldown duration is greater than zero,
     *      the ERC4626 withdrawal and redeem functions are disabled, breaking the ERC4626 standard,
     *      and enabling the cooldownShares and the cooldownAssets functions.
     * @param duration Duration of the cooldown
     */
    function setCooldownDuration(uint24 duration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (duration > MAX_COOLDOWN_DURATION) {
            revert InvalidCooldown();
        }

        uint24 previousDuration = cooldownDuration;
        cooldownDuration = duration;
        emit CooldownDurationUpdated(previousDuration, cooldownDuration);
    }

    /**
     * @notice Pause all deposits, withdrawals, and cooldown operations
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause all deposits, withdrawals, and cooldown operations
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /* --------------- PUBLIC --------------- */

    /**
     * @notice Returns the amount of nUSD tokens that are vested in the contract
     * @return The total vested assets
     */
    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - getUnvestedAmount();
    }

    /**
     * @notice Returns the amount of nUSD tokens that are unvested in the contract
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
    function decimals() public pure override(ERC4626, ERC20, IERC20Metadata) returns (uint8) {
        return 18;
    }

    /// @dev Override nonces to resolve conflict between ERC20Permit and other base classes
    function nonces(address owner) public view virtual override(ERC20Permit, IERC20Permit) returns (uint256) {
        return super.nonces(owner);
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
    ) internal override nonReentrant whenNotPaused notZero(assets) notZero(shares) {
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, caller) || hasRole(FULL_RESTRICTED_STAKER_ROLE, receiver)) {
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
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant whenNotPaused notZero(assets) notZero(shares) {
        if (
            hasRole(FULL_RESTRICTED_STAKER_ROLE, caller) ||
            hasRole(FULL_RESTRICTED_STAKER_ROLE, receiver) ||
            hasRole(FULL_RESTRICTED_STAKER_ROLE, owner)
        ) {
            revert OperationNotAllowed();
        }

        super._withdraw(caller, receiver, owner, assets, shares);
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
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, from)) {
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
