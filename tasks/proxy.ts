import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { task } from 'hardhat/config'
import {add0x, isValidEthereumAddress, log, ZERO_ADDRESS} from '../common/util'
import {
  getBeaconImplementationAddress,
  getBeaconOwnerAddress,
  getBeaconProxyImplementationAddress,
  getBeaconProxyOwnerAddress,
  getEIP1967ProxyAdminAddress,
  getEIP1967ProxyImplementationAddress,
  getProxyBeaconAddress
} from '../common/proxy'

const getProxyImplementation = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { proxyAddress } = args


  let implementation: string
  const beaconAddress = await getProxyBeaconAddress(hre.ethers.provider, proxyAddress)
  if (beaconAddress === ZERO_ADDRESS) {
    implementation = await getEIP1967ProxyImplementationAddress(hre.ethers.provider, proxyAddress)
  } else {
    implementation = await getBeaconProxyImplementationAddress(hre.ethers, proxyAddress)
  }

  log(`Implementation of ${proxyAddress} is at address: ${implementation}`)
}

const getProxyAdmin = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { proxyAddress } = args

  let admin: string
  const beaconAddress = await getProxyBeaconAddress(hre.ethers.provider, proxyAddress)
  if (beaconAddress === ZERO_ADDRESS) {
    admin = await getEIP1967ProxyAdminAddress(hre.ethers.provider, proxyAddress)
  } else {
    admin = await getBeaconProxyOwnerAddress(hre.ethers, proxyAddress)
  }

  log(`Admin of ${proxyAddress} is : ${admin}`)
}

const getBeaconImplementation = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { beaconAddress } = args

  const implementation = await getBeaconImplementationAddress(hre.ethers, beaconAddress)

  log(`Implementation of beacon ${beaconAddress} is at address: ${implementation}`)
}

const getBeaconOwner = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { beaconAddress } = args

  const implementation = await getBeaconOwnerAddress(hre.ethers, beaconAddress)

  log(`Owner of beacon ${beaconAddress} is at address: ${implementation}`)
}

export const defineProxyTasks = () => {
  // example: npx hardhat --network mainnet getProxyImplementation --proxy-address 0x14db9a91933aD9433E1A0dB04D08e5D9EF7c4808
  task('getProxyImplementation', 'Gets the implementation address of the provided proxy')
    .addParam('proxyAddress', 'The name or address of the proxy in question')
    .setAction(getProxyImplementation)

  // example: npx hardhat --network mainnet getProxyAdmin --proxy-address 0x14db9a91933aD9433E1A0dB04D08e5D9EF7c4808
  task('getProxyAdmin', 'Gets the admin address of the provided proxy')
    .addParam('proxyAddress', 'The name or address of the proxy in question')
    .setAction(getProxyAdmin)

  // example: npx hardhat --network mainnet getBeaconImplementation --beacon-address 0x1f00D6f7C18a8edf4f8Bb4Ead8a898aBDd9c9E14
  task('getBeaconImplementation', 'Gets the implementation address of the provided beacon ')
    .addParam('beaconAddress', 'The name or address of the beacon in question')
    .setAction(getBeaconImplementation)

  // example: npx hardhat --network mainnet getBeaconOwner --beacon-address 0x1f00D6f7C18a8edf4f8Bb4Ead8a898aBDd9c9E14
  task('getBeaconOwner', 'Gets the owner address of the provided beacon ')
    .addParam('beaconAddress', 'The name or address of the beacon in question')
    .setAction(getBeaconOwner)
}
