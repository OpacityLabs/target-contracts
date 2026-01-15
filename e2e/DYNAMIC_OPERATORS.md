# Dynamic Operator Support for E2E Tests

This document describes how to use the dynamic operator support in the e2e tests.

## Overview

The e2e test suite now supports running with a configurable number of operators instead of the previously hardcoded 3 operators.

## Usage

### Using Default Operators (3 operators)

By default, the tests will run with 3 operators (testacc1, testacc2, testacc3):

```bash
cd e2e/docker
./scripts/run-check-signatures.sh
```

### Using Custom Number of Operators

To run with a different set of operators, set the `OPERATOR_NAMES` environment variable:

```bash
# Run with 2 operators
export OPERATOR_NAMES="testacc1,testacc2"
./scripts/run-check-signatures.sh

# Run with 5 operators (assuming testacc4 and testacc5 are configured)
export OPERATOR_NAMES="testacc1,testacc2,testacc3,testacc4,testacc5"
./scripts/run-check-signatures.sh
```

## Configuration Requirements

For each operator name specified in `OPERATOR_NAMES`, the following files must exist in the operator keys directory:

1. `{operatorName}.private.bls.key.json` - Private BLS key
2. `{operatorName}.bls.key.json` - Public BLS key
3. `{operatorName}.ecdsa.key.json` - ECDSA key with operator address

Additionally, each operator should be registered in the AVS system before running the signature check.

## Implementation Details

The dynamic operator support is implemented in:
- `contracts/script/e2e/CheckSignature.s.sol` - Main script that reads operator configuration
- `e2e/docker/scripts/run-check-signatures.sh` - Shell script that exports the OPERATOR_NAMES variable

The script automatically:
1. Reads the comma-separated list of operator names from the environment
2. Loads the corresponding keys for each operator
3. Generates BLS signatures for all operators
4. Aggregates the signatures
5. Verifies the aggregated signature on L2