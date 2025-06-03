import { ethers } from 'hardhat'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { baseSetup } from '../setup'
import { amountBeforeFee, lastBlockTime } from '../util'
import { expect } from 'chai'
import { getModifyCollateralizableTokenAllowanceSignature } from '../cryptography'
import { getEmittedEventArgs } from '../../common/util'

describe('LetterOfCredit', function () {
  it('Should create a dynamic LOC', async function () {
    const { creator, beneficiary, vault, letterOfCredit, creditedToken, collateralToken } = await loadFixture(baseSetup)

    const creditedTokenAmount: bigint = BigInt(
      (await letterOfCredit.getCreditedToken(await creditedToken.getAddress())).minPerDynamicLOC
    ).valueOf()
    let collateralTokenAmount: bigint

    const creditedDecimals = BigInt(await creditedToken.decimals()).valueOf()
    const collateralDecimals = BigInt(await collateralToken.decimals()).valueOf()

    // NB: 1:1 exchange rate, but it needs to account for decimals
    const outputPerUnitInputTokenPrice: bigint = 1n
    let exponent: number = Number(creditedDecimals) - Number(collateralDecimals)

    if (creditedDecimals > collateralDecimals) {
      // NB: 3x so collateral factor basis points of ~3333
      collateralTokenAmount = 3n * (creditedTokenAmount / 10n ** (creditedDecimals - collateralDecimals))
    } else {
      collateralTokenAmount = 3n * (creditedTokenAmount * 10n ** (collateralDecimals - creditedDecimals))
    }

    await collateralToken.connect(creator).approve(await vault.getAddress(), collateralTokenAmount)
    await vault
      .connect(creator)
      .depositToAccount(await creator.getAddress(), [await collateralToken.getAddress()], [collateralTokenAmount])

    const expirationSeconds = await lastBlockTime(+3600)

    const allowanceSignature = await getModifyCollateralizableTokenAllowanceSignature(
      creator,
      (
        await vault.runner.provider.getNetwork()
      ).chainId,
      await letterOfCredit.getAddress(),
      await collateralToken.getAddress(),
      collateralTokenAmount,
      await vault.nonces(
        await creator.getAddress(),
        await vault.COLLATERALIZABLE_TOKEN_ALLOWANCE_ADJUSTMENT_TYPEHASH()
      ),
      await vault.getAddress()
    )

    const tx = await letterOfCredit
      .connect(creator)
      .createDynamicLOC(
        await beneficiary.getAddress(),
        await collateralToken.getAddress(),
        collateralTokenAmount,
        await creditedToken.getAddress(),
        creditedTokenAmount,
        expirationSeconds,
        ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'int32'], [outputPerUnitInputTokenPrice, exponent]),
        allowanceSignature
      )

    const ev: any = await getEmittedEventArgs(tx, letterOfCredit, 'LOCCreated')
    expect(ev.creator).to.equal(await creator.getAddress(), 'creator address mismatch')
    expect(ev.beneficiary).to.equal(await beneficiary.getAddress(), 'beneficiary address mismatch')
    expect(ev.collateralTokenAddress).to.equal(await collateralToken.getAddress(), 'collateral address mismatch')
    expect(ev.collateralTokenAmount.toString()).to.equal(collateralTokenAmount.toString(), 'collateral amount mismatch')

    const expectedClaimable = amountBeforeFee(collateralTokenAmount, Number(await vault.withdrawalFeeBasisPoints()))
    expect(ev.claimableCollateral.toString()).to.equal(
      expectedClaimable.toString(),
      'claimable collateral amount mismatch'
    )

    expect(ev.creditedTokenAddress).to.equal(await creditedToken.getAddress(), 'credited address mismatch')
    expect(ev.creditedTokenAmount.toString()).to.equal(creditedTokenAmount.toString(), 'credited amount mismatch')
    expect(ev.expirationTimestamp.toString()).to.equal(expirationSeconds.toString(), 'expiration mismatch')

    const expectedCollateralFactorBasisPoints = (
      await letterOfCredit.getCollateralFactor(await collateralToken.getAddress(), await creditedToken.getAddress())
    ).collateralFactorBasisPoints
    expect(ev.collateralFactorBasisPoints.toString()).to.equal(
      expectedCollateralFactorBasisPoints,
      'collateral factor basis points mismatch'
    )
  })
})
