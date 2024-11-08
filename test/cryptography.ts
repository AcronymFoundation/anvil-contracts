import { Signer, TypedDataDomain, TypedDataField } from 'ethers'

const CollateralizableTokenAllowanceAdjustmentType: Record<string, Array<TypedDataField>> = {
  CollateralizableTokenAllowanceAdjustment: [
    { name: 'collateralizableAddress', type: 'address' },
    { name: 'tokenAddress', type: 'address' },
    { name: 'allowanceAdjustment', type: 'int256' },
    { name: 'approverNonce', type: 'uint256' }
  ]
}

interface EIP712Preimage {
  domain: TypedDataDomain
  type: Record<string, Array<TypedDataField>>
  value: Record<string, any>
}

/**
 * Creates the modifyCollateralizableTokenAllowancePreimage that can be used with `signer._signTypedData(...)` to create
 * an EIP-712 signature to modify the collateralizable token allowance for the approver within the Collateral contract.
 * @param chainId The chain ID for which this preimage will be valid.
 * @param collateralizableAddress The collateralizable contract address for which the token allowance is being modified.
 * @param tokenAddress The address of the token for which the allowance is being modified.
 * @param allowanceAdjustment The amount by which the allowance will be adjusted.
 * @param approverNonce The signature nonce of the approver (future signer).
 * @param collateralContractAddress The collateral contract address to which the signature will be submitted.
 * @returns The populated modifyCollateralizableTokenAllowancePreimage that may be used to create the signature.
 */
function getModifyCollateralizableTokenAllowancePreimage(
  chainId: BigInt,
  collateralizableAddress: string,
  tokenAddress: string,
  allowanceAdjustment: BigInt,
  approverNonce: BigInt,
  collateralContractAddress: string
): EIP712Preimage {
  return {
    domain: {
      name: 'CollateralVault',
      version: '1',
      chainId: chainId.valueOf(),
      verifyingContract: collateralContractAddress
    },
    type: CollateralizableTokenAllowanceAdjustmentType,
    value: {
      collateralizableAddress,
      tokenAddress,
      allowanceAdjustment,
      approverNonce
    }
  }
}

/**
 * Creates a signature to be sent to the modifyCollateralizableTokenAllowanceWithSignature function with the provided
 * signer and parameters.
 * @param signer The signer to use to create the signature.
 * @param chainId The chain ID for which this preimage will be valid.
 * @param collateralizableAddress The collateralizable contract address for which the token allowance is being modified.
 * @param tokenAddress The address of the token for which the allowance is being modified.
 * @param allowanceAdjustment The amount by which the allowance will be adjusted.
 * @param approverNonce The signature nonce of the approver (future signer).
 * @param collateralContractAddress The collateral contract address to which the signature will be submitted.
 * @returns The signed data ready to send to the Collateral contract.
 */
export async function getModifyCollateralizableTokenAllowanceSignature(
  signer: Signer,
  chainId: BigInt,
  collateralizableAddress: string,
  tokenAddress: string,
  allowanceAdjustment: BigInt,
  approverNonce: BigInt,
  collateralContractAddress: string
): Promise<string> {
  const preimage = getModifyCollateralizableTokenAllowancePreimage(
    chainId,
    collateralizableAddress,
    tokenAddress,
    allowanceAdjustment,
    approverNonce,
    collateralContractAddress
  )
  return signer.signTypedData(preimage.domain, preimage.type, preimage.value)
}
