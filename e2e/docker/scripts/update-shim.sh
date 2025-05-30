#!/bin/bash

# Exit on any error
set -e

source $SCRIPTS_DIR/config.sh

cd "$FOUNDRY_ROOT_DIR"

L1_DEPLOY_PATH="$ARTIFACTS_DIR/l1-deploy.json"

# Read middleware shim address from l1-deploy file
MIDDLEWARE_SHIM_ADDRESS=$(cat $L1_DEPLOY_PATH | jq -r '.middlewareShim')

if [ -z "$MIDDLEWARE_SHIM_ADDRESS" ] || [ "$MIDDLEWARE_SHIM_ADDRESS" = "null" ]; then
    echo "Error: Could not find middleware shim address in l1-deploy file"
    exit 1
fi

# Call updateMiddlewareDataHash() on the middleware shim contract and get tx receipt
TX_HASH=$(cast send --rpc-url $L1_RPC_URL $MIDDLEWARE_SHIM_ADDRESS "updateMiddlewareDataHash()" --json --private-key $DEPLOYER_KEY | jq -r '.transactionHash')
BLOCK_NUMBER=$(cast receipt --rpc-url $L1_RPC_URL $TX_HASH | grep -E "^blockNumber" | awk '{print $2}')

echo "Called updateMiddlewareDataHash() at block number $BLOCK_NUMBER"
