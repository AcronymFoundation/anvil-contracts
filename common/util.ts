import * as ethers from 'ethers'
import {BaseContract, Signer} from 'ethers'
import { createInterface } from 'readline'
import { HardhatEthersHelpers } from '@nomicfoundation/hardhat-ethers/types'

const { PRIVATE_KEY, ADDRESS_TO_IMPERSONATE, NO_PROMPT } =
  process.env

export const ZERO_ADDRESS = '0x' + '00'.repeat(20)

export function add0x(s: string): string {
  return s.startsWith('0x') ? s : `0x${s}`
}

export function remove0x(s: string): string {
  return s.startsWith('0x') ? s.substring(2) : s
}

/**
 * Gets the chain ID from the given provider.
 * @param p The provider.
 * @return The chainId.
 */
export const chainId = async (p: ethers.Provider): Promise<bigint> => {
  return (await p.getNetwork()).chainId
}

/**
 * @return The current time in seconds (useful for relative blockchain timestamps).
 */
export function currentTimeSeconds(): number {
  return Math.floor(new Date().getTime() / 1000)
}

/**
 * Gets the event args associative array for the transaction and event name in question.
 * Note: this will only work if the event is emitted by the contract that is called.
 * If the event is emitted by another contract than the entrypoint contract, call getWrappedEventArgs(...).
 * @param tx The transaction that was executed.
 * @param contract The [ethers] contract that declares the event (likely the one that sent the tx).
 * @param eventName The name of the event (e.g. "Transfer").
 * @param eventIndex The index of the event with the provided name to return (if there are multiple).
 * @return The associative array of event parameter name => value.
 */
export async function getEmittedEventArgs(
  tx: any,
  contract: BaseContract,
  eventName: string,
  eventIndex: number = 0
): Promise<any> {
  const receipt = !!tx.logs ? tx : await tx.wait()
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

let _signer: Signer
/**
 * Gets the configured signer if one exists, giving precedence to the ADDRESS_TO_IMPERSONATE and PRIVATE_KEY env arguments in that order.
 * Note: this prompts the user with the signer's address so that it is abundantly clear (see promptUser for details on how to override).
 * @param hardhatEthers The hardhat ethers object (accessible as hre.ethers in tasks or from the hardhat lib in scripts).
 * @return The signer.
 */
export const getSigner = async (hardhatEthers: HardhatEthersHelpers): Promise<Signer> => {
  if (!!_signer) {
    return _signer
  }

  let signer: Signer
  if (!!ADDRESS_TO_IMPERSONATE && isValidEthereumAddress(ADDRESS_TO_IMPERSONATE)) {
    signer = await hardhatEthers.getImpersonatedSigner(ADDRESS_TO_IMPERSONATE)
  } else if (!!PRIVATE_KEY) {
    signer = new ethers.Wallet(PRIVATE_KEY, hardhatEthers.provider)
  } else {
    const msg = 'No PRIVATE_KEY, or IMPERSONATE_ADDRESS configured in env, aborting'
    console.error(msg)
    throw new Error(msg)
  }

  const address = await signer.getAddress()
  await promptUser(`use address: ${address}? [y/N]: `)
  _signer = signer
  return _signer
}

/**
 * NB: this is used if the event is emitted by a contract other than the one that was called.
 * The receipt will look something like this:
 *   events: [{"transactionIndex":0,"blockNumber":15,"transactionHash":"0x59d3f3cb2cc7f4d42e6d91a15ddbd4d81bd047b29edaec3bf8a11f3b5b73c6f2","address":"0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6","topics":["0x1308fdc3dbdef1f1bcb4ebbcc09e5ba17212b7f3af231b1ee0f254a17b35e9bb","0x0000000000000000000000000000000000000000000000000000000000000001","0x00000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c8"],"data":"0x0000000000000000000000008a791620dd6260079bf849dc5567adc3f2fdc3180000000000000000000000005fbdb2315678afecb367f032d93f642f64180aa30000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000032","logIndex":0,"blockHash":"0xc37430a107bc60b2e96eb406dad0bb923a55ddd1152fa22b83db46162b2c5c33"}]
 * @param tx The transaction the yielded the event.
 * @param eventAbiString The ABI of the event (e.g. "event Transfer(address indexed from, address indexed to, uint value)").
 * @return The associative array of event param name => value.
 */
export async function getWrappedEventArgs(tx: any, eventAbiString: string): Promise<any> {
  const receipt = await tx.wait()
  const eventInterface: ethers.Interface = new ethers.Interface([eventAbiString])
  for (const ev of receipt.logs) {
    try {
      const resp = eventInterface.parseLog(ev)
      if (!resp) continue
      const args: any = {}
      for (let i = 0; i < resp.fragment.inputs.length; i++) {
        args[resp.fragment.inputs[i].name] = resp.args[i]
      }
      return args
    } catch {
      // swallow error, move onto next event
    }
  }
  throw new Error(`event not found matching ABI ${eventAbiString}`)
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
          log("User prompt rejected. Exiting...", true)
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
 * JSON stringify util that handles bigint objects.
 * @param obj The object to stringify
 * @return The resulting string.
 */
export function safeStringify(obj: unknown) {
  return JSON.stringify(obj, (key, value) => (typeof value === 'bigint' ? value.toString() : value))
}

/**
 * Sleeps for the provided number of milliseconds.
 * @param millis The duration to sleep.
 */
export const sleep = async (millis: number): Promise<void> => {
  return new Promise((resolve) => setTimeout(resolve, millis))
}

/**
 * Returns whether the provided string is truthy.
 * @param s The string (or undefined).
 * @return True if truthy, false otherwise.
 */
export const truthy = (s: string | undefined): boolean => {
  return !!s && s != '' && s != '0' && s.toLowerCase() != 'false'
}
