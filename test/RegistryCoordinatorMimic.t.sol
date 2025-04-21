// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {RegistryCoordinatorMimic} from "../src/RegistryCoordinatorMimic.sol";
import {RegistryCoordinatorMimicHarness} from "./harness/RegistryCoordinatorMimicHarness.sol";
import {ISlashingRegistryCoordinatorTypes} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistryTypes} from "@eigenlayer-middleware/interfaces/IBLSApkRegistry.sol";
import {IStakeRegistryTypes} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IMiddlewareShimTypes} from "../src/interfaces/IMiddlewareShim.sol";
import {SP1Helios} from "@sp1-helios/SP1Helios.sol";
import {BN254} from "@eigenlayer-middleware/libraries/BN254.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

// NOTE: The quality of the unit tests is very sloppy intentionally. 99% of the logic is duplicated from eigenlayer middleware
// code that's gonna be deprecated in a quarter, the whole goal of this unit test file is to ensure implementation details do not accidentally change in breaking ways.
// this does not provide full coverage ofc, but prevents a VERY annoying bug where a single seemingly innocuous change to the middleware shim breaks down the line
// the whole flow.
contract RegistryCoordinatorMimicTest is Test {
    RegistryCoordinatorMimicHarness registryCoordinatorMimic;

    function setUp() public {
        registryCoordinatorMimic =
            new RegistryCoordinatorMimicHarness(SP1Helios(makeAddr("LITE_CLIENT")), makeAddr("MIDDLEWARE_SHIM"));
        registryCoordinatorMimic.harness_setMockVerifyProof(true);
    }

    function test_updateState() public {
        // Create mock APK updates
        IBLSApkRegistryTypes.ApkUpdate[] memory apkUpdates = new IBLSApkRegistryTypes.ApkUpdate[](2);
        apkUpdates[0] = IBLSApkRegistryTypes.ApkUpdate({
            apkHash: bytes24(uint192(1)),
            updateBlockNumber: 100,
            nextUpdateBlockNumber: 200
        });
        apkUpdates[1] = IBLSApkRegistryTypes.ApkUpdate({
            apkHash: bytes24(uint192(2)),
            updateBlockNumber: 200,
            nextUpdateBlockNumber: 0
        });

        // Create mock stake updates
        IStakeRegistryTypes.StakeUpdate[] memory totalStakeHistory = new IStakeRegistryTypes.StakeUpdate[](2);
        totalStakeHistory[0] =
            IStakeRegistryTypes.StakeUpdate({updateBlockNumber: 100, nextUpdateBlockNumber: 200, stake: 100});
        totalStakeHistory[1] =
            IStakeRegistryTypes.StakeUpdate({updateBlockNumber: 200, nextUpdateBlockNumber: 0, stake: 200});

        // Create mock operator stake history
        bytes32[] memory operatorIds = new bytes32[](2);
        operatorIds[0] = bytes32(uint256(1));
        operatorIds[1] = bytes32(uint256(2));

        IStakeRegistryTypes.StakeUpdate[][] memory operatorStakeHistories = new IStakeRegistryTypes.StakeUpdate[][](2);

        // First operator stake history
        operatorStakeHistories[0] = new IStakeRegistryTypes.StakeUpdate[](2);
        operatorStakeHistories[0][0] =
            IStakeRegistryTypes.StakeUpdate({updateBlockNumber: 100, nextUpdateBlockNumber: 200, stake: 50});
        operatorStakeHistories[0][1] =
            IStakeRegistryTypes.StakeUpdate({updateBlockNumber: 200, nextUpdateBlockNumber: 0, stake: 100});

        // Second operator stake history
        operatorStakeHistories[1] = new IStakeRegistryTypes.StakeUpdate[](2);
        operatorStakeHistories[1][0] =
            IStakeRegistryTypes.StakeUpdate({updateBlockNumber: 100, nextUpdateBlockNumber: 200, stake: 50});
        operatorStakeHistories[1][1] =
            IStakeRegistryTypes.StakeUpdate({updateBlockNumber: 200, nextUpdateBlockNumber: 0, stake: 100});

        // Create mock bitmap history
        ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate[][] memory operatorBitmapHistories =
            new ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate[][](2);

        // First operator bitmap history
        operatorBitmapHistories[0] = new ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate[](2);
        operatorBitmapHistories[0][0] = ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
            quorumBitmap: uint192(1),
            updateBlockNumber: 100,
            nextUpdateBlockNumber: 200
        });
        operatorBitmapHistories[0][1] = ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
            quorumBitmap: uint192(1),
            updateBlockNumber: 200,
            nextUpdateBlockNumber: 0
        });

        // Second operator bitmap history
        operatorBitmapHistories[1] = new ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate[](2);
        operatorBitmapHistories[1][0] = ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
            quorumBitmap: uint192(1),
            updateBlockNumber: 100,
            nextUpdateBlockNumber: 200
        });
        operatorBitmapHistories[1][1] = ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
            quorumBitmap: uint192(1),
            updateBlockNumber: 200,
            nextUpdateBlockNumber: 0
        });

        IMiddlewareShimTypes.OperatorKeys[][] memory operatorKeys = new IMiddlewareShimTypes.OperatorKeys[][](1);
        operatorKeys[0] = new IMiddlewareShimTypes.OperatorKeys[](2);
        operatorKeys[0][0] = IMiddlewareShimTypes.OperatorKeys({
            pkG1: BN254.G1Point({X: uint256(1), Y: uint256(2)}),
            pkG2: BN254.G2Point({X: [uint256(3), uint256(4)], Y: [uint256(5), uint256(6)]}),
            stake: 100
        });
        operatorKeys[0][1] = IMiddlewareShimTypes.OperatorKeys({
            pkG1: BN254.G1Point({X: uint256(7), Y: uint256(8)}),
            pkG2: BN254.G2Point({X: [uint256(9), uint256(10)], Y: [uint256(11), uint256(12)]}),
            stake: 100
        });

        IMiddlewareShimTypes.OperatorStakeHistoryEntry[] memory operatorStakeHistory =
            new IMiddlewareShimTypes.OperatorStakeHistoryEntry[](2);
        operatorStakeHistory[0] = IMiddlewareShimTypes.OperatorStakeHistoryEntry({
            operatorId: operatorIds[0],
            stakeHistory: operatorStakeHistories[0]
        });
        operatorStakeHistory[1] = IMiddlewareShimTypes.OperatorStakeHistoryEntry({
            operatorId: operatorIds[1],
            stakeHistory: operatorStakeHistories[1]
        });
        IMiddlewareShimTypes.OperatorBitmapHistoryEntry[] memory operatorBitmapHistory =
            new IMiddlewareShimTypes.OperatorBitmapHistoryEntry[](2);
        operatorBitmapHistory[0] = IMiddlewareShimTypes.OperatorBitmapHistoryEntry({
            operatorId: operatorIds[0],
            bitmapHistory: operatorBitmapHistories[0]
        });
        operatorBitmapHistory[1] = IMiddlewareShimTypes.OperatorBitmapHistoryEntry({
            operatorId: operatorIds[1],
            bitmapHistory: operatorBitmapHistories[1]
        });

        // Create middleware data
        IMiddlewareShimTypes.MiddlewareData memory middlewareData = IMiddlewareShimTypes.MiddlewareData({
            blockNumber: 250,
            quorumUpdateBlockNumber: 100,
            operatorKeys: operatorKeys,
            quorumApkUpdates: apkUpdates,
            totalStakeHistory: totalStakeHistory,
            operatorStakeHistory: operatorStakeHistory,
            operatorBitmapHistory: operatorBitmapHistory
        });

        // Create proof
        bytes memory proof = "mock proof";

        // Call updateState
        registryCoordinatorMimic.updateState(middlewareData, proof);

        // Verify state
        assertEq(abi.encode(registryCoordinatorMimic.harness_getQuorumApkUpdates()), abi.encode(apkUpdates));
        assertEq(abi.encode(registryCoordinatorMimic.harness_getTotalStakeHistory()), abi.encode(totalStakeHistory));
        assertEq(
            abi.encode(registryCoordinatorMimic.harness_getOperatorStakeHistory(operatorIds[0])),
            abi.encode(operatorStakeHistories[0])
        );
        assertEq(
            abi.encode(registryCoordinatorMimic.harness_getOperatorStakeHistory(operatorIds[1])),
            abi.encode(operatorStakeHistories[1])
        );
        assertEq(
            abi.encode(registryCoordinatorMimic.harness_getOperatorBitmapHistory(operatorIds[0])),
            abi.encode(operatorBitmapHistories[0])
        );
        assertEq(
            abi.encode(registryCoordinatorMimic.harness_getOperatorBitmapHistory(operatorIds[1])),
            abi.encode(operatorBitmapHistories[1])
        );
        assertEq(registryCoordinatorMimic.harness_getQuorum0UpdateBlockNumber(), 100);
        assertEq(registryCoordinatorMimic.lastBlockNumber(), 250);
    }
}
