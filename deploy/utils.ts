import { HardhatRuntimeEnvironment } from 'hardhat/types'

/**
 * Helper function to handle RPC provider issues on Ethereum mainnet
 * where contract creation transactions return empty 'to' field in the response.
 * This function retries fetching the transaction receipt with exponential backoff
 * to handle delayed transaction finalization.
 */
export async function handleDeploymentWithRetry(
    hre: HardhatRuntimeEnvironment,
    deploymentPromise: Promise<{ address: string }>,
    contractName: string,
    artifactPath: string
): Promise<{ address: string }> {
    try {
        return await deploymentPromise
    } catch (error: unknown) {
        // Handle RPC provider issue on Ethereum mainnet where contract creation returns empty 'to' field
        const err = error as { message?: string; transactionHash?: string; checkKey?: string }
        if (err?.message?.includes('invalid address') && err?.transactionHash && err?.checkKey === 'to') {
            console.log(
                `   ⚠️  RPC provider returned malformed transaction response (Ethereum mainnet issue), checking if deployment succeeded...`
            )
            const txHash = err.transactionHash
            console.log(`   Transaction hash: ${txHash}`)
            console.log(`   Waiting for transaction to be finalized...`)

            // Retry logic with exponential backoff for delayed finalization
            let receipt = null
            const maxRetries = 10
            const initialDelay = 2000 // 2 seconds
            for (let i = 0; i < maxRetries; i++) {
                receipt = await hre.ethers.provider.getTransactionReceipt(txHash)
                if (receipt && receipt.contractAddress) {
                    break
                }
                if (i < maxRetries - 1) {
                    const delay = initialDelay * Math.pow(2, i)
                    console.log(`   Retry ${i + 1}/${maxRetries}: Waiting ${delay}ms for transaction finalization...`)
                    await new Promise((resolve) => setTimeout(resolve, delay))
                }
            }

            if (receipt && receipt.contractAddress) {
                console.log(`   ✓ ${contractName} deployment succeeded (contract address from receipt)`)
                console.log(`   ✓ ${contractName} deployed at: ${receipt.contractAddress}`)
                // Save the deployment manually
                await hre.deployments.save(contractName, {
                    address: receipt.contractAddress,
                    abi: (await hre.artifacts.readArtifact(artifactPath)).abi,
                })
                return { address: receipt.contractAddress }
            } else {
                throw new Error(
                    `${contractName} deployment transaction exists (${txHash}) but contract address not found in receipt after ${maxRetries} retries. ` +
                        `The transaction may still be pending. Please check the transaction on the block explorer: ` +
                        `https://etherscan.io/tx/${txHash}`
                )
            }
        } else {
            throw error
        }
    }
}
