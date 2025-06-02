#!/bin/sh
# Util file to be sourced in other scripts, not direclty called.

# NB: address #0 that hardhat funds with ETH in local chains
HARDHAT_TEST_ACCOUNT_0=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

error() {
  if [ "$#" -gt "0" ]; then
    errorMsg=$1
    echo "error: $errorMsg" >&2
  fi
  exit 1
}

kill_node() {
  if [ "${NODE_PID+x}" ]; then
      echo "killing node..."

      pkill -P "$NODE_PID"
      kill "$NODE_PID"
  fi
}

# Kills the provided process ID no matter how this script exits
# param1: the process ID to kill
kill_node_on_exit() {
  # Kill the node no matter how this script exits
  trap kill_node EXIT HUP INT TERM
}

# Forks ethereum network via hardhat using the provider URL passed.
# param1: the relative path to the root directory (i.e. 'sol-contracts/').
# param2: the provider URL to use (e.g. https://eth-mainnet.g.alchemy.com/v2/<someKeyHere>).
# returns: The process ID of the node via set_function_result.
fork_blockchain() {
  [ "$#" -gt "0" ] || error "$fork_blockchain param 1 missing"
  path_to_root=$1
  shift

  [ "$#" -gt "0" ] || error "$fork_blockchain param 2 missing"
  provider_url=$1
  shift

  if [ "${NODE_PID+x}" ]; then
    error "blockchain is already forked; cannot call fork_blockchain"
  fi

  echo "\n********************"
  echo "forking blockchain..."
  echo "********************"

  cd "$path_to_root" > /dev/null 2>&1

  npx hardhat node --fork "$provider_url" > /dev/null 2>&1 &
  NODE_PID="$!"
  # echo "NODE PID: $NODE_PID"

  until NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$address" SILENT=1  npx hardhat --network localhost getBlocktime > /dev/null 2>&1; do
    echo "Waiting for node to come up. Retrying in 2 seconds..."
    sleep 2
  done

  cd - > /dev/null 2>&1

  echo "blockchain forked."
}