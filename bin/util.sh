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

# Executes a proposal on a running localhost node via hardhat.
# NB: This expects the node to already be running and the proposal to be created.
# param1: the relative path to the root directory (i.e. 'anvil-contracts/').
# param2: the id of the proposal to execute.
execute_proposal() {
  [ "$#" -gt "0" ] || error "execute_proposal param 1 missing"
  path_to_root=$1
  shift

  [ "$#" -gt "0" ] || error "execute_proposal param 2 missing"
  proposal_id=$1
  shift

  cd "$path_to_root" > /dev/null 2>&1

  echo "\n********************"
  echo "executing proposal id $proposal_id..."
  echo "********************"

  (
    set -e

    address=$HARDHAT_TEST_ACCOUNT_0

    # Top 5 delegate addresses at the time of writing. May need to update this if it changes.
    voters="0xbA10d0f5D3F380d173aF531B7B15e59702C9cecE 0x80ae8fb747378f63b89bed2f0187a6eec9fff9b8 0xcA2274626d5e7BCa87feff45BC40A0D8626Bba6B 0xB933AEe47C438f22DE0747D57fc239FE37878Dd1 0x71553dF14eFe2708BF16734AAB821af239A24d3B"
    echo "funding voter accounts..."
    for voter in $voters; do
      ADDRESS_TO_IMPERSONATE="$address" NO_PROMPT=1 npx hardhat --network localhost transferEth --to-address "$voter" --amount 1000000000000000000
    done

    address=0xbA10d0f5D3F380d173aF531B7B15e59702C9cecE

    echo "skipping forward until voting period..."
    # Skip forward 2 days in blocks to start voting period (+1 for a small amount of padding)
    NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$address" npx hardhat --network localhost mine --blocks-to-advance 14401

    echo "voting from accounts ($voters)..."
    for voter in $voters; do
      NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$voter" npx hardhat --network localhost castVote --proposal-id "$proposal_id" --support 1
    done

    echo "skipping forward past voting period..."
    # Skip forward 5 days in blocks to start voting period (+1 for a small amount of padding)
    NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$address" npx hardhat --network localhost mine --blocks-to-advance 36001

    echo "queueing proposal..."
    NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$address" npx hardhat --network localhost queueProposal --proposal-id "$proposal_id"

    echo "skipping forward until proposal is executable..."
    # Warp forward 1+ weeks
    NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$address" npx hardhat --network localhost warp --seconds 605000

    echo "executing proposal..."
    NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$address" npx hardhat --network localhost executeProposal --proposal-id "$proposal_id"

    echo "proposal executed."
  )

  cd - > /dev/null 2>&1
}