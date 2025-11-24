// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { StakednUSD } from "../../contracts/staked-nusd/StakednUSD.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

/**
 * @title StakedUSDeTest
 * @notice Unit tests for StakednUSD core functionality
 */
contract StakedUSDeTest is TestHelper {
    function setUp() public override {
        super.setUp();

        // Mint nUSD for testing
        nusd.mint(alice, 100_000e18);
        nusd.mint(bob, 100_000e18);
        nusd.mint(owner, 100_000e18);

        // Test contract needs nUSD for reward distribution (has REWARDER_ROLE)
        nusd.mint(address(this), 1_000_000e18);
    }

    /**
     * @notice Test basic setup
     */
    function test_Setup() public {
        assertEq(stakedNusd.name(), "Staked nUSD");
        assertEq(stakedNusd.symbol(), "snUSD");
        assertEq(stakedNusd.decimals(), 18);
        assertEq(address(stakedNusd.asset()), address(nusd));
        assertEq(stakedNusd.cooldownDuration(), 0); // Set to 0 in TestHelper
    }

    /**
     * @notice Test basic deposit (cooldown OFF)
     */
    function test_Deposit() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), depositAmount);

        uint256 shares = stakedNusd.deposit(depositAmount, alice);

        // Initially 1:1
        assertEq(shares, depositAmount, "Should receive 1:1 shares");
        assertEq(stakedNusd.balanceOf(alice), shares, "Alice should have snUSD");
        assertEq(nusd.balanceOf(address(stakedNusd)), depositAmount, "nUSD locked");

        vm.stopPrank();
    }

    /**
     * @notice Test basic redeem (cooldown OFF)
     */
    function test_Redeem_CooldownOff() public {
        // Deposit first
        uint256 depositAmount = 1000e18;
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), depositAmount);
        uint256 shares = stakedNusd.deposit(depositAmount, alice);

        // Redeem
        uint256 aliceUsdeBefore = nusd.balanceOf(alice);
        uint256 assets = stakedNusd.redeem(shares, alice, alice);
        uint256 aliceUsdeAfter = nusd.balanceOf(alice);

        assertEq(assets, depositAmount, "Should redeem 1:1");
        assertEq(aliceUsdeAfter - aliceUsdeBefore, depositAmount, "nUSD returned");
        assertEq(stakedNusd.balanceOf(alice), 0, "snUSD burned");

        vm.stopPrank();
    }

    /**
     * @notice Test cooldown shares flow
     */
    function test_CooldownShares() public {
        // Enable cooldown
        stakedNusd.setCooldownDuration(7 days);

        // Deposit
        uint256 depositAmount = 1000e18;
        vm.startPrank(alice);
        uint256 aliceUsdeBefore = nusd.balanceOf(alice);

        nusd.approve(address(stakedNusd), depositAmount);
        uint256 shares = stakedNusd.deposit(depositAmount, alice);

        // Start cooldown
        uint256 assets = stakedNusd.cooldownShares(shares);

        // Verify cooldown
        (uint104 cooldownEnd, uint152 underlyingAmount) = stakedNusd.cooldowns(alice);
        assertEq(underlyingAmount, assets, "Assets locked");
        assertEq(cooldownEnd, block.timestamp + 7 days, "Cooldown set");
        assertEq(stakedNusd.balanceOf(alice), 0, "Shares burned");

        // Try to unstake early (should fail)
        vm.expectRevert();
        stakedNusd.unstake(alice);

        // Warp forward
        vm.warp(cooldownEnd);

        // Unstake
        stakedNusd.unstake(alice);

        assertEq(nusd.balanceOf(alice), aliceUsdeBefore, "nUSD returned");

        vm.stopPrank();
    }

    /**
     * @notice Test cooldown assets flow
     */
    function test_CooldownAssets() public {
        stakedNusd.setCooldownDuration(7 days);

        uint256 depositAmount = 1000e18;
        vm.startPrank(alice);
        uint256 aliceUsdeBefore = nusd.balanceOf(alice);

        nusd.approve(address(stakedNusd), depositAmount);
        stakedNusd.deposit(depositAmount, alice);

        // Cooldown specific amount of assets
        uint256 cooldownAssets = 500e18;
        uint256 shares = stakedNusd.cooldownAssets(cooldownAssets);

        (uint104 cooldownEnd, uint152 underlyingAmount) = stakedNusd.cooldowns(alice);
        assertEq(underlyingAmount, cooldownAssets, "Correct assets locked");

        // Warp and unstake
        vm.warp(cooldownEnd);
        stakedNusd.unstake(alice);

        // Should have returned 500 (depositAmount - cooldownAssets is still staked)
        assertEq(nusd.balanceOf(alice), aliceUsdeBefore - depositAmount + cooldownAssets, "Partial nUSD returned");

        vm.stopPrank();
    }

    /**
     * @notice Test accumulating multiple cooldowns
     */
    function test_AccumulatingCooldowns() public {
        stakedNusd.setCooldownDuration(7 days);

        uint256 depositAmount = 1000e18;
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), depositAmount);
        stakedNusd.deposit(depositAmount, alice);

        // First cooldown
        stakedNusd.cooldownShares(200e18);
        (uint104 cooldownEnd1, uint152 amount1) = stakedNusd.cooldowns(alice);

        // Second cooldown (should accumulate)
        stakedNusd.cooldownShares(300e18);
        (uint104 cooldownEnd2, uint152 amount2) = stakedNusd.cooldowns(alice);

        assertGt(amount2, amount1, "Should accumulate");
        assertEq(cooldownEnd2, block.timestamp + 7 days, "Cooldown reset");

        vm.stopPrank();
    }

    /**
     * @notice Test rewards distribution
     */
    function test_RewardsDistribution() public {
        uint256 depositAmount = 1000e18;
        uint256 rewardsAmount = 100e18;

        // Alice deposits
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), depositAmount);
        uint256 sharesBefore = stakedNusd.deposit(depositAmount, alice);
        vm.stopPrank();

        // Distribute rewards (test contract has REWARDER_ROLE)
        nusd.approve(address(stakedNusd), rewardsAmount);
        stakedNusd.transferInRewards(rewardsAmount);

        // Fast forward past vesting
        vm.warp(block.timestamp + 8 hours);

        // Bob deposits after rewards (should get fewer shares)
        vm.startPrank(bob);
        nusd.approve(address(stakedNusd), depositAmount);
        uint256 sharesAfter = stakedNusd.deposit(depositAmount, bob);
        vm.stopPrank();

        assertLt(sharesAfter, sharesBefore, "Should receive fewer shares after rewards");

        // Alice's shares should be worth more
        uint256 aliceAssets = stakedNusd.convertToAssets(sharesBefore);
        assertGt(aliceAssets, depositAmount, "Alice's shares appreciated");
    }

    /**
     * @notice Test vesting mechanism
     */
    function test_RewardsVesting() public {
        uint256 rewardsAmount = 100e18;

        // Deposit initial amount
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);
        stakedNusd.deposit(1000e18, alice);
        vm.stopPrank();

        // Distribute rewards (test contract has REWARDER_ROLE)
        nusd.approve(address(stakedNusd), rewardsAmount);
        stakedNusd.transferInRewards(rewardsAmount);

        // Check unvested amount immediately
        uint256 unvested0 = stakedNusd.getUnvestedAmount();
        assertEq(unvested0, rewardsAmount, "All rewards unvested initially");

        // Half vesting period
        vm.warp(block.timestamp + 4 hours);
        uint256 unvested1 = stakedNusd.getUnvestedAmount();
        assertApproxEqRel(unvested1, rewardsAmount / 2, 0.01e18, "Half vested");

        // Full vesting period
        vm.warp(block.timestamp + 4 hours);
        uint256 unvested2 = stakedNusd.getUnvestedAmount();
        assertEq(unvested2, 0, "Fully vested");
    }

    /**
     * @notice Test burning assets (deflationary)
     */
    function test_BurnAssets() public {
        // Deposit
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);
        stakedNusd.deposit(1000e18, alice);
        vm.stopPrank();

        uint256 contractBalance = nusd.balanceOf(address(stakedNusd));
        uint256 burnAmount = 100e18;

        // Burn (test contract has REWARDER_ROLE)
        stakedNusd.burnAssets(burnAmount);

        // nUSD and MCT should be burned
        assertEq(nusd.balanceOf(address(stakedNusd)), contractBalance - burnAmount, "nUSD burned");

        // Exchange rate should worsen (same shares, fewer assets) - deflationary event
        uint256 aliceAssets = stakedNusd.convertToAssets(stakedNusd.balanceOf(alice));
        assertLt(aliceAssets, 1000e18, "Alice's shares worth less after deflationary burn");
        assertApproxEqAbs(aliceAssets, 900e18, 1e18, "Should be ~900 nUSD (1000 - 10% burn)");
    }

    /**
     * @notice Test soft blacklist (can't stake)
     */
    function test_SoftBlacklist() public {
        // Blacklist alice
        stakedNusd.addToBlacklist(alice, false); // soft = false

        // Alice can't deposit
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);

        vm.expectRevert();
        stakedNusd.deposit(1000e18, alice);

        vm.stopPrank();
    }

    /**
     * @notice Test full blacklist (can't transfer)
     */
    function test_FullBlacklist() public {
        // Alice deposits first
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);
        stakedNusd.deposit(1000e18, alice);
        vm.stopPrank();

        // Blacklist alice fully
        stakedNusd.addToBlacklist(alice, true); // full = true

        // Alice can't transfer
        vm.startPrank(alice);

        vm.expectRevert();
        stakedNusd.transfer(bob, 100e18);

        vm.stopPrank();

        // Alice can't redeem either
        vm.startPrank(alice);

        vm.expectRevert();
        stakedNusd.redeem(100e18, alice, alice);

        vm.stopPrank();
    }

    /**
     * @notice Test removing from blacklist
     */
    function test_RemoveFromBlacklist() public {
        // Blacklist and remove
        stakedNusd.addToBlacklist(alice, false);
        stakedNusd.removeFromBlacklist(alice, false);

        // Alice can deposit now
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);
        stakedNusd.deposit(1000e18, alice);
        vm.stopPrank();

        assertEq(stakedNusd.balanceOf(alice), 1000e18, "Deposit successful");
    }

    /**
     * @notice Test redistributing locked amount
     */
    function test_RedistributeLockedAmount() public {
        // Alice deposits
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);
        stakedNusd.deposit(1000e18, alice);
        vm.stopPrank();

        // Blacklist alice fully
        stakedNusd.addToBlacklist(alice, true);

        uint256 aliceShares = stakedNusd.balanceOf(alice);

        // Redistribute to bob
        stakedNusd.redistributeLockedAmount(alice, bob);

        assertEq(stakedNusd.balanceOf(alice), 0, "Alice shares burned");
        assertEq(stakedNusd.balanceOf(bob), aliceShares, "Bob received shares");
    }

    /**
     * @notice Test redistributing to burn (address(0))
     */
    function test_RedistributeAndBurn() public {
        // Alice deposits
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);
        stakedNusd.deposit(1000e18, alice);
        vm.stopPrank();

        // Blacklist alice
        stakedNusd.addToBlacklist(alice, true);

        // Redistribute to burn
        stakedNusd.redistributeLockedAmount(alice, address(0));

        assertEq(stakedNusd.balanceOf(alice), 0, "Alice shares burned");
    }

    /**
     * @notice Test pause functionality
     */
    function test_Pause() public {
        stakedNusd.pause();

        // Can't deposit when paused
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);

        vm.expectRevert();
        stakedNusd.deposit(1000e18, alice);

        vm.stopPrank();

        // Unpause
        stakedNusd.unpause();

        // Should work now
        vm.startPrank(alice);
        stakedNusd.deposit(1000e18, alice);
        assertEq(stakedNusd.balanceOf(alice), 1000e18, "Deposit after unpause");
        vm.stopPrank();
    }

    /**
     * @notice Test MIN_SHARES protection
     */
    function test_MinSharesProtection() public {
        // Try to create dust position (should fail)
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1e18);

        // First deposit sets the bar
        stakedNusd.deposit(1e18, alice);

        // Now redeem most of it to get below MIN_SHARES
        vm.expectRevert();
        stakedNusd.redeem(0.5e18, alice, alice);

        vm.stopPrank();
    }

    /**
     * @notice Test rescue tokens (not asset)
     */
    function test_RescueTokens() public {
        MockERC20 otherToken = new MockERC20("Other", "OTH", 18);
        otherToken.mint(address(stakedNusd), 1000e18);

        stakedNusd.rescueTokens(address(otherToken), 1000e18, owner);

        assertEq(otherToken.balanceOf(owner), 1000e18, "Tokens rescued");
    }

    /**
     * @notice Test can't rescue asset token
     */
    function test_RevertIf_RescueAsset() public {
        vm.expectRevert();
        stakedNusd.rescueTokens(address(nusd), 1000e18, owner);
    }

    /**
     * @notice Test cooldown duration toggle
     */
    function test_CooldownDurationToggle() public {
        // Start with cooldown off (0)
        assertEq(stakedNusd.cooldownDuration(), 0);

        // Can use standard redeem
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);
        stakedNusd.deposit(1000e18, alice);
        stakedNusd.redeem(500e18, alice, alice);
        vm.stopPrank();

        // Turn on cooldown
        stakedNusd.setCooldownDuration(7 days);

        // Now standard redeem should fail
        vm.startPrank(alice);
        vm.expectRevert();
        stakedNusd.redeem(500e18, alice, alice);

        // But cooldown should work
        stakedNusd.cooldownShares(500e18);
        vm.stopPrank();
    }

    /**
     * @notice Test setting cooldown above max fails
     */
    function test_RevertIf_CooldownTooLong() public {
        vm.expectRevert();
        stakedNusd.setCooldownDuration(91 days); // Max is 90
    }

    /**
     * @notice Test can't transfer from rewards during vesting
     */
    function test_RevertIf_StillVesting() public {
        // Distribute rewards (test contract has REWARDER_ROLE)
        nusd.approve(address(stakedNusd), 200e18);
        stakedNusd.transferInRewards(100e18);

        // Try to distribute again immediately (should fail)
        vm.expectRevert();
        stakedNusd.transferInRewards(100e18);
    }

    /**
     * @notice Test deposit zero amount fails
     */
    function test_RevertIf_DepositZero() public {
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);

        vm.expectRevert();
        stakedNusd.deposit(0, alice);

        vm.stopPrank();
    }

    /**
     * @notice Test redeem zero amount fails
     */
    function test_RevertIf_RedeemZero() public {
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);
        stakedNusd.deposit(1000e18, alice);

        vm.expectRevert();
        stakedNusd.redeem(0, alice, alice);

        vm.stopPrank();
    }

    /**
     * @notice Fuzz test deposit amounts
     */
    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1e18, 100_000e18);

        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), amount);

        uint256 shares = stakedNusd.deposit(amount, alice);

        assertEq(shares, amount, "Should receive 1:1 initially");

        vm.stopPrank();
    }

    /**
     * @notice Fuzz test deposit and redeem round trip
     */
    function testFuzz_DepositRedeemRoundTrip(uint256 amount) public {
        amount = bound(amount, 1e18, 100_000e18);

        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), amount);

        uint256 shares = stakedNusd.deposit(amount, alice);
        uint256 assets = stakedNusd.redeem(shares, alice, alice);

        assertEq(assets, amount, "Should get same amount back");

        vm.stopPrank();
    }

    /**
     * @notice Test exchange rate after rewards
     */
    function test_ExchangeRate() public {
        // Deposit
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 1000e18);
        uint256 shares = stakedNusd.deposit(1000e18, alice);
        vm.stopPrank();

        // Add rewards (test contract has REWARDER_ROLE)
        nusd.approve(address(stakedNusd), 100e18);
        stakedNusd.transferInRewards(100e18);

        // Warp past vesting
        vm.warp(block.timestamp + 8 hours);

        // Check exchange rate improved
        uint256 assetsPerShare = stakedNusd.convertToAssets(1e18);
        assertGt(assetsPerShare, 1e18, "Exchange rate improved");

        // Alice can redeem for more than deposited
        vm.startPrank(alice);
        uint256 assets = stakedNusd.redeem(shares, alice, alice);
        assertGt(assets, 1000e18, "Redeemed more than deposited");
        vm.stopPrank();
    }
}
