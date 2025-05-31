#!/bin/bash

# Exit on any error
set -e

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
cd "$SCRIPTS_DIR"

echo "Deploying bridge contracts on L1 and L2..."
./deploy-bridge.sh

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