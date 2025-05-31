#!/bin/bash

# Exit on any error
set -e

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
cd "$SCRIPTS_DIR"

# Read addresses from deployment files
L1_DEPLOY_PATH="$ARTIFACTS_DIR/l1-deploy.json"
L2_DEPLOY_PATH="$ARTIFACTS_DIR/l2-deploy.json"
AVS_DEPLOYMENT_PATH="$NODES_DIR/avs_deploy.json"

REGISTRY_COORDINATOR_ADDRESS=$(jq -r '.addresses.registryCoordinator' "$AVS_DEPLOYMENT_PATH")
SIGNATURE_CONSUMER_ADDRESS=$(cat $L2_DEPLOY_PATH | jq -r '.signatureConsumer')
STATE_RETRIEVER_ADDRESS=$(cat $L1_DEPLOY_PATH | jq -r '.stateRetriever')

# Verify all required addresses are found
if [ -z "$REGISTRY_COORDINATOR_ADDRESS" ] || [ "$REGISTRY_COORDINATOR_ADDRESS" = "null" ]; then
    echo "Error: Could not find registry coordinator address in avs-deploy file"
    exit 1
fi

if [ -z "$BLS_SIGNATURE_CHECKER_ADDRESS" ] || [ "$BLS_SIGNATURE_CHECKER_ADDRESS" = "null" ]; then
    echo "Error: Could not find BLS signature checker address in l2-deploy file"
    exit 1
fi

if [ -z "$STATE_RETRIEVER_ADDRESS" ] || [ "$STATE_RETRIEVER_ADDRESS" = "null" ]; then
    echo "Error: Could not find state retriever address in l1-deploy file"
    exit 1
fi

# Export all required environment variables for the Forge script
export REGISTRY_COORDINATOR_ADDRESS
export SIGNATURE_CONSUMER_ADDRESS
export STATE_RETRIEVER_ADDRESS
export L1_RPC_URL
export L2_RPC_URL
export PRIVATE_KEY=$DEPLOYER_KEY
export OPERATOR_KEYS_DIR="$NODES_DIR/operator_keys/"

# Run the Forge script with required environment variables
cd "$FOUNDRY_ROOT_DIR"
echo "Running check signatures..."
forge script CheckSignature \
    --rpc-url $L2_RPC_URL \
    --broadcast | silent_success
