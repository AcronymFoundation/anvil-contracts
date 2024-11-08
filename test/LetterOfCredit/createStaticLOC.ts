import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { baseSetup } from '../setup'
import { amountWithFee, getEmittedEventArgs, lastBlockTime } from '../util'
import { expect } from 'chai'
import { getModifyCollateralizableTokenAllowanceSignature } from '../cryptography'

describe('LetterOfCredit', function () {
  it('Should create a static LOC', async function () {
    const { creator, beneficiary, vault, letterOfCredit, creditedToken } = await loadFixture(baseSetup)

    const creditedTokenAmount: BigInt = (await letterOfCredit.getCreditedToken(await creditedToken.getAddress()))
      .minPerDynamicLOC
    const totalCollateralToBeReserved = amountWithFee(creditedTokenAmount, await vault.withdrawalFeeBasisPoints())

    await creditedToken.connect(creator).approve(await vault.getAddress(), totalCollateralToBeReserved)
    await vault
      .connect(creator)
      .depositToAccount(await creator.getAddress(), [await creditedToken.getAddress()], [totalCollateralToBeReserved])

    const expirationSeconds = await lastBlockTime(+3600)

    const allowanceSignature = await getModifyCollateralizableTokenAllowanceSignature(
      creator,
      (
        await vault.runner.provider.getNetwork()
      ).chainId,
      await letterOfCredit.getAddress(),
      await creditedToken.getAddress(),
      totalCollateralToBeReserved,
      await vault.nonces(
        await creator.getAddress(),
        await vault.COLLATERALIZABLE_TOKEN_ALLOWANCE_ADJUSTMENT_TYPEHASH()
      ),
      await vault.getAddress()
    )

    const tx = await letterOfCredit
      .connect(creator)
      .createStaticLOC(
        await beneficiary.getAddress(),
        await creditedToken.getAddress(),
        creditedTokenAmount,
        expirationSeconds,
        allowanceSignature
      )

    const ev: any = await getEmittedEventArgs(tx, letterOfCredit, 'LOCCreated')
    expect(ev.creator).to.equal(await creator.getAddress(), 'creator address mismatch')
    expect(ev.beneficiary).to.equal(await beneficiary.getAddress(), 'beneficiary address mismatch')
    expect(ev.collateralTokenAddress).to.equal(await creditedToken.getAddress(), 'collateral address mismatch')
    expect(ev.collateralTokenAmount.toString()).to.equal(
      totalCollateralToBeReserved.toString(),
      'collateral amount mismatch'
    )
    expect(ev.claimableCollateral.toString()).to.equal(
      creditedTokenAmount.toString(),
      'claimable collateral amount mismatch'
    )
    expect(ev.creditedTokenAddress).to.equal(await creditedToken.getAddress(), 'credited address mismatch')
    expect(ev.creditedTokenAmount.toString()).to.equal(creditedTokenAmount.toString(), 'credited amount mismatch')
    expect(ev.expirationTimestamp.toString()).to.equal(expirationSeconds.toString(), 'expiration mismatch')
    expect(ev.collateralFactorBasisPoints.toString()).to.equal('0', 'collateral factor basis points mismatch')
  })
})
