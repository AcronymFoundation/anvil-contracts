import * as ethers from 'ethers'
import { Signer} from 'ethers'
import { createInterface } from 'readline'
import { HardhatEthersHelpers } from '@nomicfoundation/hardhat-ethers/types'

const { PRIVATE_KEY, ADDRESS_TO_IMPERSONATE, NO_PROMPT } =
  process.env

export const ZERO_ADDRESS = '0x' + '00'.repeat(20)

/**
 * Gets the chain ID from the given provider.
 * @param p The provider.
 * @return The chainId.
 */
export const chainId = async (p: ethers.Provider): Promise<bigint> => {
  return (await p.getNetwork()).chainId
}

let _signerAddress: string
export const getSignerAddress = async (hardhatHelpers: HardhatEthersHelpers): Promise<string> => {
  if (!!_signerAddress) {
    return _signerAddress
  }
  // getSigner populates the address
  await getSigner(hardhatHelpers)
  return _signerAddress
}

let _signer: Signer
/**
 * Gets the configured signer if one exists, giving prcedents to the ADDRESS_TO_IMPERSONATE and PRIVATE_KEY env arguments in that order.
 * Note: this prompts the user with the signer's address so that it is abundantly clear (see promptUser for details on how to override).
 * @param hardhatHelpers The hardhat ethers object (accessible as hre.ethers in tasks or from the hardhat lib in scripts).
 * @return The signer.
 */
export const getSigner = async (hardhatHelpers: HardhatEthersHelpers): Promise<Signer> => {
  if (!!_signer) {
    return _signer
  }

  let signer: Signer
  if (!!ADDRESS_TO_IMPERSONATE && isValidEthereumAddress(ADDRESS_TO_IMPERSONATE)) {
    signer = await hardhatHelpers.getImpersonatedSigner(ADDRESS_TO_IMPERSONATE)
  } else if (!!PRIVATE_KEY) {
    signer = new ethers.Wallet(PRIVATE_KEY, hardhatHelpers.provider)
  } else {
    const msg = 'No PRIVATE_KEY, or IMPERSONATE_ADDRESS configured in env, aborting'
    console.error(msg)
    throw new Error(msg)
  }

  const address = await signer.getAddress()
  await promptUser(`use address: ${address}? [y/N]: `)
  _signerAddress = await signer.getAddress()
  _signer = signer
  return _signer
}

/**
 * Logs to the console, respecting the SILENT env argument.
 * @param msg The message to log.
 * @param force Force logging, even if SILENT env argument is set.
 */
export const log = (msg: string, force: boolean = false): void => {
  if (force || !truthy(process.env.SILENT)) {
    console.log(msg)
  }
}

/**
 * Returns whether the provided address is a valid ethereum address by running it through EthersJS's parser.
 * @param address The address to validate.
 * @return True if valid, false otherwise.
 */
export const isValidEthereumAddress = (address: string): boolean => {
  try {
    ethers.getAddress(address)
    return true
  } catch {
    return false
  }
}

/**
 * Prompts the CLI user with the provided prompt string, returning the response.
 * NOTE: If the NO_PROMPT env var is set, this prompt will automatically return a truthy string.
 * @param prompt The prompt to display to the user.
 * @param assertYes If set, exits with an exit code of 1 if the value entered is not yes.
 * @return The user's answer as the read input string.
 */
export const promptUser = async (prompt: string, assertYes: boolean = true): Promise<string> => {
  const rl = createInterface(process.stdin, process.stdout)
  return new Promise<string>((resolve, reject) => {
    if (!!NO_PROMPT) {
      resolve('y')
      return
    }

    try {
      rl.question(prompt, (answer: string) => {
        rl.close()
        if (assertYes && !answer.toLowerCase().startsWith('y')) {
          console.log("User prompt rejected. Exiting...")
          process.exit(0)
        }
        resolve(answer)
      })
    } catch (err) {
      reject(err)
    }
  })
}

/**
 * Returns whether the provided string is truthy.
 * @param s The string (or undefined).
 * @return True if truthy, false otherwise.
 */
export const truthy = (s: string | undefined): boolean => {
  return !!s && s != '' && s != '0' && s.toLowerCase() != 'false'
}

/**
 * Sleeps for the provided number of milliseconds.
 * @param millis The duration to sleep.
 */
export const sleep = async (millis: number): Promise<void> => {
  return new Promise((resolve) => setTimeout(resolve, millis))
}