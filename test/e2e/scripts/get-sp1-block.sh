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

# Function to poll for contract logs
# Usage: poll_contract_logs <contract_address> <rpc_url> <block_check_interval>
poll_contract_logs() {
    local contract_address=$1
    local rpc_url=$2
    local block_check_interval=$3

    # Get initial block number
    local initial_block=$(cast block --rpc-url $rpc_url latest --json | jq -r '.number')
    # Using next block to not accidentally skip a block
    local next_block=$((initial_block + block_check_interval))
    echo "Starting from block: $initial_block" >&2

    while true; do
        # Get current block number
        local current_block=$(cast block --rpc-url $rpc_url latest --json | jq -r '.number')
        
        # Check if enough blocks have passed
        if [ $((current_block - initial_block)) -ge $block_check_interval ]; then
            echo "Checking for logs from block $initial_block to $current_block" >&2
            
            # Try to get logs
            local log=$(cast logs --address $contract_address \
                --from-block $initial_block \
                --to-block $current_block \
                --json \
                --rpc-url $rpc_url | jq -c '.[-1]')
            
            echo "log: $log" >&2
            
            # Check if we got any logs
            if [ "$log" != "null" ] && [ ! -z "$log" ] && [ "$log" != "[]" ]; then
                echo "Found log:" >&2
                echo "$log" | tee /dev/stderr
                return 0
            fi
            
            # Update initial block for next iteration
            initial_block=$next_block
            next_block=$((initial_block + block_check_interval))
        fi
        
        echo "Waiting for more blocks... Current block: $current_block" >&2
        sleep 5
    done
}

prepare_sp1_proof() {
    local tx_hash=$1
    local rpc_url=$2
    local sp1_address=$3

    local tx_caldata=$(cast tx $tx_hash --json --rpc-url $rpc_url | jq -r ".input")
    local tx_calldata_decoded=$(cast decode-calldata --json "update(bytes,bytes)" $tx_caldata)
    local public_values_raw=$(echo $tx_calldata_decoded | jq -r .[1])
    # NOTICE: didn't find in cast how to decode arbitrary structs, so we treat as if it's the input to a function
    local proof_outputs_raw=$(cast abi-decode --input --json "dummyFunctionName((bytes32,bytes32,bytes32,uint256,bytes32,uint256,bytes32,bytes32))" $public_values_raw | jq -r .[0])
    # Remove parentheses and split into array
    local proof_outputs=($(echo $proof_outputs_raw | tr -d '()' | tr ',' ' '))
    local execution_state_root=${proof_outputs[0]}
    local new_head=${proof_outputs[3]}

    echo "executionStateRoot: $execution_state_root" >&2
    echo "newHead: $new_head" >&2

    # Get the current head from SP1Helios contract and convert from bytes32 to integer
    local current_head=$(cast call $sp1_address "head()(bytes32)" --rpc-url $rpc_url | cast to-dec)
    
    # Compare heads
    if [ "$current_head" != "$new_head" ]; then
        echo "Error: Heads don't match. SP1Helios head: $current_head, New head: $new_head" >&2
        exit 1
    fi
    
    echo "Heads match: $current_head" >&2
    echo "{\"head\": \"$current_head\", \"executionStateRoot\": \"$execution_state_root\"}" | jq .
}

# Check if IS_SP1HELIOS_MOCK is set
if [ -z "$IS_SP1HELIOS_MOCK" ]; then
    echo "Error: IS_SP1HELIOS_MOCK is not set in the environment variables."
    exit 1
fi

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

# # Call the polling function
poll_results=$(poll_contract_logs $ADDRESS $L2_RPC_URL 10)
tx_hash=$(echo "$poll_results" | tail -n 1 | jq -r '.transactionHash')

# Print the transaction hash
echo "Transaction hash: $tx_hash"

execution_state_root=$(prepare_sp1_proof $tx_hash $L2_RPC_URL $SP1HELIOS_ADDRESS)
echo "Execution state root: $execution_state_root"