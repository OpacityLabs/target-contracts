pragma solidity ^0.8.12;

import {BN254} from "@eigenlayer-middleware/libraries/BN254.sol";
import {ISlashingRegistryCoordinatorTypes} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistryTypes} from "@eigenlayer-middleware/interfaces/IBLSApkRegistry.sol";
import {IStakeRegistryTypes} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";

interface IMiddlewareShimTypes is ISlashingRegistryCoordinatorTypes, IBLSApkRegistryTypes, IStakeRegistryTypes {
    struct OperatorKeys {
        BN254.G1Point pkG1;
        BN254.G2Point pkG2;
        uint96 stake;
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
