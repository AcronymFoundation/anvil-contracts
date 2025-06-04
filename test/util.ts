import { time } from '@nomicfoundation/hardhat-network-helpers'

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
