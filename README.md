# Target Contracts

A smart contract system that bridges EigenLayer's middleware with SP1 Helios light client for cryptographic proof verification and operator management.

## Overview

Target Contracts provides infrastructure for:
- **Operator Registry Management**: Mimics EigenLayer's registry coordinator functionality
- **SP1 Proof Verification**: Integrates Succinct's SP1 Helios light client for state proof verification
- **Middleware Integration**: Bridges between registry coordination and middleware components
- **BLS Signature Verification**: Validates operator signatures using BLS cryptography

## Architecture

The system consists of three main components:

1. **RegistryCoordinatorMimic**: Manages operator registrations and updates, verifies SP1 proofs, and maintains operator state
2. **MiddlewareShim**: Acts as an interface between the registry coordinator and EigenLayer middleware
3. **SP1Helios Integration**: Provides light client functionality for proof verification

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (latest version)
- [Docker](https://docs.docker.com/get-docker/) and Docker Compose
- [Node.js](https://nodejs.org/) (v18 or higher)
- Git with submodule support

## Installation

### 1. Clone the repository with submodules

```bash
git clone --recurse-submodules https://github.com/OpacityLabs/target-contracts.git
cd target-contracts
```

### 2. Initialize submodules (if not cloned with --recurse-submodules)

```bash
git submodule update --init --recursive

# Initialize nested submodules in dependencies
cd contracts/lib/eigenlayer-middleware && git submodule update --init --recursive
cd ../sp1-helios && git submodule update --init --recursive
cd ../../..
```

### 3. Install dependencies

```bash
cd contracts
forge install
```

## Project Structure

```
target-contracts/
├── contracts/                    # Smart contracts
│   ├── src/                     # Main contract implementations
│   │   ├── MiddlewareShim.sol
│   │   ├── RegistryCoordinatorMimic.sol
│   │   └── interfaces/
│   ├── test/                    # Test files
│   │   ├── MiddlewareShim.t.sol
│   │   ├── RegistryCoordinatorMimic.t.sol
│   │   ├── OpacityFork.t.sol
│   │   └── fixtures/            # Test fixtures and proof data
│   ├── script/                  # Deployment scripts
│   │   ├── DeployEnvironment.s.sol
│   │   └── e2e/                 # End-to-end test scripts
│   └── lib/                     # Git submodules
│       ├── sp1-helios/          # SP1 light client
│       ├── eigenlayer-middleware/
│       ├── optimism/            # Trie and RLP libraries
│       └── openzeppelin-contracts/
├── e2e/                         # End-to-end testing
│   ├── docker/                  # Docker configurations
│   │   ├── bls-e2e.docker-compose.yml
│   │   ├── bls-testnet.docker-compose.yml
│   │   └── scripts/             # Deployment and test scripts
│   └── envs/                    # Environment configurations
└── README.md
```

## Configuration

### Environment Variables

Copy the example environment file and configure:

```bash
cp e2e/envs/bls-testnet.example.env .env
```

Key environment variables:
- `PRIVATE_KEY` or `DEPLOYER_KEY`: Deployer wallet private key
- `L1_RPC_URL`: Ethereum L1 RPC endpoint
- `L2_RPC_URL`: L2 RPC endpoint (if applicable)
- `SP1HELIOS_ADDRESS`: SP1 Helios contract address
- `BEACON_CHAIN_RPC`: Beacon chain RPC endpoint for state proofs

### Foundry Configuration

The `contracts/foundry.toml` file configures:
- Remappings for dependencies
- RPC endpoints
- File system permissions for artifacts

## Building

```bash
cd contracts
forge build
```

## Testing

### Run all tests

```bash
cd contracts
forge test
```

### Run specific test contracts

```bash
# Test RegistryCoordinatorMimic
forge test --match-contract RegistryCoordinatorMimic

# Test MiddlewareShim
forge test --match-contract MiddlewareShim

# Run fork tests
forge test --match-contract OpacityFork --fork-url $L1_RPC_URL
```

### Test with verbosity

```bash
# Show logs for all tests
forge test -vv

# Show execution traces for failing tests
forge test -vvv

# Show execution traces for all tests
forge test -vvvv
```

### Test coverage

```bash
forge coverage
```

## Deployment

### Local Development

Deploy to a local Anvil instance:

```bash
# Start Anvil
anvil

# In another terminal
cd contracts
forge script script/DeployEnvironment.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Testnet Deployment

Deploy to Holesky testnet:

```bash
cd contracts
forge script script/DeployEnvironment.s.sol --rpc-url $L1_RPC_URL --broadcast --verify
```

### Docker Deployment

For full end-to-end testing environment:

```bash
cd e2e/docker

# For local e2e testing
docker-compose -f bls-e2e.docker-compose.yml up

# For testnet deployment
docker-compose -f bls-testnet.docker-compose.yml up
```

## Core Contracts

### RegistryCoordinatorMimic

Manages operator registrations and verifies state proofs:
- Integrates with SP1 Helios for proof verification
- Maintains operator APK updates and stake history
- Processes state update proofs from the beacon chain

### MiddlewareShim

Bridges the registry coordinator with EigenLayer middleware:
- Computes and stores middleware data hashes
- Manages operator sets and quorum information
- Provides operator state retrieval functions

### Key Functions

#### RegistryCoordinatorMimic
- `updateStateWithProof()`: Updates operator state using SP1 proof verification
- `getOperatorAPK()`: Retrieves operator's aggregate public key
- `getQuorumApk()`: Gets the aggregate public key for a quorum

#### MiddlewareShim
- `updateMiddlewareDataHash()`: Updates the stored middleware data hash
- `getMiddlewareData()`: Retrieves current middleware operator data
- `getOperatorCount()`: Returns the number of operators in a quorum

## Scripts

### Deployment Scripts
- `DeployEnvironment.s.sol`: Deploys core contracts
- `DeployL1.s.sol`: L1-specific deployment
- `DeployL2.s.sol`: L2-specific deployment

### Utility Scripts
- `generate_proof_fixtures.sh`: Generate test proof data
- `update-mimic.sh`: Update registry coordinator state
- `check-signatures.sh`: Verify BLS signatures

## Security

### Audit Status
The codebase integrates audited components from:
- EigenLayer middleware (audited)
- OpenZeppelin contracts (audited)
- SP1 Helios (refer to Succinct's audit reports)

Note: Some components use unaudited libraries (marked in imports). Exercise caution in production deployments.

### Best Practices
- Never commit private keys or sensitive data
- Verify all external contract addresses
- Test thoroughly on testnets before mainnet deployment
- Monitor gas usage for state update operations

## Gas Optimization

Key considerations:
- State updates can be gas-intensive due to proof verification
- Batch operations where possible
- Monitor storage array modifications in `RegistryCoordinatorMimic`

## Troubleshooting

### Common Issues

1. **Submodule initialization failed**
   ```bash
   git submodule update --init --recursive --force
   ```

2. **Forge build fails**
   ```bash
   forge clean
   forge build
   ```

3. **Test fixtures missing**
   ```bash
   cd contracts
   ./script/generate_proof_fixtures.sh
   ```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines
- Follow Solidity style guide
- Add tests for new features
- Update documentation
- Run `forge fmt` before committing

## Resources

- [EigenLayer Documentation](https://docs.eigenlayer.xyz/)
- [SP1 Helios](https://github.com/succinctlabs/sp1-helios)
- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts)

## License

This project is UNLICENSED. See contract headers for specific licensing information.

## Support

For issues and questions:
- Open an issue on [GitHub](https://github.com/OpacityLabs/target-contracts/issues)
- Review existing issues for solutions

## Acknowledgments

Built with:
- [EigenLayer Middleware](https://github.com/Layr-Labs/eigenlayer-middleware)
- [Succinct SP1 Helios](https://github.com/succinctlabs/sp1-helios)
- [Optimism Libraries](https://github.com/ethereum-optimism/optimism)
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
