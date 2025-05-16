#!/bin/bash

# Exit on any error
set -e

# Function to handle errors
handle_error() {
    echo "Error: Command failed with exit code $1"
    exit 1
}

cd "$(dirname "$0")" || handle_error $?

echo "Deploying bridge contracts on L1 and L2..."
./deploy-bridge.sh || handle_error $?

echo "Updating middleware shim with latest data hash..."
./update-shim.sh || handle_error $?

echo "Getting latest SP1Helios block number..."
BLOCK_NUMBER=$(./get-sp1-block.sh | tail -n1) || handle_error $?
echo "Block number: $BLOCK_NUMBER"

echo "Generating proof..."
./generate-proof.sh $BLOCK_NUMBER || handle_error $?

echo "Updating middleware shim with latest data hash..."
./update-mimic.sh || handle_error $?