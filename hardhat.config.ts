import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-chai-matchers'
import '@nomicfoundation/hardhat-ethers'
import 'hardhat-dependency-compiler'

import { defineChainTasks } from './tasks/chain'

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.25',
    settings: {
      optimizer: {
        enabled: true,
        runs: 150
      }
    }
  },
  dependencyCompiler: {
    paths: [
      '@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol',
      '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol',
      '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol'
    ]
  }
}

defineChainTasks()

export default config
