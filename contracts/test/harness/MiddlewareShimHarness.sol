// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {MiddlewareShim} from "../../src/MiddlewareShim.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IMiddlewareShimTypes} from "../../src/interfaces/IMiddlewareShim.sol";

contract MiddlewareShimHarness is MiddlewareShim {
    constructor(ISlashingRegistryCoordinator _registryCoordinator) MiddlewareShim(_registryCoordinator) {}

    function harness_getQuorumApkUpdates(ISlashingRegistryCoordinator _registryCoordinator, uint32 blockNumber)
        external
        view
        returns (ApkUpdate[] memory)
    {
        return _getQuorumApkUpdates(_registryCoordinator, blockNumber);
    }

    function harness_getTotalStakeHistory(ISlashingRegistryCoordinator _registryCoordinator, uint32 blockNumber)
        external
        view
        returns (StakeUpdate[] memory)
    {
        return _getTotalStakeHistory(_registryCoordinator, blockNumber);
    }

    function harness_getOperatorStakeHistoryOfQuorum(
        ISlashingRegistryCoordinator _registryCoordinator,
        uint32 blockNumber
    ) external view returns (OperatorStakeHistoryEntry[] memory) {
        return _getOperatorStakeHistoryOfQuorum(_registryCoordinator, blockNumber);
    }

    function harness_getOperatorBitmapHistory(ISlashingRegistryCoordinator _registryCoordinator, uint32 blockNumber)
        external
        view
        returns (OperatorBitmapHistoryEntry[] memory)
    {
        return _getOperatorBitmapHistory(_registryCoordinator, blockNumber);
    }
}
