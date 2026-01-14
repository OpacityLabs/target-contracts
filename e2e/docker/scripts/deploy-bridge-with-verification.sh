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

# Deploy L1 contracts
echo "Deploying L1 contracts..."
if [ ! -z "$L1_ETHERSCAN_API_KEY" ]; then
    forge script DeployL1 --broadcast --rpc-url $L1_RPC_URL --verify --etherscan-api-key $L1_ETHERSCAN_API_KEY | silent_success
else
    forge script DeployL1 --broadcast --rpc-url $L1_RPC_URL | silent_success
fi

export MIDDLEWARE_SHIM_ADDRESS=$(cat $L1_OUT_PATH | jq -r '.middlewareShim')
export SP1HELIOS_ADDRESS=$SP1HELIOS_ADDRESS

# Deploy L2 contracts with library deployment
echo "Deploying L2 contracts with library..."
if [ ! -z "$L2_ETHERSCAN_API_KEY" ]; then
    # First deploy without verification to get the library address
    forge script DeployL2WithVerification --broadcast --rpc-url $L2_RPC_URL | silent_success
    
    # Extract the library address from the deployment output
    QUORUM_BITMAP_LIB=$(cat $L2_OUT_PATH | jq -r '.quorumBitmapHistoryLib')
    
    if [ "$QUORUM_BITMAP_LIB" != "null" ] && [ ! -z "$QUORUM_BITMAP_LIB" ]; then
        echo "QuorumBitmapHistoryLib deployed at: $QUORUM_BITMAP_LIB"
        
        # Verify the library contract first
        echo "Verifying QuorumBitmapHistoryLib..."
        forge verify-contract $QUORUM_BITMAP_LIB \
            QuorumBitmapHistoryLib \
            --rpc-url $L2_RPC_URL \
            --etherscan-api-key $L2_ETHERSCAN_API_KEY \
            --compiler-version v0.8.27+commit.40a35a09 \
            --num-of-optimizations 200 || echo "Library verification may have failed or already verified"
        
        # Extract other contract addresses
        REGISTRY_COORDINATOR_MIMIC=$(cat $L2_OUT_PATH | jq -r '.registryCoordinatorMimic')
        BLS_SIGNATURE_CHECKER=$(cat $L2_OUT_PATH | jq -r '.blsSignatureChecker')
        SIGNATURE_CONSUMER=$(cat $L2_OUT_PATH | jq -r '.signatureConsumer')
        
        # Verify RegistryCoordinatorMimic with library linking
        echo "Verifying RegistryCoordinatorMimic..."
        forge verify-contract $REGISTRY_COORDINATOR_MIMIC \
            RegistryCoordinatorMimic \
            --rpc-url $L2_RPC_URL \
            --etherscan-api-key $L2_ETHERSCAN_API_KEY \
            --libraries QuorumBitmapHistoryLib:$QUORUM_BITMAP_LIB \
            --constructor-args $(cast abi-encode "constructor(address,address)" $SP1HELIOS_ADDRESS $MIDDLEWARE_SHIM_ADDRESS) \
            --compiler-version v0.8.30+commit.068c8ec2 \
            --num-of-optimizations 200 || echo "RegistryCoordinatorMimic verification may have failed or already verified"
        
        # Verify BLSSignatureChecker with library linking
        echo "Verifying BLSSignatureChecker..."
        forge verify-contract $BLS_SIGNATURE_CHECKER \
            BLSSignatureChecker \
            --rpc-url $L2_RPC_URL \
            --etherscan-api-key $L2_ETHERSCAN_API_KEY \
            --libraries QuorumBitmapHistoryLib:$QUORUM_BITMAP_LIB \
            --constructor-args $(cast abi-encode "constructor(address)" $REGISTRY_COORDINATOR_MIMIC) \
            --compiler-version v0.8.27+commit.40a35a09 \
            --num-of-optimizations 200 || echo "BLSSignatureChecker verification may have failed or already verified"
        
        # Verify SignatureConsumer (doesn't need library linking)
        echo "Verifying SignatureConsumer..."
        forge verify-contract $SIGNATURE_CONSUMER \
            SignatureConsumer \
            --rpc-url $L2_RPC_URL \
            --etherscan-api-key $L2_ETHERSCAN_API_KEY \
            --constructor-args $(cast abi-encode "constructor(address)" $BLS_SIGNATURE_CHECKER) \
            --compiler-version v0.8.30+commit.068c8ec2 \
            --num-of-optimizations 200 || echo "SignatureConsumer verification may have failed or already verified"
            
        echo "All contracts deployed and verification attempted."
    else
        echo "Warning: Could not extract QuorumBitmapHistoryLib address, skipping verification"
    fi
else
    forge script DeployL2WithVerification --broadcast --rpc-url $L2_RPC_URL | silent_success
fi

echo "Deployment complete!"