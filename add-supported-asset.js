const { ethers } = require('hardhat');

async function main() {
    console.log('=== Adding Supported Asset to MultiCollateralToken ===');

    // Contract address from deployment
    const mctAddress = '0x8a0CDA1d483cd046EcB81b7A154e659037FAd043';

    // Get the contract instance
    const MCT = await ethers.getContractAt('MultiCollateralToken', mctAddress);

    console.log('MCT Address:', mctAddress);

    // Get the current signer (should be the admin)
    const [signer] = await ethers.getSigners();
    console.log('Signer:', signer.address);

    // Check if signer has admin role
    const DEFAULT_ADMIN_ROLE = await MCT.DEFAULT_ADMIN_ROLE();
    const hasAdminRole = await MCT.hasRole(DEFAULT_ADMIN_ROLE, signer.address);
    console.log('Has Admin Role:', hasAdminRole);

    if (!hasAdminRole) {
        console.error('❌ Signer does not have admin role!');
        console.log('Admin role:', DEFAULT_ADMIN_ROLE);
        return;
    }

    // ============================================
    // EDIT THIS: Add the asset you want to support
    // ============================================
    const assetToAdd = '0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773'; // TODO: Replace with actual asset address

    // ============================================
    // END OF EDITABLE SECTION
    // ============================================

    console.log('Asset to add:', assetToAdd);

    // Check if asset is already supported
    const isSupported = await MCT.isSupportedAsset(assetToAdd);
    console.log('Is already supported:', isSupported);

    if (isSupported) {
        console.log('✅ Asset is already supported!');
        return;
    }

    try {
        console.log('Adding supported asset...');

        const tx = await MCT.addSupportedAsset(assetToAdd);
        console.log('Transaction hash:', tx.hash);

        console.log('Waiting for confirmation...');
        const receipt = await tx.wait();

        console.log('✅ Asset added successfully!');
        console.log('Gas used:', receipt.gasUsed.toString());

        // Verify the asset was added
        const isNowSupported = await MCT.isSupportedAsset(assetToAdd);
        console.log('Is now supported:', isNowSupported);
    } catch (error) {
        console.error('❌ Transaction failed:');
        console.error('Error message:', error.message);

        if (error.reason) {
            console.error('Revert reason:', error.reason);
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
