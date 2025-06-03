import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { task } from 'hardhat/config'
import {
  getSigner,
  log,
  promptUser
} from '../common/util'

const transferEth = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { toAddress, amount } = args

  const signer = await getSigner(hre.ethers)
  const signerAddress = await signer.getAddress()

  await promptUser(`Send ${amount} ETH from ${signerAddress} to ${toAddress} ? [y/N] `)

  const tx = await signer.sendTransaction({
    to: toAddress,
    value: amount
  })
  log(`Sent; waiting for confirmation...`)

  await tx.wait(1)

  log(`Confirmed!`)
}

export const defineTokenTasks = () => {
  // example: npx hardhat --network localhost transferEth --to-address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --amount 1000000000000000000
  task('transferEth', `Transfers the provided amount of the provided token to the toAddress`)
    .addParam('toAddress', 'the account being sent the transfer amount')
    .addParam('amount', 'the amount [in wei] being transferred')
    .setAction(transferEth)
}
