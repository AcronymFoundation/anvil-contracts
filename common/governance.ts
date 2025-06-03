import {hashString} from "./crypto";
import {Contract, ContractTransactionResponse, Signer} from 'ethers'
import { getEmittedEventArgs, getSigner, log, safeStringify} from './util'
import { HardhatEthersHelpers } from '@nomicfoundation/hardhat-ethers/types'
import {getAnvilGovernorDelegatorAddress} from "./contracts";


/// Individual call operation within a larger proposal.
export interface ProposalCall {
  target: string
  value: BigInt
  calldata: string
}

/// A governance proposal that can be sent to the governance contract for vote + execution.
export interface Proposal {
  calls: ProposalCall[]
  description: string
}

/// The preimage of a proposal, the hash of which _should_ produce the proposal ID.
export interface ProposalPreimage {
  targets: string[]
  values: bigint[]
  calldatas: string[]
  descriptionHash: string
}

/**
 * Creates a {@link Proposal} from the provided proposal calls and description.
 * @param calls The calls that make up the proposal.
 * @param description The description to include in the proposal.
 * @return The constructed proposal.
 */
export const newProposal = (calls: ProposalCall[], description: string): Proposal => {
  return { calls, description }
}

/**
 * Creates a new {@link ProposalCall} from the provided call information.
 * @param target The address being called.
 * @param calldata The data specifying the function / arguments of the call.
 * @param value The value in wei to be sent with the call operation.
 * @return The proposal call.
 */
export const newProposalCall = (target: string, calldata: string, value: BigInt = 0n): ProposalCall => {
  return { target, calldata, value }
}

/**
 * Calculates the proposal preimage for a {@link Proposal}.
 * @param p The proposal.
 * @return The preimage.
 */
export const getProposalPreimage = (p: Proposal): ProposalPreimage => {
  return {
    targets: p.calls.map((x) => x.target),
    values: p.calls.map((x) => x.value.valueOf()),
    calldatas: p.calls.map((x) => x.calldata),
    descriptionHash: hashString(p.description)
  }
}

/**
 * Gets a well-formatted string from the provided {@link Proposal}. Given the spacing, this is largely meant for human consumption.
 * @param p The proposal from which a string will be returned.
 * @return The string listing the details of the proposal.
 */
export const getProposalAsPrintableString = (p: Proposal): string => {
  let s = `description: ${p.description}
calls:`
  for (let i = 0; i < p.calls.length; i++) {
    s += `
  ${i}:
    target: ${p.calls[i].target},
    calldata: ${p.calls[i].calldata},
    value: ${p.calls[i].value}`
  }
  return s
}

/**
 * Gets the governance proxy contract wired up with the ABI of the delegate it points to with the configured signer.
 * @param hardhatEthers The ethers object bundled into hardhat.
 * @rturn The contract.
 */
export const getGovernanceProxyContract = async (hardhatEthers: HardhatEthersHelpers): Promise<Contract> => {
  // NB: We need the ABI of the delegate but the address of the proxy (delegator) that points to it
  return hardhatEthers.getContractAt('AnvilGovernorDelegate', getAnvilGovernorDelegatorAddress(), await getSigner(hardhatEthers))
}

export interface ProposalResponse {
  proposalId: BigInt
  transaction: ContractTransactionResponse
}

/**
 * Creates the provided {@link Proposal} in the configured governance contract from the configured signer's address.
 * @param hardhatEthers The ethers object bundled into hardhat.
 * @param p The Proposal.
 * @param signer If provided, this signer will be used. If not, the default configured signer will be used.
 * @return The {@link ProposalResponse} with the proposal ID and other info.
 */
export const propose = async (
  hardhatEthers: HardhatEthersHelpers,
  p: Proposal,
  signer?: Signer
): Promise<ProposalResponse> => {
  const proxy: Contract = await getGovernanceProxyContract(hardhatEthers)

  const proposer: Signer = signer || (await getSigner(hardhatEthers))

  const preimage = getProposalPreimage(p)

  const populated = await proxy.propose.populateTransaction(
    preimage.targets,
    preimage.values,
    preimage.calldatas,
    p.description
  )
  log(`transaction to send: ${safeStringify(populated)}`)
  const proxyWithSigner: any = proxy.connect(proposer)
  const tx = await proxyWithSigner.propose(preimage.targets, preimage.values, preimage.calldatas, p.description)

  await tx.wait()

  const ev = await getEmittedEventArgs(tx, proxy, 'ProposalCreated')
  return {
    proposalId: ev.proposalId,
    transaction: tx
  }
}
