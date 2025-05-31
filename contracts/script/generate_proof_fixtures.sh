#!/bin/bash

# Check if block number and middleware shim address arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <block_number> <middleware_shim_address>"
    exit 1
fi

BLOCK_NUMBER=$1
MIDDLEWARE_SHIM=$2

# Get the directory this script is in
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEFAULT_OUTPUT_FILE="${SCRIPT_DIR}/middlewareShimProof_${BLOCK_NUMBER}.json"
OUTPUT_FILE=${OUTPUT_FILE:-"$DEFAULT_OUTPUT_FILE"}
RPC_URL=${RPC_URL:-"https://ethereum-holesky.publicnode.com"}

# Storage slot 0 contains the middlewareDataHash
STORAGE_SLOT=0

if [ -z "$MIDDLEWARE_SHIM" ]; then
    echo "Error: Could not find MiddlewareShim address"
    exit 1
fi

# Generate the proof using cast
cast proof -B $BLOCK_NUMBER $MIDDLEWARE_SHIM $STORAGE_SLOT --rpc-url $RPC_URL | jq '.' > $OUTPUT_FILE