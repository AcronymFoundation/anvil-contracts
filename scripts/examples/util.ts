import {Signer} from "ethers";
import {HardhatEthersHelpers} from "@nomicfoundation/hardhat-ethers/types";
import {getAnvlAddress} from "../../common/contracts";
import {getGovernanceProxyContract} from "../../common/governance";
import {getSigner, log} from "../../common/util";

export const verifyVotingPower = async (hardhatEthers: HardhatEthersHelpers, signer: Signer): Promise<void> => {
  const proxy = await getGovernanceProxyContract(hardhatEthers)
  const proposalThreshold = await proxy.proposalThreshold()

  const signerAddress = await signer.getAddress()
  const anvil = await hardhatEthers.getContractAt('Anvil', getAnvlAddress(), await getSigner(hardhatEthers))
  const votes = await anvil.getVotes(signerAddress)

  log('')
  if (votes < proposalThreshold) {
    console.error(
      `Proposal threshold is ${proposalThreshold.toLocaleString()} but ${signerAddress} only has ${
        votes.toLocaleString()
      } delegated votes.`
    )
    process.exit(1)
  } else {
    log(
      `Proposal threshold is ${proposalThreshold.toLocaleString()}, and ${signerAddress} has ${
        votes.toLocaleString()
      } delegated votes.`
    )
  }
  log('')
}