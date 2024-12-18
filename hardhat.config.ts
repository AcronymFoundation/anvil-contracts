import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-chai-matchers'
import '@nomicfoundation/hardhat-ethers'
import 'hardhat-dependency-compiler'

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
      '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol',
      '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol'
    ]
  }
}

export default config
