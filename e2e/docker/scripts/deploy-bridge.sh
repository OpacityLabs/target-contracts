#!/bin/bash

# Exit on any error
set -e

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
cd "$SCRIPTS_DIR"

cd "$FOUNDRY_ROOT_DIR"

AVS_DEPLOYMENT_PATH="$NODES_DIR/avs_deploy.json"
# Check if AVS deployment file exists and contains valid JSON
if [ ! -f "$AVS_DEPLOYMENT_PATH" ]; then
    echo "Error: AVS deployment file not found at $AVS_DEPLOYMENT_PATH"
    exit 1
fi

if ! jq empty "$AVS_DEPLOYMENT_PATH" 2>/dev/null; then
    echo "Error: Invalid JSON in AVS deployment file at $AVS_DEPLOYMENT_PATH"
    exit 1
fi

# Check if SP1HELIOS_ADDRESS is set
if [ -z "$SP1HELIOS_ADDRESS" ]; then
    echo "Error: SP1HELIOS_ADDRESS is not set in the environment variables"
    exit 1
fi

# Check if L1_RPC_URL is set
if [ -z "$L1_RPC_URL" ]; then
    echo "Error: L1_RPC_URL is not set in the environment variables"
    exit 1
fi

# Check if L2_RPC_URL is set
if [ -z "$L2_RPC_URL" ]; then
    echo "Error: L2_RPC_URL is not set in the environment variables"
    exit 1
fi

export REGISTRY_COORDINATOR_ADDRESS=$(jq -r '.addresses.registryCoordinator' "$AVS_DEPLOYMENT_PATH")
export PRIVATE_KEY=$DEPLOYER_KEY
export L1_OUT_PATH="$ARTIFACTS_DIR/l1-deploy.json"
export L2_OUT_PATH="$ARTIFACTS_DIR/l2-deploy.json"
export IS_SP1HELIOS_MOCK=$IS_SP1HELIOS_MOCK

# We use two separate scripts this way because EigenLayer's QuorumBitmapHistoryLib is an external library,
# and Multi chain deployment does not support library linking at the moment.
#-------------------------------------------------------------------------------#
# Error: Multi chain deployment does not support library linking at the moment. #
#-------------------------------------------------------------------------------#

# Deploy L1 contracts
if [ ! -z "$L1_ETHERSCAN_API_KEY" ]; then
    forge script DeployL1 --broadcast --rpc-url $L1_RPC_URL --verify --etherscan-api-key $L1_ETHERSCAN_API_KEY | silent_success
else
    forge script DeployL1 --broadcast --rpc-url $L1_RPC_URL | silent_success
fi

export MIDDLEWARE_SHIM_ADDRESS=$(cat $L1_OUT_PATH | jq -r '.middlewareShim')
export SP1HELIOS_ADDRESS=$SP1HELIOS_ADDRESS

# Deploy L2 contracts
if [ ! -z "$L2_ETHERSCAN_API_KEY" ]; then
    echo "Deploying L2 contracts..."
    # Deploy contracts first without verification to avoid library linking issues during deployment
    forge script DeployL2 --broadcast --rpc-url $L2_RPC_URL | silent_success
    
    echo "Attempting contract verification on Gnosisscan..."
    
    # Extract contract addresses from deployment output
    if [ -f "$L2_OUT_PATH" ]; then
        REGISTRY_COORDINATOR_MIMIC=$(cat $L2_OUT_PATH | jq -r '.registryCoordinatorMimic')
        BLS_SIGNATURE_CHECKER=$(cat $L2_OUT_PATH | jq -r '.blsSignatureChecker')
        SIGNATURE_CONSUMER=$(cat $L2_OUT_PATH | jq -r '.signatureConsumer')
        
        # Note: QuorumBitmapHistoryLib is deployed as part of the BLSSignatureChecker/RegistryCoordinatorMimic
        # The library verification needs special handling due to it being an external library
        
        # Verify contracts that don't depend on the external library first
        echo "Verifying SignatureConsumer..."
        forge verify-contract $SIGNATURE_CONSUMER \
            SignatureConsumer \
            --rpc-url $L2_RPC_URL \
            --etherscan-api-key $L2_ETHERSCAN_API_KEY \
            --constructor-args $(cast abi-encode "constructor(address)" $BLS_SIGNATURE_CHECKER) \
            2>/dev/null || echo "SignatureConsumer verification may require manual intervention"
        
        # For contracts using QuorumBitmapHistoryLib, verification may need manual steps
        echo ""
        echo "NOTE: RegistryCoordinatorMimic and BLSSignatureChecker use QuorumBitmapHistoryLib,"
        echo "which is an external library. These contracts may require manual verification on Gnosisscan"
        echo "due to library linking requirements."
        echo ""
        echo "To manually verify these contracts:"
        echo "1. Deploy QuorumBitmapHistoryLib separately if needed"
        echo "2. Use the --libraries flag with forge verify-contract"
        echo "3. Or verify manually through Gnosisscan web interface"
    else
        echo "Warning: L2 deployment output not found at $L2_OUT_PATH"
    fi
else
    forge script DeployL2 --broadcast --rpc-url $L2_RPC_URL | silent_success
fi