import { ethers } from 'hardhat'

async function main() {
    const HELPER_ADDRESS = '0x8fd3F0c25c5E38821e9775Ba78B4eAD9bF318FDe'
    const USDE_OFT_ADDRESS = '0x9E98a76aCe0BE6bA3aFF1a230931cdCd0bf544dc'

    const [signer] = await ethers.getSigners()
    console.log('Testing with address:', signer.address)

    // 1. Check helper config
    const helper = await ethers.getContractAt('StakingSpokeHelper', HELPER_ADDRESS)

    console.log('\n=== Helper Configuration ===')
    console.log('usdeOFT:', await helper.usdeOFT())
    console.log('hubEid:', await helper.hubEid())
    console.log('composerOnHub:', await helper.composerOnHub())

    // 2. Check USDe balance
    const usdeOFT = await ethers.getContractAt('USDeOFT', USDE_OFT_ADDRESS)

    console.log('\n=== USDe Balance ===')
    const balance = await usdeOFT.balanceOf(signer.address)
    console.log('Your USDe balance:', ethers.utils.formatEther(balance))

    if (balance.eq(0)) {
        console.log("\n❌ You don't have any USDe!")
        console.log('To mint USDe on Base Sepolia:')
        console.log('1. Go to your frontend on Arbitrum Sepolia')
        console.log('2. Mint some USDe there')
        console.log('3. Bridge it to Base using the "Bridge USDe to Base" card')
        console.log('4. Or bridge from Base → Arbitrum → mint → bridge back\n')
        return
    }

    // 3. Check allowance
    const allowance = await usdeOFT.allowance(signer.address, HELPER_ADDRESS)
    console.log('Allowance for helper:', ethers.utils.formatEther(allowance))

    // 4. Try to quote a stake
    console.log('\n=== Testing Quote ===')
    const amount = ethers.utils.parseEther('1')
    const dstEid = 40245 // Base Sepolia
    const to = ethers.utils.hexZeroPad(signer.address, 32)
    const minShares = amount.mul(99).div(100) // 1% slippage
    const extraOptions = '0x'

    try {
        const fee = await helper.quoteStakeRemote(amount, dstEid, to, minShares, extraOptions, false)
        console.log('✅ Quote successful!')
        console.log('Required fee:', ethers.utils.formatEther(fee.nativeFee), 'ETH')

        // 5. Check if we have enough ETH
        const ethBalance = await ethers.provider.getBalance(signer.address)
        console.log('\n=== ETH Balance ===')
        console.log('Your ETH balance:', ethers.utils.formatEther(ethBalance))

        if (ethBalance < fee.nativeFee) {
            console.log('❌ Not enough ETH for fees!')
            return
        }

        // 6. Try the actual call (static call to see if it would revert)
        console.log('\n=== Testing Actual Stake (Static Call) ===')
        try {
            await helper.callStatic.stakeRemote(amount, dstEid, to, minShares, extraOptions, {
                value: fee.nativeFee,
            })
            console.log('✅ Static call successful! The transaction should work.')
            console.log('\n🎉 Everything looks good! Try it from your frontend now.')
        } catch (error: any) {
            console.log('❌ Static call failed:')
            console.log(error.message)

            // Try to get more details
            if (error.data) {
                try {
                    const iface = new ethers.Interface([
                        'error InvalidAmount()',
                        'error InvalidZeroAddress()',
                        'error InsufficientFee()',
                    ])
                    const decoded = iface.parseError(error.data)
                    console.log('Decoded error:', decoded)
                } catch (e) {
                    console.log('Raw error data:', error.data)
                }
            }
        }
    } catch (error: any) {
        console.log('❌ Quote failed:', error.message)
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
