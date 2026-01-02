// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { NaraUSDPlus } from "../../contracts/narausd-plus/NaraUSDPlus.sol";
import { INaraUSDPlus } from "../../contracts/interfaces/narausd-plus/INaraUSDPlus.sol";
import { MultiCollateralToken } from "../../contracts/mct/MultiCollateralToken.sol";
import { IMultiCollateralToken } from "../../contracts/interfaces/mct/IMultiCollateralToken.sol";
import { StakingRewardsDistributor } from "../../contracts/narausd-plus/StakingRewardsDistributor.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AuditFixesTest
 * @notice Tests for audit fixes
 */
contract AuditFixesTest is TestHelper {
    StakingRewardsDistributor public stakingRewardsDistributor;

    function setUp() public override {
        super.setUp();

        // Fund test accounts
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);

        // Deploy StakingRewardsDistributor
        StakingRewardsDistributor impl = new StakingRewardsDistributor();
        bytes memory initData = abi.encodeWithSelector(
            StakingRewardsDistributor.initialize.selector,
            naraUsdPlus,
            naraUsd,
            delegate, // admin
            delegate // operator
        );
        stakingRewardsDistributor = StakingRewardsDistributor(
            payable(address(new ERC1967Proxy(address(impl), initData)))
        );

        // Grant REWARDER_ROLE to stakingRewardsDistributor
        naraUsdPlus.grantRole(naraUsdPlus.REWARDER_ROLE(), address(stakingRewardsDistributor));

        // Ensure cooldown is enabled (should be 7 days by default, but verify)
        if (naraUsdPlus.cooldownDuration() == 0) {
            naraUsdPlus.setCooldownDuration(7 days);
        }
    }

    function test_InitializeSetsOperator() public {
        // stakingRewardsDistributor is deployed in TestHelper
        // Verify operator was set correctly during initialization
        assertEq(stakingRewardsDistributor.operator(), delegate, "Operator should be set to delegate");
    }

    function test_RevertIf_DuplicateAsset() public {
        // USDC is already added in setup
        vm.expectRevert(MultiCollateralToken.AssetAlreadySupported.selector);
        mct.addSupportedAsset(address(usdc));
    }

    function test_RevertIf_BlacklistedUnstake() public {
        // Ensure cooldown is enabled
        assertGt(naraUsdPlus.cooldownDuration(), 0, "Cooldown should be enabled");

        // Setup: Alice stakes using existing NaraUSD.t.sol pattern
        uint256 depositAmount = 100e18;
        _mintNaraUsdAndStake(alice, depositAmount);

        // Alice starts cooldown
        vm.prank(alice);
        naraUsdPlus.cooldownShares(50e18);

        // Warp past cooldown
        vm.warp(block.timestamp + 8 days);

        // Blacklist Alice
        naraUsdPlus.addToBlacklist(alice);

        // Alice tries to unstake - should fail
        vm.prank(alice);
        vm.expectRevert(INaraUSDPlus.OperationNotAllowed.selector);
        naraUsdPlus.unstake(bob); // Even to non-blacklisted receiver
    }

    function test_RedistributeIncludesSiloShares() public {
        // Ensure cooldown is enabled
        assertGt(naraUsdPlus.cooldownDuration(), 0, "Cooldown should be enabled");

        // Setup: Alice stakes
        uint256 depositAmount = 100e18;
        _mintNaraUsdAndStake(alice, depositAmount);

        // Alice starts cooldown (locks shares in silo)
        vm.prank(alice);
        naraUsdPlus.cooldownShares(50e18);

        // Verify Alice has shares in silo
        (uint104 cooldownEnd, uint152 sharesAmount) = naraUsdPlus.cooldowns(alice);
        assertGt(sharesAmount, 0, "Alice should have shares in cooldown");

        uint256 aliceDirectBalance = naraUsdPlus.balanceOf(alice);
        uint256 totalToRedistribute = aliceDirectBalance + sharesAmount;

        // Blacklist Alice
        naraUsdPlus.addToBlacklist(alice);

        // Redistribute - should handle both direct balance AND silo shares
        naraUsdPlus.redistributeLockedAmount(alice, bob);

        // Verify all shares transferred to Bob
        assertEq(naraUsdPlus.balanceOf(bob), totalToRedistribute, "Bob should receive all shares");
        assertEq(naraUsdPlus.balanceOf(alice), 0, "Alice should have 0 balance");

        // Verify cooldown cleared
        (cooldownEnd, sharesAmount) = naraUsdPlus.cooldowns(alice);
        assertEq(sharesAmount, 0, "Alice cooldown shares should be cleared");
    }

    function test_MaxRedeemWithMultipleStakers() public {
        uint256 MIN_SHARES = naraUsdPlus.minShares();

        // Setup: Alice stakes exactly 2 * MIN_SHARES
        _mintNaraUsdAndStake(alice, 2 * MIN_SHARES);

        // Also have Bob stake MIN_SHARES so Alice isn't only staker
        _mintNaraUsdAndStake(bob, MIN_SHARES);

        // Now totalSupply = 3 * MIN_SHARES, Alice has 2 * MIN_SHARES
        // maxRedeem for Alice should be 2 * MIN_SHARES (she can redeem all hers,
        // leaving Bob's MIN_SHARES which satisfies invariant)
        uint256 maxRedeemable = naraUsdPlus.maxRedeem(alice);
        assertEq(maxRedeemable, 2 * MIN_SHARES, "Alice should be able to redeem all her shares");
    }

    function test_MaxWithdrawSingleStaker() public {
        uint256 MIN_SHARES = naraUsdPlus.minShares();

        // Setup: Alice stakes exactly 2 * MIN_SHARES (only staker)
        _mintNaraUsdAndStake(alice, 2 * MIN_SHARES);

        // As only staker, Alice can redeem all (leaving totalSupply = 0 which is valid)
        uint256 maxRedeemable = naraUsdPlus.maxRedeem(alice);
        assertEq(maxRedeemable, 2 * MIN_SHARES, "Single staker should be able to redeem all");

        uint256 maxWithdrawable = naraUsdPlus.maxWithdraw(alice);
        uint256 expectedMax = naraUsdPlus.convertToAssets(2 * MIN_SHARES);
        assertEq(maxWithdrawable, expectedMax, "maxWithdraw should match full amount for single staker");
    }

    function test_RedeemAllShares() public {
        uint256 MIN_SHARES = naraUsdPlus.minShares();

        // Setup: Alice is only staker with MIN_SHARES
        _mintNaraUsdAndStake(alice, MIN_SHARES);

        // Alice should be able to redeem all (leaving totalSupply = 0)
        uint256 maxRedeemable = naraUsdPlus.maxRedeem(alice);
        assertEq(maxRedeemable, MIN_SHARES, "Should be able to redeem all when only staker");
    }

    function test_RevertIf_BurnCausesUnderflow() public {
        // Setup: Stake some NaraUSD
        _mintNaraUsdAndStake(alice, 100e18);

        // Transfer rewards (creates unvested amount)
        uint256 rewardAmount = 10e18;
        _mintNaraUsd(address(stakingRewardsDistributor), rewardAmount);
        vm.prank(delegate);
        stakingRewardsDistributor.transferInRewards(rewardAmount);

        // Get unvested amount
        uint256 unvested = naraUsdPlus.getUnvestedAmount();
        assertGt(unvested, 0, "Should have unvested amount");

        // Try to burn more than (balance - unvested) - should fail
        uint256 contractBalance = IERC20(address(naraUsd)).balanceOf(address(naraUsdPlus));
        uint256 burnAmount = contractBalance - unvested + 1; // Would cause underflow

        vm.prank(delegate);
        vm.expectRevert(INaraUSDPlus.InvalidAmount.selector);
        stakingRewardsDistributor.burnAssets(burnAmount);
    }

    function test_RevertIf_CancelCooldownWhenPaused() public {
        // Ensure cooldown is enabled
        assertGt(naraUsdPlus.cooldownDuration(), 0, "Cooldown should be enabled");

        // Setup: Alice stakes and starts cooldown
        uint256 depositAmount = 100e18;
        _mintNaraUsdAndStake(alice, depositAmount);

        vm.prank(alice);
        naraUsdPlus.cooldownShares(50e18);

        // Pause the contract using GATEKEEPER_ROLE
        vm.prank(delegate);
        naraUsdPlus.pause();

        // Try to cancel cooldown - should fail
        vm.prank(alice);
        vm.expectRevert(); // Pausable: paused
        naraUsdPlus.cancelCooldown();
    }

    function test_GatekeeperCanPause() public {
        bytes32 GATEKEEPER_ROLE = naraUsdPlus.GATEKEEPER_ROLE();

        // Verify delegate has GATEKEEPER_ROLE (granted in initialize)
        assertTrue(naraUsdPlus.hasRole(GATEKEEPER_ROLE, delegate), "Delegate should have GATEKEEPER_ROLE");

        // Non-gatekeeper cannot pause
        vm.prank(alice);
        vm.expectRevert();
        naraUsdPlus.pause();

        // Gatekeeper can pause
        vm.prank(delegate);
        naraUsdPlus.pause();
        assertTrue(naraUsdPlus.paused(), "Should be paused");

        // Gatekeeper can unpause
        vm.prank(delegate);
        naraUsdPlus.unpause();
        assertFalse(naraUsdPlus.paused(), "Should be unpaused");
    }

    function test_RevertIf_BlacklistZeroAddress() public {
        vm.expectRevert(INaraUSDPlus.InvalidZeroAddress.selector);
        naraUsdPlus.addToBlacklist(address(0));
    }

    function test_RevertIf_RescueZeroAddress() public {
        vm.expectRevert(INaraUSDPlus.InvalidZeroAddress.selector);
        naraUsdPlus.rescueTokens(address(0), 100, alice);

        vm.expectRevert(INaraUSDPlus.InvalidZeroAddress.selector);
        naraUsdPlus.rescueTokens(address(usdc), 100, address(0));
    }

    function test_RevertIf_SetSameCooldown() public {
        uint24 currentDuration = naraUsdPlus.cooldownDuration();

        vm.expectRevert(INaraUSDPlus.InvalidAmount.selector);
        naraUsdPlus.setCooldownDuration(currentDuration);
    }

    function test_RevertIf_SetSameVestingPeriod() public {
        uint256 currentPeriod = naraUsdPlus.vestingPeriod();

        vm.expectRevert(INaraUSDPlus.InvalidAmount.selector);
        naraUsdPlus.setVestingPeriod(currentPeriod);
    }

    function _mintNaraUsdAndStake(address user, uint256 amount) internal {
        // Mint USDC to this test contract (which has MINTER_ROLE)
        uint256 usdcAmount = amount / 1e12; // Convert 18 decimals to 6
        usdc.mint(address(this), usdcAmount);

        // Approve and mint NaraUSD as this contract (has MINTER_ROLE)
        usdc.approve(address(naraUsd), usdcAmount);
        naraUsd.mintWithCollateral(address(usdc), usdcAmount);

        // Transfer NaraUSD to user
        naraUsd.transfer(user, amount);

        // User stakes
        vm.startPrank(user);
        naraUsd.approve(address(naraUsdPlus), amount);
        naraUsdPlus.deposit(amount, user);
        vm.stopPrank();
    }

    function _mintNaraUsd(address to, uint256 amount) internal {
        // Mint USDC to this test contract
        uint256 usdcAmount = amount / 1e12; // Convert 18 decimals to 6
        usdc.mint(address(this), usdcAmount);

        // Approve and mint NaraUSD
        usdc.approve(address(naraUsd), usdcAmount);
        naraUsd.mintWithCollateral(address(usdc), usdcAmount);

        // Transfer to recipient
        naraUsd.transfer(to, amount);
    }
}
