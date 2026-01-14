# Gnosisscan Verification Guide

## Issue Description

The L2 bridge contracts verification on Gnosisscan does not work fully due to the use of `QuorumBitmapHistoryLib`, which is an external library in the EigenLayer middleware. This causes issues with automatic verification through forge scripts.

## Root Causes

1. **External Library Dependency**: `QuorumBitmapHistoryLib` is deployed as an external library, not inlined during compilation
2. **Library Linking Requirements**: Verification requires explicit library linking with the `--libraries` flag
3. **Mixed Library Types**: Potential conflicts between external libraries (QuorumBitmapHistoryLib) and internal libraries (Optimism's RLP libraries) during verification

## Affected Contracts

- `RegistryCoordinatorMimic` - Uses QuorumBitmapHistoryLib
- `BLSSignatureChecker` - Uses QuorumBitmapHistoryLib  
- `SignatureConsumer` - No library issues (can be verified normally)

## Solutions

### Solution 1: Deploy Library Separately (Recommended)

Use the new `DeployL2WithVerification` script that deploys the library as a separate contract:

```bash
# Set environment variables
export L2_RPC_URL="<your_gnosis_rpc>"
export L2_ETHERSCAN_API_KEY="<your_gnosisscan_api_key>"
export PRIVATE_KEY="<deployer_private_key>"
export MIDDLEWARE_SHIM_ADDRESS="<from_l1_deployment>"
export SP1HELIOS_ADDRESS="<sp1_helios_address>"
export IS_SP1HELIOS_MOCK=false
export L2_OUT_PATH="./artifacts/l2-deploy.json"

# Run the deployment with verification script
forge script DeployL2WithVerification --broadcast --rpc-url $L2_RPC_URL

# The script will output the library address, use it for verification
```

### Solution 2: Manual Verification Steps

If automatic verification fails:

1. **Deploy contracts normally**:
```bash
forge script DeployL2 --broadcast --rpc-url $L2_RPC_URL
```

2. **Extract the library address from deployment logs**:
Look for `QuorumBitmapHistoryLib` deployment in the broadcast files or transaction logs

3. **Verify each contract manually**:

```bash
# Get addresses from l2-deploy.json
REGISTRY_COORDINATOR=$(cat artifacts/l2-deploy.json | jq -r '.registryCoordinatorMimic')
BLS_CHECKER=$(cat artifacts/l2-deploy.json | jq -r '.blsSignatureChecker')
SIGNATURE_CONSUMER=$(cat artifacts/l2-deploy.json | jq -r '.signatureConsumer')
LIBRARY_ADDRESS="<extracted_library_address>"

# Verify SignatureConsumer (no library needed)
forge verify-contract $SIGNATURE_CONSUMER \
  SignatureConsumer \
  --rpc-url $L2_RPC_URL \
  --etherscan-api-key $L2_ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address)" $BLS_CHECKER)

# Verify RegistryCoordinatorMimic with library
forge verify-contract $REGISTRY_COORDINATOR \
  RegistryCoordinatorMimic \
  --rpc-url $L2_RPC_URL \
  --etherscan-api-key $L2_ETHERSCAN_API_KEY \
  --libraries QuorumBitmapHistoryLib:$LIBRARY_ADDRESS \
  --constructor-args $(cast abi-encode "constructor(address,address)" $SP1HELIOS_ADDRESS $MIDDLEWARE_SHIM_ADDRESS)

# Verify BLSSignatureChecker with library
forge verify-contract $BLS_CHECKER \
  BLSSignatureChecker \
  --rpc-url $L2_RPC_URL \
  --etherscan-api-key $L2_ETHERSCAN_API_KEY \
  --libraries QuorumBitmapHistoryLib:$LIBRARY_ADDRESS \
  --constructor-args $(cast abi-encode "constructor(address)" $REGISTRY_COORDINATOR)
```

### Solution 3: Gnosisscan Web Interface

If command-line verification fails:

1. Go to Gnosisscan.io
2. Navigate to each contract address
3. Click "Verify and Publish"
4. Select compiler version matching foundry.toml
5. For contracts using QuorumBitmapHistoryLib:
   - Enable "Optimization"
   - Add library addresses in the "Library" section
   - Paste the flattened source code

## Finding the Library Address

The QuorumBitmapHistoryLib address can be found in:

1. **Broadcast files**: Check `broadcast/DeployL2.s.sol/<chain_id>/run-latest.json`
2. **Transaction logs**: Look for CREATE2 operations in the deployment transaction
3. **Etherscan/Gnosisscan**: Check internal transactions of the deployment

## Compiler Settings

Ensure these settings match when verifying:
- Solidity version: Check each contract's pragma
- Optimizer: Enabled with 200 runs (default Foundry setting)
- EVM version: Paris (or as specified in foundry.toml)

## Known Issues

1. **API Rate Limiting**: Gnosisscan may throttle verification requests. Wait and retry if you get rate limit errors.
2. **Compiler Version Mismatch**: Different contracts may use different Solidity versions. Check the pragma in each file.
3. **Library Already Deployed**: If the library was already deployed in a previous transaction, use that address instead of deploying again.

## Testing Verification Locally

Before deploying to mainnet/testnet:

```bash
# Compile and check for library usage
forge build --force
forge inspect QuorumBitmapHistoryLib bytecode
forge inspect RegistryCoordinatorMimic bytecode | grep -c "__"  # Check for library placeholders
```

## Alternative: Modify Contracts (Not Recommended)

As a last resort, you could modify the contracts to not use external libraries, but this would require:
1. Inlining the QuorumBitmapHistoryLib functions
2. Extensive testing to ensure functionality remains the same
3. Potential gas cost increases

This approach is not recommended as it changes the audited code.