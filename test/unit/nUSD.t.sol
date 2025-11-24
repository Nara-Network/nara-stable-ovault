// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { nUSD } from "../../contracts/nusd/nUSD.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

/**
 * @title nUSDTest
 * @notice Unit tests for nUSD core functionality
 */
contract nUSDTest is TestHelper {
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
    function test_Setup() public {
        assertEq(nusd.name(), "nUSD");
        assertEq(nusd.symbol(), "nUSD");
        assertEq(nusd.decimals(), 18);
        assertEq(address(nusd.mct()), address(mct));
        assertEq(nusd.cooldownDuration(), 7 days);
    }

    /**
     * @notice Test minting nUSD with USDC
     */
    function test_MintWithCollateral_USDC() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedNusd = 1000e18;
        
        vm.startPrank(alice);
        usdc.approve(address(nusd), usdcAmount);
        
        uint256 aliceNusdBefore = nusd.balanceOf(alice);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 nusdContractMctBefore = mct.balanceOf(address(nusd));
        
        uint256 nusdAmount = nusd.mintWithCollateral(address(usdc), usdcAmount);
        uint256 aliceUsdcAfter = usdc.balanceOf(alice);
        
        // Verify nUSD minted
        assertEq(nusdAmount, expectedNusd, "Should mint 1000 nUSD");
        assertEq(nusd.balanceOf(alice) - aliceNusdBefore, expectedNusd, "Alice should have additional nUSD");
        
        // Verify USDC transferred
        assertEq(aliceUsdcBefore - aliceUsdcAfter, usdcAmount, "USDC transferred");
        
        // Verify MCT created (held by nUSD contract)
        assertEq(mct.balanceOf(address(nusd)) - nusdContractMctBefore, expectedNusd, "nUSD holds additional MCT");
        
        vm.stopPrank();
    }

    /**
     * @notice Test minting nUSD with USDT
     */
    function test_MintWithCollateral_USDT() public {
        uint256 usdtAmount = 500e6;
        uint256 expectedNusd = 500e18;
        
        vm.startPrank(alice);
        usdt.approve(address(nusd), usdtAmount);
        
        uint256 aliceNusdBefore = nusd.balanceOf(alice);
        uint256 nusdAmount = nusd.mintWithCollateral(address(usdt), usdtAmount);
        
        assertEq(nusdAmount, expectedNusd, "Should mint 500 nUSD");
        assertEq(nusd.balanceOf(alice) - aliceNusdBefore, expectedNusd, "Alice should have additional nUSD");
        
        vm.stopPrank();
    }

    /**
     * @notice Test cooldown redemption flow
     */
    function test_CooldownRedemption_Complete() public {
        // Setup: Mint nUSD
        uint256 nusdAmount = 1000e18;
        vm.startPrank(alice);
        uint256 aliceNusdBefore = nusd.balanceOf(alice);
        usdc.approve(address(nusd), 1000e6);
        nusd.mintWithCollateral(address(usdc), 1000e6);
        
        // Step 1: Request redemption
        nusd.cooldownRedeem(address(usdc), nusdAmount);
        
        // Verify redemption request
        (uint104 cooldownEnd, uint152 lockedAmount, address collateral) = 
            nusd.redemptionRequests(alice);
        
        assertEq(lockedAmount, nusdAmount, "Amount should be locked");
        assertEq(collateral, address(usdc), "Collateral should be USDC");
        assertEq(cooldownEnd, block.timestamp + 7 days, "Cooldown should be 7 days");
        
        // Verify nUSD is in silo (alice balance should be same as before mint)
        assertEq(nusd.balanceOf(alice), aliceNusdBefore, "Alice nUSD should be in silo");
        assertEq(nusd.balanceOf(address(nusd.redeemSilo())), nusdAmount, "nUSD in silo");
        
        // Step 2: Try to complete too early (should fail)
        vm.expectRevert(nUSD.CooldownNotFinished.selector);
        nusd.completeRedeem();
        
        // Step 3: Fast forward time
        vm.warp(cooldownEnd);
        
        // Step 4: Complete redemption
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 collateralReceived = nusd.completeRedeem();
        uint256 aliceUsdcAfter = usdc.balanceOf(alice);
        
        // Verify redemption completed
        assertEq(collateralReceived, 1000e6, "Should receive 1000 USDC");
        assertEq(aliceUsdcAfter - aliceUsdcBefore, 1000e6, "USDC received");
        assertEq(nusd.balanceOf(alice), aliceNusdBefore, "nUSD burned, balance back to initial");
        
        // Verify request cleared
        (uint104 endAfter, uint152 amountAfter, ) = nusd.redemptionRequests(alice);
        assertEq(endAfter, 0, "Request cleared");
        assertEq(amountAfter, 0, "Amount cleared");
        
        vm.stopPrank();
    }

    /**
     * @notice Test cancelling redemption request
     */
    function test_CancelRedemption() public {
        // Setup: Mint and request redemption
        uint256 nusdAmount = 1000e18;
        vm.startPrank(alice);
        uint256 aliceBalanceBefore = nusd.balanceOf(alice);
        
        usdc.approve(address(nusd), 1000e6);
        nusd.mintWithCollateral(address(usdc), 1000e6);
        nusd.cooldownRedeem(address(usdc), nusdAmount);
        
        uint256 aliceBalanceAfterRedeem = nusd.balanceOf(alice);
        assertEq(aliceBalanceAfterRedeem, aliceBalanceBefore, "nUSD locked in silo");
        
        // Cancel redemption
        nusd.cancelRedeem();
        
        // Verify nUSD returned
        assertEq(nusd.balanceOf(alice), aliceBalanceBefore + nusdAmount, "nUSD returned");
        assertEq(nusd.balanceOf(address(nusd.redeemSilo())), 0, "Silo empty");
        
        // Verify request cleared
        (uint104 cooldownEnd, uint152 amount, ) = nusd.redemptionRequests(alice);
        assertEq(cooldownEnd, 0, "Request cleared");
        assertEq(amount, 0, "Amount cleared");
        
        vm.stopPrank();
    }

    /**
     * @notice Test multiple redemption requests fail
     */
    function test_RevertIf_ExistingRedemptionRequest() public {
        vm.startPrank(alice);
        usdc.approve(address(nusd), 2000e6);
        nusd.mintWithCollateral(address(usdc), 2000e6);
        
        // First request
        nusd.cooldownRedeem(address(usdc), 1000e18);
        
        // Second request should fail
        vm.expectRevert(nUSD.ExistingRedemptionRequest.selector);
        nusd.cooldownRedeem(address(usdc), 500e18);
        
        vm.stopPrank();
    }

    /**
     * @notice Test completing redemption without request fails
     */
    function test_RevertIf_NoRedemptionRequest() public {
        vm.startPrank(alice);
        
        vm.expectRevert(nUSD.NoRedemptionRequest.selector);
        nusd.completeRedeem();
        
        vm.stopPrank();
    }

    /**
     * @notice Test cancelling without request fails
     */
    function test_RevertIf_CancelWithoutRequest() public {
        vm.startPrank(alice);
        
        vm.expectRevert(nUSD.NoRedemptionRequest.selector);
        nusd.cancelRedeem();
        
        vm.stopPrank();
    }

    /**
     * @notice Test setting cooldown duration
     */
    function test_SetCooldownDuration() public {
        assertEq(nusd.cooldownDuration(), 7 days, "Initial cooldown");
        
        nusd.setCooldownDuration(14 days);
        
        assertEq(nusd.cooldownDuration(), 14 days, "Updated cooldown");
    }

    /**
     * @notice Test setting cooldown duration above max fails
     */
    function test_RevertIf_CooldownTooLong() public {
        vm.expectRevert(nUSD.InvalidCooldown.selector);
        nusd.setCooldownDuration(91 days); // Max is 90 days
    }

    /**
     * @notice Test rate limiting on minting
     */
    function test_RateLimiting_Mint() public {
        // Set low rate limit for testing
        nusd.setMaxMintPerBlock(1000e18);
        
        vm.startPrank(alice);
        usdc.approve(address(nusd), 2000e6);
        
        // First mint should succeed
        nusd.mintWithCollateral(address(usdc), 500e6); // 500 nUSD
        
        // Second mint in same block should succeed (total 1000)
        nusd.mintWithCollateral(address(usdc), 500e6); // 500 nUSD
        
        // Third mint should fail (total would be 1500, exceeds 1000 limit)
        vm.expectRevert(nUSD.MaxMintPerBlockExceeded.selector);
        nusd.mintWithCollateral(address(usdc), 500e6);
        
        vm.stopPrank();
        
        // Roll to next block - should work again
        vm.roll(block.number + 1);
        
        vm.startPrank(alice);
        nusd.mintWithCollateral(address(usdc), 500e6); // Should succeed
        vm.stopPrank();
    }

    /**
     * @notice Test minting without collateral (admin function)
     */
    function test_MintWithoutCollateral() public {
        uint256 amount = 1000e18;
        
        uint256 bobBalanceBefore = nusd.balanceOf(bob);
        uint256 mctBalanceBefore = mct.balanceOf(address(nusd));
        
        nusd.mint(bob, amount);
        
        assertEq(nusd.balanceOf(bob) - bobBalanceBefore, amount, "Bob should have additional nUSD");
        
        // MCT should also be minted to maintain backing
        assertEq(mct.balanceOf(address(nusd)) - mctBalanceBefore, amount, "MCT minted for backing");
    }

    /**
     * @notice Test burning nUSD
     */
    function test_Burn() public {
        // Setup: Mint nUSD
        vm.startPrank(alice);
        usdc.approve(address(nusd), 1000e6);
        nusd.mintWithCollateral(address(usdc), 1000e6);
        
        uint256 burnAmount = 500e18;
        uint256 aliceNusdBefore = nusd.balanceOf(alice);
        uint256 mctBefore = mct.totalSupply();
        
        // Burn
        nusd.burn(burnAmount);
        
        uint256 aliceNusdAfter = nusd.balanceOf(alice);
        uint256 mctAfter = mct.totalSupply();
        
        // Verify burn
        assertEq(aliceNusdBefore - aliceNusdAfter, burnAmount, "nUSD burned");
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
        nusd.pause();
        
        // Minting should fail
        vm.startPrank(alice);
        usdc.approve(address(nusd), 1000e6);
        
        vm.expectRevert();
        nusd.mintWithCollateral(address(usdc), 1000e6);
        
        vm.stopPrank();
        
        // Unpause
        nusd.unpause();
        
        // Minting should work again
        vm.startPrank(alice);
        uint256 nusdAmount = nusd.mintWithCollateral(address(usdc), 1000e6);
        assertGt(nusdAmount, 0, "Should mint after unpause");
        vm.stopPrank();
    }

    /**
     * @notice Test disable mint and redeem
     */
    function test_DisableMintRedeem() public {
        nusd.disableMintRedeem();
        
        assertEq(nusd.maxMintPerBlock(), 0, "Mint disabled");
        assertEq(nusd.maxRedeemPerBlock(), 0, "Redeem disabled");
        
        // Minting should fail
        vm.startPrank(alice);
        usdc.approve(address(nusd), 1000e6);
        
        vm.expectRevert(nUSD.MaxMintPerBlockExceeded.selector);
        nusd.mintWithCollateral(address(usdc), 1000e6);
        
        vm.stopPrank();
    }

    /**
     * @notice Test delegated signer flow
     */
    function test_DelegatedSigner() public {
        // Alice initiates delegation to Bob
        vm.prank(alice);
        nusd.setDelegatedSigner(bob);
        
        // Verify pending status
        assertEq(
            uint(nusd.delegatedSigner(bob, alice)),
            uint(nUSD.DelegatedSignerStatus.PENDING),
            "Should be pending"
        );
        
        // Bob confirms
        vm.prank(bob);
        nusd.confirmDelegatedSigner(alice);
        
        // Verify accepted status
        assertEq(
            uint(nusd.delegatedSigner(bob, alice)),
            uint(nUSD.DelegatedSignerStatus.ACCEPTED),
            "Should be accepted"
        );
        
        // Alice approves nUSD to spend her USDC
        vm.prank(alice);
        usdc.approve(address(nusd), 1000e6);
        
        // Bob can now mint for Alice using Alice's collateral
        uint256 aliceNusdBefore = nusd.balanceOf(alice);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        
        vm.prank(bob);
        uint256 nusdAmount = nusd.mintWithCollateralFor(address(usdc), 1000e6, alice);
        
        // Verify Alice received nUSD and her USDC was spent
        assertEq(nusd.balanceOf(alice) - aliceNusdBefore, nusdAmount, "Alice should have additional nUSD");
        assertEq(aliceUsdcBefore - usdc.balanceOf(alice), 1000e6, "Alice's USDC was spent");
        
        vm.stopPrank();
    }

    /**
     * @notice Test removing delegated signer
     */
    function test_RemoveDelegatedSigner() public {
        // Setup delegation
        vm.prank(alice);
        nusd.setDelegatedSigner(bob);
        
        vm.prank(bob);
        nusd.confirmDelegatedSigner(alice);
        
        // Remove delegation
        vm.prank(alice);
        nusd.removeDelegatedSigner(bob);
        
        assertEq(
            uint(nusd.delegatedSigner(bob, alice)),
            uint(nUSD.DelegatedSignerStatus.REJECTED),
            "Should be rejected"
        );
        
        // Bob can no longer mint for Alice
        vm.startPrank(bob);
        usdc.mint(bob, 1000e6);
        usdc.approve(address(nusd), 1000e6);
        
        vm.expectRevert(nUSD.InvalidSignature.selector);
        nusd.mintWithCollateralFor(address(usdc), 1000e6, alice);
        
        vm.stopPrank();
    }

    /**
     * @notice Test minting with unsupported collateral fails
     */
    function test_RevertIf_UnsupportedCollateral() public {
        MockERC20 unsupported = new MockERC20("Unsupported", "UNSUP", 6);
        unsupported.mint(alice, 1000e6);
        
        vm.startPrank(alice);
        unsupported.approve(address(nusd), 1000e6);
        
        vm.expectRevert(nUSD.UnsupportedAsset.selector);
        nusd.mintWithCollateral(address(unsupported), 1000e6);
        
        vm.stopPrank();
    }

    /**
     * @notice Test minting zero amount fails
     */
    function test_RevertIf_MintZeroAmount() public {
        vm.startPrank(alice);
        usdc.approve(address(nusd), 1000e6);
        
        vm.expectRevert(nUSD.InvalidAmount.selector);
        nusd.mintWithCollateral(address(usdc), 0);
        
        vm.stopPrank();
    }

    /**
     * @notice Test redeeming zero amount fails
     */
    function test_RevertIf_RedeemZeroAmount() public {
        vm.startPrank(alice);
        
        vm.expectRevert(nUSD.InvalidAmount.selector);
        nusd.cooldownRedeem(address(usdc), 0);
        
        vm.stopPrank();
    }

    /**
     * @notice Test standard ERC4626 withdraw/redeem are disabled
     */
    function test_RevertIf_UseStandardWithdraw() public {
        // Mint some nUSD
        vm.startPrank(alice);
        usdc.approve(address(nusd), 1000e6);
        nusd.mintWithCollateral(address(usdc), 1000e6);
        
        // Standard withdraw should revert
        vm.expectRevert("Use cooldownRedeem");
        nusd.withdraw(100e18, alice, alice);
        
        // Standard redeem should revert
        vm.expectRevert("Use cooldownRedeem");
        nusd.redeem(100e18, alice, alice);
        
        vm.stopPrank();
    }

    /**
     * @notice Test full redemption cycle with different collateral
     */
    function test_RedemptionCycle_USDT() public {
        // Mint with USDT
        vm.startPrank(alice);
        uint256 aliceUsdtBefore = usdt.balanceOf(alice);
        
        usdt.approve(address(nusd), 1000e6);
        nusd.mintWithCollateral(address(usdt), 1000e6);
        
        // Redeem
        nusd.cooldownRedeem(address(usdt), 1000e18);
        
        // Verify correct collateral tracked
        (, , address collateral) = nusd.redemptionRequests(alice);
        assertEq(collateral, address(usdt), "Should be USDT");
        
        // Complete
        vm.warp(block.timestamp + 7 days);
        uint256 collateralReceived = nusd.completeRedeem();
        
        assertEq(collateralReceived, 1000e6, "Should receive 1000 USDT");
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
        usdc.approve(address(nusd), amount);
        
        uint256 expectedNusd = amount * 1e12; // 6 to 18 decimals
        uint256 nusdAmount = nusd.mintWithCollateral(address(usdc), amount);
        
        assertEq(nusdAmount, expectedNusd, "Should mint correct amount");
        
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
        usdc.approve(address(nusd), amount);
        uint256 nusdAmount = nusd.mintWithCollateral(address(usdc), amount);
        
        // Redeem
        nusd.cooldownRedeem(address(usdc), nusdAmount);
        
        vm.warp(block.timestamp + 7 days);
        
        uint256 collateralReceived = nusd.completeRedeem();
        
        assertEq(collateralReceived, amount, "Should receive same amount back");
        
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
        emit nUSD.MintFeeUpdated(0, 50);
        nusd.setMintFee(50);
        
        assertEq(nusd.mintFeeBps(), 50, "Mint fee should be 50 bps");
    }

    /**
     * @notice Test setting redeem fee
     */
    function test_SetRedeemFee() public {
        // Note: address(this) is the admin in TestHelper setup
        
        // Set 0.3% redeem fee (30 bps)
        vm.expectEmit(true, true, true, true);
        emit nUSD.RedeemFeeUpdated(0, 30);
        nusd.setRedeemFee(30);
        
        assertEq(nusd.redeemFeeBps(), 30, "Redeem fee should be 30 bps");
    }

    /**
     * @notice Test setting fee treasury
     */
    function test_SetFeeTreasury() public {
        address treasury = makeAddr("treasury");
        
        // Note: address(this) is the admin in TestHelper setup
        
        vm.expectEmit(true, true, true, true);
        emit nUSD.FeeTreasuryUpdated(address(0), treasury);
        nusd.setFeeTreasury(treasury);
        
        assertEq(nusd.feeTreasury(), treasury, "Treasury should be set");
    }

    /**
     * @notice Test minting with fee
     */
    function test_MintWithFee() public {
        address treasury = makeAddr("treasury");
        
        // Setup fees (address(this) is admin)
        nusd.setMintFee(50); // 0.5%
        nusd.setFeeTreasury(treasury);
        
        uint256 usdcAmount = 1000e6;
        uint256 expectedTotal = 1000e18;
        uint256 expectedFee = (expectedTotal * 50) / 10000; // 0.5%
        uint256 expectedUserAmount = expectedTotal - expectedFee;
        
        vm.startPrank(alice);
        uint256 aliceBalanceBefore = nusd.balanceOf(alice);
        usdc.approve(address(nusd), usdcAmount);
        
        uint256 nusdAmount = nusd.mintWithCollateral(address(usdc), usdcAmount);
        
        // Verify user receives amount after fee
        assertEq(nusdAmount, expectedUserAmount, "User should receive amount after fee");
        assertEq(nusd.balanceOf(alice) - aliceBalanceBefore, expectedUserAmount, "Alice balance should be after fee");
        
        // Verify treasury receives fee
        assertEq(nusd.balanceOf(treasury), expectedFee, "Treasury should receive fee");
        
        vm.stopPrank();
    }

    /**
     * @notice Test redeeming with fee
     */
    function test_RedeemWithFee() public {
        address treasury = makeAddr("treasury");
        
        // Setup: Mint nUSD first (no fee)
        vm.startPrank(alice);
        uint256 usdcAmount = 1000e6;
        usdc.approve(address(nusd), usdcAmount);
        nusd.mintWithCollateral(address(usdc), usdcAmount);
        uint256 nusdAmount = 1000e18;
        vm.stopPrank();
        
        // Set redeem fee (address(this) is admin)
        nusd.setRedeemFee(30); // 0.3%
        nusd.setFeeTreasury(treasury);
        
        // Redeem with fee
        vm.startPrank(alice);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        
        nusd.cooldownRedeem(address(usdc), nusdAmount);
        vm.warp(block.timestamp + 7 days);
        
        uint256 collateralReceived = nusd.completeRedeem();
        
        // Calculate expected amounts
        uint256 expectedCollateralTotal = 1000e6;
        uint256 expectedFee = (expectedCollateralTotal * 30) / 10000; // 0.3%
        uint256 expectedUserCollateral = expectedCollateralTotal - expectedFee;
        
        // Verify user receives collateral after fee
        assertEq(collateralReceived, expectedUserCollateral, "User should receive collateral after fee");
        assertEq(usdc.balanceOf(alice) - aliceUsdcBefore, expectedUserCollateral, "Alice USDC increased by after-fee amount");
        
        // Verify treasury receives fee
        assertEq(usdc.balanceOf(treasury), expectedFee, "Treasury should receive fee in collateral");
        
        vm.stopPrank();
    }

    /**
     * @notice Test minting with fee disabled (zero fee)
     */
    function test_MintWithZeroFee() public {
        address treasury = makeAddr("treasury");
        
        // Setup (address(this) is admin)
        nusd.setMintFee(0); // No fee
        nusd.setFeeTreasury(treasury);
        
        uint256 usdcAmount = 1000e6;
        uint256 expectedNusd = 1000e18;
        
        vm.startPrank(alice);
        uint256 aliceBalanceBefore = nusd.balanceOf(alice);
        usdc.approve(address(nusd), usdcAmount);
        
        uint256 nusdAmount = nusd.mintWithCollateral(address(usdc), usdcAmount);
        
        // Verify user receives full amount
        assertEq(nusdAmount, expectedNusd, "User should receive full amount");
        assertEq(nusd.balanceOf(alice) - aliceBalanceBefore, expectedNusd, "Alice balance increase should be full amount");
        
        // Verify treasury receives nothing
        assertEq(nusd.balanceOf(treasury), 0, "Treasury should receive no fee");
        
        vm.stopPrank();
    }

    /**
     * @notice Test setting fee above maximum reverts
     */
    function test_RevertIf_SetFeeAboveMax() public {
        // Note: address(this) is the admin in TestHelper setup
        
        // Try to set 11% fee (1100 bps, max is 1000)
        vm.expectRevert(nUSD.InvalidFee.selector);
        nusd.setMintFee(1100);
        
        vm.expectRevert(nUSD.InvalidFee.selector);
        nusd.setRedeemFee(1100);
    }

    /**
     * @notice Test non-admin cannot set fees
     */
    function test_RevertIf_NonAdminSetsFee() public {
        vm.startPrank(alice);
        
        vm.expectRevert();
        nusd.setMintFee(50);
        
        vm.expectRevert();
        nusd.setRedeemFee(50);
        
        vm.stopPrank();
    }

    /**
     * @notice Test setting zero address as treasury reverts
     */
    function test_RevertIf_SetZeroAddressTreasury() public {
        // Note: address(this) is the admin in TestHelper setup
        
        vm.expectRevert(nUSD.ZeroAddressException.selector);
        nusd.setFeeTreasury(address(0));
    }

    /**
     * @notice Test minting with fee but no treasury set (fee not collected)
     */
    function test_MintWithFeeNoTreasury() public {
        // Setup (address(this) is admin)
        nusd.setMintFee(50); // 0.5% fee
        // Don't set treasury
        
        uint256 usdcAmount = 1000e6;
        uint256 expectedNusd = 1000e18; // Full amount since treasury not set
        
        vm.startPrank(alice);
        usdc.approve(address(nusd), usdcAmount);
        
        uint256 nusdAmount = nusd.mintWithCollateral(address(usdc), usdcAmount);
        
        // Verify user receives full amount when treasury not set
        assertEq(nusdAmount, expectedNusd, "User should receive full amount without treasury");
        
        vm.stopPrank();
    }

    /**
     * @notice Fuzz test minting with various fee amounts
     */
    function testFuzz_MintWithFee(uint256 amount, uint16 feeBps) public {
        amount = bound(amount, 1e6, 100_000e6);
        feeBps = uint16(bound(feeBps, 1, 1000)); // 0.01% to 10%
        
        address treasury = makeAddr("treasury");
        
        // Setup (address(this) is admin)
        nusd.setMintFee(feeBps);
        nusd.setFeeTreasury(treasury);
        
        vm.startPrank(alice);
        usdc.mint(alice, amount);
        usdc.approve(address(nusd), amount);
        
        uint256 expectedTotal = amount * 1e12; // Convert to 18 decimals
        uint256 expectedFee = (expectedTotal * feeBps) / 10000;
        uint256 expectedUserAmount = expectedTotal - expectedFee;
        
        uint256 nusdAmount = nusd.mintWithCollateral(address(usdc), amount);
        
        assertEq(nusdAmount, expectedUserAmount, "User amount incorrect");
        assertEq(nusd.balanceOf(treasury), expectedFee, "Treasury fee incorrect");
        
        vm.stopPrank();
    }
}


