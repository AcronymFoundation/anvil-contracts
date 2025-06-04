
/* Deployed mainnet contract addresses */
const anvlAddress = '0x2Ca9242c1810029Efed539F1c60D68B63AD01BFc'
export const getAnvlAddress = () => process.env.ANVL_ADDRESS || anvlAddress

const anvilGovernorDelegateAddress = '0xfe1118cE38818EA3C167929eacb6310CDc42a361'
export const getAnvilGovernorDelegateAddress = () => process.env.ANVL_GOVERNOR_DELEGATE_ADDRESS || anvilGovernorDelegateAddress

const anvilGovernorDelegatorAddress = '0x00e83d0698FAf01BD080A4Dd2927e6aB7C4874c9'
export const getAnvilGovernorDelegatorAddress = () => process.env.ANVIL_GOVERNOR_DELEGATOR_ADDRESS || anvilGovernorDelegatorAddress

const anvilTimelockAddress = '0x4eeB7c5BB75Fc0DBEa4826BF568FD577f62cad21'
export const getTimelockAddress = () => process.env.ANVIL_TIMELOCK_ADDRESS || anvilTimelockAddress

const claimAddress = '0xeFd194D4Ff955E8958d132319F31D2aB9f7E29Ac'
export const getClaimAddress = () => process.env.ANVIL_CLAIM_ADDRESS || claimAddress

const collateralVaultAddress = '0x5d2725fdE4d7Aa3388DA4519ac0449Cc031d675f'
export const getCollateralVaultAddress = () => process.env.COLLATERAL_VAULT_ADDRESS || collateralVaultAddress

const letterOfCreditProxyAddress = '0x14db9a91933aD9433E1A0dB04D08e5D9EF7c4808'
export const getLetterOfCreditProxyAddress = () => process.env.LETTER_OF_CREDIT_PROXY_ADDRESS || letterOfCreditProxyAddress

const letterOfCreditSingletonAddress = '0x750Ab78B4fe51292d1F0053845AACe3eA959D5AD'
export const getLetterOfCreditSingletonAddress = () => process.env.LETTER_OF_CREDIT_SINGLETON_ADDRESS || letterOfCreditSingletonAddress

const letterOfCreditProxyAdminAddress = '0x12225bB169b38EF8849DD4F5Cc466ae5996e341D'
export const getLetterOfCreditProxyAdminAddress = process.env.LETTER_OF_CREDIT_PROXY_ADMIN_ADDRESS || letterOfCreditProxyAdminAddress

const pythPriceOraceAddress = '0xC6f3405c861Fa0dca04EC4BA59Bc189D1d56Ee05'
export const getPythPriceOraceAddress = () => process.env.PYTH_PRICE_ORALCE_ADDRESS || pythPriceOraceAddress

const timeBasedCollateralPoolSingletonAddress = '0xCc437a7Bb14f07de09B0F4438df007c8F64Cf29f'
export const getTimeBasedCollateralPoolSingletonAddress = () => process.env.TIME_BASED_COLLATERAL_POOL_SINGLETON_ADDRESS || timeBasedCollateralPoolSingletonAddress

const timeBasedCollateralPoolBeaconAddress = '0x1f00D6f7C18a8edf4f8Bb4Ead8a898aBDd9c9E14'
export const getTimeBasedCollateralPoolBeaconAddress = () => process.env.TIME_BASED_COLLATERAL_POOL_BEACON_ADDRESS || timeBasedCollateralPoolBeaconAddress

const rewardAddress = '0xC6a06f2D000b8CFDd392C4d6AB715a9ff1dA22dA'
export const getRewardAddress = () => process.env.REWARD_ADDRESS || rewardAddress
