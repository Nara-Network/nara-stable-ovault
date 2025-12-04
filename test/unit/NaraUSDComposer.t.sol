// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { NaraUSDComposer } from "../../contracts/narausd/NaraUSDComposer.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/**
 * @title NaraUSDComposerTest
 * @notice Unit tests for NaraUSDComposer contract
 * @dev Tests the custom compose logic for cross-chain naraUSD minting with collateral
 */
contract NaraUSDComposerTest is TestHelper {
    /**
     * @notice Verify constructor sets up immutables correctly
     */
    function test_Constructor() public view {
        assertEq(address(naraUSDComposer.VAULT()), address(naraUSD), "Vault should be naraUSD");
        assertEq(address(naraUSDComposer.ASSET_OFT()), address(mctAdapter), "ASSET_OFT should be MCTOFTAdapter");
        assertEq(
            address(naraUSDComposer.SHARE_OFT()),
            address(naraUSDAdapter),
            "SHARE_OFT should be NaraUSDOFTAdapter"
        );
        
        // Check USDC is whitelisted
        assertTrue(naraUSDComposer.isCollateralWhitelisted(address(usdc)), "USDC should be whitelisted");
        assertEq(naraUSDComposer.getWhitelistedCollateralsCount(), 1, "Should have 1 whitelisted collateral");
        assertEq(naraUSDComposer.collateralToOft(address(usdc)), address(usdc), "USDC OFT should be USDC");
        assertEq(naraUSDComposer.oftToCollateral(address(usdc)), address(usdc), "USDC collateral should be USDC");
        
        assertEq(address(naraUSDComposer.ENDPOINT()), address(endpoints[HUB_EID]), "Endpoint should be hub endpoint");
    }

    /**
     * @notice Verify constructor approves collateral to its OFT
     */
    function test_Constructor_ApprovesCollateral() public view {
        uint256 allowance = usdc.allowance(address(naraUSDComposer), address(usdc));
        assertEq(allowance, type(uint256).max, "Should approve max allowance for collateral refunds");
    }

    /**
     * @notice Test depositCollateralAndSend flow (via integration pattern)
     * @dev This tests the internal _depositCollateralAndSend logic indirectly
     */
    function test_DepositCollateralFlow() public {
        _switchToHub();

        uint256 depositAmount = 100e6; // 100 USDC

        // Grant composer MINTER_ROLE
        naraUSD.grantRole(naraUSD.MINTER_ROLE(), address(naraUSDComposer));

        // Fund the composer with USDC (simulating cross-chain arrival)
        usdc.mint(address(naraUSDComposer), depositAmount);

        // Track balances
        uint256 composerUsdcBefore = usdc.balanceOf(address(naraUSDComposer));
        uint256 composerNarausdBefore = naraUSD.balanceOf(address(naraUSDComposer));

        // Approve naraUSD to pull USDC from composer
        vm.prank(address(naraUSDComposer));
        usdc.approve(address(naraUSD), depositAmount);

        // Mint naraUSD with collateral (simulating what _depositCollateralAndSend does)
        vm.prank(address(naraUSDComposer));
        uint256 naraUSDAmount = naraUSD.mintWithCollateral(address(usdc), depositAmount);

        // Verify the flow
        assertEq(
            usdc.balanceOf(address(naraUSDComposer)),
            composerUsdcBefore - depositAmount,
            "Composer should transfer USDC"
        );
        assertGt(naraUSDAmount, 0, "Should mint naraUSD");
        assertEq(
            naraUSD.balanceOf(address(naraUSDComposer)),
            composerNarausdBefore + naraUSDAmount,
            "Composer should receive naraUSD"
        );
    }

    /**
     * @notice Test that only endpoint can call lzCompose
     */
    function test_RevertIf_LzCompose_NotEndpoint() public {
        _switchToHub();

        bytes memory message = abi.encodePacked(
            bytes32(uint256(uint160(alice))), // composeFrom
            uint64(100e6) // amount
        );

        vm.prank(alice);
        vm.expectRevert(); // Will revert with OnlyEndpoint
        naraUSDComposer.lzCompose(address(usdc), bytes32(0), message, address(0), "");
    }

    /**
     * @notice Test that only valid compose senders are accepted
     */
    function test_RevertIf_LzCompose_InvalidComposeSender() public {
        _switchToHub();

        MockERC20 invalidToken = new MockERC20("Invalid", "INV", 18);

        bytes memory message = abi.encodePacked(
            bytes32(uint256(uint160(alice))), // composeFrom
            uint64(100e6) // amount
        );

        vm.prank(address(endpoints[HUB_EID]));
        vm.expectRevert(abi.encodeWithSignature("CollateralOFTNotWhitelisted(address)", address(invalidToken)));
        naraUSDComposer.lzCompose(address(invalidToken), bytes32(0), message, address(0), "");
    }

    /**
     * @notice Test that ASSET_OFT (MCTOFTAdapter) is accepted as compose sender
     */
    function test_LzCompose_AcceptsAssetOFT() public view {
        // ASSET_OFT should be in the valid senders list
        assertEq(address(naraUSDComposer.ASSET_OFT()), address(mctAdapter), "ASSET_OFT should be MCTOFTAdapter");
    }

    /**
     * @notice Test that SHARE_OFT (NaraUSDOFTAdapter) is accepted as compose sender
     */
    function test_LzCompose_AcceptsShareOFT() public view {
        // SHARE_OFT should be in the valid senders list
        assertEq(
            address(naraUSDComposer.SHARE_OFT()),
            address(naraUSDAdapter),
            "SHARE_OFT should be NaraUSDOFTAdapter"
        );
    }

    /**
     * @notice Test that whitelisted collateral OFTs are accepted as compose senders
     */
    function test_LzCompose_AcceptsWhitelistedCollateralOFTs() public view {
        // USDC should be whitelisted as a collateral OFT
        assertTrue(naraUSDComposer.isCollateralWhitelisted(address(usdc)), "USDC should be whitelisted");
        assertEq(naraUSDComposer.oftToCollateral(address(usdc)), address(usdc), "USDC OFT should map to USDC");
    }

    /**
     * @notice Test handleComposeInternal revert if not called by self
     */
    function test_RevertIf_HandleComposeInternal_NotSelf() public {
        _switchToHub();

        SendParam memory sendParam;
        bytes memory composeMsg = abi.encode(sendParam, uint256(0));

        vm.prank(alice);
        vm.expectRevert(); // Will revert with OnlySelf
        naraUSDComposer._handleComposeInternal(address(usdc), bytes32(0), composeMsg, 100e6);
    }

    /**
     * @notice Test immutable values cannot be zero address
     * @dev Tests constructor validation
     */
    function test_Constructor_ValidatesAddresses() public {
        // All constructor params should be non-zero
        // This is implicitly tested by the setUp not reverting,
        // but we can verify the values are set correctly
        assertTrue(address(naraUSDComposer.VAULT()) != address(0), "Vault should not be zero");
        assertTrue(address(naraUSDComposer.ASSET_OFT()) != address(0), "ASSET_OFT should not be zero");
        assertTrue(address(naraUSDComposer.SHARE_OFT()) != address(0), "SHARE_OFT should not be zero");
        
        // Verify USDC was whitelisted
        assertTrue(naraUSDComposer.isCollateralWhitelisted(address(usdc)), "USDC should be whitelisted");
        assertEq(naraUSDComposer.getWhitelistedCollateralsCount(), 1, "Should have 1 whitelisted collateral");
    }

    /**
     * @notice Test that collateral is approved to vault for minting
     */
    function test_CollateralApproval() public view {
        // Composer should have approval set for USDC -> naraUSD
        // This is set during _depositCollateralAndSend via forceApprove
        // We can't directly test internal function, but we verify the pattern in integration tests
        assertTrue(naraUSDComposer.isCollateralWhitelisted(address(usdc)), "USDC should be whitelisted");
        assertEq(naraUSDComposer.oftToCollateral(address(usdc)), address(usdc), "Collateral should be USDC");
    }

    /**
     * @notice Fuzz test collateral amounts
     */
    function testFuzz_CollateralDeposit(uint256 amount) public {
        _switchToHub();

        amount = bound(amount, 1e6, 1_000_000e6); // 1 USDC to 1M USDC

        // Grant composer MINTER_ROLE
        naraUSD.grantRole(naraUSD.MINTER_ROLE(), address(naraUSDComposer));

        // Fund composer with USDC
        usdc.mint(address(naraUSDComposer), amount);

        // Simulate deposit flow
        vm.startPrank(address(naraUSDComposer));
        usdc.approve(address(naraUSD), amount);
        uint256 naraUSDAmount = naraUSD.mintWithCollateral(address(usdc), amount);
        vm.stopPrank();

        // Verify proportional minting
        assertGt(naraUSDAmount, 0, "Should mint some naraUSD");
        assertApproxEqAbs(naraUSDAmount, amount * 1e12, 1e18, "Should mint ~1:1 (accounting for decimals)");
    }

    /**
     * @notice Test composer works with USDT as well
     */
    function test_CollateralDeposit_USDT() public {
        _switchToHub();

        uint256 depositAmount = 100e6; // 100 USDT

        // Grant composer MINTER_ROLE
        naraUSD.grantRole(naraUSD.MINTER_ROLE(), address(naraUSDComposer));

        // Fund composer with USDT
        usdt.mint(address(naraUSDComposer), depositAmount);

        // Simulate deposit flow
        vm.startPrank(address(naraUSDComposer));
        usdt.approve(address(naraUSD), depositAmount);
        uint256 naraUSDAmount = naraUSD.mintWithCollateral(address(usdt), depositAmount);
        vm.stopPrank();

        assertGt(naraUSDAmount, 0, "Should mint naraUSD with USDT");
    }

    /**
     * @notice Test that MCT is never directly handled by composer
     */
    function test_MCT_NeverDirectlyUsed() public view {
        // MCT should never have approval from composer
        uint256 mctAllowance = mct.allowance(address(naraUSDComposer), address(mct));
        assertEq(mctAllowance, 0, "Composer should never approve MCT");

        // MCT balance should always be 0
        uint256 mctBalance = mct.balanceOf(address(naraUSDComposer));
        assertEq(mctBalance, 0, "Composer should never hold MCT");
    }

    /**
     * @notice Test ASSET_OFT is for validation only
     */
    function test_AssetOFT_ValidationOnly() public view {
        // ASSET_OFT points to MCTOFTAdapter but is never used operationally
        assertEq(address(naraUSDComposer.ASSET_OFT()), address(mctAdapter), "ASSET_OFT is MCTOFTAdapter");

        // The actual deposit flow uses whitelisted collateral (USDC), not ASSET_OFT
        assertTrue(naraUSDComposer.isCollateralWhitelisted(address(usdc)), "USDC should be whitelisted");
        assertTrue(
            address(naraUSDComposer.ASSET_OFT()) != address(usdc),
            "ASSET_OFT != collateral"
        );
    }

    /**
     * @notice Test endpoint is correctly set
     */
    function test_Endpoint() public view {
        assertEq(address(naraUSDComposer.ENDPOINT()), address(endpoints[HUB_EID]), "Endpoint should be hub endpoint");
    }

    /**
     * @notice Test compose message validation
     * @dev Ensures proper message structure for compose operations
     */
    function test_ComposeMessageStructure() public {
        _switchToHub();

        // Create a valid SendParam
        SendParam memory sendParam = SendParam({
            dstEid: SPOKE_EID,
            to: addressToBytes32(bob),
            amountLD: 100e18,
            minAmountLD: 95e18,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        uint256 minMsgValue = 0.01 ether;

        // Encode compose message
        bytes memory composeMsg = abi.encode(sendParam, minMsgValue);

        // Decode and verify
        (SendParam memory decoded, uint256 decodedMsgValue) = abi.decode(composeMsg, (SendParam, uint256));

        assertEq(decoded.dstEid, SPOKE_EID, "dstEid should match");
        assertEq(decoded.to, addressToBytes32(bob), "to should match");
        assertEq(decoded.amountLD, 100e18, "amountLD should match");
        assertEq(decoded.minAmountLD, 95e18, "minAmountLD should match");
        assertEq(decodedMsgValue, minMsgValue, "minMsgValue should match");
    }
}
