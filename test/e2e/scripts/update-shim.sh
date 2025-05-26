#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR
source ../envs/bls-testnet.env

L1_DEPLOY_PATH="./artifacts/l1-deploy.json"

# Read middleware shim address from l1-deploy file
MIDDLEWARE_SHIM_ADDRESS=$(cat $L1_DEPLOY_PATH | jq -r '.middlewareShim')

if [ -z "$MIDDLEWARE_SHIM_ADDRESS" ] || [ "$MIDDLEWARE_SHIM_ADDRESS" = "null" ]; then
    echo "Error: Could not find middleware shim address in l1-deploy file"
    exit 1
fi


if [ "$ENVIRONMENT" = "TESTNET" ]; then
    if [ -z "$FUNDED_KEY" ]; then
        echo "Error: FUNDED_KEY is not set in the environment variables. This is required for testnet."
        exit 1
    fi
    SENDER_KEY=$FUNDED_KEY
else
    SENDER_INFO=$(cast wallet new --json)
    SENDER_KEY=$(echo "$SENDER_INFO" | jq -r '.[0].private_key')
    SENDER_ADDRESS=$(echo "$SENDER_INFO" | jq -r '.[0].address')
    cast rpc anvil_setBalance $SENDER_ADDRESS 0x10000000000000000000 --rpc-url $L1_RPC_URL > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set balance for deployer account"
        exit 1
    fi
fi

# Call updateMiddlewareDataHash() on the middleware shim contract and get tx receipt
TX_HASH=$(cast send --rpc-url $L1_RPC_URL $MIDDLEWARE_SHIM_ADDRESS "updateMiddlewareDataHash()" --json --private-key $SENDER_KEY | jq -r '.transactionHash')
BLOCK_NUMBER=$(cast receipt --rpc-url $L1_RPC_URL $TX_HASH | grep -E "^blockNumber" | awk '{print $2}')

echo "Called updateMiddlewareDataHash() at block number $BLOCK_NUMBER"
