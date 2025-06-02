import { ethers } from 'hardhat'
import {log} from "../../common/util";
import {Contract, ContractFactory} from "ethers";

// NB: This may be executed easily on a fork of an existing environment via `bin/examples/deployTBCPBeaconProxy.sh`. See that file for more info.

// See: README.md for defaults. These can be overridden by env vars with the same name.
const DEFAULT_COLLATERAL_VAULT_CONTRACT_ADDRESS= '0x5d2725fdE4d7Aa3388DA4519ac0449Cc031d675f'
const DEFAULT_TBCP_BEACON_ADDRESS= '0x1f00D6f7C18a8edf4f8Bb4Ead8a898aBDd9c9E14'
const DEFAULT_TBCP_SINGLETON_ADDRESS= '0xCc437a7Bb14f07de09B0F4438df007c8F64Cf29f'

// TBCP constructor / proxy initialization parameters.
// See TimeBasedCollateralPool.sol's initialize(...) function for documentation on each parameter.
const tbcpEpochSeconds = 123456
const tbcpAdminAddress = `0x${'aa'.repeat(20)}`
const tbcpClaimantAddress = `0x${'cc'.repeat(20)}`
const tbcpDefaultClaimDestinationAddress = `0x${'dc'.repeat(20)}`
const tbcpClaimRouterAddress = `0x${'c1'.repeat(20)}`
const tbcpPoolResetterAddress = `0x${'ff'.repeat(20)}`

async function main() {
  const vault: Contract = await ethers.getContractAt('CollateralVault', process.env.COLLATERAL_VAULT_CONTRACT_ADDRESS || DEFAULT_COLLATERAL_VAULT_CONTRACT_ADDRESS)
  const tbcpSingleton: Contract = await ethers.getContractAt('TimeBasedCollateralPool', process.env.TBCP_SINGLETON_ADDRESS || DEFAULT_TBCP_SINGLETON_ADDRESS)
  const tbcpBeacon: Contract = await ethers.getContractAt('BeaconProxy', process.env.TBCP_BEACON_ADDRESS || DEFAULT_TBCP_BEACON_ADDRESS)

  log(`deploying TBCP proxy...`)

  const stakePoolProxyInitTx = await tbcpSingleton.initialize.populateTransaction(
    await vault.getAddress(),
    tbcpEpochSeconds,
    tbcpDefaultClaimDestinationAddress,
    tbcpAdminAddress,
    tbcpClaimantAddress,
    tbcpClaimRouterAddress,
    tbcpPoolResetterAddress
  )

  // NB: Use this if you want to be able to query beacon and implementation easily.
  // const BeaconProxy: ContractFactory = await ethers.getContractFactory('VisibleBeaconProxy')
  // NB: Use this if you want deployment to be as cheap as possible. You can still look up beacon and implementation by storage slot.
  const BeaconProxy: ContractFactory = await ethers.getContractFactory('BeaconProxy')
  const tbcpProxy: Contract = <Contract>(
    await BeaconProxy.deploy(await tbcpBeacon.getAddress(), stakePoolProxyInitTx.data)
  )

  await tbcpProxy.waitForDeployment()
  log(`TimeBasedCollateralPoolProxy deployed to ${await tbcpProxy.getAddress()}`)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(`ERROR: ${error}`)
  process.exitCode = 1
})