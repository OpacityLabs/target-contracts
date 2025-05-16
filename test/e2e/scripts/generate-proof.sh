#!/bin/bash

#######################################################################
# IMPORTANT NOTICE:                                                     #
# The block number needs to be a block number the SP1Helios has an     #
# execution state root for.                                            #
#######################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR
source ../envs/bls-local.env

# Check if block number argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <block_number>"
    exit 1
fi

BLOCK_NUMBER=$1

# Get the directory this script is in
OUTPUT_FILE="${SCRIPT_DIR}/artifacts/middlewareDataProof.json"

L1_DEPLOY_PATH="${SCRIPT_DIR}/artifacts/l1-deploy.json"
MIDDLEWARE_SHIM=$(cat $L1_DEPLOY_PATH | jq -r '.middlewareShim')

if [ -z "$MIDDLEWARE_SHIM" ] || [ "$MIDDLEWARE_SHIM" = "null" ]; then
    echo "Error: Could not find middleware shim address in l1-deploy file"
    exit 1
fi

# Storage slot 0 contains the middlewareDataHash
STORAGE_SLOT=0

# Get the proof data using cast
PROOF_DATA=$(cast proof -B $BLOCK_NUMBER $MIDDLEWARE_SHIM $STORAGE_SLOT --rpc-url $L1_RPC_URL | jq '.')

# Get the execution state root using cast block
EXECUTION_STATE_ROOT=$(cast block $BLOCK_NUMBER --rpc-url $L1_RPC_URL --json | jq -r '.stateRoot')

# Create the custom proof layout
CUSTOM_PROOF=$(jq -n \
    --arg blockNumber "$BLOCK_NUMBER" \
    --arg storageHash "$(echo $PROOF_DATA | jq -r '.storageHash')" \
    --arg executionStateRoot "$EXECUTION_STATE_ROOT" \
    --argjson storageProof "$(echo $PROOF_DATA | jq -r '.storageProof[0].proof')" \
    --argjson accountProof "$(echo $PROOF_DATA | jq -r '.accountProof')" \
    '{
        "blockNumber": $blockNumber,
        "storageHash": $storageHash,
        "executionStateRoot": $executionStateRoot,
        "storageProof": $storageProof,
        "accountProof": $accountProof
    }')

# Write the custom proof to the output file
echo "$CUSTOM_PROOF" > $OUTPUT_FILE