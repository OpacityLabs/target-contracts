#!/bin/bash

# After running deploy-bridge.sh (which deploys all the contracts),
# We need to wait for SP1Helios to be updated with some new state root in order to generate a proof for the L2.
# Currently, the SP1Helios deployments aren't very stable so we use an SP1HeliosMock which allows us to set the state root manually.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR
source ../envs/bls-local.env

# If using mock SP1Helios, just get latest L1 block number
if [ "$IS_SP1HELIOS_MOCK" = "1" ]; then
    echo "Using mock SP1Helios, getting latest L1 block number"
    LATEST_BLOCK=$(cast block --rpc-url $L1_RPC_URL latest --json | jq -r '.number')
    echo $LATEST_BLOCK
    exit 0
fi

if [ -z "$SP1HELIOS_ADDRESS" ]; then
    echo "Error: SP1HELIOS_ADDRESS is not set in the environment variables."
    exit 1
fi

# Function to get the current head from SP1Helios
get_current_head() {
    result=$(cast call $SP1HELIOS_ADDRESS "head()" --rpc-url $L2_RPC_URL 2>&1)
    if [ $? -ne 0 ]; then
        echo "Error calling contract: $result"
        return 1
    fi
    echo "$result"
}

# Get initial head
echo "Attempting to get initial head..."
initial_head=$(get_current_head)
if [ $? -ne 0 ]; then
    echo "Failed to get initial head"
    exit 1
fi
echo "Initial head: $initial_head"

# TODO this currently gets the latest beacon chain slot which is not what we want
# we want latest execution state root, so we need to fetch last update transaction, reads its logs and from there get the block number and not slot number

# Poll until we get a new header
while true; do
    current_head=$(get_current_head)
    if [ $? -ne 0 ]; then
        echo "Failed to get current head"
        exit 1
    fi
    # lexographical comparison works here because both hex strings are the same length
    if [[ "0x${current_head#0x}" > "0x${initial_head#0x}" ]]; then
        current_head=$(cast to-dec $current_head)
        echo "New header found at block: $current_head"
        exit 0
    fi
    echo "Waiting for new header..."
    sleep 5
done