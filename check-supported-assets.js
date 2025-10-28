const { ethers } = require('hardhat');

async function main() {
    console.log('=== Checking MultiCollateralToken Supported Assets ===');

    // Contract address from deployment
    const mctAddress = '0x8a0CDA1d483cd046EcB81b7A154e659037FAd043';

    // Get the contract instance
    const MCT = await ethers.getContractAt('MultiCollateralToken', mctAddress);

    console.log('MCT Address:', mctAddress);

    // Get contract info
    const name = await MCT.name();
    const symbol = await MCT.symbol();
    const decimals = await MCT.decimals();
    const totalSupply = await MCT.totalSupply();

    console.log('\n=== Contract Info ===');
    console.log('Name:', name);
    console.log('Symbol:', symbol);
    console.log('Decimals:', decimals);
    console.log('Total Supply:', ethers.utils.formatUnits(totalSupply, decimals));

    // Get admin info
    const [signer] = await ethers.getSigners();
    const DEFAULT_ADMIN_ROLE = await MCT.DEFAULT_ADMIN_ROLE();
    const hasAdminRole = await MCT.hasRole(DEFAULT_ADMIN_ROLE, signer.address);

    console.log('\n=== Admin Info ===');
    console.log('Current Signer:', signer.address);
    console.log('Has Admin Role:', hasAdminRole);
    console.log('Admin Role:', DEFAULT_ADMIN_ROLE);

    // Check supported assets
    console.log('\n=== Supported Assets ===');

    // Check some common asset addresses
    const commonAssets = [
        '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d', // USDC (Arbitrum Sepolia)
        '0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773', // USDC (stargate supported)
    ];

    for (const asset of commonAssets) {
        try {
            const isSupported = await MCT.isSupportedAsset(asset);
            console.log(`${asset}: ${isSupported ? '✅ Supported' : '❌ Not Supported'}`);
        } catch (error) {
            console.log(`${asset}: Error checking - ${error.message}`);
        }
    }

    // Try to get all supported assets (if there's a function for it)
    try {
        // Check if there's a function to get all supported assets
        const supportedAssetsCount = await MCT.getSupportedAssetsCount();
        console.log('\nSupported Assets Count:', supportedAssetsCount.toString());

        // Get each supported asset
        for (let i = 0; i < supportedAssetsCount.toNumber(); i++) {
            const asset = await MCT.getSupportedAsset(i);
            console.log(`Asset ${i}: ${asset}`);
        }
    } catch (error) {
        console.log('\nNote: Could not enumerate all supported assets');
        console.log('Error:', error.message);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
