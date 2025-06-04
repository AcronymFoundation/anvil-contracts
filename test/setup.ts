import { ethers } from 'hardhat'
import { Contract, ContractFactory } from 'ethers'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getEmittedEventArgs } from '../common/util'

export interface TestInput {
  vault: Contract
  priceOracle: Contract
  letterOfCredit: Contract
  letterOfCreditProxyAdmin: Contract
  letterOfCreditSingleton: Contract
  mockLiquidator: Contract
  collateralToken: Contract
  creditedToken: Contract
  owner: HardhatEthersSigner
  creator: HardhatEthersSigner
  beneficiary: HardhatEthersSigner
  liquidator: HardhatEthersSigner
  other: HardhatEthersSigner
}

interface CreditedTokenConfig {
  tokenAddress: string
  minPerDynamicLOC: BigInt
  maxPerDynamicLOC: BigInt
  globalMaxInDynamicUse: BigInt
}

interface CollateralFactor {
  creationCollateralFactorBasisPoints: BigInt
  collateralFactorBasisPoints: BigInt
  liquidatorIncentiveBasisPoints?: BigInt
}

interface AssetPairCollateralFactor {
  collateralTokenAddress: string
  creditedTokenAddress: string
  collateralFactor: CollateralFactor
}

interface CollateralizableContractApprovalConfig {
  collateralizableAddress: string
  isApproved: boolean
}

export async function baseSetup(): Promise<TestInput> {
  // Contracts are deployed using the first signer/account by default
  const [owner, creator, beneficiary, liquidator, other] = await ethers.getSigners()

  /*** Deploy test token contracts ***/

  const TestToken: ContractFactory = await ethers.getContractFactory('TestToken')
  const collateralToken: Contract = <Contract>await TestToken.deploy('A', 'AYE', 6)
  const creditedToken: Contract = <Contract>await TestToken.deploy('B', 'BEE', 18)

  /*** Deploy CollateralVault with approved collateral tokens ***/

  const CollateralVault: ContractFactory = await ethers.getContractFactory('CollateralVault')
  const vault: Contract = <Contract>await CollateralVault.deploy([
    { enabled: true, tokenAddress: await collateralToken.getAddress() },
    { enabled: true, tokenAddress: await creditedToken.getAddress() }
  ])

  /*** Deploy mock price oracle ***/

  const PriceOracle: ContractFactory = await ethers.getContractFactory('MockPriceOracle')
  const priceOracle: Contract = <Contract>await PriceOracle.deploy()

  /*** Deploy LetterOfCredit via proxy ***/

  const LetterOfCredit: ContractFactory = await ethers.getContractFactory('LetterOfCredit')
  const letterOfCreditSingleton: Contract = <Contract>await LetterOfCredit.deploy()

  const creditedTokens: CreditedTokenConfig[] = [
    {
      tokenAddress: await creditedToken.getAddress(),
      minPerDynamicLOC: 10n * 10n ** BigInt(await creditedToken.decimals()).valueOf(),
      maxPerDynamicLOC: 1000n * 10n ** BigInt(await creditedToken.decimals()).valueOf(),
      globalMaxInDynamicUse: 100_000n * 10n ** BigInt(await creditedToken.decimals()).valueOf()
    }
  ]

  const assetPairCollateralFactors: AssetPairCollateralFactor[] = [
    {
      collateralTokenAddress: await collateralToken.getAddress(),
      creditedTokenAddress: await creditedToken.getAddress(),
      collateralFactor: {
        creationCollateralFactorBasisPoints: 5_000n,
        collateralFactorBasisPoints: 7_500n,
        liquidatorIncentiveBasisPoints: 800n
      }
    }
  ]

  const letterOfCreditInitData = (
    await letterOfCreditSingleton.initialize.populateTransaction(
      await owner.getAddress(),
      await vault.getAddress(),
      await priceOracle.getAddress(),
      300, // 5 minutes
      60 * 60 * 24 * 500, // 500 days
      creditedTokens,
      assetPairCollateralFactors,
      { gasLimit: 30_000_000 }
    )
  ).data!

  const Proxy = await ethers.getContractFactory('TransparentUpgradeableProxy')
  const letterOfCreditProxy = await Proxy.deploy(
    await letterOfCreditSingleton.getAddress(),
    await owner.getAddress(),
    letterOfCreditInitData
  )
  await letterOfCreditProxy.waitForDeployment()

  const adminChangedEv = await getEmittedEventArgs(
    letterOfCreditProxy.deploymentTransaction(),
    letterOfCreditProxy,
    'AdminChanged'
  )

  const letterOfCreditProxyAdmin = await ethers.getContractAt('ProxyAdmin', adminChangedEv.newAdmin, owner)

  const letterOfCredit = await ethers.getContractAt('LetterOfCredit', await letterOfCreditProxy.getAddress(), owner)

  /*** Allow LetterOfCredit to use Vault ***/

  const approval: CollateralizableContractApprovalConfig = {
    collateralizableAddress: await letterOfCredit.getAddress(),
    isApproved: true
  }
  await vault.upsertCollateralizableContractApprovals([approval])

  /*** Deploy Mock Liquidator ***/

  const MockLiquidator: ContractFactory = await ethers.getContractFactory('MockLiquidator')
  const mockLiquidator: Contract = <Contract>await MockLiquidator.deploy()

  /*** Mint test tokens to relevant addresses ***/
  creditedToken.mint(
    await mockLiquidator.getAddress(),
    1_000_000n * 10n ** BigInt(await creditedToken.decimals()).valueOf()
  )

  collateralToken.mint(
    await creator.getAddress(),
    1_000_000n * 10n ** BigInt(await collateralToken.decimals()).valueOf()
  )
  creditedToken.mint(await creator.getAddress(), 1_000_000n * 10n ** BigInt(await creditedToken.decimals()).valueOf())

  return {
    vault,
    priceOracle,
    letterOfCredit,
    letterOfCreditProxyAdmin,
    letterOfCreditSingleton,
    mockLiquidator,
    collateralToken,
    creditedToken,
    owner,
    creator,
    beneficiary,
    liquidator,
    other
  }
}
