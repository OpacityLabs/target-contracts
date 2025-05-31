pragma solidity ^0.8.12;

import {BN254} from "@eigenlayer-middleware/libraries/BN254.sol";
import {
    ISlashingRegistryCoordinator,
    ISlashingRegistryCoordinatorTypes
} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistryTypes} from "@eigenlayer-middleware/interfaces/IBLSApkRegistry.sol";
import {IStakeRegistryTypes} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";

interface IMiddlewareShimTypes is ISlashingRegistryCoordinatorTypes, IBLSApkRegistryTypes, IStakeRegistryTypes {
    struct OperatorKeys {
        BN254.G1Point pkG1;
        BN254.G2Point pkG2;
        uint96 stake; // TODO: I think the stake here is unecessary, review
    }

    struct OperatorStakeHistoryEntry {
        bytes32 operatorId;
        StakeUpdate[] stakeHistory;
    }

    struct OperatorBitmapHistoryEntry {
        bytes32 operatorId;
        QuorumBitmapUpdate[] bitmapHistory;
    }

    struct MiddlewareData {
        uint256 blockNumber;
        uint256 quorumUpdateBlockNumber;
        OperatorKeys[][] operatorKeys; // notice: double array because copied from function that was multi-quorum but for practical purposes it's 1d array
        ApkUpdate[] quorumApkUpdates;
        StakeUpdate[] totalStakeHistory;
        OperatorStakeHistoryEntry[] operatorStakeHistory;
        OperatorBitmapHistoryEntry[] operatorBitmapHistory;
    }
}

interface IMiddlewareShim is IMiddlewareShimTypes {
    function updateMiddlewareDataHash() external;

    function getMiddlewareData(ISlashingRegistryCoordinator _registryCoordinator, uint32 blockNumber)
        external
        view
        returns (MiddlewareData memory);

    function middlewareDataHash() external view returns (bytes32);

    function registryCoordinator() external view returns (ISlashingRegistryCoordinator);
}
