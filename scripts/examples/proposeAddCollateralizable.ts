import { ethers } from 'hardhat'
import {getSigner, isValidEthereumAddress, log} from '../../common/util'
import {
  getProposalAsPrintableString,
  newProposal,
  newProposalCall,
  Proposal,
  ProposalCall,
  propose
} from '../../common/governance'
import {Contract} from "ethers";
import {getCollateralVaultAddress} from "../../common/contracts";
import {verifyVotingPower} from "./util";

const collateralizableAddresses = process.env.COLLATERALIZABLE_ADDRESSES
const parsedAddresses = (collateralizableAddresses || '').split(',').map(x => x.trim()).filter(x => x !== '')

const getAddCollateralizableProposalCall = async (): Promise<ProposalCall> => {
  const vault: Contract = await ethers.getContractAt('CollateralVault', getCollateralVaultAddress())

  if (!parsedAddresses.length || parsedAddresses.filter(x => !isValidEthereumAddress(x)).length > 0) {
    console.error(`ERROR: COLLATERALIZABLE_ADDRESSES variable is not populated or does not contain a valid comma-separated list of addresses.`)
    process.exit(1)
  }

  const approvals = parsedAddresses.map(collateralizableAddress => {
    return {
      collateralizableAddress,
      isApproved: true
    }
  })

  const approvalUpdates = await vault.upsertCollateralizableContractApprovals.populateTransaction(approvals)

  return newProposalCall(await vault.getAddress(), approvalUpdates.data!)
}

/**
 * Usage: COLLATERALIZABLE_ADDRESSES="someAddressHere" npx hardhat run --network localhost scripts/examples/proposeAddCollateralizable.ts
 */
async function main() {
  // Just to prompt for address now rather than later
  const signer = await getSigner(ethers)

  await verifyVotingPower(ethers, signer)

  const description = parsedAddresses.length > 1
    ? `Adds ${parsedAddresses} as approved collateralizable contracts in the vault ${getCollateralVaultAddress()}`
    : `Adds ${parsedAddresses} as an approved collateralizable contract in the vault ${getCollateralVaultAddress()}`

  const proposal: Proposal = newProposal([await getAddCollateralizableProposalCall()], description)

  log(`Creating the following proposal: ${getProposalAsPrintableString(proposal)}`)
  const resp = await propose(ethers, proposal, signer)

  log(`Proposal Created. Proposal ID: ${resp.proposalId}`)
}

main()
  .catch((error) => {
    console.error(`ERROR: ${error}`)
    process.exit(1)
  })
  .finally(() => {
    process.exit(0)
  })
