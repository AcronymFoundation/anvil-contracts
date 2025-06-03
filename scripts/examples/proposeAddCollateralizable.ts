import { ethers } from 'hardhat'
import {getSigner, log} from '../../common/util'
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

const collateralizableAddress = process.env.COLLATERALIZABLE_ADDRESS

const getAddCollateralizableProposalCall = async (): Promise<ProposalCall> => {
  const vault: Contract = await ethers.getContractAt('CollateralVault', getCollateralVaultAddress())

  const approvals = [
    {
      collateralizableAddress: collateralizableAddress,
      isApproved: true
    },
  ]

  const approvalUpdates = await vault.upsertCollateralizableContractApprovals.populateTransaction(approvals)

  return newProposalCall(await vault.getAddress(), approvalUpdates.data!)
}

/**
 * Usage: COLLATERALIZABLE_ADDRESS="someAddressHere" npx hardhat run --network localhost scripts/examples/proposeAddCollateralizable.ts
 */
async function main() {
  // Just to prompt for address now rather than later
  const signer = await getSigner(ethers)

  await verifyVotingPower(ethers, signer)

  const description = `Adds ${collateralizableAddress} as an approved collateralizable contract in the vault ${getCollateralVaultAddress()}`

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
