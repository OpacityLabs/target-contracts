#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR
source ../envs/bls-local.env

# Read addresses from deployment files
L1_DEPLOY_PATH="${SCRIPT_DIR}/artifacts/l1-deploy.json"
L2_DEPLOY_PATH="${SCRIPT_DIR}/artifacts/l2-deploy.json"
AVS_DEPLOYMENT_PATH="$SCRIPT_DIR"/../docker/.nodes/avs_deploy.json

REGISTRY_COORDINATOR_ADDRESS=$(jq -r '.addresses.registryCoordinator' "$AVS_DEPLOYMENT_PATH")
BLS_SIGNATURE_CHECKER_ADDRESS=$(cat $L2_DEPLOY_PATH | jq -r '.blsSignatureChecker')
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
export BLS_SIGNATURE_CHECKER_ADDRESS
export STATE_RETRIEVER_ADDRESS
export L1_RPC_URL
export L2_RPC_URL
export PRIVATE_KEY

# Run the Forge script with required environment variables
cd $SCRIPT_DIR/../../../
forge script script/e2e/CheckSignature.s.sol:CheckSignature \
    --broadcast \
    -vvvv
