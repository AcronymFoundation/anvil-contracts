import { ethers } from 'hardhat'
import {log} from "../../common/util";
import {Contract, ContractFactory} from "ethers";
import {
  getCollateralVaultAddress,
  getTimeBasedCollateralPoolBeaconAddress,
  getTimeBasedCollateralPoolSingletonAddress,
} from "../../common/contracts";

// NB: This may be executed easily on a fork of an existing environment via `bin/examples/deployAndApproveTBCPBeaconProxy.sh`. See that file for more info.

// TBCP constructor / proxy initialization parameters.
// See TimeBasedCollateralPool.sol's initialize(...) function for documentation on each parameter.
const tbcpEpochSeconds = 123456
const tbcpAdminAddress = `0x${'aa'.repeat(20)}`
const tbcpClaimantAddress = `0x${'cc'.repeat(20)}`
const tbcpDefaultClaimDestinationAddress = `0x${'dc'.repeat(20)}`
const tbcpClaimRouterAddress = `0x${'c1'.repeat(20)}`
const tbcpPoolResetterAddress = `0x${'ff'.repeat(20)}`

async function main() {
  const vault: Contract = await ethers.getContractAt('CollateralVault', getCollateralVaultAddress())
  const tbcpSingleton: Contract = await ethers.getContractAt('TimeBasedCollateralPool', getTimeBasedCollateralPoolSingletonAddress())
  const tbcpBeacon: Contract = await ethers.getContractAt('BeaconProxy', getTimeBasedCollateralPoolBeaconAddress())

  log(`deploying TBCP proxy...`)

  // Create the call to TBCP.initialize, but do not send it. We'll pass it's calldata to the BeaconProxy constructor.
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
  // NB: Use this if you want deployment to be as cheap as possible. You can still look up the beacon and implementation by storage slot.
  // See `tasks/proxy.ts` for more information.
  const BeaconProxy: ContractFactory = await ethers.getContractFactory('BeaconProxy')
  const tbcpProxy: Contract = <Contract>(
    await BeaconProxy.deploy(await tbcpBeacon.getAddress(), stakePoolProxyInitTx.data)
  )

  await tbcpProxy.waitForDeployment()
  log(`TimeBasedCollateralPoolProxy deployed to:`)
  // New address is the last line printed for ease of parsing programmatically
  log(`${await tbcpProxy.getAddress()}`)
}

main().catch((error) => {
  console.error(`ERROR: ${error}`)
  process.exitCode = 1
})