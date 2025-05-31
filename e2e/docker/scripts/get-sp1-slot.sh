#!/bin/bash

# After running deploy-bridge.sh (which deploys all the contracts),
# We need to wait for SP1Helios to be updated with some new state root in order to generate a proof for the L2.
# Currently, the SP1Helios deployments aren't very stable so we use an SP1HeliosMock which allows us to set the state root manually.

# This address is an ERC4337 entry point with lots of activity (as of 2025-05-20)
# Useful for testing cast logs polling
# ADDRESS=0x0000000071727De22E5E9d8BAf0edAc6f37da032

# Exit on any error
set -e

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
cd "$SCRIPTS_DIR"

if [ "$IS_SP1HELIOS_MOCK" = "1" ]; then
    echo "SP1Helios is mocked, not using slot number" >&2
    echo 0
    exit 0
fi

TARGET_BLOCK_NUMBER=$(cast block latest --rpc-url $L1_RPC_URL --json | jq -r '.number' | cast to-dec)

poll_contract_for_new_head() {
    local contract_address=$1
    local rpc_url=$2
    local sleep_interval=${3:-10}

    # Starting head
    local initial_head=$(cast call $contract_address "head()(bytes32)" --rpc-url $rpc_url | cast to-dec)

    while true; do
        # Get current head
        local current_head=$(cast call $contract_address "head()(bytes32)" --rpc-url $rpc_url | cast to-dec)
        
        # Check if head has changed
        if [ "$current_head" != "$initial_head" ]; then
            echo "Found new head: $current_head" >&2
            
            # Get the execution block number for this slot
            local execution_block_number=$(curl --request GET --url ${BEACON_CHAIN_RPC}/eth/v2/beacon/blocks/${current_head} | jq -r ".data.message.body.execution_payload.block_number")
            
            # Check if the execution block number is greater than target
            if [ "$execution_block_number" -gt "$TARGET_BLOCK_NUMBER" ]; then
                echo "Found slot with execution block number $execution_block_number > $TARGET_BLOCK_NUMBER" >&2
                echo "$current_head"
                return 0
            else
                echo "Slot $current_head has execution block number $execution_block_number <= $TARGET_BLOCK_NUMBER, continuing to poll..." >&2
                initial_head=$current_head
            fi
        fi
        
        echo "Waiting for new head... Current head: $current_head" >&2
        sleep $sleep_interval
    done
}

poll_contract_for_new_head $SP1HELIOS_ADDRESS $L2_RPC_URL 10