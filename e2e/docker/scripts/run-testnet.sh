#!/bin/bash

# Exit on any error
set -e

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
cd "$SCRIPTS_DIR"

echo "Deploying bridge contracts on L1 and L2..."
# Use the improved deployment script if it exists and verification is needed
if [ ! -z "$L2_ETHERSCAN_API_KEY" ] && [ -f ./deploy-bridge-with-verification.sh ]; then
    echo "Using improved deployment script with verification support..."
    ./deploy-bridge-with-verification.sh
else
    ./deploy-bridge.sh
fi

./update-shim.sh

echo "Generating proof..."
if [ "$IS_SP1HELIOS_MOCK" = "1" ]; then
    echo "Using mock proof generation..."
    SLOT_NUMBER=1234
    ./generate-mock-proof.sh $SLOT_NUMBER
else
    echo "Getting latest SP1Helios slot number..."
    SLOT_NUMBER=$(./get-sp1-slot.sh | tail -n1)
    echo "Slot number: $SLOT_NUMBER"
    echo "Using real proof generation..."
    ./generate-proof.sh $SLOT_NUMBER
fi

./update-mimic.sh

./run-check-signatures.sh