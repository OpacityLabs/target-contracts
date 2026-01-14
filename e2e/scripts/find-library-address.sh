#!/bin/bash

# Script to find the QuorumBitmapHistoryLib address from deployment broadcasts

BROADCAST_DIR="../contracts/broadcast"
CHAIN_ID="${1:-17000}"  # Default to Gnosis testnet, can be overridden

echo "Searching for QuorumBitmapHistoryLib deployment in chain $CHAIN_ID..."

# Search in DeployL2 broadcasts
L2_BROADCAST="$BROADCAST_DIR/DeployL2.s.sol/$CHAIN_ID/run-latest.json"
if [ -f "$L2_BROADCAST" ]; then
    echo "Checking $L2_BROADCAST..."
    LIBRARY_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "QuorumBitmapHistoryLib") | .contractAddress' "$L2_BROADCAST" 2>/dev/null)
    
    if [ ! -z "$LIBRARY_ADDRESS" ] && [ "$LIBRARY_ADDRESS" != "null" ]; then
        echo "Found QuorumBitmapHistoryLib at: $LIBRARY_ADDRESS"
        exit 0
    fi
fi

# Search in DeployL2WithVerification broadcasts
L2_VERIFY_BROADCAST="$BROADCAST_DIR/DeployL2WithVerification.s.sol/$CHAIN_ID/run-latest.json"
if [ -f "$L2_VERIFY_BROADCAST" ]; then
    echo "Checking $L2_VERIFY_BROADCAST..."
    LIBRARY_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "QuorumBitmapHistoryLib") | .contractAddress' "$L2_VERIFY_BROADCAST" 2>/dev/null)
    
    if [ ! -z "$LIBRARY_ADDRESS" ] && [ "$LIBRARY_ADDRESS" != "null" ]; then
        echo "Found QuorumBitmapHistoryLib at: $LIBRARY_ADDRESS"
        exit 0
    fi
fi

# If not found in broadcasts, check deployment output
L2_OUTPUT="../artifacts/l2-deploy.json"
if [ -f "$L2_OUTPUT" ]; then
    echo "Checking deployment output..."
    LIBRARY_ADDRESS=$(jq -r '.quorumBitmapHistoryLib' "$L2_OUTPUT" 2>/dev/null)
    
    if [ ! -z "$LIBRARY_ADDRESS" ] && [ "$LIBRARY_ADDRESS" != "null" ]; then
        echo "Found QuorumBitmapHistoryLib at: $LIBRARY_ADDRESS"
        exit 0
    fi
fi

echo "QuorumBitmapHistoryLib address not found in deployment files."
echo "You may need to check the deployment transaction on Gnosisscan for CREATE/CREATE2 operations."
exit 1