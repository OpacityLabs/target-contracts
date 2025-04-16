// SPDX-License-Identifier: UNLICENSED
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

    // TODO: should there be access control here? 
    // I sense a mild possibility of grifting due to asynchrones behavior of the diferent processes (lite client, shim, mimic)
    // Thought I don't have anything yet
    function updateMiddlewareDataHash() external {
        // assume there is only one quorum 0
        // REVIEW: I'm not actually convinced that you have to do block.number - 1 here
        // The original rational is that you can't do a state proof over the storage slot in the block that has the transaction modifying the storage,
        // But this shim contract is agnostic to the whole proof stuff: Why can't it query an EigenLayer middleware at the current executing block?
        // Need to review this more critically
        MiddlewareData memory middlewareData = getMiddlewareData(registryCoordinator, uint32(block.number - 1));
        middlewareDataHash = keccak256(abi.encode(middlewareData));
    }

    function getMiddlewareData(ISlashingRegistryCoordinator _registryCoordinator, uint32 blockNumber)
        public
        view
        returns (MiddlewareData memory)
    {
        return MiddlewareData({
            blockNumber: blockNumber,
            quorumUpdateBlockNumber: _registryCoordinator.quorumUpdateBlockNumber(0),
            operatorKeys: getOperatorKeys(_registryCoordinator, hex"00", blockNumber),
            quorumApkUpdates: _getQuorumApkUpdates(_registryCoordinator),  // TODO: make take blockNumber
            totalStakeHistory: _getTotalStakeHistory(_registryCoordinator), // TODO: make take blockNumber
            operatorStakeHistory: _getOperatorStakeHistoryOfQuorum(_registryCoordinator, blockNumber),
            operatorBitmapHistory: _getOperatorBitmapHistory(_registryCoordinator, blockNumber)
        });
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
            bytes32[] memory operatorIds = indexRegistry.getOperatorListAtBlockNumber(quorumNumber, blockNumber);
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
                    operatorKeys[i][j].stake =
                        stakeRegistry.getStakeAtBlockNumber(bytes32(operatorIds[j]), quorumNumber, blockNumber);
                }
            }
        }

        return operatorKeys;
    }

    function _getQuorumApkUpdates(ISlashingRegistryCoordinator _registryCoordinator)
        internal
        view
        returns (ApkUpdate[] memory)
    {
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

    function _getTotalStakeHistory(ISlashingRegistryCoordinator _registryCoordinator)
        internal
        view
        returns (StakeUpdate[] memory)
    {
        IStakeRegistry stakeRegistry = _registryCoordinator.stakeRegistry();
        uint256 totalStakeHistoryLength = stakeRegistry.getTotalStakeHistoryLength(0);
        StakeUpdate[] memory totalStakeHistory = new StakeUpdate[](totalStakeHistoryLength);

        for (uint256 i = 0; i < totalStakeHistoryLength; i++) {
            totalStakeHistory[i] = stakeRegistry.getTotalStakeUpdateAtIndex(0, i);
        }
        return totalStakeHistory;
    }

    // TODO: recomputing all operator ids of quorum 0, if this function starts to hit gas limits this is optimizable
    function _getOperatorStakeHistoryOfQuorum(ISlashingRegistryCoordinator _registryCoordinator, uint32 blockNumber)
        internal
        view
        returns (OperatorStakeHistoryEntry[] memory)
    {
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
    function _getOperatorBitmapHistory(ISlashingRegistryCoordinator _registryCoordinator, uint32 blockNumber)
        internal
        view
        returns (OperatorBitmapHistoryEntry[] memory)
    {
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
            operatorBitmapHistory[i] =
                OperatorBitmapHistoryEntry({operatorId: operatorId, bitmapHistory: bitmapHistory});
        }
        return operatorBitmapHistory;
    }
}
