import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { task } from 'hardhat/config'
import { setNextBlockTimestamp } from '@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time'
import {getSigner, log, sleep} from '../common/util'
import {mineIfLocal} from "./util";

const getCurrentBlockNumber = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const blockNumber = await hre.ethers.provider!.getBlockNumber()
  log(`${blockNumber}`)
}

const getBlocktime = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { blockNumber } = args

  let block
  if (!blockNumber) {
    block = await hre.ethers.provider!.getBlock('latest')
  } else {
    block = await hre.ethers.provider!.getBlock(Number(blockNumber))
  }

  if (!block) {
    log(`Block with number "${blockNumber}" not found`)
  } else {
    log(`${block.timestamp}`)
  }
}

const mine = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { blocksToAdvance } = args

  await mineIfLocal(hre.ethers.provider, parseInt(blocksToAdvance))
}

const warp = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { seconds } = args

  const block = await hre.ethers.provider!.getBlock('latest')

  const next = block!.timestamp + Number(seconds * 1_000)
  log(`last block: ${block!.timestamp}, setting next to ${next}`)

  await setNextBlockTimestamp(next)
}

const waitBlocks = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { blocks } = args

  const blocksInt = parseInt(blocks)

  if (await mineIfLocal(hre.ethers.provider, blocksInt)) {
    return
  }

  const blockNumber = await hre.ethers.provider.getBlockNumber()
  log(`Current block is ${blockNumber.toString()}. Waiting for next block...`)
  while ((await hre.ethers.provider.getBlockNumber()) <= blockNumber) {
    log(`Sleeping 1s...`)
    await sleep(1_000)
  }
  log(`Block ${(BigInt(blockNumber).valueOf() + 1n).toString()} mined!`)
}

const ethBalanceOf = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  let { address } = args

  const signer = await getSigner(hre.ethers)
  if (!address) {
    address = await signer.getAddress()
  }

  const balance = await signer.provider?.getBalance(address)

  log(`${balance!.toLocaleString()}`)
}

export const defineChainTasks = () => {
  // example: npx hardhat --network localhost blockNumber
  task('blockNumber', 'Gets the current block number for the configured chain').setAction(getCurrentBlockNumber)

  // example: npx hardhat --network localhost mine --blocks-to-advance 1
  task('mine', 'Adds a new block to the chain if running a local devnet')
    .addOptionalParam('blocksToAdvance', 'The number of blocks to add to the chain', '1')
    .setAction(mine)

  // example: npx hardhat --network localhost warp --seconds 100
  task('warp', 'Adds a new block to the chain if running a local devnet')
    .addOptionalParam('seconds', 'The number of seconds to move forward', '300')
    .setAction(warp)

  // example: npx hardhat --network localhost waitBlocks --blocks 1
  task('waitBlocks', 'Waits for the provided number of blocks to be mined from the current block')
    .addParam('blocks', 'The number of blocks to wait')
    .setAction(waitBlocks)

  // example: npx hardhat --network localhost getBlocktime
  task('getBlocktime', 'Gets the time of the block in question')
    .addOptionalParam(
      'blockNumber',
      '(optional) The number of the block for which to get the time. If not provided, returns latest block time.'
    )
    .setAction(getBlocktime)

  // example: npx hardhat --network localhost ethBalanceOf --address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
  task('ethBalanceOf', 'Gets the ETH balance of the provided account')
    .addOptionalParam('address', '(optional) The address of the account. Defaults to signer')
    .setAction(ethBalanceOf)
}
