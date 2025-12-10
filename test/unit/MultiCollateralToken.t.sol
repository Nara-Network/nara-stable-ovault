// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { MultiCollateralToken } from "../../contracts/mct/MultiCollateralToken.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MultiCollateralTokenTest
 * @notice Unit tests for MCT core functionality
 */
contract MultiCollateralTokenTest is TestHelper {
    MockERC20 public dai;

    function setUp() public override {
        super.setUp();

        // Create additional collateral for testing
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);

        // Fund test contract with collateral (test contract has MINTER_ROLE)
        usdc.mint(address(this), 100_000e6);
        usdt.mint(address(this), 100_000e6);
        dai.mint(address(this), 100_000e18);
    }

    /**
     * @notice Helper function to mint MCT (test contract has MINTER_ROLE)
     */
    function _mintMct(address collateral, uint256 amount, address beneficiary) internal returns (uint256) {
        IERC20(collateral).approve(address(mct), amount);
        return mct.mint(collateral, amount, beneficiary);
    }

    /**
     * @notice Test basic setup
     */
    function test_Setup() public {
        assertEq(mct.name(), "MultiCollateralToken");
        assertEq(mct.symbol(), "MCT");
        assertEq(mct.decimals(), 18);
        assertTrue(mct.isSupportedAsset(address(usdc)));
        assertTrue(mct.isSupportedAsset(address(usdt)));
    }

    /**
     * @notice Test minting MCT with USDC (6 decimals)
     */
    function test_MintWithUSDC() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedMct = 1000e18;

        uint256 bobBalanceBefore = mct.balanceOf(bob);
        uint256 mctAmount = _mintMct(address(usdc), usdcAmount, bob);

        assertEq(mctAmount, expectedMct, "Should mint 1000 MCT");
        assertEq(mct.balanceOf(bob) - bobBalanceBefore, expectedMct, "Bob should have additional MCT");
        assertEq(mct.collateralBalance(address(usdc)), usdcAmount, "Collateral balance tracked");
    }

    /**
     * @notice Test minting MCT with USDT (6 decimals)
     */
    function test_MintWithUSDT() public {
        uint256 usdtAmount = 500e6;
        uint256 expectedMct = 500e18;

        uint256 bobBalanceBefore = mct.balanceOf(bob);
        uint256 mctAmount = _mintMct(address(usdt), usdtAmount, bob);

        assertEq(mctAmount, expectedMct, "Should mint 500 MCT");
        assertEq(mct.balanceOf(bob) - bobBalanceBefore, expectedMct, "Bob should have additional MCT");
        assertEq(mct.collateralBalance(address(usdt)), usdtAmount, "USDT collateral tracked");
    }

    /**
     * @notice Test decimal normalization for 6 decimal tokens
     */
    function test_DecimalNormalization_6Decimals() public {
        uint256 usdcAmount = 12345e6; // 12,345 USDC
        uint256 expectedMct = 12345e18;

        uint256 mctAmount = _mintMct(address(usdc), usdcAmount, bob);

        assertEq(mctAmount, expectedMct, "Decimal conversion should be exact");
    }

    /**
     * @notice Test decimal normalization for 18 decimal tokens
     */
    function test_DecimalNormalization_18Decimals() public {
        // Add DAI as supported asset
        mct.addSupportedAsset(address(dai));

        uint256 daiAmount = 1000e18;
        uint256 expectedMct = 1000e18;

        uint256 mctAmount = _mintMct(address(dai), daiAmount, bob);

        assertEq(mctAmount, expectedMct, "18 decimal should not convert");
    }

    /**
     * @notice Test redeeming MCT for USDC
     */
    function test_RedeemForUSDC() public {
        // First mint MCT
        uint256 usdcAmount = 1000e6;
        uint256 mctAmount = _mintMct(address(usdc), usdcAmount, alice);

        // Redeem (transfer MCT to naraUSD which has MINTER_ROLE to redeem)
        vm.startPrank(alice);
        mct.transfer(address(naraUSD), mctAmount);
        vm.stopPrank();

        // naraUSD redeems
        vm.startPrank(address(naraUSD));
        mct.approve(address(mct), mctAmount);

        uint256 collateralReceived = mct.redeem(address(usdc), mctAmount, bob);

        assertEq(collateralReceived, usdcAmount, "Should receive 1000 USDC");
        assertEq(mct.collateralBalance(address(usdc)), 0, "Collateral balance should be 0");
        vm.stopPrank();
    }

    /**
     * @notice Test multiple deposits with same collateral
     */
    function test_MultipleDeposits() public {
        uint256 bobBalanceBefore = mct.balanceOf(bob);

        // First deposit
        uint256 mct1 = _mintMct(address(usdc), 1000e6, bob);
        assertEq(mct1, 1000e18, "First mint");
        assertEq(mct.collateralBalance(address(usdc)), 1000e6, "Collateral after 1st");

        // Second deposit
        uint256 mct2 = _mintMct(address(usdc), 2000e6, bob);
        assertEq(mct2, 2000e18, "Second mint");
        assertEq(mct.collateralBalance(address(usdc)), 3000e6, "Collateral after 2nd");

        assertEq(mct.balanceOf(bob) - bobBalanceBefore, 3000e18, "Total MCT minted");
    }

    /**
     * @notice Test multiple collateral types simultaneously
     */
    function test_MultipleCollateralTypes() public {
        uint256 bobBalanceBefore = mct.balanceOf(bob);

        // Mint with USDC
        _mintMct(address(usdc), 1000e6, bob);

        // Mint with USDT
        _mintMct(address(usdt), 500e6, bob);

        // Check balances
        assertEq(mct.collateralBalance(address(usdc)), 1000e6, "USDC collateral");
        assertEq(mct.collateralBalance(address(usdt)), 500e6, "USDT collateral");
        assertEq(mct.balanceOf(bob) - bobBalanceBefore, 1500e18, "Total MCT minted");
    }

    /**
     * @notice Test unbacked minting (admin function)
     */
    function test_MintWithoutCollateral() public {
        uint256 amount = 1000e18;
        uint256 bobBalanceBefore = mct.balanceOf(bob);

        // Test contract has MINTER_ROLE
        mct.mintWithoutCollateral(bob, amount);

        assertEq(mct.balanceOf(bob) - bobBalanceBefore, amount, "Bob should have MCT");
        // No collateral should be tracked
        assertEq(mct.collateralBalance(address(usdc)), 0, "No USDC collateral");
    }

    /**
     * @notice Test collateral withdrawal by manager
     */
    function test_WithdrawCollateral() public {
        // Setup: Mint MCT with collateral
        _mintMct(address(usdc), 1000e6, bob);

        // Withdraw collateral (for yield strategies)
        uint256 withdrawAmount = 500e6;
        uint256 ownerUsdcBefore = usdc.balanceOf(owner);

        mct.withdrawCollateral(address(usdc), withdrawAmount, owner);

        uint256 ownerUsdcAfter = usdc.balanceOf(owner);

        assertEq(ownerUsdcAfter - ownerUsdcBefore, withdrawAmount, "Owner received USDC");
        assertEq(mct.collateralBalance(address(usdc)), 500e6, "Collateral balance reduced");
    }

    /**
     * @notice Test depositing collateral back
     */
    function test_DepositCollateral() public {
        // Setup: Mint and withdraw
        _mintMct(address(usdc), 1000e6, bob);
        mct.withdrawCollateral(address(usdc), 500e6, address(this));

        // Deposit back (e.g., after earning yield) - test contract has COLLATERAL_MANAGER_ROLE
        usdc.approve(address(mct), 600e6);
        mct.depositCollateral(address(usdc), 600e6);

        assertEq(mct.collateralBalance(address(usdc)), 1100e6, "Collateral increased");
    }

    /**
     * @notice Test adding supported asset
     */
    function test_AddSupportedAsset() public {
        assertFalse(mct.isSupportedAsset(address(dai)), "DAI not supported initially");

        mct.addSupportedAsset(address(dai));

        assertTrue(mct.isSupportedAsset(address(dai)), "DAI should be supported");

        // Verify we can mint with it
        uint256 mctAmount = _mintMct(address(dai), 1000e18, bob);
        assertEq(mctAmount, 1000e18, "Should mint with DAI");
    }

    /**
     * @notice Test removing supported asset
     */
    function test_RemoveSupportedAsset() public {
        assertTrue(mct.isSupportedAsset(address(usdc)), "USDC supported initially");

        mct.removeSupportedAsset(address(usdc));

        assertFalse(mct.isSupportedAsset(address(usdc)), "USDC should not be supported");
    }

    /**
     * @notice Test getSupportedAssets
     */
    function test_GetSupportedAssets() public {
        address[] memory assets = mct.getSupportedAssets();

        assertEq(assets.length, 2, "Should have 2 assets");
        assertEq(assets[0], address(usdc), "First asset should be USDC");
        assertEq(assets[1], address(usdt), "Second asset should be USDT");
    }

    /**
     * @notice Test minting with zero amount reverts
     */
    function test_RevertIf_ZeroAmount() public {
        usdc.approve(address(mct), 1000e6);

        vm.expectRevert(MultiCollateralToken.InvalidAmount.selector);
        mct.mint(address(usdc), 0, bob);
    }

    /**
     * @notice Test redeeming more than collateral balance reverts
     */
    function test_RevertIf_InsufficientCollateral() public {
        // Mint with 1000 USDC
        _mintMct(address(usdc), 1000e6, bob);

        // Try to redeem 2000 MCT (more than available collateral)
        vm.startPrank(address(naraUSD));
        mct.mintWithoutCollateral(address(naraUSD), 1000e18); // Extra unbacked MCT
        mct.approve(address(mct), 2000e18);

        vm.expectRevert(MultiCollateralToken.InsufficientCollateral.selector);
        mct.redeem(address(usdc), 2000e18, bob);

        vm.stopPrank();
    }

    /**
     * @notice Test withdrawing more than balance reverts
     */
    function test_RevertIf_WithdrawExceedsBalance() public {
        _mintMct(address(usdc), 1000e6, bob);

        vm.expectRevert(MultiCollateralToken.InsufficientCollateral.selector);
        mct.withdrawCollateral(address(usdc), 2000e6, owner);
    }

    /**
     * @notice Test adding zero address as asset reverts
     */
    function test_RevertIf_AddZeroAddress() public {
        vm.expectRevert(MultiCollateralToken.InvalidAssetAddress.selector);
        mct.addSupportedAsset(address(0));
    }

    /**
     * @notice Test adding MCT itself as asset reverts
     */
    function test_RevertIf_AddSelfAsAsset() public {
        vm.expectRevert(MultiCollateralToken.InvalidAssetAddress.selector);
        mct.addSupportedAsset(address(mct));
    }

    /**
     * @notice Test adding duplicate asset reverts
     */
    function test_RevertIf_AddDuplicateAsset() public {
        vm.expectRevert(MultiCollateralToken.InvalidAssetAddress.selector);
        mct.addSupportedAsset(address(usdc)); // Already added
    }

    /**
     * @notice Test minting with unsupported asset reverts
     */
    function test_RevertIf_MintUnsupportedAsset() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNSUP", 18);
        unsupportedToken.mint(address(this), 1000e18);
        unsupportedToken.approve(address(mct), 1000e18);

        vm.expectRevert(MultiCollateralToken.UnsupportedAsset.selector);
        mct.mint(address(unsupportedToken), 1000e18, bob);
    }

    /**
     * @notice Test redeeming to unsupported asset reverts
     */
    function test_RevertIf_RedeemUnsupportedAsset() public {
        // Mint some MCT with USDC first
        _mintMct(address(usdc), 1000e6, alice);

        // Transfer MCT to naraUSD (which has MINTER_ROLE)
        vm.prank(alice);
        mct.transfer(address(naraUSD), 1000e18);

        // Try to redeem to unsupported asset
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNSUP", 18);

        vm.startPrank(address(naraUSD));
        mct.approve(address(mct), 1000e18);

        vm.expectRevert(MultiCollateralToken.UnsupportedAsset.selector);
        mct.redeem(address(unsupportedToken), 1000e18, alice);

        vm.stopPrank();
    }

    /**
     * @notice Test withdrawing unsupported asset reverts
     */
    function test_RevertIf_WithdrawUnsupportedAsset() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNSUP", 18);

        vm.expectRevert(MultiCollateralToken.UnsupportedAsset.selector);
        mct.withdrawCollateral(address(unsupportedToken), 100e18, owner);
    }

    /**
     * @notice Test depositing unsupported asset reverts
     */
    function test_RevertIf_DepositUnsupportedAsset() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNSUP", 18);
        unsupportedToken.mint(address(this), 1000e18);
        unsupportedToken.approve(address(mct), 1000e18);

        vm.expectRevert(MultiCollateralToken.UnsupportedAsset.selector);
        mct.depositCollateral(address(unsupportedToken), 1000e18);
    }

    /**
     * @notice Fuzz test decimal conversions
     */
    function testFuzz_DecimalConversion(uint256 amount) public {
        amount = bound(amount, 1e6, 100_000e6); // 1 to 100k USDC

        uint256 expectedMct = amount * 1e12; // 6 decimals -> 18 decimals
        uint256 mctAmount = _mintMct(address(usdc), amount, bob);

        assertEq(mctAmount, expectedMct, "Decimal conversion should be exact");
    }

    /**
     * @notice Fuzz test mint and redeem round trip
     */
    function testFuzz_MintRedeemRoundTrip(uint256 amount) public {
        amount = bound(amount, 1e6, 100_000e6); // 1 to 100k USDC

        // Mint
        uint256 mctAmount = _mintMct(address(usdc), amount, alice);

        // Transfer to naraUSD for redemption
        vm.prank(alice);
        mct.transfer(address(naraUSD), mctAmount);

        // Redeem
        vm.startPrank(address(naraUSD));
        mct.approve(address(mct), mctAmount);
        uint256 collateralReceived = mct.redeem(address(usdc), mctAmount, bob);
        vm.stopPrank();

        assertEq(collateralReceived, amount, "Should receive same amount back");
    }
}
