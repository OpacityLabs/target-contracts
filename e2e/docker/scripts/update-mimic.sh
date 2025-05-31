#!/bin/bash

# Exit on any error
set -e

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
cd "$SCRIPTS_DIR"

# Set PROOF_FILE relative to artifacts directory
PROOF_FILE="$ARTIFACTS_DIR/middlewareDataProof.json"

# Read addresses from deployment files
L1_DEPLOY_PATH="$ARTIFACTS_DIR/l1-deploy.json"
L2_DEPLOY_PATH="$ARTIFACTS_DIR/l2-deploy.json"

REGISTRY_COORDINATOR_MIMIC_ADDRESS=$(cat $L2_DEPLOY_PATH | jq -r '.registryCoordinatorMimic')
BLS_SIGNATURE_CHECKER_ADDRESS=$(cat $L2_DEPLOY_PATH | jq -r '.blsSignatureChecker')
MIDDLEWARE_SHIM_ADDRESS=$(cat $L1_DEPLOY_PATH | jq -r '.middlewareShim')

# Verify all required addresses are found
if [ -z "$REGISTRY_COORDINATOR_MIMIC_ADDRESS" ] || [ "$REGISTRY_COORDINATOR_MIMIC_ADDRESS" = "null" ]; then
    echo "Error: Could not find registry coordinator mimic address in l2-deploy file"
    exit 1
fi

if [ -z "$BLS_SIGNATURE_CHECKER_ADDRESS" ] || [ "$BLS_SIGNATURE_CHECKER_ADDRESS" = "null" ]; then
    echo "Error: Could not find BLS signature checker address in l2-deploy file"
    exit 1
fi

if [ -z "$MIDDLEWARE_SHIM_ADDRESS" ] || [ "$MIDDLEWARE_SHIM_ADDRESS" = "null" ]; then
    echo "Error: Could not find middleware shim address in l1-deploy file"
    exit 1
fi

# Export all required environment variables for the Forge script
export PROOF_FILE
export REGISTRY_COORDINATOR_MIMIC_ADDRESS
export BLS_SIGNATURE_CHECKER_ADDRESS
export MIDDLEWARE_SHIM_ADDRESS
export IS_SP1HELIOS_MOCK
export L1_RPC_URL
export L2_RPC_URL
export PRIVATE_KEY=$DEPLOYER_KEY

# Run the Forge script with required environment variables
cd "$FOUNDRY_ROOT_DIR"
echo "Updating middleware shim with latest data hash..."
forge script script/e2e/UpdateMimic.s.sol:UpdateMimic \
    --broadcast \
    -vvvv | silent_success