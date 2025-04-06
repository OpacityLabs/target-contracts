// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {BitmapUtils} from "@eigenlayer-middleware/libraries/BitmapUtils.sol";
import {BN254} from "@eigenlayer-middleware/libraries/BN254.sol";

import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistry} from "@eigenlayer-middleware/interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "@eigenlayer-middleware/interfaces/IIndexRegistry.sol";
import {IMiddlewareShimTypes} from "./interfaces/IMiddlewareShim.sol";

contract MiddlewareShim is IMiddlewareShimTypes {
    bytes32 public middlewareDataHash;
    ISlashingRegistryCoordinator public registryCoordinator;
    
    constructor(ISlashingRegistryCoordinator _registryCoordinator) {
        registryCoordinator = _registryCoordinator;
    }

    function updateKeysHash() external {
        // assume there is only one quorum 0
        uint256 quorumUpdateBlockNumber = registryCoordinator.quorumUpdateBlockNumber(0);
        OperatorKeys[][] memory operatorKeys = getOperatorKeys(registryCoordinator, hex"00", uint32(block.number - 1));
        ApkUpdate[] memory quorumApkUpdates = _getQuorumApkUpdates(registryCoordinator);  // TODO: should pass blocknumber? Is there a case where we don't want the mimic to have future information
        StakeUpdate[] memory totalStakeHistory = _getTotalStakeHistory();  // TODO: should pass blocknumber? Is there a case where we don't want the mimic to have future information
        OperatorStakeHistoryEntry[] memory operatorStakeHistory = _getOperatorStakeHistoryOfQuorum(registryCoordinator, uint32(block.number - 1));
        OperatorBitmapHistoryEntry[] memory operatorBitmapHistory = _getOperatorBitmapHistory(registryCoordinator, uint32(block.number - 1));
        MiddlewareData memory middlewareData = MiddlewareData({
            quorumUpdateBlockNumber: quorumUpdateBlockNumber,
            operatorKeys: operatorKeys,
            quorumApkUpdates: quorumApkUpdates,
            totalStakeHistory: totalStakeHistory,
            operatorStakeHistory: operatorStakeHistory,
            operatorBitmapHistory: operatorBitmapHistory
        });
        middlewareDataHash = keccak256(abi.encode(middlewareData));
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

    function _getQuorumApkUpdates(
        ISlashingRegistryCoordinator _registryCoordinator
    ) internal view returns (ApkUpdate[] memory) {
        IBLSApkRegistry blsApkRegistry = _registryCoordinator.blsApkRegistry();
        uint32 apkHistoryLength = blsApkRegistry.getApkHistoryLength(0);
        ApkUpdate[] memory apkUpdates = new ApkUpdate[](apkHistoryLength);

        for (uint32 i = 0; i < apkHistoryLength; i++) {
            (bytes24 apkHash, uint32 updateBlockNumber, uint32 nextUpdateBlockNumber) = blsApkRegistry.apkHistory(0, i);
            apkUpdates[i] = ApkUpdate({
                apkHash: apkHash,
                updateBlockNumber: updateBlockNumber,
                nextUpdateBlockNumber: nextUpdateBlockNumber
            });
        }

        return apkUpdates;
    }

    function _getTotalStakeHistory(
    ) internal view returns (StakeUpdate[] memory) {
        IStakeRegistry stakeRegistry = registryCoordinator.stakeRegistry();
        uint256 totalStakeHistoryLength = stakeRegistry.getTotalStakeHistoryLength(0);
        StakeUpdate[] memory totalStakeHistory = new StakeUpdate[](totalStakeHistoryLength);

        for (uint256 i = 0; i < totalStakeHistoryLength; i++) {
            totalStakeHistory[i] = stakeRegistry.getTotalStakeUpdateAtIndex(0, i);
        }
        return totalStakeHistory;
    }

    // TODO: recomputing all operator ids of quorum 0, if this function starts to hit gas limits this is optimizable
    function _getOperatorStakeHistoryOfQuorum(
        ISlashingRegistryCoordinator _registryCoordinator,
        uint32 blockNumber
    ) internal view returns (OperatorStakeHistoryEntry[] memory) {
        IStakeRegistry stakeRegistry = _registryCoordinator.stakeRegistry();
        IIndexRegistry indexRegistry = _registryCoordinator.indexRegistry();

        bytes32[] memory operatorIds = indexRegistry.getOperatorListAtBlockNumber(0, blockNumber);
        OperatorStakeHistoryEntry[] memory operatorStakeHistory = new OperatorStakeHistoryEntry[](operatorIds.length);
        for (uint256 i = 0; i < operatorIds.length; i++) {
            operatorStakeHistory[i] = OperatorStakeHistoryEntry({
                operatorId: operatorIds[i],
                stakeHistory: stakeRegistry.getStakeHistory(operatorIds[i], 0)
            });
        }
        return operatorStakeHistory;
    }

    // TODO: recomputing all operator ids of quorum 0, if this function starts to hit gas limits this is optimizable
    function _getOperatorBitmapHistory(
        ISlashingRegistryCoordinator _registryCoordinator,
        uint32 blockNumber
    ) internal view returns (OperatorBitmapHistoryEntry[] memory) {
        IIndexRegistry indexRegistry = _registryCoordinator.indexRegistry();

        bytes32[] memory operatorIds = indexRegistry.getOperatorListAtBlockNumber(0, blockNumber);
        OperatorBitmapHistoryEntry[] memory operatorBitmapHistory = new OperatorBitmapHistoryEntry[](operatorIds.length);
        for (uint256 i = 0; i < operatorIds.length; i++) {
            bytes32 operatorId = operatorIds[i];
            uint256 quorumBitmapHistoryLength = _registryCoordinator.getQuorumBitmapHistoryLength(operatorId);
            QuorumBitmapUpdate[] memory bitmapHistory = new QuorumBitmapUpdate[](quorumBitmapHistoryLength);
            for (uint256 j = 0; j < quorumBitmapHistoryLength; j++) {
                bitmapHistory[j] = _registryCoordinator.getQuorumBitmapUpdateByIndex(operatorId, j);
            }
            operatorBitmapHistory[i] = OperatorBitmapHistoryEntry({
                operatorId: operatorId,
                bitmapHistory: bitmapHistory
            });
        }
        return operatorBitmapHistory;
    }
}