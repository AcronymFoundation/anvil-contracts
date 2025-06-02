#!/bin/sh
# Script to test deploying a TBCP proxy on an Ethereum fork.
# Note: PROVIDER_URL env var must be set. Create a free account at Infura, Alchemy, etc. to get a valid URL for your environment.
# Example: PROVIDER_URL="https://eth-mainnet.g.alchemy.com/v2/yourKeyHere" ./deployTBCPBeaconProxy.sh

path_to_root="${0%/*}/../.."
. "${path_to_root}/bin/util.sh"

usage() {
   echo "usage: PROVIDER_URL=\"\$(cat providerUrlFile)\" ./deployTBCPBeaconProxy.sh"
   exit 1
}

# ARG PARSING & VALIDATION
[ "$#" -eq "0" ] || usage

if [ -z "${PROVIDER_URL+x}" ]; then
  # This means it was not set as an env var.
  usage
fi

fork_blockchain $path_to_root $PROVIDER_URL
kill_node_on_exit

cd "$path_to_root" > /dev/null 2>&1

echo "\n********************"
echo "Deploying TBCP..."
echo "********************"

NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$HARDHAT_TEST_ACCOUNT_0" npx hardhat run --network localhost scripts/examples/deployTBCPBeaconProxy.ts

cd - > /dev/null 2>&1
