// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { USDe } from "../../contracts/usde/USDe.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

/**
 * @title USDeTest
 * @notice Unit tests for USDe core functionality
 */
contract USDeTest is TestHelper {
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
        assertEq(usde.name(), "USDe");
        assertEq(usde.symbol(), "USDe");
        assertEq(usde.decimals(), 18);
        assertEq(address(usde.mct()), address(mct));
        assertEq(usde.cooldownDuration(), 7 days);
    }

    /**
     * @notice Test minting USDe with USDC
     */
    function test_MintWithCollateral_USDC() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedUsde = 1000e18;
        
        vm.startPrank(alice);
        usdc.approve(address(usde), usdcAmount);
        
        uint256 aliceUsdeBefore = usde.balanceOf(alice);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 usdeContractMctBefore = mct.balanceOf(address(usde));
        
        uint256 usdeAmount = usde.mintWithCollateral(address(usdc), usdcAmount);
        uint256 aliceUsdcAfter = usdc.balanceOf(alice);
        
        // Verify USDe minted
        assertEq(usdeAmount, expectedUsde, "Should mint 1000 USDe");
        assertEq(usde.balanceOf(alice) - aliceUsdeBefore, expectedUsde, "Alice should have additional USDe");
        
        // Verify USDC transferred
        assertEq(aliceUsdcBefore - aliceUsdcAfter, usdcAmount, "USDC transferred");
        
        // Verify MCT created (held by USDe contract)
        assertEq(mct.balanceOf(address(usde)) - usdeContractMctBefore, expectedUsde, "USDe holds additional MCT");
        
        vm.stopPrank();
    }

    /**
     * @notice Test minting USDe with USDT
     */
    function test_MintWithCollateral_USDT() public {
        uint256 usdtAmount = 500e6;
        uint256 expectedUsde = 500e18;
        
        vm.startPrank(alice);
        usdt.approve(address(usde), usdtAmount);
        
        uint256 aliceUsdeBefore = usde.balanceOf(alice);
        uint256 usdeAmount = usde.mintWithCollateral(address(usdt), usdtAmount);
        
        assertEq(usdeAmount, expectedUsde, "Should mint 500 USDe");
        assertEq(usde.balanceOf(alice) - aliceUsdeBefore, expectedUsde, "Alice should have additional USDe");
        
        vm.stopPrank();
    }

    /**
     * @notice Test cooldown redemption flow
     */
    function test_CooldownRedemption_Complete() public {
        // Setup: Mint USDe
        uint256 usdeAmount = 1000e18;
        vm.startPrank(alice);
        uint256 aliceUsdeBefore = usde.balanceOf(alice);
        usdc.approve(address(usde), 1000e6);
        usde.mintWithCollateral(address(usdc), 1000e6);
        
        // Step 1: Request redemption
        usde.cooldownRedeem(address(usdc), usdeAmount);
        
        // Verify redemption request
        (uint104 cooldownEnd, uint152 lockedAmount, address collateral) = 
            usde.redemptionRequests(alice);
        
        assertEq(lockedAmount, usdeAmount, "Amount should be locked");
        assertEq(collateral, address(usdc), "Collateral should be USDC");
        assertEq(cooldownEnd, block.timestamp + 7 days, "Cooldown should be 7 days");
        
        // Verify USDe is in silo (alice balance should be same as before mint)
        assertEq(usde.balanceOf(alice), aliceUsdeBefore, "Alice USDe should be in silo");
        assertEq(usde.balanceOf(address(usde.redeemSilo())), usdeAmount, "USDe in silo");
        
        // Step 2: Try to complete too early (should fail)
        vm.expectRevert(USDe.CooldownNotFinished.selector);
        usde.completeRedeem();
        
        // Step 3: Fast forward time
        vm.warp(cooldownEnd);
        
        // Step 4: Complete redemption
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 collateralReceived = usde.completeRedeem();
        uint256 aliceUsdcAfter = usdc.balanceOf(alice);
        
        // Verify redemption completed
        assertEq(collateralReceived, 1000e6, "Should receive 1000 USDC");
        assertEq(aliceUsdcAfter - aliceUsdcBefore, 1000e6, "USDC received");
        assertEq(usde.balanceOf(alice), aliceUsdeBefore, "USDe burned, balance back to initial");
        
        // Verify request cleared
        (uint104 endAfter, uint152 amountAfter, ) = usde.redemptionRequests(alice);
        assertEq(endAfter, 0, "Request cleared");
        assertEq(amountAfter, 0, "Amount cleared");
        
        vm.stopPrank();
    }

    /**
     * @notice Test cancelling redemption request
     */
    function test_CancelRedemption() public {
        // Setup: Mint and request redemption
        uint256 usdeAmount = 1000e18;
        vm.startPrank(alice);
        uint256 aliceBalanceBefore = usde.balanceOf(alice);
        
        usdc.approve(address(usde), 1000e6);
        usde.mintWithCollateral(address(usdc), 1000e6);
        usde.cooldownRedeem(address(usdc), usdeAmount);
        
        uint256 aliceBalanceAfterRedeem = usde.balanceOf(alice);
        assertEq(aliceBalanceAfterRedeem, aliceBalanceBefore, "USDe locked in silo");
        
        // Cancel redemption
        usde.cancelRedeem();
        
        // Verify USDe returned
        assertEq(usde.balanceOf(alice), aliceBalanceBefore + usdeAmount, "USDe returned");
        assertEq(usde.balanceOf(address(usde.redeemSilo())), 0, "Silo empty");
        
        // Verify request cleared
        (uint104 cooldownEnd, uint152 amount, ) = usde.redemptionRequests(alice);
        assertEq(cooldownEnd, 0, "Request cleared");
        assertEq(amount, 0, "Amount cleared");
        
        vm.stopPrank();
    }

    /**
     * @notice Test multiple redemption requests fail
     */
    function test_RevertIf_ExistingRedemptionRequest() public {
        vm.startPrank(alice);
        usdc.approve(address(usde), 2000e6);
        usde.mintWithCollateral(address(usdc), 2000e6);
        
        // First request
        usde.cooldownRedeem(address(usdc), 1000e18);
        
        // Second request should fail
        vm.expectRevert(USDe.ExistingRedemptionRequest.selector);
        usde.cooldownRedeem(address(usdc), 500e18);
        
        vm.stopPrank();
    }

    /**
     * @notice Test completing redemption without request fails
     */
    function test_RevertIf_NoRedemptionRequest() public {
        vm.startPrank(alice);
        
        vm.expectRevert(USDe.NoRedemptionRequest.selector);
        usde.completeRedeem();
        
        vm.stopPrank();
    }

    /**
     * @notice Test cancelling without request fails
     */
    function test_RevertIf_CancelWithoutRequest() public {
        vm.startPrank(alice);
        
        vm.expectRevert(USDe.NoRedemptionRequest.selector);
        usde.cancelRedeem();
        
        vm.stopPrank();
    }

    /**
     * @notice Test setting cooldown duration
     */
    function test_SetCooldownDuration() public {
        assertEq(usde.cooldownDuration(), 7 days, "Initial cooldown");
        
        usde.setCooldownDuration(14 days);
        
        assertEq(usde.cooldownDuration(), 14 days, "Updated cooldown");
    }

    /**
     * @notice Test setting cooldown duration above max fails
     */
    function test_RevertIf_CooldownTooLong() public {
        vm.expectRevert(USDe.InvalidCooldown.selector);
        usde.setCooldownDuration(91 days); // Max is 90 days
    }

    /**
     * @notice Test rate limiting on minting
     */
    function test_RateLimiting_Mint() public {
        // Set low rate limit for testing
        usde.setMaxMintPerBlock(1000e18);
        
        vm.startPrank(alice);
        usdc.approve(address(usde), 2000e6);
        
        // First mint should succeed
        usde.mintWithCollateral(address(usdc), 500e6); // 500 USDe
        
        // Second mint in same block should succeed (total 1000)
        usde.mintWithCollateral(address(usdc), 500e6); // 500 USDe
        
        // Third mint should fail (total would be 1500, exceeds 1000 limit)
        vm.expectRevert(USDe.MaxMintPerBlockExceeded.selector);
        usde.mintWithCollateral(address(usdc), 500e6);
        
        vm.stopPrank();
        
        // Roll to next block - should work again
        vm.roll(block.number + 1);
        
        vm.startPrank(alice);
        usde.mintWithCollateral(address(usdc), 500e6); // Should succeed
        vm.stopPrank();
    }

    /**
     * @notice Test minting without collateral (admin function)
     */
    function test_MintWithoutCollateral() public {
        uint256 amount = 1000e18;
        
        uint256 bobBalanceBefore = usde.balanceOf(bob);
        uint256 mctBalanceBefore = mct.balanceOf(address(usde));
        
        usde.mint(bob, amount);
        
        assertEq(usde.balanceOf(bob) - bobBalanceBefore, amount, "Bob should have additional USDe");
        
        // MCT should also be minted to maintain backing
        assertEq(mct.balanceOf(address(usde)) - mctBalanceBefore, amount, "MCT minted for backing");
    }

    /**
     * @notice Test burning USDe
     */
    function test_Burn() public {
        // Setup: Mint USDe
        vm.startPrank(alice);
        usdc.approve(address(usde), 1000e6);
        usde.mintWithCollateral(address(usdc), 1000e6);
        
        uint256 burnAmount = 500e18;
        uint256 aliceUsdeBefore = usde.balanceOf(alice);
        uint256 mctBefore = mct.totalSupply();
        
        // Burn
        usde.burn(burnAmount);
        
        uint256 aliceUsdeAfter = usde.balanceOf(alice);
        uint256 mctAfter = mct.totalSupply();
        
        // Verify burn
        assertEq(aliceUsdeBefore - aliceUsdeAfter, burnAmount, "USDe burned");
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
        usde.pause();
        
        // Minting should fail
        vm.startPrank(alice);
        usdc.approve(address(usde), 1000e6);
        
        vm.expectRevert();
        usde.mintWithCollateral(address(usdc), 1000e6);
        
        vm.stopPrank();
        
        // Unpause
        usde.unpause();
        
        // Minting should work again
        vm.startPrank(alice);
        uint256 usdeAmount = usde.mintWithCollateral(address(usdc), 1000e6);
        assertGt(usdeAmount, 0, "Should mint after unpause");
        vm.stopPrank();
    }

    /**
     * @notice Test disable mint and redeem
     */
    function test_DisableMintRedeem() public {
        usde.disableMintRedeem();
        
        assertEq(usde.maxMintPerBlock(), 0, "Mint disabled");
        assertEq(usde.maxRedeemPerBlock(), 0, "Redeem disabled");
        
        // Minting should fail
        vm.startPrank(alice);
        usdc.approve(address(usde), 1000e6);
        
        vm.expectRevert(USDe.MaxMintPerBlockExceeded.selector);
        usde.mintWithCollateral(address(usdc), 1000e6);
        
        vm.stopPrank();
    }

    /**
     * @notice Test delegated signer flow
     */
    function test_DelegatedSigner() public {
        // Alice initiates delegation to Bob
        vm.prank(alice);
        usde.setDelegatedSigner(bob);
        
        // Verify pending status
        assertEq(
            uint(usde.delegatedSigner(bob, alice)),
            uint(USDe.DelegatedSignerStatus.PENDING),
            "Should be pending"
        );
        
        // Bob confirms
        vm.prank(bob);
        usde.confirmDelegatedSigner(alice);
        
        // Verify accepted status
        assertEq(
            uint(usde.delegatedSigner(bob, alice)),
            uint(USDe.DelegatedSignerStatus.ACCEPTED),
            "Should be accepted"
        );
        
        // Alice approves USDe to spend her USDC
        vm.prank(alice);
        usdc.approve(address(usde), 1000e6);
        
        // Bob can now mint for Alice using Alice's collateral
        uint256 aliceUsdeBefore = usde.balanceOf(alice);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        
        vm.prank(bob);
        uint256 usdeAmount = usde.mintWithCollateralFor(address(usdc), 1000e6, alice);
        
        // Verify Alice received USDe and her USDC was spent
        assertEq(usde.balanceOf(alice) - aliceUsdeBefore, usdeAmount, "Alice should have additional USDe");
        assertEq(aliceUsdcBefore - usdc.balanceOf(alice), 1000e6, "Alice's USDC was spent");
        
        vm.stopPrank();
    }

    /**
     * @notice Test removing delegated signer
     */
    function test_RemoveDelegatedSigner() public {
        // Setup delegation
        vm.prank(alice);
        usde.setDelegatedSigner(bob);
        
        vm.prank(bob);
        usde.confirmDelegatedSigner(alice);
        
        // Remove delegation
        vm.prank(alice);
        usde.removeDelegatedSigner(bob);
        
        assertEq(
            uint(usde.delegatedSigner(bob, alice)),
            uint(USDe.DelegatedSignerStatus.REJECTED),
            "Should be rejected"
        );
        
        // Bob can no longer mint for Alice
        vm.startPrank(bob);
        usdc.mint(bob, 1000e6);
        usdc.approve(address(usde), 1000e6);
        
        vm.expectRevert(USDe.InvalidSignature.selector);
        usde.mintWithCollateralFor(address(usdc), 1000e6, alice);
        
        vm.stopPrank();
    }

    /**
     * @notice Test minting with unsupported collateral fails
     */
    function test_RevertIf_UnsupportedCollateral() public {
        MockERC20 unsupported = new MockERC20("Unsupported", "UNSUP", 6);
        unsupported.mint(alice, 1000e6);
        
        vm.startPrank(alice);
        unsupported.approve(address(usde), 1000e6);
        
        vm.expectRevert(USDe.UnsupportedAsset.selector);
        usde.mintWithCollateral(address(unsupported), 1000e6);
        
        vm.stopPrank();
    }

    /**
     * @notice Test minting zero amount fails
     */
    function test_RevertIf_MintZeroAmount() public {
        vm.startPrank(alice);
        usdc.approve(address(usde), 1000e6);
        
        vm.expectRevert(USDe.InvalidAmount.selector);
        usde.mintWithCollateral(address(usdc), 0);
        
        vm.stopPrank();
    }

    /**
     * @notice Test redeeming zero amount fails
     */
    function test_RevertIf_RedeemZeroAmount() public {
        vm.startPrank(alice);
        
        vm.expectRevert(USDe.InvalidAmount.selector);
        usde.cooldownRedeem(address(usdc), 0);
        
        vm.stopPrank();
    }

    /**
     * @notice Test standard ERC4626 withdraw/redeem are disabled
     */
    function test_RevertIf_UseStandardWithdraw() public {
        // Mint some USDe
        vm.startPrank(alice);
        usdc.approve(address(usde), 1000e6);
        usde.mintWithCollateral(address(usdc), 1000e6);
        
        // Standard withdraw should revert
        vm.expectRevert("Use cooldownRedeem");
        usde.withdraw(100e18, alice, alice);
        
        // Standard redeem should revert
        vm.expectRevert("Use cooldownRedeem");
        usde.redeem(100e18, alice, alice);
        
        vm.stopPrank();
    }

    /**
     * @notice Test full redemption cycle with different collateral
     */
    function test_RedemptionCycle_USDT() public {
        // Mint with USDT
        vm.startPrank(alice);
        uint256 aliceUsdtBefore = usdt.balanceOf(alice);
        
        usdt.approve(address(usde), 1000e6);
        usde.mintWithCollateral(address(usdt), 1000e6);
        
        // Redeem
        usde.cooldownRedeem(address(usdt), 1000e18);
        
        // Verify correct collateral tracked
        (, , address collateral) = usde.redemptionRequests(alice);
        assertEq(collateral, address(usdt), "Should be USDT");
        
        // Complete
        vm.warp(block.timestamp + 7 days);
        uint256 collateralReceived = usde.completeRedeem();
        
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
        usdc.approve(address(usde), amount);
        
        uint256 expectedUsde = amount * 1e12; // 6 to 18 decimals
        uint256 usdeAmount = usde.mintWithCollateral(address(usdc), amount);
        
        assertEq(usdeAmount, expectedUsde, "Should mint correct amount");
        
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
        usdc.approve(address(usde), amount);
        uint256 usdeAmount = usde.mintWithCollateral(address(usdc), amount);
        
        // Redeem
        usde.cooldownRedeem(address(usdc), usdeAmount);
        
        vm.warp(block.timestamp + 7 days);
        
        uint256 collateralReceived = usde.completeRedeem();
        
        assertEq(collateralReceived, amount, "Should receive same amount back");
        
        vm.stopPrank();
    }
}


