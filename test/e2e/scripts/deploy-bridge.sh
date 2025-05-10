#!/bin/bash

# Get to the root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"/../../..

AVS_DEPLOYMENT_PATH="$SCRIPT_DIR"/../eigenlayer-bls-local/.nodes/avs_deploy.json
# Check if AVS deployment file exists and contains valid JSON
if [ ! -f "$AVS_DEPLOYMENT_PATH" ]; then
    echo "Error: AVS deployment file not found at $AVS_DEPLOYMENT_PATH"
    exit 1
fi

if ! jq empty "$AVS_DEPLOYMENT_PATH" 2>/dev/null; then
    echo "Error: Invalid JSON in AVS deployment file at $AVS_DEPLOYMENT_PATH"
    exit 1
fi

L1_RPC_URL="http://localhost:8545"
L2_RPC_URL="http://localhost:8546"

DEPLOYER_INFO=$(cast wallet new --json)
DEPLOYER_KEY=$(echo "$DEPLOYER_INFO" | jq -r '.[0].private_key')
DEPLOYER_ADDRESS=$(echo "$DEPLOYER_INFO" | jq -r '.[0].address')

if [ "$ENVIRONMENT" = "TESTNET" ]; then
    if [ -z "$FUNDED_KEY" ]; then
        echo "Error: FUNDED_KEY is not set in the environment variables. This is required for testnet."
        exit 1
    fi
    DEPLOYER_KEY=$FUNDED_KEY
else
    cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0x10000000000000000000 --rpc-url $L1_RPC_URL > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set balance for deployer account"
        exit 1
    fi
    cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0x10000000000000000000 --rpc-url $L2_RPC_URL > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set balance for deployer account"
        exit 1
    fi
fi


export REGISTRY_COORDINATOR_ADDRESS=$(jq -r '.addresses.registryCoordinator' "$AVS_DEPLOYMENT_PATH")
export PRIVATE_KEY=$DEPLOYER_KEY
export L1_OUT_PATH=$SCRIPT_DIR/artifacts/l1-deploy.json

# We use two separate scripts this way because EigenLayer's QuorumBitmapHistoryLib is an external library,
# and Multi chain deployment does not support library linking at the moment.
#-------------------------------------------------------------------------------#
# Error: Multi chain deployment does not support library linking at the moment. #
#-------------------------------------------------------------------------------#

forge script DeployL1 --broadcast --rpc-url $L1_RPC_URL
export MIDDLEWARE_SHIM_ADDRESS=$(jq -r '.middlewareShim' "$L1_OUT_PATH")
forge script DeployL2 --broadcast --rpc-url $L2_RPC_URL
