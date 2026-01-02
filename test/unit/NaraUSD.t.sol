// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { NaraUSD } from "../../contracts/narausd/NaraUSD.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockKeyring } from "../mocks/MockKeyring.sol";

/**
 * @title naraUsdTest
 * @notice Unit tests for naraUsd core functionality
 */
contract NaraUSDTest is TestHelper {
    function setUp() public override {
        super.setUp();

        // Fund test accounts
        usdc.mint(alice, 100_000e6);
        usdt.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
    }

    /**
     * @notice Test basic setup
     */
    function test_Setup() public view {
        assertEq(naraUsd.name(), "Nara USD");
        assertEq(naraUsd.symbol(), "NaraUSD");
        assertEq(naraUsd.decimals(), 18);
        assertEq(address(naraUsd.mct()), address(mct));
    }

    /**
     * @notice Test minting naraUsd with USDC
     */
    function test_MintWithCollateral_USDC() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedNaraUsd = 1000e18;

        vm.startPrank(alice);
        usdc.approve(address(naraUsd), usdcAmount);

        uint256 aliceNaraUsdBefore = naraUsd.balanceOf(alice);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 naraUsdContractMctBefore = mct.balanceOf(address(naraUsd));

        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), usdcAmount);
        uint256 aliceUsdcAfter = usdc.balanceOf(alice);

        // Verify naraUsd minted
        assertEq(naraUsdAmount, expectedNaraUsd, "Should mint 1000 naraUsd");
        assertEq(
            naraUsd.balanceOf(alice) - aliceNaraUsdBefore,
            expectedNaraUsd,
            "Alice should have additional naraUsd"
        );

        // Verify USDC transferred
        assertEq(aliceUsdcBefore - aliceUsdcAfter, usdcAmount, "USDC transferred");

        // Verify MCT created (held by naraUsd contract)
        assertEq(
            mct.balanceOf(address(naraUsd)) - naraUsdContractMctBefore,
            expectedNaraUsd,
            "naraUsd holds additional MCT"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test minting naraUsd with USDT
     */
    function test_MintWithCollateral_USDT() public {
        uint256 usdtAmount = 500e6;
        uint256 expectedNaraUsd = 500e18;

        vm.startPrank(alice);
        usdt.approve(address(naraUsd), usdtAmount);

        uint256 aliceNaraUsdBefore = naraUsd.balanceOf(alice);
        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdt), usdtAmount);

        assertEq(naraUsdAmount, expectedNaraUsd, "Should mint 500 naraUsd");
        assertEq(
            naraUsd.balanceOf(alice) - aliceNaraUsdBefore,
            expectedNaraUsd,
            "Alice should have additional naraUsd"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test instant redemption when liquidity is available
     */
    function test_InstantRedemption() public {
        // Setup: Mint naraUsd
        uint256 naraUsdAmount = 1000e18;
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);

        // Redeem instantly (MCT has liquidity)
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 aliceNaraUsdBefore = naraUsd.balanceOf(alice);

        (uint256 collateralAmount, bool wasQueued) = naraUsd.redeem(address(usdc), naraUsdAmount, false);

        // Verify instant redemption
        assertEq(wasQueued, false, "Should be instant redemption");
        assertEq(collateralAmount, 1000e6, "Should receive correct USDC amount");
        assertEq(usdc.balanceOf(alice) - aliceUsdcBefore, 1000e6, "Should receive USDC instantly");
        assertEq(naraUsd.balanceOf(alice), aliceNaraUsdBefore - naraUsdAmount, "naraUsd burned");

        // Verify no redemption request exists
        (uint152 amount, ) = naraUsd.redemptionRequests(alice);
        assertEq(amount, 0, "No redemption request");

        vm.stopPrank();
    }

    /**
     * @notice Test queued redemption when liquidity is insufficient
     */
    function test_QueuedRedemption_Complete() public {
        // Setup: Mint naraUsd
        uint256 naraUsdAmount = 1000e18;
        vm.startPrank(alice);
        uint256 aliceNaraUsdBefore = naraUsd.balanceOf(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);

        // Withdraw all USDC from MCT to simulate insufficient liquidity
        vm.stopPrank();
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // Step 1: Request redemption (will be queued due to no liquidity)
        vm.startPrank(alice);
        (uint256 collateralAmount, bool wasQueued) = naraUsd.redeem(address(usdc), naraUsdAmount, true);

        // Verify it was queued
        assertEq(wasQueued, true, "Should be queued");
        assertEq(collateralAmount, 0, "Collateral amount should be 0 when queued");

        // Verify redemption request
        (uint152 lockedAmount, address collateral) = naraUsd.redemptionRequests(alice);
        assertEq(lockedAmount, naraUsdAmount, "Amount should be locked");
        assertEq(collateral, address(usdc), "Collateral should be USDC");

        // Verify naraUsd is in silo
        assertEq(naraUsd.balanceOf(alice), aliceNaraUsdBefore, "Alice naraUsd should be in silo");
        assertEq(naraUsd.balanceOf(address(naraUsd.redeemSilo())), naraUsdAmount, "naraUsd in silo");

        // Step 2: Restore liquidity
        vm.stopPrank();
        usdc.approve(address(mct), 1000e6);
        mct.depositCollateral(address(usdc), 1000e6);

        // Step 3: Complete redemption (admin only)
        vm.startPrank(owner);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 collateralReceived = naraUsd.completeRedeem(alice);
        uint256 aliceUsdcAfter = usdc.balanceOf(alice);

        // Verify redemption completed
        assertEq(collateralReceived, 1000e6, "Should receive 1000 USDC");
        assertEq(aliceUsdcAfter - aliceUsdcBefore, 1000e6, "USDC received");
        assertEq(naraUsd.balanceOf(alice), aliceNaraUsdBefore, "naraUsd burned, balance back to initial");

        // Verify request cleared
        (uint152 amountAfter, ) = naraUsd.redemptionRequests(alice);
        assertEq(amountAfter, 0, "Amount cleared");

        vm.stopPrank();
    }

    /**
     * @notice Test redemption reverts when no liquidity and allowQueue is false
     */
    function test_RedemptionRevertsWithoutLiquidity() public {
        // Setup: Mint naraUsd
        uint256 naraUsdAmount = 1000e18;
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);

        // Withdraw all USDC from MCT
        vm.stopPrank();
        // Use test contract which has COLLATERAL_MANAGER_ROLE
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // Try instant redemption (should revert due to no liquidity)
        vm.startPrank(alice);
        vm.expectRevert(NaraUSD.InsufficientCollateral.selector);
        naraUsd.redeem(address(usdc), naraUsdAmount, false);

        vm.stopPrank();
    }

    /**
     * @notice Test cancelling queued redemption request
     */
    function test_CancelRedemption() public {
        // Setup: Mint and queue redemption
        uint256 naraUsdAmount = 1000e18;
        vm.startPrank(alice);
        uint256 aliceBalanceBefore = naraUsd.balanceOf(alice);

        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);

        // Withdraw liquidity to force queueing
        vm.stopPrank();
        // Use test contract which has COLLATERAL_MANAGER_ROLE
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // Queue redemption
        vm.startPrank(alice);
        (uint256 collateralAmount, bool wasQueued) = naraUsd.redeem(address(usdc), naraUsdAmount, true);
        assertEq(wasQueued, true, "Should be queued");
        assertEq(collateralAmount, 0, "Collateral amount should be 0 when queued");

        uint256 aliceBalanceAfterRedeem = naraUsd.balanceOf(alice);
        assertEq(aliceBalanceAfterRedeem, aliceBalanceBefore, "naraUsd locked in silo");

        // Cancel redemption
        naraUsd.cancelRedeem();

        // Verify naraUsd returned
        assertEq(naraUsd.balanceOf(alice), aliceBalanceBefore + naraUsdAmount, "naraUsd returned");
        assertEq(naraUsd.balanceOf(address(naraUsd.redeemSilo())), 0, "Silo empty");

        // Verify request cleared
        (uint152 amount, ) = naraUsd.redemptionRequests(alice);
        assertEq(amount, 0, "Amount cleared");

        vm.stopPrank();
    }

    /**
     * @notice Test multiple queued redemption requests fail
     */
    function test_RevertIf_ExistingRedemptionRequest() public {
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 2000e6);
        naraUsd.mintWithCollateral(address(usdc), 2000e6);

        // Withdraw liquidity to force queueing
        vm.stopPrank();
        // Use test contract which has COLLATERAL_MANAGER_ROLE
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // First queued request
        vm.startPrank(alice);
        naraUsd.redeem(address(usdc), 1000e18, true);

        // Second request should fail
        vm.expectRevert(NaraUSD.ExistingRedemptionRequest.selector);
        naraUsd.redeem(address(usdc), 500e18, true);

        vm.stopPrank();
    }

    /**
     * @notice Test completing redemption without request fails
     */
    function test_RevertIf_NoRedemptionRequest() public {
        // Use test contract which has COLLATERAL_MANAGER_ROLE
        vm.expectRevert(NaraUSD.NoRedemptionRequest.selector);
        naraUsd.completeRedeem(alice);
    }

    /**
     * @notice Test cancelling without request fails
     */
    function test_RevertIf_CancelWithoutRequest() public {
        vm.startPrank(alice);

        vm.expectRevert(NaraUSD.NoRedemptionRequest.selector);
        naraUsd.cancelRedeem();

        vm.stopPrank();
    }

    /**
     * @notice Test cancelling redemption while paused fails
     */
    function test_RevertIf_CancelRedemptionWhilePaused() public {
        // Setup: Mint and queue redemption
        uint256 naraUsdAmount = 1000e18;
        vm.startPrank(alice);

        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);

        // Withdraw liquidity to force queueing
        vm.stopPrank();
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // Queue redemption
        vm.startPrank(alice);
        (uint256 collateralAmount, bool wasQueued) = naraUsd.redeem(address(usdc), naraUsdAmount, true);
        assertEq(wasQueued, true, "Should be queued");
        vm.stopPrank();

        // Pause the contract
        naraUsd.pause();

        // Try to cancel redemption - should fail
        vm.startPrank(alice);
        vm.expectRevert();
        naraUsd.cancelRedeem();
        vm.stopPrank();

        // Unpause and verify cancel works
        naraUsd.unpause();
        vm.startPrank(alice);
        naraUsd.cancelRedeem();
        assertEq(naraUsd.balanceOf(address(naraUsd.redeemSilo())), 0, "Silo should be empty after cancel");
        vm.stopPrank();
    }

    /**
     * @notice Test bulk complete redeem by collateral manager
     */
    function test_BulkCompleteRedeem() public {
        // Setup: Multiple users queue redemptions
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;

        // Mint for both users
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(naraUsd), 500e6);
        naraUsd.mintWithCollateral(address(usdc), 500e6);
        vm.stopPrank();

        // Withdraw liquidity to force queueing
        // Use test contract which has COLLATERAL_MANAGER_ROLE
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // Queue redemptions
        vm.startPrank(alice);
        naraUsd.redeem(address(usdc), 1000e18, true);
        vm.stopPrank();

        vm.startPrank(bob);
        naraUsd.redeem(address(usdc), 500e18, true);
        vm.stopPrank();

        // Restore liquidity
        // Use test contract which has COLLATERAL_MANAGER_ROLE
        usdc.approve(address(mct), 1500e6);
        mct.depositCollateral(address(usdc), 1500e6);

        // Bulk complete as collateral manager
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        naraUsd.bulkCompleteRedeem(users);

        // Verify both received collateral
        assertEq(usdc.balanceOf(alice) - aliceUsdcBefore, 1000e6, "Alice should receive USDC");
        assertEq(usdc.balanceOf(bob) - bobUsdcBefore, 500e6, "Bob should receive USDC");

        // Verify requests cleared
        (uint152 aliceAmount, ) = naraUsd.redemptionRequests(alice);
        (uint152 bobAmount, ) = naraUsd.redemptionRequests(bob);
        assertEq(aliceAmount, 0, "Alice request cleared");
        assertEq(bobAmount, 0, "Bob request cleared");

        vm.stopPrank();
    }

    /* --------------- UPDATE REDEMPTION REQUEST TESTS --------------- */

    /**
     * @notice Test updating redemption request when still no liquidity (decrease amount)
     */
    function test_UpdateRedemptionRequest_DecreaseAmount() public {
        // Setup: Mint and queue redemption
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Drain liquidity to force queueing
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // Queue redemption for 1000e18
        vm.startPrank(alice);
        naraUsd.redeem(address(usdc), 1000e18, true);

        // Update to 500e18 (decrease) - should return 500e18 to alice
        uint256 aliceBalanceBefore = naraUsd.balanceOf(alice);
        naraUsd.updateRedemptionRequest(500e18);
        uint256 aliceBalanceAfter = naraUsd.balanceOf(alice);

        // Verify alice received the excess back
        assertEq(aliceBalanceAfter - aliceBalanceBefore, 500e18, "Should receive excess NaraUSD back");

        // Verify updated request
        (uint152 amount, ) = naraUsd.redemptionRequests(alice);
        assertEq(amount, 500e18, "Request should be updated to 500e18");

        vm.stopPrank();
    }

    /**
     * @notice Test updating redemption request when still no liquidity (increase amount)
     */
    function test_UpdateRedemptionRequest_IncreaseAmount() public {
        // Setup: Mint and queue redemption
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 2000e6);
        naraUsd.mintWithCollateral(address(usdc), 2000e6);
        vm.stopPrank();

        // Drain liquidity
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // Queue redemption for 1000e18
        vm.startPrank(alice);
        naraUsd.redeem(address(usdc), 1000e18, true);

        // Update to 1500e18 (increase) - should transfer 500e18 more to silo
        uint256 aliceBalanceBefore = naraUsd.balanceOf(alice);
        naraUsd.updateRedemptionRequest(1500e18);
        uint256 aliceBalanceAfter = naraUsd.balanceOf(alice);

        // Verify alice sent more to silo
        assertEq(aliceBalanceBefore - aliceBalanceAfter, 500e18, "Should send additional NaraUSD to silo");

        // Verify updated request
        (uint152 amount, ) = naraUsd.redemptionRequests(alice);
        assertEq(amount, 1500e18, "Request should be updated to 1500e18");

        vm.stopPrank();
    }

    /**
     * @notice Test blacklisted user cannot update redemption request
     * @dev This tests the fix for Issue #07
     */
    function test_RevertIf_UpdateRedemptionRequest_Blacklisted() public {
        // Setup: Mint and queue redemption
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Drain liquidity
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // Queue redemption
        vm.startPrank(alice);
        naraUsd.redeem(address(usdc), 1000e18, true);
        vm.stopPrank();

        // Blacklist alice after queuing
        naraUsd.addToBlacklist(alice);

        // Try to update redemption request (decrease) - should fail
        vm.startPrank(alice);
        vm.expectRevert(NaraUSD.OperationNotAllowed.selector);
        naraUsd.updateRedemptionRequest(500e18);
        vm.stopPrank();
    }

    /**
     * @notice Test user without Keyring credentials cannot update redemption request
     * @dev This tests the fix for Issue #07
     */
    function test_RevertIf_UpdateRedemptionRequest_NoKeyringCredential() public {
        // Setup keyring
        MockKeyring keyring = new MockKeyring();
        naraUsd.setKeyringConfig(address(keyring), 1);

        // Alice has valid credentials initially
        keyring.setCredential(1, alice, true);

        // Mint and queue redemption
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Drain liquidity
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // Queue redemption
        vm.startPrank(alice);
        naraUsd.redeem(address(usdc), 1000e18, true);
        vm.stopPrank();

        // Revoke alice's credentials
        keyring.setCredential(1, alice, false);

        // Try to update redemption request - should fail
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NaraUSD.KeyringCredentialInvalid.selector, alice));
        naraUsd.updateRedemptionRequest(500e18);
        vm.stopPrank();
    }

    /**
     * @notice Test updating to instant redemption when liquidity becomes available
     */
    function test_UpdateRedemptionRequest_BecomesInstant() public {
        // Setup: Mint and queue redemption
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);

        uint256 aliceBalanceAfterMint = naraUsd.balanceOf(alice);
        vm.stopPrank();

        // Drain liquidity
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // Queue redemption
        vm.startPrank(alice);
        naraUsd.redeem(address(usdc), 1000e18, true);
        vm.stopPrank();

        // Restore liquidity
        usdc.approve(address(mct), 1000e6);
        mct.depositCollateral(address(usdc), 1000e6);

        // Update request - should execute instantly now
        vm.startPrank(alice);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        naraUsd.updateRedemptionRequest(1000e18);
        uint256 aliceUsdcAfter = usdc.balanceOf(alice);

        // Verify instant redemption happened
        assertEq(aliceUsdcAfter - aliceUsdcBefore, 1000e6, "Should receive USDC");
        assertEq(naraUsd.balanceOf(alice), aliceBalanceAfterMint - 1000e18, "1000e18 NaraUSD should be burned");

        // Verify request cleared
        (uint152 amount, ) = naraUsd.redemptionRequests(alice);
        assertEq(amount, 0, "Request should be cleared");

        vm.stopPrank();
    }

    /**
     * @notice Test updating to instant redemption with different amount
     */
    function test_UpdateRedemptionRequest_BecomesInstantWithChange() public {
        // Setup: Mint and queue redemption
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 2000e6);
        naraUsd.mintWithCollateral(address(usdc), 2000e6);

        uint256 aliceBalanceAfterMint = naraUsd.balanceOf(alice);
        vm.stopPrank();

        // Drain liquidity
        mct.withdrawCollateral(address(usdc), mct.collateralBalance(address(usdc)), address(this));

        // Queue redemption for 1000e18
        vm.startPrank(alice);
        naraUsd.redeem(address(usdc), 1000e18, true);
        vm.stopPrank();

        // Restore liquidity
        usdc.approve(address(mct), 2000e6);
        mct.depositCollateral(address(usdc), 2000e6);

        // Update to 500e18 (decrease) and execute instantly
        vm.startPrank(alice);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        naraUsd.updateRedemptionRequest(500e18);
        uint256 aliceUsdcAfter = usdc.balanceOf(alice);

        // Verify: 500e18 redeemed for USDC, 500e18 excess returned to wallet
        assertEq(aliceUsdcAfter - aliceUsdcBefore, 500e6, "Should receive 500 USDC");
        assertEq(
            naraUsd.balanceOf(alice),
            aliceBalanceAfterMint - 500e18,
            "Should have 500e18 less (500 excess returned, 500 redeemed, 1000 initially queued)"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test rate limiting on minting
     */
    function test_RateLimiting_Mint() public {
        // Set low rate limit for testing
        naraUsd.setMaxMintPerBlock(1000e18);

        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 2000e6);

        // First mint should succeed
        naraUsd.mintWithCollateral(address(usdc), 500e6); // 500 naraUsd

        // Second mint in same block should succeed (total 1000)
        naraUsd.mintWithCollateral(address(usdc), 500e6); // 500 naraUsd

        // Third mint should fail (total would be 1500, exceeds 1000 limit)
        vm.expectRevert(NaraUSD.MaxMintPerBlockExceeded.selector);
        naraUsd.mintWithCollateral(address(usdc), 500e6);

        vm.stopPrank();

        // Roll to next block - should work again
        vm.roll(block.number + 1);

        vm.startPrank(alice);
        naraUsd.mintWithCollateral(address(usdc), 500e6); // Should succeed
        vm.stopPrank();
    }

    /**
     * @notice Test that maxMintPerBlock is enforced correctly across different decimal collaterals
     * @dev This tests the fix for Issue #06 - ensures the limit is enforced in 18-decimal NaraUSD units
     */
    function test_MaxMintPerBlock_ConsistentAcrossDecimals() public {
        // Set limit to 1000e18 NaraUSD per block
        naraUsd.setMaxMintPerBlock(1000e18);

        vm.startPrank(alice);

        // Mint 500 NaraUSD with USDC (6 decimals)
        usdc.approve(address(naraUsd), 500e6);
        uint256 naraUsdFromUsdc = naraUsd.mintWithCollateral(address(usdc), 500e6);
        assertEq(naraUsdFromUsdc, 500e18, "Should mint 500e18 NaraUSD from 500e6 USDC");

        // Mint 500 NaraUSD with USDT (6 decimals) - should succeed (total = 1000e18)
        usdt.approve(address(naraUsd), 500e6);
        uint256 naraUsdFromUsdt = naraUsd.mintWithCollateral(address(usdt), 500e6);
        assertEq(naraUsdFromUsdt, 500e18, "Should mint 500e18 NaraUSD from 500e6 USDT");

        // Try to mint more - should fail because we've hit the 1000e18 limit
        usdc.approve(address(naraUsd), 100e6);
        vm.expectRevert(NaraUSD.MaxMintPerBlockExceeded.selector);
        naraUsd.mintWithCollateral(address(usdc), 100e6);

        vm.stopPrank();

        // Verify the tracked amount is in 18 decimals
        assertEq(naraUsd.mintedPerBlock(block.number), 1000e18, "Should track 1000e18 total minted");
    }

    /**
     * @notice Test that decimal conversion is correct for per-block limit
     * @dev Verifies small amounts with 6-decimal collateral are properly converted
     */
    function test_MaxMintPerBlock_SmallAmounts() public {
        // Set limit to 10e18 NaraUSD per block (very small for testing)
        naraUsd.setMaxMintPerBlock(10e18);

        vm.startPrank(alice);

        // Mint 5 NaraUSD with USDC (5e6 in 6 decimals)
        usdc.approve(address(naraUsd), 5e6);
        naraUsd.mintWithCollateral(address(usdc), 5e6);

        // Mint another 5 NaraUSD - should succeed (total = 10e18)
        usdc.approve(address(naraUsd), 5e6);
        naraUsd.mintWithCollateral(address(usdc), 5e6);

        // Try to mint 1 more - should fail
        usdc.approve(address(naraUsd), 1e6);
        vm.expectRevert(NaraUSD.MaxMintPerBlockExceeded.selector);
        naraUsd.mintWithCollateral(address(usdc), 1e6);

        vm.stopPrank();

        // Verify exact tracking
        assertEq(naraUsd.mintedPerBlock(block.number), 10e18, "Should track exactly 10e18");
    }

    /**
     * @notice Test that minting with different users in same block counts toward same limit
     */
    function test_MaxMintPerBlock_MultipleUsers() public {
        naraUsd.setMaxMintPerBlock(1000e18);

        // Alice mints 600e18
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 600e6);
        naraUsd.mintWithCollateral(address(usdc), 600e6);
        vm.stopPrank();

        // Bob mints 400e18 - should succeed (total = 1000e18)
        vm.startPrank(bob);
        usdc.approve(address(naraUsd), 400e6);
        naraUsd.mintWithCollateral(address(usdc), 400e6);
        vm.stopPrank();

        // Alice tries to mint more - should fail
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 100e6);
        vm.expectRevert(NaraUSD.MaxMintPerBlockExceeded.selector);
        naraUsd.mintWithCollateral(address(usdc), 100e6);
        vm.stopPrank();

        assertEq(naraUsd.mintedPerBlock(block.number), 1000e18, "Should track 1000e18 total");
    }

    /**
     * @notice Test edge case: minting exactly at the limit
     */
    function test_MaxMintPerBlock_ExactLimit() public {
        naraUsd.setMaxMintPerBlock(1000e18);

        vm.startPrank(alice);

        // Mint exactly 1000e18 in one transaction - should succeed
        usdc.approve(address(naraUsd), 1000e6);
        uint256 minted = naraUsd.mintWithCollateral(address(usdc), 1000e6);
        assertEq(minted, 1000e18, "Should mint exactly at limit");

        // Try to mint any more - should fail
        usdc.approve(address(naraUsd), 1);
        vm.expectRevert(NaraUSD.MaxMintPerBlockExceeded.selector);
        naraUsd.mintWithCollateral(address(usdc), 1);

        vm.stopPrank();
    }

    /**
     * @notice Test that mintedPerBlock tracks post-fee amount (Issue #11)
     * @dev Verifies that per-block tracking uses actual minted amount, not pre-fee amount
     */
    function test_MaxMintPerBlock_TracksPostFeeAmount() public {
        // Set up 10% mint fee
        address treasury = makeAddr("treasury");
        naraUsd.setFeeTreasury(treasury);
        naraUsd.setMintFee(1000); // 10% fee (1000 bps)

        // Set limit to 1000e18 NaraUSD per block
        naraUsd.setMaxMintPerBlock(1000e18);

        vm.startPrank(alice);

        // Mint with 1000 USDC
        // Pre-fee: 1000e18 NaraUSD
        // After 10% fee: 900e18 NaraUSD actually minted
        usdc.approve(address(naraUsd), 1000e6);
        uint256 minted = naraUsd.mintWithCollateral(address(usdc), 1000e6);
        assertEq(minted, 900e18, "Should mint 900e18 after 10% fee");

        // Verify tracking uses post-fee amount (900e18, not 1000e18)
        assertEq(naraUsd.mintedPerBlock(block.number), 900e18, "Should track actual minted amount (post-fee)");

        vm.stopPrank();
    }

    /**
     * @notice Test that with fees, more gross collateral can be deposited per block
     * @dev Verifies the fix allows proper limit calculation based on actual minting
     */
    function test_MaxMintPerBlock_WithFees_AllowsMoreDeposits() public {
        // Set up 10% mint fee
        address treasury = makeAddr("treasury");
        naraUsd.setFeeTreasury(treasury);
        naraUsd.setMintFee(1000); // 10% fee

        // Set limit to 900e18 actual minted NaraUSD per block
        naraUsd.setMaxMintPerBlock(900e18);

        vm.startPrank(alice);

        // Deposit 500 USDC -> 450e18 minted (after 10% fee)
        usdc.approve(address(naraUsd), 500e6);
        uint256 minted1 = naraUsd.mintWithCollateral(address(usdc), 500e6);
        assertEq(minted1, 450e18, "Should mint 450e18");

        // Deposit another 500 USDC -> 450e18 minted (after 10% fee)
        // Total minted: 900e18 (exactly at limit)
        // Total deposited: 1000 USDC (but only 900 actually minted)
        usdc.approve(address(naraUsd), 500e6);
        uint256 minted2 = naraUsd.mintWithCollateral(address(usdc), 500e6);
        assertEq(minted2, 450e18, "Should mint another 450e18");

        // Verify we hit exactly the limit with actual minted amounts
        assertEq(naraUsd.mintedPerBlock(block.number), 900e18, "Should track 900e18 total");

        // Try to mint more - should fail
        usdc.approve(address(naraUsd), 100e6);
        vm.expectRevert(NaraUSD.MaxMintPerBlockExceeded.selector);
        naraUsd.mintWithCollateral(address(usdc), 100e6);

        vm.stopPrank();

        // Verify total fees collected
        assertEq(usdc.balanceOf(treasury), 100e6, "Treasury should have 100 USDC in fees (10% of 1000)");
    }

    /**
     * @notice Test minting without collateral (admin function)
     */
    function test_MintWithoutCollateral() public {
        uint256 amount = 1000e18;

        uint256 bobBalanceBefore = naraUsd.balanceOf(bob);
        uint256 mctBalanceBefore = mct.balanceOf(address(naraUsd));

        naraUsd.mintWithoutCollateral(bob, amount);

        assertEq(naraUsd.balanceOf(bob) - bobBalanceBefore, amount, "Bob should have additional naraUsd");

        // MCT should also be minted to maintain backing
        assertEq(mct.balanceOf(address(naraUsd)) - mctBalanceBefore, amount, "MCT minted for backing");
    }

    /**
     * @notice Test minting without collateral for beneficiary (admin function)
     */
    function test_MintWithoutCollateralFor() public {
        uint256 amount = 500e18;

        uint256 aliceBalanceBefore = naraUsd.balanceOf(alice);
        uint256 mctBalanceBefore = mct.balanceOf(address(naraUsd));

        naraUsd.mintWithoutCollateralFor(alice, amount);

        assertEq(naraUsd.balanceOf(alice) - aliceBalanceBefore, amount, "Alice should have additional naraUsd");

        // MCT should also be minted to maintain backing
        assertEq(mct.balanceOf(address(naraUsd)) - mctBalanceBefore, amount, "MCT minted for backing");
    }

    /**
     * @notice Test burning naraUsd
     */
    function test_Burn() public {
        // Setup: Mint naraUsd
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);

        uint256 burnAmount = 500e18;
        uint256 aliceNaraUsdBefore = naraUsd.balanceOf(alice);
        uint256 mctBefore = mct.totalSupply();

        // Burn
        naraUsd.burn(burnAmount);

        uint256 aliceNaraUsdAfter = naraUsd.balanceOf(alice);
        uint256 mctAfter = mct.totalSupply();

        // Verify burn
        assertEq(aliceNaraUsdBefore - aliceNaraUsdAfter, burnAmount, "naraUsd burned");
        assertEq(mctBefore - mctAfter, burnAmount, "MCT burned");

        // Collateral stays in MCT (deflationary)
        assertEq(mct.collateralBalance(address(usdc)), 1000e6, "Collateral remains");

        vm.stopPrank();
    }

    /**
     * @notice Test pause functionality
     */
    function test_Pause() public {
        // Pause
        naraUsd.pause();

        // Minting should fail
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);

        vm.expectRevert();
        naraUsd.mintWithCollateral(address(usdc), 1000e6);

        vm.stopPrank();

        // Unpause
        naraUsd.unpause();

        // Minting should work again
        vm.startPrank(alice);
        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), 1000e6);
        assertGt(naraUsdAmount, 0, "Should mint after unpause");
        vm.stopPrank();
    }

    /**
     * @notice Test disable mint and redeem
     */
    function test_DisableMintRedeem() public {
        naraUsd.disableMintRedeem();

        assertEq(naraUsd.maxMintPerBlock(), 0, "Mint disabled");
        assertEq(naraUsd.maxRedeemPerBlock(), 0, "Redeem disabled");

        // Minting should fail
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);

        vm.expectRevert(NaraUSD.MaxMintPerBlockExceeded.selector);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);

        vm.stopPrank();
    }

    /**
     * @notice Test minting with unsupported collateral fails
     */
    function test_RevertIf_UnsupportedCollateral() public {
        MockERC20 unsupported = new MockERC20("Unsupported", "UNSUP", 6);
        unsupported.mint(alice, 1000e6);

        vm.startPrank(alice);
        unsupported.approve(address(naraUsd), 1000e6);

        vm.expectRevert(NaraUSD.UnsupportedAsset.selector);
        naraUsd.mintWithCollateral(address(unsupported), 1000e6);

        vm.stopPrank();
    }

    /**
     * @notice Test minting zero amount fails
     */
    function test_RevertIf_MintZeroAmount() public {
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);

        vm.expectRevert(NaraUSD.InvalidAmount.selector);
        naraUsd.mintWithCollateral(address(usdc), 0);

        vm.stopPrank();
    }

    /**
     * @notice Test redeeming zero amount fails
     */
    function test_RevertIf_RedeemZeroAmount() public {
        vm.startPrank(alice);

        vm.expectRevert(NaraUSD.InvalidAmount.selector);
        naraUsd.redeem(address(usdc), 0, false);

        vm.stopPrank();
    }

    /**
     * @notice Test standard ERC4626 withdraw/redeem are disabled
     */
    function test_RevertIf_UseStandardWithdraw() public {
        // Mint some naraUsd
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);

        // Standard withdraw should revert
        vm.expectRevert("Use redeem()");
        naraUsd.withdraw(100e18, alice, alice);

        // Standard ERC4626 redeem should revert
        vm.expectRevert("Use redeem(collateralAsset, naraUsdAmount, allowQueue)");
        naraUsd.redeem(100e18, alice, alice);

        vm.stopPrank();
    }

    /**
     * @notice Test instant redemption with USDT collateral
     */
    function test_InstantRedemption_USDT() public {
        // Mint with USDT
        vm.startPrank(alice);
        uint256 aliceUsdtBefore = usdt.balanceOf(alice);

        usdt.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdt), 1000e6);

        // Instant redeem (MCT has liquidity)
        (uint256 collateralAmount, bool wasQueued) = naraUsd.redeem(address(usdt), 1000e18, false);

        assertEq(wasQueued, false, "Should be instant");
        assertGt(collateralAmount, 0, "Should receive collateral amount");
        assertEq(usdt.balanceOf(alice), aliceUsdtBefore, "USDT balance restored");

        vm.stopPrank();
    }

    /**
     * @notice Fuzz test minting with various amounts
     */
    function testFuzz_MintWithCollateral(uint256 amount) public {
        amount = bound(amount, 1e6, 100_000e6);

        vm.startPrank(alice);

        usdc.mint(alice, amount);
        usdc.approve(address(naraUsd), amount);

        uint256 expectedNaraUsd = amount * 1e12; // 6 to 18 decimals
        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), amount);

        assertEq(naraUsdAmount, expectedNaraUsd, "Should mint correct amount");

        vm.stopPrank();
    }

    /**
     * @notice Fuzz test redemption flow
     */
    function testFuzz_RedemptionFlow(uint256 amount) public {
        amount = bound(amount, 1e6, 10_000e6);

        vm.startPrank(alice);

        // Mint
        usdc.mint(alice, amount);
        usdc.approve(address(naraUsd), amount);
        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), amount);

        // Instant redeem (liquidity available)
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        (uint256 collateralAmount, bool wasQueued) = naraUsd.redeem(address(usdc), naraUsdAmount, false);

        assertEq(wasQueued, false, "Should be instant");
        assertEq(collateralAmount, amount, "Should receive correct collateral amount");
        assertEq(usdc.balanceOf(alice) - aliceUsdcBefore, amount, "Should receive same amount back");

        vm.stopPrank();
    }

    /* --------------- FEE TESTS --------------- */

    /**
     * @notice Test setting mint fee
     */
    function test_SetMintFee() public {
        // Note: address(this) is the admin in TestHelper setup

        // Set 0.5% mint fee (50 bps)
        vm.expectEmit(true, true, true, true);
        emit NaraUSD.MintFeeUpdated(0, 50);
        naraUsd.setMintFee(50);

        assertEq(naraUsd.mintFeeBps(), 50, "Mint fee should be 50 bps");
    }

    /**
     * @notice Test setting redeem fee
     */
    function test_SetRedeemFee() public {
        // Note: address(this) is the admin in TestHelper setup

        // Set 0.3% redeem fee (30 bps)
        vm.expectEmit(true, true, true, true);
        emit NaraUSD.RedeemFeeUpdated(0, 30);
        naraUsd.setRedeemFee(30);

        assertEq(naraUsd.redeemFeeBps(), 30, "Redeem fee should be 30 bps");
    }

    /**
     * @notice Test setting fee treasury
     */
    function test_SetFeeTreasury() public {
        address treasury = makeAddr("treasury");

        // Note: address(this) is the admin in TestHelper setup

        vm.expectEmit(true, true, true, true);
        emit NaraUSD.FeeTreasuryUpdated(address(0), treasury);
        naraUsd.setFeeTreasury(treasury);

        assertEq(naraUsd.feeTreasury(), treasury, "Treasury should be set");
    }

    /**
     * @notice Test setting minimum mint fee amount
     */
    function test_SetMinMintFeeAmount() public {
        // Note: address(this) is the admin in TestHelper setup

        uint256 minFee = 10e18; // 10 naraUsd minimum

        vm.expectEmit(true, true, true, true);
        emit NaraUSD.MinMintFeeAmountUpdated(0, minFee);
        naraUsd.setMinMintFeeAmount(minFee);

        assertEq(naraUsd.minMintFeeAmount(), minFee, "Min mint fee amount should be set");
    }

    /**
     * @notice Test setting minimum redeem fee amount
     */
    function test_SetMinRedeemFeeAmount() public {
        // Note: address(this) is the admin in TestHelper setup

        uint256 minFee = 5e18; // 5 naraUsd minimum

        vm.expectEmit(true, true, true, true);
        emit NaraUSD.MinRedeemFeeAmountUpdated(0, minFee);
        naraUsd.setMinRedeemFeeAmount(minFee);

        assertEq(naraUsd.minRedeemFeeAmount(), minFee, "Min redeem fee amount should be set");
    }

    /**
     * @notice Test minting with minimum fee (when percentage fee is lower)
     */
    function test_MintWithMinFee() public {
        address treasury = makeAddr("treasury");
        usdc.mint(treasury, 0); // Initialize treasury balance

        // Setup: Small percentage fee but high minimum
        naraUsd.setMintFee(10); // 0.1%
        naraUsd.setMinMintFeeAmount(10e18); // 10 naraUsd minimum (in 18 decimals)
        naraUsd.setFeeTreasury(treasury);

        uint256 usdcAmount = 1000e6; // 1000 USDC
        uint256 expectedTotal = 1000e18;
        uint256 percentageFee18 = (expectedTotal * 10) / 10000; // 0.1% = 0.1e18
        uint256 minFee18 = 10e18;
        uint256 expectedFee18 = minFee18 > percentageFee18 ? minFee18 : percentageFee18; // Should use min
        uint256 expectedFeeCollateral = expectedFee18 / 1e12; // Convert to 6 decimals
        uint256 expectedUserAmount = expectedTotal - expectedFee18;

        vm.startPrank(alice);
        uint256 treasuryUsdcBefore = usdc.balanceOf(treasury);
        usdc.approve(address(naraUsd), usdcAmount);

        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), usdcAmount);

        // Verify minimum fee is used
        assertEq(naraUsdAmount, expectedUserAmount, "User should receive amount after min fee");
        assertEq(
            usdc.balanceOf(treasury) - treasuryUsdcBefore,
            expectedFeeCollateral,
            "Treasury should receive min fee in USDC"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test minting with minimum fee even when percentage is zero
     */
    function test_MintWithMinFeeZeroPercentage() public {
        address treasury = makeAddr("treasury");
        usdc.mint(treasury, 0); // Initialize treasury balance

        // Setup: Zero percentage but minimum fee set
        naraUsd.setMintFee(0); // 0%
        naraUsd.setMinMintFeeAmount(5e18); // 5 naraUsd minimum
        naraUsd.setFeeTreasury(treasury);

        uint256 usdcAmount = 1000e6;
        uint256 expectedTotal = 1000e18;
        uint256 expectedFee18 = 5e18; // Should use minimum
        uint256 expectedFeeCollateral = expectedFee18 / 1e12;
        uint256 expectedUserAmount = expectedTotal - expectedFee18;

        vm.startPrank(alice);
        uint256 treasuryUsdcBefore = usdc.balanceOf(treasury);
        usdc.approve(address(naraUsd), usdcAmount);

        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), usdcAmount);

        // Verify minimum fee is still applied
        assertEq(naraUsdAmount, expectedUserAmount, "User should receive amount after min fee");
        assertEq(
            usdc.balanceOf(treasury) - treasuryUsdcBefore,
            expectedFeeCollateral,
            "Treasury should receive min fee even with 0%"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test minting with fee
     */
    function test_MintWithFee() public {
        address treasury = makeAddr("treasury");
        usdc.mint(treasury, 0); // Initialize treasury balance

        // Setup fees (address(this) is admin)
        naraUsd.setMintFee(50); // 0.5%
        naraUsd.setFeeTreasury(treasury);

        uint256 usdcAmount = 1000e6;
        uint256 expectedTotal = 1000e18;
        uint256 expectedFee18 = (expectedTotal * 50) / 10000; // 0.5% in 18 decimals
        uint256 expectedFeeCollateral = expectedFee18 / 1e12; // Convert to 6 decimals
        uint256 expectedUserAmount = expectedTotal - expectedFee18;

        vm.startPrank(alice);
        uint256 aliceBalanceBefore = naraUsd.balanceOf(alice);
        uint256 treasuryUsdcBefore = usdc.balanceOf(treasury);
        usdc.approve(address(naraUsd), usdcAmount);

        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), usdcAmount);

        // Verify user receives amount after fee
        assertEq(naraUsdAmount, expectedUserAmount, "User should receive amount after fee");
        assertEq(
            naraUsd.balanceOf(alice) - aliceBalanceBefore,
            expectedUserAmount,
            "Alice balance should be after fee"
        );

        // Verify treasury receives fee in collateral (USDC)
        assertEq(
            usdc.balanceOf(treasury) - treasuryUsdcBefore,
            expectedFeeCollateral,
            "Treasury should receive fee in USDC"
        );
        assertEq(naraUsd.balanceOf(treasury), 0, "Treasury should not receive naraUsd");

        vm.stopPrank();
    }

    /**
     * @notice Test minting with fee disabled (zero fee)
     */
    function test_MintWithZeroFee() public {
        address treasury = makeAddr("treasury");
        usdc.mint(treasury, 0); // Initialize treasury balance

        // Setup (address(this) is admin)
        naraUsd.setMintFee(0); // No fee
        naraUsd.setFeeTreasury(treasury);

        uint256 usdcAmount = 1000e6;
        uint256 expectedNaraUsd = 1000e18;

        vm.startPrank(alice);
        uint256 aliceBalanceBefore = naraUsd.balanceOf(alice);
        uint256 treasuryUsdcBefore = usdc.balanceOf(treasury);
        usdc.approve(address(naraUsd), usdcAmount);

        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), usdcAmount);

        // Verify user receives full amount
        assertEq(naraUsdAmount, expectedNaraUsd, "User should receive full amount");
        assertEq(
            naraUsd.balanceOf(alice) - aliceBalanceBefore,
            expectedNaraUsd,
            "Alice balance increase should be full amount"
        );

        // Verify treasury receives nothing
        assertEq(usdc.balanceOf(treasury) - treasuryUsdcBefore, 0, "Treasury should receive no fee in USDC");
        assertEq(naraUsd.balanceOf(treasury), 0, "Treasury should receive no fee in naraUsd");

        vm.stopPrank();
    }

    /**
     * @notice Test setting fee above maximum reverts
     */
    function test_RevertIf_SetFeeAboveMax() public {
        // Note: address(this) is the admin in TestHelper setup

        // Try to set 11% fee (1100 bps, max is 1000)
        vm.expectRevert(NaraUSD.InvalidFee.selector);
        naraUsd.setMintFee(1100);

        vm.expectRevert(NaraUSD.InvalidFee.selector);
        naraUsd.setRedeemFee(1100);
    }

    /**
     * @notice Test non-admin cannot set fees
     */
    function test_RevertIf_NonAdminSetsFee() public {
        vm.startPrank(alice);

        vm.expectRevert();
        naraUsd.setMintFee(50);

        vm.expectRevert();
        naraUsd.setRedeemFee(50);

        vm.stopPrank();
    }

    /**
     * @notice Test setting zero address as treasury reverts
     */
    function test_RevertIf_SetZeroAddressTreasury() public {
        // Note: address(this) is the admin in TestHelper setup

        vm.expectRevert(NaraUSD.ZeroAddressException.selector);
        naraUsd.setFeeTreasury(address(0));
    }

    /**
     * @notice Test minting with fee but no treasury set (fee not collected)
     */
    function test_MintWithFeeNoTreasury() public {
        // Setup (address(this) is admin)
        naraUsd.setMintFee(50); // 0.5% fee
        // Don't set treasury

        uint256 usdcAmount = 1000e6;
        uint256 expectedNaraUsd = 1000e18; // Full amount since treasury not set

        vm.startPrank(alice);
        usdc.approve(address(naraUsd), usdcAmount);

        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), usdcAmount);

        // Verify user receives full amount when treasury not set
        assertEq(naraUsdAmount, expectedNaraUsd, "User should receive full amount without treasury");

        vm.stopPrank();
    }

    /**
     * @notice Fuzz test minting with various fee amounts
     */
    function testFuzz_MintWithFee(uint256 amount, uint16 feeBps) public {
        amount = bound(amount, 1e6, 100_000e6);
        feeBps = uint16(bound(feeBps, 1, 1000)); // 0.01% to 10%

        address treasury = makeAddr("treasury");
        usdc.mint(treasury, 0); // Initialize treasury balance

        // Setup (address(this) is admin)
        naraUsd.setMintFee(feeBps);
        naraUsd.setFeeTreasury(treasury);

        vm.startPrank(alice);
        usdc.mint(alice, amount);
        usdc.approve(address(naraUsd), amount);

        uint256 expectedTotal = amount * 1e12; // Convert to 18 decimals
        uint256 expectedFee18 = (expectedTotal * feeBps) / 10000;
        uint256 expectedFeeCollateral = expectedFee18 / 1e12; // Convert to 6 decimals
        uint256 expectedUserAmount = expectedTotal - expectedFee18;

        uint256 treasuryUsdcBefore = usdc.balanceOf(treasury);
        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), amount);

        // Allow small rounding errors due to decimal conversions (6 decimals <-> 18 decimals)
        assertApproxEqAbs(naraUsdAmount, expectedUserAmount, 1e12, "User amount incorrect");
        assertApproxEqAbs(
            usdc.balanceOf(treasury) - treasuryUsdcBefore,
            expectedFeeCollateral,
            1,
            "Treasury fee in USDC incorrect"
        );
        assertEq(naraUsd.balanceOf(treasury), 0, "Treasury should not receive naraUsd");

        vm.stopPrank();
    }

    /* --------------- BLACKLIST TESTS --------------- */

    /**
     * @notice Test full restriction prevents transfers
     */
    function test_FullRestriction_PreventsTransfers() public {
        // Mint some naraUsd to alice first
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Add alice to blacklist
        naraUsd.addToBlacklist(alice);

        // Alice should NOT be able to transfer
        vm.startPrank(alice);
        vm.expectRevert(NaraUSD.OperationNotAllowed.selector);
        naraUsd.transfer(bob, 100e18);
        vm.stopPrank();
    }

    /**
     * @notice Test full restriction prevents receiving transfers
     */
    function test_FullRestriction_PreventsReceiving() public {
        // Mint some naraUsd to alice
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Add bob to full blacklist
        naraUsd.addToBlacklist(bob);

        // Alice should NOT be able to send to bob
        vm.startPrank(alice);
        vm.expectRevert(NaraUSD.OperationNotAllowed.selector);
        naraUsd.transfer(bob, 100e18);
        vm.stopPrank();
    }

    /**
     * @notice Test full restriction prevents redemption request
     */
    function test_FullRestriction_PreventsRedemption() public {
        // Mint some naraUsd to alice first
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Add alice to blacklist
        naraUsd.addToBlacklist(alice);

        // Alice should NOT be able to redeem
        vm.startPrank(alice);
        vm.expectRevert(NaraUSD.OperationNotAllowed.selector);
        naraUsd.redeem(address(usdc), 500e18, false);
        vm.stopPrank();
    }

    /**
     * @notice Test removing from blacklist
     */
    function test_RemoveFromBlacklist() public {
        // Mint some naraUsd to alice first (before blacklisting)
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Add alice to blacklist
        naraUsd.addToBlacklist(alice);

        // Verify she can't transfer
        vm.startPrank(alice);
        vm.expectRevert(NaraUSD.OperationNotAllowed.selector);
        naraUsd.transfer(bob, 100e18);
        vm.stopPrank();

        // Remove from blacklist
        naraUsd.removeFromBlacklist(alice);

        // Now she should be able to transfer
        uint256 bobBalanceBefore = naraUsd.balanceOf(bob);
        vm.startPrank(alice);
        naraUsd.transfer(bob, 100e18);
        assertEq(naraUsd.balanceOf(bob) - bobBalanceBefore, 100e18, "Bob should receive 100 naraUsd after removal");
        vm.stopPrank();
    }

    /**
     * @notice Test redistributing locked amount (legacy test - wallet only)
     */
    function test_RedistributeLockedAmount() public {
        // Mint some naraUsd to alice
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Add alice to blacklist
        naraUsd.addToBlacklist(alice);

        uint256 aliceBalance = naraUsd.balanceOf(alice);
        uint256 bobBalanceBefore = naraUsd.balanceOf(bob);

        // Redistribute alice's balance to bob
        vm.expectEmit(true, true, true, true);
        emit NaraUSD.LockedAmountRedistributed(alice, bob, aliceBalance, 0);
        naraUsd.redistributeLockedAmount(alice, bob);

        assertEq(naraUsd.balanceOf(alice), 0, "Alice balance should be 0");
        assertEq(naraUsd.balanceOf(bob), bobBalanceBefore + aliceBalance, "Bob should receive alice's balance");
    }

    /**
     * @notice Test burning locked amount (redistribute to address(0))
     */
    function test_RedistributeLockedAmount_Burn() public {
        // Mint some naraUsd to alice
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Add alice to blacklist
        naraUsd.addToBlacklist(alice);

        uint256 totalSupplyBefore = naraUsd.totalSupply();
        uint256 aliceBalance = naraUsd.balanceOf(alice);

        // Burn alice's balance by redistributing to address(0)
        vm.expectEmit(true, true, true, true);
        emit NaraUSD.LockedAmountRedistributed(alice, address(0), aliceBalance, 0);
        naraUsd.redistributeLockedAmount(alice, address(0));

        assertEq(naraUsd.balanceOf(alice), 0, "Alice balance should be 0");
        assertEq(naraUsd.totalSupply(), totalSupplyBefore - aliceBalance, "Total supply should decrease");
    }

    /**
     * @notice Test cannot blacklist admin
     */
    function test_RevertIf_BlacklistAdmin() public {
        address admin = address(this);

        vm.expectRevert(NaraUSD.CantBlacklistOwner.selector);
        naraUsd.addToBlacklist(admin);
    }

    /**
     * @notice Test non-admin cannot manage blacklist
     */
    function test_RevertIf_NonAdminManagesBlacklist() public {
        vm.startPrank(alice);

        vm.expectRevert();
        naraUsd.addToBlacklist(bob);

        vm.expectRevert();
        naraUsd.removeFromBlacklist(bob);

        vm.stopPrank();
    }

    /**
     * @notice Test blacklisted operator cannot use transferFrom (Issue #13)
     */
    function test_RevertIf_BlacklistedOperatorUsesTransferFrom() public {
        address carol = makeAddr("carol");

        // Get initial balances (alice and bob have tokens from setup)
        uint256 aliceBalanceBefore = naraUsd.balanceOf(alice);
        uint256 bobBalanceBefore = naraUsd.balanceOf(bob);

        // Setup: Alice gives approval to Carol
        vm.startPrank(alice);
        naraUsd.approve(carol, 500e18); // Carol can spend Alice's tokens
        vm.stopPrank();

        // Blacklist Carol
        naraUsd.addToBlacklist(carol);

        // Carol (blacklisted operator) tries to transfer Alice's tokens to Bob
        // This should fail even though Alice and Bob are not blacklisted
        vm.startPrank(carol);
        vm.expectRevert(NaraUSD.OperationNotAllowed.selector);
        naraUsd.transferFrom(alice, bob, 100e18);
        vm.stopPrank();

        // Verify balances unchanged
        assertEq(naraUsd.balanceOf(alice), aliceBalanceBefore, "Alice balance should be unchanged");
        assertEq(naraUsd.balanceOf(bob), bobBalanceBefore, "Bob balance should be unchanged");
    }

    /**
     * @notice Test non-blacklisted operator can use transferFrom normally
     */
    function test_NonBlacklistedOperatorCanTransferFrom() public {
        address carol = makeAddr("carol");

        // Get initial balances (alice and bob have tokens from setup)
        uint256 aliceBalanceBefore = naraUsd.balanceOf(alice);
        uint256 bobBalanceBefore = naraUsd.balanceOf(bob);

        // Setup: Alice gives approval to Carol
        vm.startPrank(alice);
        naraUsd.approve(carol, 500e18); // Carol can spend Alice's tokens
        vm.stopPrank();

        // Carol (NOT blacklisted) transfers Alice's tokens to Bob - should work
        vm.startPrank(carol);
        naraUsd.transferFrom(alice, bob, 100e18);
        vm.stopPrank();

        // Verify balances
        assertEq(naraUsd.balanceOf(alice), aliceBalanceBefore - 100e18, "Alice balance should decrease by 100");
        assertEq(naraUsd.balanceOf(bob), bobBalanceBefore + 100e18, "Bob balance should increase by 100");
    }

    /**
     * @notice Test blacklisted user cannot transfer even with approval from others
     */
    function test_RevertIf_BlacklistedFromSendsViaTransferFrom() public {
        address carol = makeAddr("carol");

        // Setup: Alice has tokens, gives approval to Carol
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        naraUsd.approve(carol, 500e18); // Carol can spend Alice's tokens
        vm.stopPrank();

        // Blacklist Alice (the token owner)
        naraUsd.addToBlacklist(alice);

        // Carol tries to transfer Alice's tokens to Bob
        // Should fail because Alice (from) is blacklisted
        vm.startPrank(carol);
        vm.expectRevert(NaraUSD.OperationNotAllowed.selector);
        naraUsd.transferFrom(alice, bob, 100e18);
        vm.stopPrank();
    }

    /**
     * @notice Test cannot transferFrom to blacklisted recipient
     */
    function test_RevertIf_TransferFromToBlacklisted() public {
        address carol = makeAddr("carol");

        // Setup: Alice has tokens, gives approval to Carol
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        naraUsd.approve(carol, 500e18); // Carol can spend Alice's tokens
        vm.stopPrank();

        // Blacklist Bob (the recipient)
        naraUsd.addToBlacklist(bob);

        // Carol tries to transfer Alice's tokens to Bob (blacklisted)
        // Should fail because Bob (to) is blacklisted
        vm.startPrank(carol);
        vm.expectRevert(NaraUSD.OperationNotAllowed.selector);
        naraUsd.transferFrom(alice, bob, 100e18);
        vm.stopPrank();
    }

    /**
     * @notice Test redistribute requires full restriction
     */
    function test_RevertIf_RedistributeNonRestricted() public {
        // Mint some naraUsd to alice (not blacklisted)
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Try to redistribute without full restriction
        vm.expectRevert(NaraUSD.OperationNotAllowed.selector);
        naraUsd.redistributeLockedAmount(alice, bob);
    }

    /* --------------- ESCROWED AMOUNT REDISTRIBUTION TESTS --------------- */

    /**
     * @notice Test redistributing only escrowed amount (no wallet balance)
     */
    function test_RedistributeLockedAmount_OnlyEscrowed() public {
        // 0. Burn alice's initial balance from setUp (clean slate)
        uint256 aliceInitialBalance = naraUsd.balanceOf(alice);
        if (aliceInitialBalance > 0) {
            vm.prank(alice);
            naraUsd.burn(aliceInitialBalance);
        }

        // 1. Mint naraUsd to alice
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6); // Alice has 1000e18, MCT has 1000e6 USDC
        vm.stopPrank();

        // 2. Drain MCT collateral: mint unbacked NaraUSD to bob, then bob redeems to drain USDC
        naraUsd.mintWithoutCollateral(bob, 2000e18); // Bob gets 2000e18 unbacked NaraUSD
        vm.startPrank(bob);
        naraUsd.redeem(address(usdc), 1000e18, false); // Bob redeems 1000e18, drains the 1000e6 USDC
        vm.stopPrank();

        // 3. Now alice tries to queue redemption (all her balance, no liquidity available)
        vm.startPrank(alice);
        uint256 redeemAmount = 1000e18;
        (uint256 collateralReceived, bool wasQueued) = naraUsd.redeem(address(usdc), redeemAmount, true);
        assertEq(collateralReceived, 0, "Should not receive collateral");
        assertTrue(wasQueued, "Should be queued");
        vm.stopPrank();

        // 3. Verify escrowed amount and wallet balance
        (uint152 escrowedAmount, address collateralAsset) = naraUsd.redemptionRequests(alice);
        assertEq(escrowedAmount, redeemAmount, "Should have escrowed amount");
        assertEq(collateralAsset, address(usdc), "Should be USDC");
        assertEq(naraUsd.balanceOf(alice), 0, "Wallet balance should be 0");

        // 4. Blacklist alice
        naraUsd.addToBlacklist(alice);

        // 5. Verify alice cannot cancel redemption
        vm.startPrank(alice);
        vm.expectRevert(NaraUSD.OperationNotAllowed.selector);
        naraUsd.cancelRedeem();
        vm.stopPrank();

        // 6. Admin redistributes to bob (should handle only escrowed amount)
        uint256 bobBalanceBefore = naraUsd.balanceOf(bob);

        vm.expectEmit(true, true, true, true);
        emit NaraUSD.LockedAmountRedistributed(alice, bob, 0, redeemAmount);
        naraUsd.redistributeLockedAmount(alice, bob);

        // 7. Verify results
        (uint152 escrowedAmountAfter, ) = naraUsd.redemptionRequests(alice);
        assertEq(escrowedAmountAfter, 0, "Redemption request should be cleared");
        assertEq(naraUsd.balanceOf(bob), bobBalanceBefore + redeemAmount, "Bob should receive escrowed amount");
    }

    /**
     * @notice Test redistributing only wallet balance (no escrowed amount)
     */
    function test_RedistributeLockedAmount_OnlyWallet() public {
        // 1. Mint naraUsd to alice (no redemption queue)
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        uint256 aliceBalance = naraUsd.balanceOf(alice);

        // 2. Blacklist alice
        naraUsd.addToBlacklist(alice);

        // 3. Redistribute wallet balance to bob
        uint256 bobBalanceBefore = naraUsd.balanceOf(bob);

        vm.expectEmit(true, true, true, true);
        emit NaraUSD.LockedAmountRedistributed(alice, bob, aliceBalance, 0);
        naraUsd.redistributeLockedAmount(alice, bob);

        // 4. Verify results
        assertEq(naraUsd.balanceOf(alice), 0, "Alice wallet balance should be 0");
        assertEq(naraUsd.balanceOf(bob), bobBalanceBefore + aliceBalance, "Bob should receive wallet balance");
    }

    /**
     * @notice Test redistributing both wallet and escrowed amounts in single call
     */
    function test_RedistributeLockedAmount_WalletAndEscrowed() public {
        // 1. Mint naraUsd to alice
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 2000e6);
        naraUsd.mintWithCollateral(address(usdc), 2000e6); // Alice has 2000e18, MCT has 2000e6 USDC
        vm.stopPrank();

        // 2. Drain MCT collateral: mint unbacked NaraUSD to bob, then bob redeems
        naraUsd.mintWithoutCollateral(bob, 3000e18); // Bob gets unbacked NaraUSD
        vm.startPrank(bob);
        naraUsd.redeem(address(usdc), 2000e18, false); // Drains all 2000e6 USDC
        vm.stopPrank();

        // 3. Alice queue redemption (half her balance, no liquidity available)
        vm.startPrank(alice);
        uint256 redeemAmount = 1000e18;
        naraUsd.redeem(address(usdc), redeemAmount, true);
        vm.stopPrank();

        uint256 walletBalance = naraUsd.balanceOf(alice);
        uint256 totalAmount = walletBalance + redeemAmount;

        // 3. Blacklist alice
        naraUsd.addToBlacklist(alice);

        // 4. Redistribute everything to bob in single call
        uint256 bobBalanceBefore = naraUsd.balanceOf(bob);

        vm.expectEmit(true, true, true, true);
        emit NaraUSD.LockedAmountRedistributed(alice, bob, walletBalance, redeemAmount);
        naraUsd.redistributeLockedAmount(alice, bob);

        // 5. Verify results
        assertEq(naraUsd.balanceOf(alice), 0, "Alice wallet balance should be 0");
        (uint152 escrowedAmount, ) = naraUsd.redemptionRequests(alice);
        assertEq(escrowedAmount, 0, "Redemption request should be cleared");
        assertEq(naraUsd.balanceOf(bob), bobBalanceBefore + totalAmount, "Bob should receive total amount");
    }

    /**
     * @notice Test burning both wallet and escrowed amounts (redistribute to address(0))
     */
    function test_RedistributeLockedAmount_BurnBoth() public {
        // 1. Mint naraUsd to alice
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 2000e6);
        naraUsd.mintWithCollateral(address(usdc), 2000e6); // Alice has 2000e18, MCT has 2000e6 USDC
        vm.stopPrank();

        // 2. Drain MCT collateral: mint unbacked NaraUSD to bob, then bob redeems
        naraUsd.mintWithoutCollateral(bob, 3000e18); // Bob gets unbacked NaraUSD
        vm.startPrank(bob);
        naraUsd.redeem(address(usdc), 2000e18, false); // Drains all 2000e6 USDC
        vm.stopPrank();

        // 3. Alice queue redemption (half her balance, no liquidity available)
        vm.startPrank(alice);
        uint256 redeemAmount = 1000e18;
        naraUsd.redeem(address(usdc), redeemAmount, true);
        vm.stopPrank();

        uint256 walletBalance = naraUsd.balanceOf(alice);
        uint256 totalAmount = walletBalance + redeemAmount;

        // 3. Blacklist alice
        naraUsd.addToBlacklist(alice);

        // 4. Burn everything by redistributing to address(0)
        uint256 totalSupplyBefore = naraUsd.totalSupply();

        vm.expectEmit(true, true, true, true);
        emit NaraUSD.LockedAmountRedistributed(alice, address(0), walletBalance, redeemAmount);
        naraUsd.redistributeLockedAmount(alice, address(0));

        // 5. Verify results
        assertEq(naraUsd.balanceOf(alice), 0, "Alice wallet balance should be 0");
        (uint152 escrowedAmount, ) = naraUsd.redemptionRequests(alice);
        assertEq(escrowedAmount, 0, "Redemption request should be cleared");
        assertEq(naraUsd.totalSupply(), totalSupplyBefore - totalAmount, "Total supply should decrease");
    }

    /**
     * @notice Test redistributeLockedAmount reverts if target is blacklisted
     */
    function test_RevertIf_RedistributeLockedAmount_TargetBlacklisted() public {
        // 1. Mint naraUsd to alice
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // 2. Blacklist both alice and bob
        naraUsd.addToBlacklist(alice);
        naraUsd.addToBlacklist(bob);

        // 3. Try to redistribute to blacklisted bob (should fail)
        vm.expectRevert(NaraUSD.OperationNotAllowed.selector);
        naraUsd.redistributeLockedAmount(alice, bob);
    }

    /* --------------- MINIMUM AMOUNT TESTS --------------- */

    /**
     * @notice Test setting minimum mint amount
     */
    function test_SetMinMintAmount() public {
        uint256 minAmount = 100e18; // 100 naraUsd

        vm.expectEmit(true, true, true, true);
        emit NaraUSD.MinMintAmountUpdated(0, minAmount);
        naraUsd.setMinMintAmount(minAmount);

        assertEq(naraUsd.minMintAmount(), minAmount, "Min mint amount should be set");
    }

    /**
     * @notice Test setting minimum redeem amount
     */
    function test_SetMinRedeemAmount() public {
        uint256 minAmount = 100e18; // 100 naraUsd

        vm.expectEmit(true, true, true, true);
        emit NaraUSD.MinRedeemAmountUpdated(0, minAmount);
        naraUsd.setMinRedeemAmount(minAmount);

        assertEq(naraUsd.minRedeemAmount(), minAmount, "Min redeem amount should be set");
    }

    /**
     * @notice Test mint below minimum reverts
     */
    function test_RevertIf_MintBelowMinimum() public {
        uint256 minAmount = 100e18; // 100 naraUsd
        naraUsd.setMinMintAmount(minAmount);

        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 50e6); // 50 USDC = 50 naraUsd, below minimum

        vm.expectRevert(NaraUSD.BelowMinimumAmount.selector);
        naraUsd.mintWithCollateral(address(usdc), 50e6);

        vm.stopPrank();
    }

    /**
     * @notice Test mint at exactly minimum succeeds
     */
    function test_MintAtMinimum() public {
        uint256 minAmount = 100e18; // 100 naraUsd
        naraUsd.setMinMintAmount(minAmount);

        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 100e6); // Exactly 100 USDC = 100 naraUsd

        uint256 minted = naraUsd.mintWithCollateral(address(usdc), 100e6);
        assertEq(minted, minAmount, "Should mint exactly minimum amount");

        vm.stopPrank();
    }

    /**
     * @notice Test mint above minimum succeeds
     */
    function test_MintAboveMinimum() public {
        uint256 minAmount = 100e18; // 100 naraUsd
        naraUsd.setMinMintAmount(minAmount);

        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 200e6); // 200 USDC = 200 naraUsd, above minimum

        uint256 minted = naraUsd.mintWithCollateral(address(usdc), 200e6);
        assertEq(minted, 200e18, "Should mint above minimum");

        vm.stopPrank();
    }

    /**
     * @notice Test minimum mint amount is checked after fees
     */
    function test_MinMintAmount_CheckedAfterFees() public {
        // Set up fees
        address treasury = makeAddr("treasury");
        naraUsd.setFeeTreasury(treasury);
        naraUsd.setMintFee(1000); // 10% fee (1000 bps)

        // Set minimum to 100 NaraUSD
        uint256 minAmount = 100e18;
        naraUsd.setMinMintAmount(minAmount);

        vm.startPrank(alice);

        // Try to mint 110 USDC
        // Pre-fee: 110 NaraUSD (above minimum)
        // After 10% fee: 99 NaraUSD (below minimum)
        // This should fail
        usdc.approve(address(naraUsd), 110e6);
        vm.expectRevert(NaraUSD.BelowMinimumAmount.selector);
        naraUsd.mintWithCollateral(address(usdc), 110e6);

        vm.stopPrank();
    }

    /**
     * @notice Test minting with fees where post-fee amount meets minimum
     */
    function test_MinMintAmount_WithFees_Success() public {
        // Set up fees
        address treasury = makeAddr("treasury");
        naraUsd.setFeeTreasury(treasury);
        naraUsd.setMintFee(1000); // 10% fee (1000 bps)

        // Set minimum to 90 NaraUSD
        uint256 minAmount = 90e18;
        naraUsd.setMinMintAmount(minAmount);

        vm.startPrank(alice);

        // Mint 100 USDC
        // Pre-fee: 100 NaraUSD
        // After 10% fee: 90 NaraUSD (exactly at minimum)
        // This should succeed
        usdc.approve(address(naraUsd), 100e6);
        uint256 minted = naraUsd.mintWithCollateral(address(usdc), 100e6);

        assertEq(minted, 90e18, "Should mint 90 NaraUSD after 10% fee");
        assertEq(usdc.balanceOf(treasury), 10e6, "Treasury should receive 10 USDC fee");

        vm.stopPrank();
    }

    /**
     * @notice Test redeem below minimum reverts
     */
    function test_RevertIf_RedeemBelowMinimum() public {
        // First mint some naraUsd
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Set minimum redeem amount
        uint256 minAmount = 100e18; // 100 naraUsd
        naraUsd.setMinRedeemAmount(minAmount);

        // Try to redeem below minimum
        vm.startPrank(alice);
        vm.expectRevert(NaraUSD.BelowMinimumAmount.selector);
        naraUsd.redeem(address(usdc), 50e18, false); // 50 naraUsd, below minimum
        vm.stopPrank();
    }

    /**
     * @notice Test redeem at exactly minimum succeeds
     */
    function test_RedeemAtMinimum() public {
        // First mint some naraUsd
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Set minimum redeem amount
        uint256 minAmount = 100e18; // 100 naraUsd
        naraUsd.setMinRedeemAmount(minAmount);

        // Instant redeem at minimum
        vm.startPrank(alice);
        (uint256 collateralAmount, bool wasQueued) = naraUsd.redeem(address(usdc), minAmount, false);
        assertEq(wasQueued, false, "Should be instant");
        assertGt(collateralAmount, 0, "Should receive collateral amount");
        vm.stopPrank();
    }

    /**
     * @notice Test redeem above minimum succeeds
     */
    function test_RedeemAboveMinimum() public {
        // First mint some naraUsd
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Set minimum redeem amount
        uint256 minAmount = 100e18; // 100 naraUsd
        naraUsd.setMinRedeemAmount(minAmount);

        // Instant redeem above minimum
        vm.startPrank(alice);
        (uint256 collateralAmount, bool wasQueued) = naraUsd.redeem(address(usdc), 200e18, false);
        assertEq(wasQueued, false, "Should be instant");
        assertGt(collateralAmount, 0, "Should receive collateral amount");
        vm.stopPrank();
    }

    /**
     * @notice Test minimum of 0 allows any amount
     */
    function test_MinimumZeroAllowsAnyAmount() public {
        // Minimum defaults to 0, should allow any amount
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1e6); // 1 USDC = 1 naraUsd

        uint256 minted = naraUsd.mintWithCollateral(address(usdc), 1e6);
        assertEq(minted, 1e18, "Should mint even tiny amounts when minimum is 0");

        vm.stopPrank();
    }

    /**
     * @notice Test non-admin cannot set minimums
     */
    function test_RevertIf_NonAdminSetsMinimums() public {
        vm.startPrank(alice);

        vm.expectRevert();
        naraUsd.setMinMintAmount(100e18);

        vm.expectRevert();
        naraUsd.setMinRedeemAmount(100e18);

        vm.stopPrank();
    }

    /**
     * @notice Fuzz test minimum mint amount
     */
    function testFuzz_MinMintAmount(uint256 minAmount, uint256 mintAmount) public {
        minAmount = bound(minAmount, 1e18, 1000e18); // 1-1000 naraUsd minimum
        mintAmount = bound(mintAmount, 1e6, 2000e6); // 1-2000 USDC (non-zero)

        naraUsd.setMinMintAmount(minAmount);

        uint256 expectedNaraUsd = mintAmount * 1e12; // Convert USDC to naraUsd

        vm.startPrank(alice);
        usdc.mint(alice, mintAmount);
        usdc.approve(address(naraUsd), mintAmount);

        if (expectedNaraUsd < minAmount) {
            vm.expectRevert(NaraUSD.BelowMinimumAmount.selector);
            naraUsd.mintWithCollateral(address(usdc), mintAmount);
        } else {
            naraUsd.mintWithCollateral(address(usdc), mintAmount);
        }

        vm.stopPrank();
    }

    /* ========== KEYRING INTEGRATION TESTS ========== */

    /**
     * @notice Test setting Keyring config
     */
    function test_SetKeyringConfig() public {
        MockKeyring keyring = new MockKeyring();
        uint256 policyId = 1;

        vm.expectEmit(true, true, false, true);
        emit NaraUSD.KeyringConfigUpdated(address(keyring), policyId);

        naraUsd.setKeyringConfig(address(keyring), policyId);

        assertEq(naraUsd.keyringAddress(), address(keyring), "Keyring address not set");
        assertEq(naraUsd.keyringPolicyId(), policyId, "Policy ID not set");
    }

    /**
     * @notice Test setting Keyring whitelist
     */
    function test_SetKeyringWhitelist() public {
        address testAddr = makeAddr("testAddr");

        vm.expectEmit(true, false, false, true);
        emit NaraUSD.KeyringWhitelistUpdated(testAddr, true);

        naraUsd.setKeyringWhitelist(testAddr, true);
        assertTrue(naraUsd.keyringWhitelist(testAddr), "Address not whitelisted");

        vm.expectEmit(true, false, false, true);
        emit NaraUSD.KeyringWhitelistUpdated(testAddr, false);

        naraUsd.setKeyringWhitelist(testAddr, false);
        assertFalse(naraUsd.keyringWhitelist(testAddr), "Address still whitelisted");
    }

    /**
     * @notice Test minting requires sender to have Keyring credentials
     */
    function test_RevertIf_MintWithoutKeyringCredential() public {
        MockKeyring keyring = new MockKeyring();
        uint256 policyId = 1;

        naraUsd.setKeyringConfig(address(keyring), policyId);

        // Alice (sender) doesn't have credentials
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);

        vm.expectRevert(abi.encodeWithSelector(NaraUSD.KeyringCredentialInvalid.selector, alice));
        naraUsd.mintWithCollateral(address(usdc), 1000e6);

        vm.stopPrank();
    }

    /**
     * @notice Test minting succeeds with Keyring credentials
     */
    function test_MintWithKeyringCredential() public {
        MockKeyring keyring = new MockKeyring();
        uint256 policyId = 1;

        naraUsd.setKeyringConfig(address(keyring), policyId);
        keyring.setCredential(policyId, alice, true);

        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);

        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), 1000e6);
        assertEq(naraUsdAmount, 1000e18, "Should mint successfully with credentials");

        vm.stopPrank();
    }

    /**
     * @notice Test whitelisted addresses bypass Keyring checks
     */
    function test_WhitelistedAddressBypassesKeyring() public {
        MockKeyring keyring = new MockKeyring();
        uint256 policyId = 1;

        naraUsd.setKeyringConfig(address(keyring), policyId);
        naraUsd.setKeyringWhitelist(alice, true);

        // Alice doesn't have credentials but is whitelisted
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);

        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), 1000e6);
        assertEq(naraUsdAmount, 1000e18, "Whitelisted address should bypass Keyring");

        vm.stopPrank();
    }

    /**
     * @notice Test redeem requires Keyring credentials
     */
    function test_RevertIf_RedeemWithoutKeyringCredential() public {
        // First mint with credentials
        MockKeyring keyring = new MockKeyring();
        uint256 policyId = 1;
        keyring.setCredential(policyId, alice, true);

        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Now enable Keyring and revoke credentials
        naraUsd.setKeyringConfig(address(keyring), policyId);
        keyring.setCredential(policyId, alice, false);

        // Try to redeem without credentials
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NaraUSD.KeyringCredentialInvalid.selector, alice));
        naraUsd.redeem(address(usdc), 500e18, false);
        vm.stopPrank();
    }

    /**
     * @notice Test transfers are completely free - no Keyring checks
     */
    function test_TransfersFreelyWithoutKeyringCheck() public {
        // Mint with credentials
        MockKeyring keyring = new MockKeyring();
        uint256 policyId = 1;
        keyring.setCredential(policyId, alice, true);

        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Enable Keyring and revoke Alice's credentials
        naraUsd.setKeyringConfig(address(keyring), policyId);
        keyring.setCredential(policyId, alice, false);

        // Transfer should still work even without credentials
        vm.startPrank(alice);
        uint256 bobBalanceBefore = naraUsd.balanceOf(bob);
        naraUsd.transfer(bob, 100e18);
        assertEq(naraUsd.balanceOf(bob) - bobBalanceBefore, 100e18, "Transfers are free regardless of credentials");
        vm.stopPrank();
    }

    /**
     * @notice Test anyone can transfer to anyone - completely free transferability
     */
    function test_FreeTransferability() public {
        // Mint with credentials
        MockKeyring keyring = new MockKeyring();
        uint256 policyId = 1;
        keyring.setCredential(policyId, alice, true);

        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        naraUsd.mintWithCollateral(address(usdc), 1000e6);
        vm.stopPrank();

        // Enable Keyring - neither alice nor bob have credentials after minting
        naraUsd.setKeyringConfig(address(keyring), policyId);
        keyring.setCredential(policyId, alice, false);

        // Alice can transfer to bob
        vm.startPrank(alice);
        naraUsd.transfer(bob, 100e18);
        vm.stopPrank();

        // Bob can transfer to charlie (neither have credentials)
        address charlie = makeAddr("charlie");
        vm.startPrank(bob);
        naraUsd.transfer(charlie, 50e18);
        vm.stopPrank();

        assertEq(naraUsd.balanceOf(charlie), 50e18, "Free transferability works");
    }

    /**
     * @notice Test disabling Keyring by setting address to zero
     */
    function test_DisableKeyring() public {
        MockKeyring keyring = new MockKeyring();
        uint256 policyId = 1;

        naraUsd.setKeyringConfig(address(keyring), policyId);

        // Disable Keyring
        naraUsd.setKeyringConfig(address(0), 0);
        assertEq(naraUsd.keyringAddress(), address(0), "Keyring should be disabled");

        // Minting should work without credentials
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), 1000e6);
        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), 1000e6);
        assertEq(naraUsdAmount, 1000e18, "Should mint without Keyring");
        vm.stopPrank();
    }

    /**
     * @notice Test only admin can set Keyring config
     */
    function test_RevertIf_NonAdminSetsKeyringConfig() public {
        MockKeyring keyring = new MockKeyring();

        vm.startPrank(alice);
        vm.expectRevert();
        naraUsd.setKeyringConfig(address(keyring), 1);
        vm.stopPrank();
    }

    /**
     * @notice Test only admin can set Keyring whitelist
     */
    function test_RevertIf_NonAdminSetsKeyringWhitelist() public {
        vm.startPrank(alice);
        vm.expectRevert();
        naraUsd.setKeyringWhitelist(bob, true);
        vm.stopPrank();
    }

    /**
     * @notice Test hasValidCredentials returns true when Keyring is disabled
     */
    function test_HasValidCredentials_NoKeyring() public view {
        // Keyring not configured - everyone should be valid
        assertTrue(naraUsd.hasValidCredentials(alice), "Should be valid when Keyring disabled");
        assertTrue(naraUsd.hasValidCredentials(bob), "Should be valid when Keyring disabled");
        assertTrue(naraUsd.hasValidCredentials(address(0x123)), "Should be valid when Keyring disabled");
    }

    /**
     * @notice Test hasValidCredentials with Keyring enabled
     */
    function test_HasValidCredentials_WithKeyring() public {
        MockKeyring keyring = new MockKeyring();
        uint256 policyId = 1;

        naraUsd.setKeyringConfig(address(keyring), policyId);

        // Alice doesn't have credentials
        assertFalse(naraUsd.hasValidCredentials(alice), "Should be invalid without credentials");

        // Give Alice credentials
        keyring.setCredential(policyId, alice, true);
        assertTrue(naraUsd.hasValidCredentials(alice), "Should be valid with credentials");

        // Bob still doesn't have credentials
        assertFalse(naraUsd.hasValidCredentials(bob), "Should be invalid without credentials");
    }

    /**
     * @notice Test hasValidCredentials respects whitelist
     */
    function test_HasValidCredentials_Whitelist() public {
        MockKeyring keyring = new MockKeyring();
        uint256 policyId = 1;

        naraUsd.setKeyringConfig(address(keyring), policyId);

        // Alice doesn't have credentials but is whitelisted
        naraUsd.setKeyringWhitelist(alice, true);
        assertTrue(naraUsd.hasValidCredentials(alice), "Should be valid when whitelisted");

        // Bob is not whitelisted and has no credentials
        assertFalse(naraUsd.hasValidCredentials(bob), "Should be invalid");
    }

    /**
     * @notice Test hasValidCredentials can be called by anyone
     */
    function test_HasValidCredentials_PublicAccess() public {
        MockKeyring keyring = new MockKeyring();
        uint256 policyId = 1;

        naraUsd.setKeyringConfig(address(keyring), policyId);
        keyring.setCredential(policyId, alice, true);

        // Anyone can call hasValidCredentials
        vm.startPrank(bob);
        assertTrue(naraUsd.hasValidCredentials(alice), "Bob can check Alice's credentials");
        assertFalse(naraUsd.hasValidCredentials(bob), "Bob can check his own credentials");
        vm.stopPrank();
    }
}
