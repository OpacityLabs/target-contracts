#!/bin/bash

#######################################################################
# IMPORTANT NOTICE:                                                     #
# This script generates mock proofs for testing purposes when          #
# SP1Helios is mocked.                                                 #
#######################################################################

# Exit on any error
set -e

source $SCRIPTS_DIR/config.sh
# Check if slot number argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <slot_number>"
    exit 1
fi

# Slot number is mock
SLOT_NUMBER=$1

STORAGE_SLOT=0
OUTPUT_FILE="$ARTIFACTS_DIR/middlewareDataProof.json"

echo "SP1Helios is mocked, getting SP1Helios address from registry coordinator mimic..."
L1_DEPLOY_PATH="$ARTIFACTS_DIR/l1-deploy.json"
L2_DEPLOY_PATH="$ARTIFACTS_DIR/l2-deploy.json"
REGISTRY_COORDINATOR_MIMIC=$(cat $L2_DEPLOY_PATH | jq -r '.registryCoordinatorMimic')
MIDDLEWARE_SHIM=$(cat $L1_DEPLOY_PATH | jq -r '.middlewareShim')
SP1HELIOS_ADDRESS=$(cast call $REGISTRY_COORDINATOR_MIMIC "LITE_CLIENT()(address)" --rpc-url $L2_RPC_URL)
echo "SP1Helios address: $SP1HELIOS_ADDRESS"

MIDDLEWARE_BLOCK_NUMBER=$(cast call $MIDDLEWARE_SHIM "lastBlockNumber()" --rpc-url $L1_RPC_URL | cast to-dec)
LATEST_BLOCK=$(cast block latest --rpc-url $L1_RPC_URL --json | jq -r '.number')
PROOF_DATA=$(cast proof -B $LATEST_BLOCK $MIDDLEWARE_SHIM $STORAGE_SLOT --json --rpc-url $L1_RPC_URL | jq '.')
EXECUTION_STATE_ROOT=$(cast block $LATEST_BLOCK --rpc-url $L1_RPC_URL --json | jq -r '.stateRoot')

# Set the execution state root on the SP1Helios mock
cast send $SP1HELIOS_ADDRESS "setExecutionStateRoot(uint256,bytes32)" $SLOT_NUMBER $EXECUTION_STATE_ROOT --rpc-url $L2_RPC_URL --private-key $DEPLOYER_KEY > /dev/null 2>&1
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
echo "Mock proof generation completed" 