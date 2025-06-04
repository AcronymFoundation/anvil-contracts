import * as ethers from 'ethers'
import { HardhatEthersHelpers } from '@nomicfoundation/hardhat-ethers/types'

const eip1967ImplementationSlot = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
export async function getEIP1967ProxyImplementationAddress(
  provider: ethers.Provider,
  proxyAddress: string
): Promise<string> {
  const implementationAddress = await provider.getStorage(proxyAddress, eip1967ImplementationSlot)
  // Result is 0x + 32 bytes (64 chars), we want the last 20 bytes (40 chars)
  return ethers.getAddress('0x' + implementationAddress.slice(26))
}

const eip1967AdminSlot = '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103'
export async function getEIP1967ProxyAdminAddress(provider: ethers.Provider, proxyAddress: string): Promise<string> {
  const implementationAddress = await provider.getStorage(proxyAddress, eip1967AdminSlot)
  // Result is 0x + 32 bytes (64 chars), we want the last 20 bytes (40 chars)
  return ethers.getAddress('0x' + implementationAddress.slice(26))
}

const beaconSlot = '0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50'
export async function getProxyBeaconAddress(provider: ethers.Provider, proxyAddress: string): Promise<string> {
  const implementationAddress = await provider.getStorage(proxyAddress, beaconSlot)
  // Result is 0x + 32 bytes (64 chars), we want the last 20 bytes (40 chars)
  return ethers.getAddress('0x' + implementationAddress.slice(26))
}

export async function getBeaconProxyImplementationAddress(
  hardhatHelpers: HardhatEthersHelpers,
  proxyAddress: string
): Promise<string> {
  const beaconAddress = await getProxyBeaconAddress(hardhatHelpers.provider, proxyAddress)
  return await getBeaconImplementationAddress(hardhatHelpers, beaconAddress)
}

export async function getBeaconImplementationAddress(
  hardhatHelpers: HardhatEthersHelpers,
  beaconAddress: string
): Promise<string> {
  const beacon = await hardhatHelpers.getContractAt('UpgradeableBeacon', beaconAddress)
  return await beacon.implementation()
}

export async function getBeaconProxyOwnerAddress(
  hardhatHelpers: HardhatEthersHelpers,
  proxyAddress: string
): Promise<string> {
  const beaconAddress = await getProxyBeaconAddress(hardhatHelpers.provider, proxyAddress)
  return await getBeaconOwnerAddress(hardhatHelpers, beaconAddress)
}

export async function getBeaconOwnerAddress(
  hardhatHelpers: HardhatEthersHelpers,
  beaconAddress: string
): Promise<string> {
  const beacon = await hardhatHelpers.getContractAt('UpgradeableBeacon', beaconAddress)
  return await beacon.owner()
}
