#!/bin/bash

#######################################################################
# IMPORTANT NOTICE:                                                     #
# The block number needs to be a block number the SP1Helios has an     #
# execution state root for.                                            #
#######################################################################

# Exit on any error
set -e

source $SCRIPTS_DIR/config.sh

# Check if block number argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <slot_number>"
    exit 1
fi

SLOT_NUMBER=$1
SLOT_BLOCK_NUMBER=$(curl --request GET --url ${BEACON_CHAIN_RPC}/eth/v2/beacon/blocks/${SLOT_NUMBER} | jq -r ".data.message.body.execution_payload.block_number")

OUTPUT_FILE="$ARTIFACTS_DIR/middlewareDataProof.json"
L1_DEPLOY_PATH="$ARTIFACTS_DIR/l1-deploy.json"
MIDDLEWARE_SHIM=$(cat $L1_DEPLOY_PATH | jq -r '.middlewareShim')

if [ -z "$MIDDLEWARE_SHIM" ] || [ "$MIDDLEWARE_SHIM" = "null" ]; then
    echo "Error: Could not find middleware shim address in l1-deploy file"
    exit 1
fi

# Storage slot 0 contains the middlewareDataHash
STORAGE_SLOT=0

echo "SLOT_BLOCK_NUMBER: $SLOT_BLOCK_NUMBER"

MIDDLEWARE_BLOCK_NUMBER=$(cast call $MIDDLEWARE_SHIM "lastBlockNumber()" --rpc-url $L1_RPC_URL | cast to-dec)
# Get the proof data using cast
PROOF_DATA=$(cast proof -B $SLOT_BLOCK_NUMBER $MIDDLEWARE_SHIM $STORAGE_SLOT --rpc-url $L1_RPC_URL | jq '.')
# Get the execution state root using cast block
EXECUTION_STATE_ROOT=$(cast block $SLOT_BLOCK_NUMBER --rpc-url $L1_RPC_URL --json | jq -r '.stateRoot')

# Create the custom proof layout
CUSTOM_PROOF=$(jq -n \
    --arg middlewareBlockNumber "$MIDDLEWARE_BLOCK_NUMBER" \
    --arg slotNumber "$SLOT_NUMBER" \
    --arg storageHash "$(echo $PROOF_DATA | jq -r '.storageHash')" \
    --arg executionStateRoot "$EXECUTION_STATE_ROOT" \
    --argjson storageProof "$(echo $PROOF_DATA | jq -r '.storageProof[0].proof')" \
    --argjson accountProof "$(echo $PROOF_DATA | jq -r '.accountProof')" \
    '{
        "middlewareBlockNumber": $middlewareBlockNumber,
        "slotNumber": $slotNumber,
        "storageHash": $storageHash,
        "executionStateRoot": $executionStateRoot,
        "storageProof": $storageProof,
        "accountProof": $accountProof
    }')

# Write the custom proof to the output file
echo "$CUSTOM_PROOF" > $OUTPUT_FILE