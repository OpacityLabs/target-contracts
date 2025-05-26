#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR
source ../envs/bls-local.env
cd "$SCRIPT_DIR"/../../..

AVS_DEPLOYMENT_PATH="$SCRIPT_DIR"/../docker/.nodes/avs_deploy.json
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

if [ "$ENVIRONMENT" = "TESTNET" ]; then
    if [ -z "$FUNDED_KEY" ]; then
        echo "Error: FUNDED_KEY is not set in the environment variables. This is required for testnet."
        exit 1
    fi
    DEPLOYER_KEY=$FUNDED_KEY
else
    DEPLOYER_INFO=$(cast wallet new --json)
    DEPLOYER_KEY=$(echo "$DEPLOYER_INFO" | jq -r '.[0].private_key')
    DEPLOYER_ADDRESS=$(echo "$DEPLOYER_INFO" | jq -r '.[0].address')
    cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0x10000000000000000000 --rpc-url $L1_RPC_URL > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set balance for deployer account"
        exit 1
    fi
    cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0x10000000000000000000 --rpc-url $L2_RPC_URL > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set balance for deployer account"
        exit 1
    fi
fi

export REGISTRY_COORDINATOR_ADDRESS=$(jq -r '.addresses.registryCoordinator' "$AVS_DEPLOYMENT_PATH")
export PRIVATE_KEY=$DEPLOYER_KEY
export L1_OUT_PATH=$SCRIPT_DIR/artifacts/l1-deploy.json
export L2_OUT_PATH=$SCRIPT_DIR/artifacts/l2-deploy.json
export IS_SP1HELIOS_MOCK=$IS_SP1HELIOS_MOCK

# We use two separate scripts this way because EigenLayer's QuorumBitmapHistoryLib is an external library,
# and Multi chain deployment does not support library linking at the moment.
#-------------------------------------------------------------------------------#
# Error: Multi chain deployment does not support library linking at the moment. #
#-------------------------------------------------------------------------------#

# Deploy L1 contracts
if [ ! -z "$L1_ETHERSCAN_API_KEY" ]; then
    forge script DeployL1 --broadcast --rpc-url $L1_RPC_URL --verify --etherscan-api-key $L1_ETHERSCAN_API_KEY
else
    forge script DeployL1 --broadcast --rpc-url $L1_RPC_URL
fi

export MIDDLEWARE_SHIM_ADDRESS=$(jq -r '.middlewareShim' "$L1_OUT_PATH")
export SP1HELIOS_ADDRESS=$SP1HELIOS_ADDRESS

# Deploy L2 contracts
if [ ! -z "$L2_ETHERSCAN_API_KEY" ]; then
    # This fails to verify QuorumBitmapHistoryLib because it's an external library and you need to link it with --libraries flag
    # I tried doing that but then it failed to verify the mimic, because it's somehow affected the verification of the RLP library
    # My guess is that maybe there is some weird issue with mixing external and internal libraries when it comes to solc, but I don't knoq

    # TODO: Find solution: Either fix the verification of the QuorumBitmapHistoryLib or find a way to detect the script's etherscan verification failed
    # forge script DeployL2 --broadcast --rpc-url $L2_RPC_URL --verify --etherscan-api-key $L2_ETHERSCAN_API_KEY

    forge script DeployL2 --broadcast --rpc-url $L2_RPC_URL
else
    forge script DeployL2 --broadcast --rpc-url $L2_RPC_URL
fi