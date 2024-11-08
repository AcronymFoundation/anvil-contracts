import { time } from '@nomicfoundation/hardhat-network-helpers'
import { BaseContract } from 'ethers'

/**
 * Gets the last block time plus the optional number of seconds to add.
 * @param modifyBySeconds The seconds to add to the last block time.
 * @returns The time, in seconds, of the last block plus the adjustment.
 */
export async function lastBlockTime(modifyBySeconds: number = 0): Promise<number> {
  return (await time.latest()) + modifyBySeconds
}

/**
 * Calculates the amount that results from adding a relative fee to the provided amount.
 * Note: this uses integer division, so precision may be lost such that calling this and then `amountBeforeFee` does not
 * produce the starting value.
 * @param amountBeforeFee The amount to which the fee will be added.
 * @param feeBasisPoints The fee in basis points (i.e. 1_000 = 10%).
 * @returns The resulting amount with the provided fee.
 */
export function amountWithFee(amountBeforeFee: BigInt, feeBasisPoints: number): BigInt {
  return (amountBeforeFee.valueOf() * (10_000n + BigInt(feeBasisPoints).valueOf())) / 10_000n
}

/**
 * Calculates the amount that the provided value was prior to the provided relative fee being added to it.
 * Note: this uses integer division, so precision may be lost such that calling this and then `amountWithFee` does not
 * produce the starting value.
 * @param amountAfterFee The amount from which the fee will be removed.
 * @param feeBasisPoints The fee in basis points (i.e. 1_000 = 10%).
 * @returns The value of amountAfterFee before the fee was added to it.
 */
export function amountBeforeFee(amountAfterFee: BigInt, feeBasisPoints: number): BigInt {
  // amountAfterFee = amountBeforeFee.mul(10_000 + feeBasisPoints).div(10_000)
  // amountBeforeFee = amountAfterFee.mul(10_000).div(10_000 + feeBasisPoints)
  return (amountAfterFee.valueOf() * 10_000n) / BigInt(10_000 + feeBasisPoints).valueOf()
}

/**
 * Gets the event args associative array for the transaction and event name in question.
 * Note: this will only work if the event is emitted by the contract that is called.
 * If the event is emitted by another contract than the entrypoint contract, call getWrappedEventArgs(...).
 * @param tx The transaction that was executed.
 * @param contract The contract that declares the event (likely the one that sent the tx).
 * @param eventName The name of the event (e.g. "Transfer").
 * @param eventIndex The index of the event with the provided name to return (if there are multiple).
 */
export async function getEmittedEventArgs(
  tx: any,
  contract: BaseContract,
  eventName: string,
  eventIndex: number = 0
): Promise<any> {
  const receipt = await tx.wait()
  let currIndex = 0
  for (const log of receipt.logs) {
    const parsed = contract.interface.parseLog(log)
    if (!parsed || parsed?.name != eventName || currIndex++ != eventIndex) {
      continue
    }

    const args: any = {}
    for (let i = 0; i < parsed.fragment.inputs.length; i++) {
      args[parsed.fragment.inputs[i].name] = parsed.args[i]
    }

    return args
  }

  throw new Error(
    `Event "${eventName}" not found in transaction receipt${eventIndex != 0 ? ` at index ${eventIndex}` : ''}`
  )
}
