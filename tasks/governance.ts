import {getGovernanceProxyContract} from "../common/governance";
import {HardhatRuntimeEnvironment} from "hardhat/types";
import {add0x, currentTimeSeconds, getEmittedEventArgs, getSigner, log, promptUser, truthy} from "../common/util";
import {task} from "hardhat/config";
import {getAnvilGovernorDelegatorAddress, getAnvlAddress, getClaimAddress} from "../common/contracts";

const getProposal = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { proposalId } = args

  const proxy = await getGovernanceProxyContract(hre.ethers)
  const [targets, values, calldatas, _descriptionHash] = await proxy.proposalDetails(BigInt(proposalId))
  const [againstVotes, forVotes, abstainVotes] = await proxy.proposalVotes(BigInt(proposalId))

  const state = await getProposalStateString(proposalId, hre)

  let etaString = 'n/a'
  if (state !== 'Executed' && state != 'Expired') {
    const eta = Number(await proxy.proposalEta(proposalId))

    if (eta != 0) {
      const etaSeconds = eta - currentTimeSeconds()
      etaString = etaSeconds < 0 ? 'now' : `${etaSeconds.toString(10)} seconds from now`
    }
  }

  log(`{
  id: ${proposalId},
  targets: [${targets.join(', ')}],
  values: [${values.map((x: any) => x.toString()).join(', ')}],
  calldatas: [${calldatas.join(', ')}],
  currentBlock: ${(await proxy.runner!.provider!.getBlockNumber()).toString()},
  voteStartBlock: ${(await proxy.proposalSnapshot(proposalId)).toString()}
  voteEndBlock: ${(await proxy.proposalDeadline(proposalId)).toString()}
  proposalExecutable: ${etaString}
  forVotes: ${forVotes.toString()},
  againstVotes: ${againstVotes.toString()},
  abstainVotes: ${abstainVotes.toString()},
  state: ${state} (may change on tx submission since that will be a new block),
}`)
}

const getProposalAt = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { index, valueOnly } = args

  const proxy = await getGovernanceProxyContract(hre.ethers)

  // NB: proposalDetailsAt return: (proposalId, targets, values, calldatas, descriptionHash)
  const details = await proxy.proposalDetailsAt(index)
  if (truthy(valueOnly)) {
    log(`${details[0]}`, true)
  } else {
    await getProposal({ proposalId: details[0] }, hre)
  }
}

const getProposalCount = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const {valueOnly} = args
  const proxy = await getGovernanceProxyContract(hre.ethers)

  const count = await proxy.proposalCount()
  if (truthy(valueOnly)) {
    log(`${count}`, true)
  } else {
    log(`Proposal count: ${count}`)
  }
}

const getProposalStateString = async (proposalId: string, hre: HardhatRuntimeEnvironment): Promise<string> => {
  const proxy = await getGovernanceProxyContract(hre.ethers)

  try {
    const state = await proxy.state(proposalId)
    switch (state) {
      case 0n:
        return 'Pending'
      case 1n:
        return 'Active'
      case 2n:
        return 'Canceled'
      case 3n:
        return 'Defeated'
      case 4n:
        return 'Succeeded'
      case 5n:
        return 'Queued'
      case 6n:
        return 'Expired'
      case 7n:
        return 'Executed'
      default:
        return 'Unknown'
    }
  } catch (e) {
    return 'Unknown'
  }
}

/*** STATE MODIFYING FUNCTIONS ***/

const castVote = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { proposalId, support, reason, v, r, s } = args

  await getProposal(args, hre)

  await promptUser(`Vote ${support === '0' ? 'against' : support === '1' ? 'for' : 'to abstain from'} proposal? [y/N] `)

  const proxy = await getGovernanceProxyContract(hre.ethers)

  let tx
  if (!!reason) {
    tx = await proxy.castVoteWithReason(BigInt(proposalId), parseInt(support), reason)
  } else if (!!v && !!r && !!s) {
    tx = await proxy.castVoteBySig(BigInt(proposalId), parseInt(support), add0x(v), add0x(r), add0x(s))
  } else {
    tx = await proxy.castVote(BigInt(proposalId), parseInt(support))
  }
  await tx.wait(1)

  log(`vote cast for proposal ${proposalId}: ${support}`)

  await getProposal(args, hre)
}

const delegateVotes = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { toAddress } = args

  const signer = await getSigner(hre.ethers)
  const anvlContract = await hre.ethers.getContractAt('Anvil', getAnvlAddress(), signer)

  const claimContract = await hre.ethers.getContractAt('Claim', getClaimAddress(), signer)

  const signerAddress = await signer.getAddress()
  const balance = await anvlContract.balanceOf(signerAddress)
  const provenUnclaimed = await claimContract.getProvenUnclaimedBalance(signerAddress)
  const totalBalance = balance.valueOf() + provenUnclaimed.valueOf()

  const delegate = toAddress || signerAddress
  const tx = await anvlContract.delegate(delegate)
  await tx.wait(1)

  log(`delegated ${totalBalance.toString()} votes to ${delegate}`)
}

const queueProposal = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { proposalId } = args

  const proxy = await getGovernanceProxyContract(hre.ethers)
  // NB: this method of accessing `queue` is necessary because the proxy.queue function is overloaded with two signatures
  // This overload comes from the GovernorStorageUpgradeable contract
  const tx = await proxy['queue(uint256)'](BigInt(proposalId))
  await tx.wait(1)

  const ev = await getEmittedEventArgs(tx, proxy, 'ProposalQueued')
  await tx.wait(1)

  log(`proposal ${ev.proposalId} queued!`)

  await getProposal(args, hre)
}

const executeProposal = async (args: any, hre: HardhatRuntimeEnvironment): Promise<void> => {
  const { proposalId } = args

  const proxy = await getGovernanceProxyContract(hre.ethers)
  // NB: this method of accessing `execute` is necessary because the proxy.execute function is overloaded with two signatures
  // This overload comes from the GovernorStorageUpgradeable contract
  const txData = (await proxy['execute(uint256)'].populateTransaction(BigInt(proposalId))).data!
  const gasRes = await proxy.runner!.provider!.estimateGas({
    to: await proxy.getAddress(),
    value: 0,
    data: txData
  })
  log(`gas estimate: ${gasRes.toLocaleString()}`)

  const tx = await proxy['execute(uint256)'](BigInt(proposalId))
  await tx.wait(1)

  const ev = await getEmittedEventArgs(tx, proxy, 'ProposalExecuted')

  log(`proposal ${ev.proposalId} executed!`)

  await getProposal(args, hre)
}


export const defineGovernanceTasks = () => {

  // example: npx hardhat --network localhost getProposalAt --index 0
  task('getProposalAt', 'Gets the proposal at the provided index')
    .addParam('index', 'The index in the proposals list')
    .addOptionalParam('valueOnly', 'If set to a truthy value, will only log the value')
    .setAction(getProposalAt)

  // example: npx hardhat --network localhost getProposalCount
  task('getProposalCount', 'Gets the number of proposals that currently exist')
    .addOptionalParam('valueOnly', 'If set to a truthy value, will only log the value')
    .setAction(getProposalCount)

  /*** STATE MODIFYING FUNCTIONS ***/

  // example: npx hardhat --network localhost castVote --proposal-id 1 --support 1 --reason "because I can"
  task('castVote', 'Casts a vote for the provided proposal')
    .addParam('proposalId', 'The ID of the proposal to vote on')
    .addParam('support', 'The vote value: 0 = against, 1 = for, 2 = abstain')
    .addOptionalParam('reason', 'The reason associated with the vote, if there is one')
    .setAction(castVote)

  // example: npx hardhat --network localhost delegate --to-address "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
  task('delegate', 'Delegates votes from the calling address to the specified address')
    .addOptionalParam(
      'toAddress',
      'The address to which votes will be delegated. If empty, calling address will be used.'
    )
    .setAction(delegateVotes)

  // example: npx hardhat --network localhost queueProposal --proposal-id 1
  task('queueProposal', 'Queues the proposal with the provided data')
    .addParam('proposalId', 'The ID of the proposal to queue')
    .setAction(queueProposal)

  // example: npx hardhat --network localhost executeProposal --proposal-id 1
  task('executeProposal', 'Executes the proposal with the provided data')
    .addParam('proposalId', 'The ID of the proposal to execute')
    .setAction(executeProposal)
}