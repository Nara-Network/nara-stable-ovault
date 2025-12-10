// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { IOFT } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { MultiCollateralToken } from "../../contracts/mct/MultiCollateralToken.sol";
import { NaraUSD } from "../../contracts/narausd/NaraUSD.sol";
import { NaraUSDPlus } from "../../contracts/narausd-plus/NaraUSDPlus.sol";

import { MCTOFTAdapter } from "../../contracts/mct/MCTOFTAdapter.sol";
import { NaraUSDOFTAdapter } from "../../contracts/narausd/NaraUSDOFTAdapter.sol";
import { NaraUSDOFT } from "../../contracts/narausd/NaraUSDOFT.sol";
import { NaraUSDPlusOFTAdapter } from "../../contracts/narausd-plus/NaraUSDPlusOFTAdapter.sol";
import { NaraUSDPlusOFT } from "../../contracts/narausd-plus/NaraUSDPlusOFT.sol";
import { NaraUSDComposer } from "../../contracts/narausd/NaraUSDComposer.sol";
import { NaraUSDPlusComposer } from "../../contracts/narausd-plus/NaraUSDPlusComposer.sol";

/**
 * @title TestHelper
 * @notice Base test helper with common setup and utilities for cross-chain testing
 */
abstract contract TestHelper is TestHelperOz5 {
    using OptionsBuilder for bytes;

    // Endpoint IDs
    uint32 public constant HUB_EID = 1;
    uint32 public constant SPOKE_EID = 2;

    // Test accounts
    address public alice;
    address public bob;
    address public owner;
    address public delegate;

    // Mock tokens (only for collateral)
    MockERC20 public usdc;
    MockERC20 public usdt;

    // Real contracts
    MultiCollateralToken public mct;
    NaraUSD public naraUSD;
    NaraUSDPlus public naraUSDPlus;

    // Hub chain contracts (Arbitrum)
    MCTOFTAdapter public mctAdapter; // Note: MCT doesn't go cross-chain, but adapter needed for composer validation
    NaraUSDOFTAdapter public naraUSDAdapter;
    NaraUSDPlusOFTAdapter public naraUSDPlusAdapter;
    NaraUSDComposer public naraUSDComposer;
    NaraUSDPlusComposer public naraUSDPlusComposer;

    // Spoke chain contracts (Base, OP, etc.)
    NaraUSDOFT public naraUSDOFT;
    NaraUSDPlusOFT public naraUSDPlusOFT;

    // Helper variables
    uint256 public constant INITIAL_BALANCE = 1_000_000e6; // 1M USDC
    uint256 public constant INITIAL_BALANCE_18 = 1_000_000e18; // 1M with 18 decimals

    function setUp() public virtual override {
        // Setup endpoints for hub and spoke chains
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // Setup test accounts
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        owner = makeAddr("owner");
        delegate = address(this); // Use test contract as delegate for OFT ownership

        // Fund test accounts with ETH for gas
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(owner, 100 ether);
        vm.deal(delegate, 100 ether);

        // Deploy on hub chain
        _deployHubContracts();

        // Deploy on spoke chain
        _deploySpokeContracts();

        // Wire OApps together
        _wireOApps();

        // Setup initial balances
        _setupInitialBalances();
    }

    /**
     * @notice Deploy all hub chain contracts
     */
    function _deployHubContracts() internal {
        // Simulates hub chain using mock endpoints (no Foundry fork switching)

        // Deploy mock collateral tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);

        // Prepare initial assets array for MCT
        address[] memory initialAssets = new address[](2);
        initialAssets[0] = address(usdc);
        initialAssets[1] = address(usdt);

        // Deploy real MCT with test contract as admin
        mct = new MultiCollateralToken(address(this), initialAssets);
        // Grant MINTER_ROLE to test contract for minting without collateral
        mct.grantRole(mct.MINTER_ROLE(), address(this));

        // Deploy real NaraUSD vault
        naraUSD = new NaraUSD(
            mct,
            address(this), // admin
            type(uint256).max, // maxMintPerBlock (unlimited for testing)
            type(uint256).max // maxRedeemPerBlock (unlimited for testing)
        );
        // Grant necessary roles
        naraUSD.grantRole(naraUSD.MINTER_ROLE(), address(this));
        naraUSD.grantRole(naraUSD.COLLATERAL_MANAGER_ROLE(), address(this));
        // Add MCT as minter to itself for NaraUSD minting flow
        mct.grantRole(mct.MINTER_ROLE(), address(naraUSD));

        // Deploy real NaraUSDPlus vault
        naraUSDPlus = new NaraUSDPlus(
            naraUSD,
            address(this), // initialRewarder
            address(this) // admin
        );
        // Set cooldown to 0 for easier testing (can be changed in specific tests)
        naraUSDPlus.setCooldownDuration(0);

        // Deploy OFT Adapters
        // Note: MCT adapter exists on hub but MCT never actually goes cross-chain
        // It's only needed to satisfy composer validation checks
        mctAdapter = new MCTOFTAdapter(address(mct), address(endpoints[HUB_EID]), delegate);

        naraUSDAdapter = new NaraUSDOFTAdapter(address(naraUSD), address(endpoints[HUB_EID]), delegate);

        naraUSDPlusAdapter = new NaraUSDPlusOFTAdapter(address(naraUSDPlus), address(endpoints[HUB_EID]), delegate);

        // Deploy Composers
        naraUSDComposer = new NaraUSDComposer(
            address(naraUSD),
            address(mctAdapter), // ASSET_OFT for validation (MCT is vault's underlying asset)
            address(naraUSDAdapter) // SHARE_OFT (NaraUSD goes cross-chain)
        );

        // Whitelist USDC as collateral
        vm.prank(address(this)); // Test contract has DEFAULT_ADMIN_ROLE
        naraUSDComposer.addWhitelistedCollateral(address(usdc), address(usdc)); // Using USDC as both asset and OFT for simplicity

        naraUSDPlusComposer = new NaraUSDPlusComposer(
            address(naraUSDPlus),
            address(naraUSDAdapter),
            address(naraUSDPlusAdapter)
        );
    }

    /**
     * @notice Deploy all spoke chain contracts
     */
    function _deploySpokeContracts() internal {
        // Simulates spoke chain using mock endpoints (no Foundry fork switching)

        // Deploy OFTs on spoke chain
        naraUSDOFT = new NaraUSDOFT(address(endpoints[SPOKE_EID]), delegate);

        naraUSDPlusOFT = new NaraUSDPlusOFT(address(endpoints[SPOKE_EID]), delegate);
    }

    /**
     * @notice Wire all OApps together for cross-chain communication
     */
    function _wireOApps() internal {
        // Wire NaraUSD OFT <-> Adapter
        address[] memory naraUSDPath = new address[](2);
        naraUSDPath[0] = address(naraUSDAdapter);
        naraUSDPath[1] = address(naraUSDOFT);
        this.wireOApps(naraUSDPath);

        // Wire NaraUSDPlus OFT <-> Adapter
        address[] memory naraUSDPlusPath = new address[](2);
        naraUSDPlusPath[0] = address(naraUSDPlusAdapter);
        naraUSDPlusPath[1] = address(naraUSDPlusOFT);
        this.wireOApps(naraUSDPlusPath);
    }

    /**
     * @notice Setup initial token balances for testing
     */
    function _setupInitialBalances() internal {
        // Setup balances in mock multi-chain environment

        // Mint USDC to test accounts
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        usdc.mint(owner, INITIAL_BALANCE);

        // Mint USDT to test accounts
        usdt.mint(alice, INITIAL_BALANCE);
        usdt.mint(bob, INITIAL_BALANCE);
        usdt.mint(owner, INITIAL_BALANCE);

        // Mint MCT to test accounts for direct vault operations
        mct.mintWithoutCollateral(alice, INITIAL_BALANCE_18);
        mct.mintWithoutCollateral(bob, INITIAL_BALANCE_18);

        // Mint NaraUSD to test accounts for staking tests
        // First mint MCT, then deposit to get NaraUSD
        mct.mintWithoutCollateral(address(this), INITIAL_BALANCE_18 * 2);
        mct.approve(address(naraUSD), INITIAL_BALANCE_18 * 2);
        naraUSD.deposit(INITIAL_BALANCE_18, alice);
        naraUSD.deposit(INITIAL_BALANCE_18, bob);
    }

    /**
     * @notice Helper to build send parameters for OFT transfers
     */
    function _buildSendParam(
        uint32 dstEid,
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory extraOptions,
        bytes memory composeMsg,
        bytes memory oftCmd
    ) internal pure returns (SendParam memory) {
        return
            SendParam({
                dstEid: dstEid,
                to: addressToBytes32(to),
                amountLD: amount,
                minAmountLD: minAmount,
                extraOptions: extraOptions,
                composeMsg: composeMsg,
                oftCmd: oftCmd
            });
    }

    /**
     * @notice Helper to build basic send parameters
     */
    function _buildBasicSendParam(uint32 dstEid, address to, uint256 amount) internal pure returns (SendParam memory) {
        return
            _buildSendParam(
                dstEid,
                to,
                amount,
                amount, // minAmount = amount (no slippage)
                OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0), // default gas limit
                "", // no compose message
                "" // no OFT command
            );
    }

    /**
     * @notice Helper to get messaging fee for an OFT send
     */
    function _getMessagingFee(address oft, SendParam memory sendParam) internal view returns (MessagingFee memory) {
        return IOFT(oft).quoteSend(sendParam, false);
    }

    /**
     * @notice Helper to build options for gas limit
     */
    function _buildOptions(uint128 gas) internal pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(gas, 0);
    }

    /**
     * @notice Helper to build compose options
     */
    function _buildComposeOptions(uint128 gas, uint128 composeGas) internal pure returns (bytes memory) {
        return
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(gas, 0).addExecutorLzComposeOption(0, composeGas, 0);
    }

    /**
     * @notice Switch to hub chain (no-op - all chains in same test environment)
     */
    function _switchToHub() internal {
        // Mock endpoints handle multi-chain state automatically
    }

    /**
     * @notice Switch to spoke chain (no-op - all chains in same test environment)
     */
    function _switchToSpoke() internal {
        // Mock endpoints handle multi-chain state automatically
    }

    /**
     * @notice Verify packets
     */
    function _verifyAndSwitchBack(uint32 srcEid, address srcOApp, uint256 /*originalFork*/) internal {
        verifyPackets(srcEid, addressToBytes32(srcOApp));
    }
}
