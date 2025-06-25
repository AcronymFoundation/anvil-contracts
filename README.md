# Anvil Protocol

## Overview
Anvil is a decentralized finance (DeFi) protocol for the issuance of fully secured credit. 
The protocol's Ethereum-based smart contracts allow users to deposit collateral in a vault, 
issue collateral-backed letters of credit, and make vault-based tokens available to collateral 
pools. Anvil's mission is to provide flexible building blocks to bring efficient and transparent 
collateralized finance into an increasingly decentralized world.

## Local Development
### Dependencies
* NodeJS 20 (recommended via [NVM](https://github.com/nvm-sh/nvm))

### Installing, building, and running tests
* `nvm i` (if using NVM)
* `npm i`
* `npm run build`
* `npm test`

### Testing
There are some sample tests that can be run via `npm run test`.

You may also easily run example scripts on a fork of an existing environment (e.g. mainnet). See [./bin/examples](./bin/examples) for more info.

### Tools
There are various Hardhat tasks defined in the [tasks/](tasks/) directory and scripts in the [scripts/](scripts/) directory. They may be useful for querying information about and interacting with deployed contracts and/or deploying contracts.
Disclaimer: The Anvil team does not represent that any of these tools work as described. Please read the code and repurpose and use them at your own risk.

Note that to use these tasks, you'll need to set the `PRIVATE_KEY` environment variable. For read-only tasks, that address does not need any ETH, and in all cases, using an address with as little ETH as possible to accomplish your goals is recommended.

If not using a local node, you'll also need to set the `PROVIDER_URL` environment variable to the Ethereum JSON RPC provider URL to use.

Example:
```
# Note: private key is a well-known test key in this case
PROVIDER_URL="https://eth-mainnet.g.alchemy.com/v2/yourKeyHere" \
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" \
npx hardhat --network mainnet getProxyImplementation --proxy-address 0x14db9a91933aD9433E1A0dB04D08e5D9EF7c4808
```

## Documentation
Protocol Documentation: https://docs.anvil.xyz/protocol-concepts

Performed Audits: https://docs.anvil.xyz/audits

There are also example scripts in [./scripts/examples](./scripts/examples) and examples that can be run on a [mainnet] fork in [./bin/examples](./bin/examples).
Note: you will need to set the `PRIVATE_KEY` environment variable (and also the `PROVIDER_URL` environment variable if not pointing to a local node). See the `Testing` section above for more info. 

## Mainnet Contract Addresses

| Name                              | Address                                                                                                                 |
|-----------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| Anvil                             | [0x2Ca9242c1810029Efed539F1c60D68B63AD01BFc](https://etherscan.io/address/0x2Ca9242c1810029Efed539F1c60D68B63AD01BFc)   |
| AnvilGovernorDelegate             | [0xfe1118cE38818EA3C167929eacb6310CDc42a361](https://etherscan.io/address/0xfe1118cE38818EA3C167929eacb6310CDc42a361)   |
| AnvilGovernorDelegator            | [0x00e83d0698FAf01BD080A4Dd2927e6aB7C4874c9](https://etherscan.io/address/0x00e83d0698FAf01BD080A4Dd2927e6aB7C4874c9)   |
| AnvilTimelock                     | [0x4eeB7c5BB75Fc0DBEa4826BF568FD577f62cad21](https://etherscan.io/address/0x4eeB7c5BB75Fc0DBEa4826BF568FD577f62cad21)   |
| Claim                             | [0xeFd194D4Ff955E8958d132319F31D2aB9f7E29Ac](https://etherscan.io/address/0xeFd194D4Ff955E8958d132319F31D2aB9f7E29Ac)   |
| CollateralVault                   | [0x5d2725fdE4d7Aa3388DA4519ac0449Cc031d675f](https://etherscan.io/address/0x5d2725fdE4d7Aa3388DA4519ac0449Cc031d675f)   |
| LetterOfCredit Proxy              | [0x14db9a91933aD9433E1A0dB04D08e5D9EF7c4808](https://etherscan.io/address/0x14db9a91933aD9433E1A0dB04D08e5D9EF7c4808)   |
| LetterOfCredit Proxy Admin        | [0x12225bB169b38EF8849DD4F5Cc466ae5996e341D](https://etherscan.io/address/0x12225bB169b38EF8849DD4F5Cc466ae5996e341D)   |
| LetterOfCredit Singleton          | [0x24573B112456d3a96c97fB460B436e8CA870e27E](https://etherscan.io/address/0x24573B112456d3a96c97fB460B436e8CA870e27E)   |
| PassThroughLiquidator             | [0x9ae1CAA5cE6fA330fcE98315159BCD433B1342b8](https://etherscan.io/address/0x9ae1CAA5cE6fA330fcE98315159BCD433B1342b8)   |
| Permit2PassThroughLiquidator      | [0x8Aa57e442e4562c80FDDAD1b71ADF0BA75E2eb4C](https://etherscan.io/address/0x8Aa57e442e4562c80FDDAD1b71ADF0BA75E2eb4C)   |
| PythPriceOracle                   | [0xC6f3405c861Fa0dca04EC4BA59Bc189D1d56Ee05](https://etherscan.io/address/0xC6f3405c861Fa0dca04EC4BA59Bc189D1d56Ee05)   |
| Reward                            | [0xC6a06f2D000b8CFDd392C4d6AB715a9ff1dA22dA](https://etherscan.io/address/0xC6a06f2D000b8CFDd392C4d6AB715a9ff1dA22dA)   |
| TimeBasedCollateralPool Singleton | [0xCc437a7Bb14f07de09B0F4438df007c8F64Cf29f](https://etherscan.io/address/0xCc437a7Bb14f07de09B0F4438df007c8F64Cf29f)   |
| TimeBasedCollateralPool Beacon    | [0x1f00D6f7C18a8edf4f8Bb4Ead8a898aBDd9c9E14](https://etherscan.io/address/0x1f00D6f7C18a8edf4f8Bb4Ead8a898aBDd9c9E14)   |
| UniswapLiquidator                 | [0x716321565e1EAbA200789E14ad92c9dA40B14589](https://etherscan.io/address/0x716321565e1EAbA200789E14ad92c9dA40B14589)   |

## Contract Descriptions
### Anvil.sol
Anvil’s ERC-20 governance token contract with extended functionality in order to allow 
for Governance participation by claimants with provable balances in `Claim.sol`. 
This allows claimants to delegate voting power of both vested and unvested 
tokens in the `Claim` contract in addition to balances held in their wallets.

### AnvilGovernorDelegate.sol
Governance logic contract delegated to by `AnvilGovernorDelegator.sol`. 
This utilizes OpenZeppelin’s 
[GovernorUpgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/governance/GovernorUpgradeable.sol) 
contract.

### AnvilGovernorDelegator.sol
Upgradeable proxy contract utilizing OpenZeppelin’s 
[ERC1967Proxy.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/ERC1967/ERC1967Proxy.sol) 
that delegates Governance logic to the `AnvilGovernorDelegate.sol` implementation.

### AnvilTimelock.sol
Implementation of OpenZeppelin’s 
[TimeLockController.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/TimelockController.sol) 
to allow for time delay before Governance updates. Currently, this deployed contract’s 
address owns `CollateralVault.sol`, `LetterOfCredit.sol`, `PythPriceOracle.sol`.

### Claim.sol
Claim contract for the one-time initial issuance of Anvil tokens. 
Initialization sets a Merkle root for balance proofs as well as details regarding 
token vesting (delay to start, vesting period). While this contract can be directly 
called to claim vested tokens, initial proof of token balances held in this contract 
and all delegation actions must be done through `Anvil.sol`. 

### CollateralVault.sol
Vault to house collateral across the protocol, tracking available and reserved balances 
for each account including `TimeBasedCollateralPool` instances. This contract serves as the 
primary entrypoint into and exit point from the protocol. The vault is compatible with 
ERC-20 tokens that have been approved via Governance. It also maintains a record of which 
other contracts have been approved to interact with it, both by the protocol and the 
individual accounts.

### LetterOfCredit.sol
Contract for the creation, management, and redemption of collateralized Letters of Credit(“LOCs”) 
between two parties: a creator and a beneficiary. LOCs consist of a reserved collateral 
amount from the creator (housed in `CollateralVault.sol`) and a credited amount 
(in either the same collateral token or a different token) claimable by the beneficiary. 
In the event that the collateral and credited tokens are different (a “dynamic LOC”), 
the LOC must be overcollateralized and is subject to liquidation if at risk. Every supported 
asset pair has an `AssetPairCollateralFactor` configuration that defines the creation and 
liquidation thresholds along with the incentive to the liquidator to process the conversion. 
This contract’s token support is configured with ERC-20 tokens that must also be supported by the 
`CollateralVault.sol` and `PythPriceOracle.sol` as well as their respective maximum usage 
limits. Note: `LetterofCredit` is deployed as a proxy that delegates to a singleton contract.

### PassThroughLiquidator.sol
A flexible liquidator that allows calldata a target to be configured off-chain and passed through the LetterOfCredit
contract to accomplish liquidation. This allows more complex liquidation strategies and the use of many different protocols
generically. See the contract details for information on how to encode the pass-through data that configures liquidation.

### Permit2PassThroughLiquidator.sol
A flexible liquidator that allows calldata a target to be configured off-chain and passed through the LetterOfCredit
contract to accomplish liquidation. This allows more complex liquidation strategies and the use of many different protocols
generically. See the contract details for information on how to encode the pass-through data that configures liquidation.
The difference between this contract and `PassThroughLiquidator` is that this contract assumes that the target contract 
uses the Permit2 contract to manage approvals rather than ERC-20.

### Pricing.sol
A contract of math-related helpers to support `CollateralVault.sol`, `PythPriceOracle.sol`, and 
`TimeBasedCollateralPool.sol`in pricing calculations.

### PythPriceOracle.sol
Price oracle utilizing [Pyth](https://www.pyth.network/) that provides data to `LetterOfCredit.sol` for functions that 
require recent and accurate pricing. Pyth makes whole token-to-USD prices available, whereas Anvil protocol contracts need
token-to-token prices in the most granular units possible, so this adapter contract pieces X-to-USD and Y-to-USD 
prices together to get a X-to-Y price without loss of precision. This contract must be configured with the [Pyth price 
feed ids](https://www.pyth.network/developers/price-feed-ids) for all supported tokens in the `LetterOfCredit.sol` contract.

### Refundable.sol
Contract that exposes a function modifier that may be used to ensure that calls to the modified function refund any ETH 
to the caller that was passed to the function and not used in the function's execution.

### Reward.sol
Generic reward contract enabling cumulative reward publishing and claiming via Merkle roots by rewarded accounts. It may
be configured to use any ERC-20 token for rewards. The `Reward.sol` address listed above uses `ANVL` as the reward token.

### SignatureNonces.sol
Built on OpenZeppelin’s 
[Nonces.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Nonces.sol), 
this contract provides protocol-wide nonces per account per operation for use in signatures in order to 
ensure data synchronization, prevent replay attacks, and allow for signature cancellation.

### SignatureNoncesUpgradeable.sol
Upgradeable version of `SignatureNonces` built based on OpenZeppelin’s
[NoncesUpgradeable.sol](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/utils/NoncesUpgradeable.sol),


### TimeBasedCollateralPool.sol
A singleton contract that defines the protocol mechanism for multi-party collateral pooling for the benefit of a 
specified claimant. Defines the logic for participation in a pool via staking one or many different types 
of ERC-20 tokens compatible with `CollateralVault.sol` in exchange for corresponding stake units on a per 
token basis. It also defines a predictable and trustless unstaking process via utilizing a pool’s configured epoch time 
period. Pool instances may be created by standing up a proxy contract (such as `VisibleBeaconProxy.sol`), configuring
its beacon to be the Anvil governance-managed [Beacon](https://etherscan.io/address/0x1f00D6f7C18a8edf4f8Bb4Ead8a898aBDd9c9E14), 
and submitting a Governance proposal to have the `CollateralVault` accept the proxy as an approved collaterizable 
contract. The benefit of using this proxy pattern is that the implementation is easily upgraded and maximally 
lightweight via separating state storage (in the proxy contract) from core logic (this contract).

### UniswapLiquidator.sol
A simple liquidator that may be configured and used to convert at-risk LOCs. There are much more efficient and 
profit-maximizing liquidators that can and hopefully will be written by 3rd party liquidators, but it is in Anvil's 
best interest to have many functioning liquidators that guarantee that at-risk LOCs are converted, so Anvil has
provided an implementation using UniswapV2 liquidity that others may use.

### VisibileBeaconProxy.sol
Extends OpenZeppelin’s [BeaconProxy](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/beacon/BeaconProxy.sol) 
to make the implementation and beacon publicly-accessible via getters.

## Discussion
For any concerns with the protocol, please open an issue and/or visit us on [Discord](https://discord.gg/esfFn3dedz) to discuss.

For security concerns, please email security@anvil.xyz.

© Copyright 2025, Acronym Foundation