import { ethers } from 'ethers'

/**
 * Creates the hash of a UTF-8 string exactly as keccak256("some string") would in solidity.
 * @param str The string to hash.
 */
export const hashString = (str: string): string => {
  return ethers.keccak256(ethers.toUtf8Bytes(str))
}
