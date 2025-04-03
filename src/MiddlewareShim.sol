// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistry} from "@eigenlayer-middleware/interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "@eigenlayer-middleware/interfaces/IIndexRegistry.sol";

import {BitmapUtils} from "@eigenlayer-middleware/libraries/BitmapUtils.sol";
import {BN254} from "@eigenlayer-middleware/libraries/BN254.sol";

contract MiddlewareShim {
    ISlashingRegistryCoordinator public registryCoordinator;
    bytes32 public keysHash;
    
    constructor(ISlashingRegistryCoordinator _registryCoordinator) {
        registryCoordinator = _registryCoordinator;
    }

    struct OperatorKeys {
        BN254.G1Point pkG1;
        BN254.G2Point pkG2;
        uint96 stake;
    }

    // TODO: add all other fields needed by the mimic
    struct MiddlewareData {
        OperatorKeys[][] operatorKeys;
    }

    function updateKeysHash() external {
        // assume there is only one quorum 0
        OperatorKeys[][] memory operatorKeys = getOperatorKeys(registryCoordinator, hex"00", uint32(block.number - 1));
        MiddlewareData memory middlewareData = MiddlewareData({
            operatorKeys: operatorKeys
        });
        keysHash = keccak256(abi.encode(middlewareData));
    }

    function getOperatorKeys(
        ISlashingRegistryCoordinator _registryCoordinator,
        bytes memory quorumNumbers,
        uint32 blockNumber
    ) public view returns (OperatorKeys[][] memory) {
        IStakeRegistry stakeRegistry = _registryCoordinator.stakeRegistry();
        IIndexRegistry indexRegistry = _registryCoordinator.indexRegistry();
        IBLSApkRegistry blsApkRegistry = _registryCoordinator.blsApkRegistry();

        OperatorKeys[][] memory operatorKeys = new OperatorKeys[][](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            bytes32[] memory operatorIds =
                indexRegistry.getOperatorListAtBlockNumber(quorumNumber, blockNumber);
            operatorKeys[i] = new OperatorKeys[](operatorIds.length);
            for (uint256 j = 0; j < operatorIds.length; j++) {
                address operator = blsApkRegistry.getOperatorFromPubkeyHash(operatorIds[j]);
                {
                (uint256 x, uint256 y) = blsApkRegistry.operatorToPubkey(operator);
                operatorKeys[i][j].pkG1 = BN254.G1Point(x, y);
                }
                {
                operatorKeys[i][j].pkG2 = blsApkRegistry.getOperatorPubkeyG2(operator);
                }
                {
                operatorKeys[i][j].stake = stakeRegistry.getStakeAtBlockNumber(
                    bytes32(operatorIds[j]), quorumNumber, blockNumber
                );
                }
            }
        }

        return operatorKeys;
    }
}