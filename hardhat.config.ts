import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-chai-matchers'
import '@nomicfoundation/hardhat-ethers'
import 'hardhat-dependency-compiler'

import { defineChainTasks } from './tasks/chain'
import { defineGovernanceTasks } from './tasks/governance'
import { defineTokenTasks } from './tasks/token'
import { defineProxyTasks } from './tasks/proxy'

// NB: Will need to set this to interact with non-localhost environments.
const { PROVIDER_URL } = process.env
// If compiling LetterOfCredit contract
const optimizerRuns = 833
// If not compiling LetterOfCredit contract
// const optimizerRuns = 999999

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.25',
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: optimizerRuns
      }
    }
  },
  dependencyCompiler: {
    paths: [
      '@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol',
      '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol',
      '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol',
      '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol'
    ]
  },
  networks: {
    sepolia: {
      url: `${PROVIDER_URL}`
    },
    mainnet: {
      url: `${PROVIDER_URL}`
    },
    hardhat: {}
  }
}

defineChainTasks()
defineGovernanceTasks()
defineProxyTasks()
defineTokenTasks()

export default config
