#!/bin/bash

# After running deploy-bridge.sh (which deploys all the contracts),
# We need to wait for SP1Helios to be updated with some new state root in order to generate a proof for the L2.
# Currently, the SP1Helios deployments aren't very stable so we use an SP1HeliosMock which allows us to set the state root manually.

# This address is an ERC4337 entry point with lots of activity (as of 2025-05-20)
# Useful for testing cast logs polling
# ADDRESS=0x0000000071727De22E5E9d8BAf0edAc6f37da032


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR
source ../envs/bls-local.env

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
            echo "$current_head"
            return 0
        fi
        
        echo "Waiting for new head... Current head: $current_head" >&2
        sleep $sleep_interval
    done
}

poll_contract_for_new_head $SP1HELIOS_ADDRESS $L2_RPC_URL 10