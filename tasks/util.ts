import {Provider} from "ethers";
import {chainId} from "../common/util";
import {mine} from "@nomicfoundation/hardhat-network-helpers";

export const mineIfLocal = async (provider: Provider, blocksToAdvance: number = 1): Promise<boolean> => {
  if ((await chainId(provider)) === 31337n) {
    await mine(blocksToAdvance)
    return true
  }
  return false
}