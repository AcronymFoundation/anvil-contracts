#!/bin/sh
# Script to test deploying a TBCP proxy on an Ethereum fork.
# Note: PROVIDER_URL env var must be set. Create a free account at Infura, Alchemy, etc. to get a valid URL for your environment.
# Example: PROVIDER_URL="https://eth-mainnet.g.alchemy.com/v2/yourKeyHere" ./deployAndApproveTBCPBeaconProxy.sh

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
echo "Deploying TBCP proxy..."
echo "********************"

tbcp_proxy_address=$(NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$HARDHAT_TEST_ACCOUNT_0" npx hardhat run --network localhost scripts/examples/deployTBCPBeaconProxy.ts | tail -n 1)
echo "TBCP proxy deployed to $tbcp_proxy_address"

echo "\n********************"
echo "Creating proposal to add TBCP to vault..."
echo "********************"

# NB: This is a "dead" address, meaning that tokens it has shouldn't ever move. It has > 1B ANVL.
address_with_delegated_anvil=0x000000000000000000000000000000000000dEaD
# Fund account with ETH
ADDRESS_TO_IMPERSONATE="$HARDHAT_TEST_ACCOUNT_0" NO_PROMPT=1 npx hardhat --network localhost transferEth --to-address "$address_with_delegated_anvil" --amount 1000000000000000000
# Self-delegate ANVL so this address can propose
ADDRESS_TO_IMPERSONATE="$address_with_delegated_anvil" NO_PROMPT=1 npx hardhat --network localhost delegate

# Run proposal script
NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$address_with_delegated_anvil" COLLATERALIZABLE_ADDRESS="$tbcp_proxy_address" npx hardhat run --network localhost scripts/examples/proposeAddCollateralizable.ts

# Get proposal ID
proposal_count=$(NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$HARDHAT_TEST_ACCOUNT_0" npx hardhat --network localhost getProposalCount --value-only "y")
proposal_index=$((proposal_count - 1))
proposal_id=$(NO_PROMPT=1 ADDRESS_TO_IMPERSONATE="$HARDHAT_TEST_ACCOUNT_0" npx hardhat --network localhost getProposalAt --index "$proposal_index" --value-only "y")

# Pass proposal.
execute_proposal "$path_to_root" "$proposal_id"

cd - > /dev/null 2>&1
