// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MiddlewareShimHarness} from "./harness/MiddlewareShimHarness.sol";
import {IMiddlewareShimTypes} from "../src/interfaces/IMiddlewareShim.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistry} from "@eigenlayer-middleware/interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry, IStakeRegistryTypes} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "@eigenlayer-middleware/interfaces/IIndexRegistry.sol";

// NOTE: The quality of the unit tests is very sloppy intentionally. 99% of the logic is duplicated from eigenlayer middleware
// code that's gonna be deprecated in a quarter, the whole goal of this unit test file is to ensure implementation details do not accidentally change in breaking ways.
// this does not provide full coverage ofc, but prevents a VERY annoying bug where a single seemingly innocuous change to the middleware shim breaks down the line
// the whole flow.
contract MiddlewareShimTest is Test, IMiddlewareShimTypes {
    address registryCoordinator = makeAddr("registryCoordinator");

    MiddlewareShimHarness middlewareShim;

    function setUp() public {
        middlewareShim = new MiddlewareShimHarness(ISlashingRegistryCoordinator(registryCoordinator));
    }

    function test_getOperatorKeys() public {
        // Create test operator data
        bytes32[] memory operatorIds = new bytes32[](2);
        operatorIds[0] = bytes32(uint256(1));
        operatorIds[1] = bytes32(uint256(2));

        // Mock addresses for registry contracts
        address stakeRegistry = makeAddr("stakeRegistry");
        address indexRegistry = makeAddr("indexRegistry");
        address blsApkRegistry = makeAddr("blsApkRegistry");

        // Mock registry coordinator to return registry contracts
        _vm_expectMockCall(
            address(registryCoordinator),
            abi.encodeCall(ISlashingRegistryCoordinator.stakeRegistry, ()),
            abi.encode(stakeRegistry)
        );

        _vm_expectMockCall(
            address(registryCoordinator),
            abi.encodeCall(ISlashingRegistryCoordinator.indexRegistry, ()),
            abi.encode(indexRegistry)
        );

        _vm_expectMockCall(
            address(registryCoordinator),
            abi.encodeCall(ISlashingRegistryCoordinator.blsApkRegistry, ()),
            abi.encode(blsApkRegistry)
        );

        // Mock index registry to return operator list
        _vm_expectMockCall(
            indexRegistry,
            abi.encodeCall(IIndexRegistry.getOperatorListAtBlockNumber, (0, uint32(block.number))),
            abi.encode(operatorIds)
        );

        // Mock BLS registry data for each operator
        address operator1 = makeAddr("operator1");
        address operator2 = makeAddr("operator2");

        // Mock operator address lookups
        _vm_expectMockCall(
            blsApkRegistry,
            abi.encodeCall(IBLSApkRegistry.getOperatorFromPubkeyHash, (operatorIds[0])),
            abi.encode(operator1)
        );
        _vm_expectMockCall(
            blsApkRegistry,
            abi.encodeCall(IBLSApkRegistry.getOperatorFromPubkeyHash, (operatorIds[1])),
            abi.encode(operator2)
        );

        // Mock pubkey data
        _vm_expectMockCall(
            blsApkRegistry,
            abi.encodeCall(IBLSApkRegistry.operatorToPubkey, (operator1)),
            abi.encode(uint256(1), uint256(2))
        );
        _vm_expectMockCall(
            blsApkRegistry,
            abi.encodeCall(IBLSApkRegistry.operatorToPubkey, (operator2)),
            abi.encode(uint256(3), uint256(4))
        );

        // Mock G2 pubkey data (using dummy values since actual G2 points would be complex)
        _vm_expectMockCall(
            blsApkRegistry,
            abi.encodeCall(IBLSApkRegistry.getOperatorPubkeyG2, (operator1)),
            abi.encode([uint256(1), uint256(2)], [uint256(3), uint256(4)])
        );
        _vm_expectMockCall(
            blsApkRegistry,
            abi.encodeCall(IBLSApkRegistry.getOperatorPubkeyG2, (operator2)),
            abi.encode([uint256(5), uint256(6)], [uint256(7), uint256(8)])
        );

        // Mock stake amounts
        _vm_expectMockCall(
            stakeRegistry,
            abi.encodeCall(IStakeRegistry.getStakeAtBlockNumber, (operatorIds[0], 0, uint32(block.number))),
            abi.encode(uint96(100))
        );
        _vm_expectMockCall(
            stakeRegistry,
            abi.encodeCall(IStakeRegistry.getStakeAtBlockNumber, (operatorIds[1], 0, uint32(block.number))),
            abi.encode(uint96(200))
        );

        // Call getOperatorKeys
        OperatorKeys[][] memory result = middlewareShim.getOperatorKeys(
            ISlashingRegistryCoordinator(registryCoordinator), hex"00", uint32(block.number)
        );

        // Verify results
        assertEq(result.length, 1, "Expected 1 quorum"); // One quorum
        assertEq(result[0].length, 2, "Expected 2 operators"); // Two operators

        // Verify operator 1 data
        assertEq(result[0][0].pkG1.X, 1, "Expected operator 1 G1 X to be 1");
        assertEq(result[0][0].pkG1.Y, 2, "Expected operator 1 G1 Y to be 2");
        assertEq(result[0][0].pkG2.X[0], 1, "Expected operator 1 G2 X[0] to be 1");
        assertEq(result[0][0].pkG2.X[1], 2, "Expected operator 1 G2 X[1] to be 2");
        assertEq(result[0][0].pkG2.Y[0], 3, "Expected operator 1 G2 Y[0] to be 3");
        assertEq(result[0][0].pkG2.Y[1], 4, "Expected operator 1 G2 Y[1] to be 4");
        assertEq(result[0][0].stake, 100, "Expected operator 1 stake to be 100");

        // Verify operator 2 data
        assertEq(result[0][1].pkG1.X, 3, "Expected operator 2 G1 X to be 3");
        assertEq(result[0][1].pkG1.Y, 4, "Expected operator 2 G1 Y to be 4");
        assertEq(result[0][1].pkG2.X[0], 5, "Expected operator 2 G2 X[0] to be 5");
        assertEq(result[0][1].pkG2.X[1], 6, "Expected operator 2 G2 X[1] to be 6");
        assertEq(result[0][1].pkG2.Y[0], 7, "Expected operator 2 G2 Y[0] to be 7");
        assertEq(result[0][1].pkG2.Y[1], 8, "Expected operator 2 G2 Y[1] to be 8");
        assertEq(result[0][1].stake, 200, "Expected operator 2 stake to be 200");
    }

    function test_getOperatorStakeHistoryOfQuorum() public {
        // Create test operator data
        bytes32[] memory operatorIds = new bytes32[](2);
        operatorIds[0] = bytes32(uint256(1));
        operatorIds[1] = bytes32(uint256(2));

        // Mock addresses for registry contracts
        address stakeRegistry = makeAddr("stakeRegistry");
        address indexRegistry = makeAddr("indexRegistry");

        // Mock registry coordinator to return registry contracts
        _vm_expectMockCall(
            address(registryCoordinator),
            abi.encodeCall(ISlashingRegistryCoordinator.stakeRegistry, ()),
            abi.encode(stakeRegistry)
        );

        _vm_expectMockCall(
            address(registryCoordinator),
            abi.encodeCall(ISlashingRegistryCoordinator.indexRegistry, ()),
            abi.encode(indexRegistry)
        );

        // Mock index registry to return operator list
        _vm_expectMockCall(
            address(indexRegistry),
            abi.encodeCall(IIndexRegistry.getOperatorListAtBlockNumber, (0, uint32(block.number))),
            abi.encode(operatorIds)
        );

        // Create mock stake history for operators
        IStakeRegistryTypes.StakeUpdate[] memory operator1History = new IStakeRegistryTypes.StakeUpdate[](2);
        operator1History[0] =
            IStakeRegistryTypes.StakeUpdate({updateBlockNumber: 100, nextUpdateBlockNumber: 200, stake: 100});
        operator1History[1] =
            IStakeRegistryTypes.StakeUpdate({updateBlockNumber: 200, nextUpdateBlockNumber: 0, stake: 200});

        IStakeRegistryTypes.StakeUpdate[] memory operator2History = new IStakeRegistryTypes.StakeUpdate[](2);
        operator2History[0] =
            IStakeRegistryTypes.StakeUpdate({updateBlockNumber: 300, nextUpdateBlockNumber: 400, stake: 300});
        operator2History[1] =
            IStakeRegistryTypes.StakeUpdate({updateBlockNumber: 400, nextUpdateBlockNumber: 0, stake: 400});

        // Mock stake registry to return operator stake history
        _vm_expectMockCall(
            stakeRegistry,
            abi.encodeCall(IStakeRegistry.getStakeHistory, (operatorIds[0], 0)),
            abi.encode(operator1History)
        );
        _vm_expectMockCall(
            stakeRegistry,
            abi.encodeCall(IStakeRegistry.getStakeHistory, (operatorIds[1], 0)),
            abi.encode(operator2History)
        );

        // Call getOperatorStakeHistoryOfQuorum
        OperatorStakeHistoryEntry[] memory result = middlewareShim.harness_getOperatorStakeHistoryOfQuorum(
            ISlashingRegistryCoordinator(registryCoordinator), uint32(block.number)
        );

        // Verify results
        assertEq(result.length, 2, "Expected 2 operators");
        assertEq(result[0].operatorId, operatorIds[0], "Expected operator 1 ID");
        assertEq(result[0].stakeHistory.length, 2, "Expected 2 stake updates for operator 1");
        assertEq(
            result[0].stakeHistory[0].updateBlockNumber,
            100,
            "Expected first update block number for operator 1 to be 100"
        );
        assertEq(result[0].stakeHistory[0].stake, 100, "Expected first stake for operator 1 to be 100");
        assertEq(
            result[0].stakeHistory[1].updateBlockNumber,
            200,
            "Expected second update block number for operator 1 to be 200"
        );
        assertEq(result[0].stakeHistory[1].stake, 200, "Expected second stake for operator 1 to be 200");

        assertEq(result[1].operatorId, operatorIds[1], "Expected operator 2 ID");
        assertEq(result[1].stakeHistory.length, 2, "Expected 2 stake updates for operator 2");
        assertEq(
            result[1].stakeHistory[0].updateBlockNumber,
            300,
            "Expected first update block number for operator 2 to be 300"
        );
        assertEq(result[1].stakeHistory[0].stake, 300, "Expected first stake for operator 2 to be 300");
        assertEq(
            result[1].stakeHistory[1].updateBlockNumber,
            400,
            "Expected second update block number for operator 2 to be 400"
        );
        assertEq(result[1].stakeHistory[1].stake, 400, "Expected second stake for operator 2 to be 400");
    }

    function test_getOperatorBitmapHistory() public {
        // Set up bitmap history in the mock coordinator
        bytes32 operatorId1 = bytes32(uint256(1));
        bytes32 operatorId2 = bytes32(uint256(2));

        QuorumBitmapUpdate[] memory updates1 = new QuorumBitmapUpdate[](3);
        updates1[0] = QuorumBitmapUpdate({quorumBitmap: uint192(1), updateBlockNumber: 100, nextUpdateBlockNumber: 200});
        updates1[1] = QuorumBitmapUpdate({quorumBitmap: uint192(2), updateBlockNumber: 200, nextUpdateBlockNumber: 300});
        updates1[2] = QuorumBitmapUpdate({quorumBitmap: uint192(3), updateBlockNumber: 300, nextUpdateBlockNumber: 0});

        QuorumBitmapUpdate[] memory updates2 = new QuorumBitmapUpdate[](3);
        updates2[0] = QuorumBitmapUpdate({quorumBitmap: uint192(4), updateBlockNumber: 100, nextUpdateBlockNumber: 200});
        updates2[1] = QuorumBitmapUpdate({quorumBitmap: uint192(5), updateBlockNumber: 200, nextUpdateBlockNumber: 300});
        updates2[2] = QuorumBitmapUpdate({quorumBitmap: uint192(6), updateBlockNumber: 300, nextUpdateBlockNumber: 0});

        QuorumBitmapUpdate[][] memory allUpdates = new QuorumBitmapUpdate[][](2);
        allUpdates[0] = updates1;
        allUpdates[1] = updates2;

        // Mock the coordinator to return itself as the BLS APK registry
        _vm_expectMockCall(
            address(registryCoordinator),
            abi.encodeCall(ISlashingRegistryCoordinator.indexRegistry, ()),
            abi.encode(makeAddr("indexRegistry"))
        );

        // Mock index registry to return operator list
        bytes32[] memory operatorIds = new bytes32[](2);
        operatorIds[0] = operatorId1;
        operatorIds[1] = operatorId2;

        _vm_expectMockCall(
            makeAddr("indexRegistry"),
            abi.encodeCall(IIndexRegistry.getOperatorListAtBlockNumber, (0, uint32(block.number))),
            abi.encode(operatorIds)
        );

        // Mock the BLS APK registry to return the bitmap history
        for (uint256 i = 0; i < 2; i++) {
            bytes32 operatorId = operatorIds[i];

            _vm_expectMockCall(
                address(registryCoordinator),
                abi.encodeCall(ISlashingRegistryCoordinator.getQuorumBitmapHistoryLength, (operatorId)),
                abi.encode(uint32(3))
            );

            for (uint256 j = 0; j < 3; j++) {
                _vm_expectMockCall(
                    address(registryCoordinator),
                    abi.encodeCall(ISlashingRegistryCoordinator.getQuorumBitmapUpdateByIndex, (operatorId, j)),
                    abi.encode(allUpdates[i][j])
                );
            }
        }

        // Get bitmap history at block 250 - should only return first two updates
        OperatorBitmapHistoryEntry[] memory result = middlewareShim.harness_getOperatorBitmapHistory(
            ISlashingRegistryCoordinator(registryCoordinator), uint32(block.number)
        );

        // Verify length
        assertEq(result.length, 2, "Expected 2 bitmap updates");

        // Verify contents
        assertEq(result[0].operatorId, operatorId1, "operator ID should be operator ID 1");
        assertEq(result[0].bitmapHistory[0].quorumBitmap, uint192(1), "First bitmap should be 1");
        assertEq(result[0].bitmapHistory[0].updateBlockNumber, 100, "First update block number should be 100");
        assertEq(result[0].bitmapHistory[0].nextUpdateBlockNumber, 200, "First next update block number should be 200");
        assertEq(result[0].bitmapHistory[1].quorumBitmap, uint192(2), "Second bitmap should be 2");
        assertEq(result[0].bitmapHistory[1].updateBlockNumber, 200, "Second update block number should be 200");
        assertEq(result[0].bitmapHistory[1].nextUpdateBlockNumber, 300, "Second next update block number should be 300");
        assertEq(result[0].bitmapHistory[2].quorumBitmap, uint192(3), "Third bitmap should be 4");
        assertEq(result[0].bitmapHistory[2].updateBlockNumber, 300, "Third update block number should be 300");
        assertEq(result[0].bitmapHistory[2].nextUpdateBlockNumber, 0, "Third next update block number should be 0");
    }

    function test_getQuorumApkUpdates_cutsOffHistory() public {
        // Set up APK history in the mock coordinator
        ApkUpdate[] memory updates = new ApkUpdate[](3);
        updates[0] = ApkUpdate({apkHash: bytes24(uint192(1)), updateBlockNumber: 100, nextUpdateBlockNumber: 200});
        updates[1] = ApkUpdate({apkHash: bytes24(uint192(2)), updateBlockNumber: 200, nextUpdateBlockNumber: 300});
        updates[2] = ApkUpdate({apkHash: bytes24(uint192(3)), updateBlockNumber: 300, nextUpdateBlockNumber: 0});

        // Mock the coordinator to return itself as the BLS APK registry
        _vm_expectMockCall(
            address(registryCoordinator),
            abi.encodeCall(ISlashingRegistryCoordinator.blsApkRegistry, ()),
            abi.encode(makeAddr("blsApkRegistry"))
        );

        // Mock the coordinator to return these updates
        _vm_expectMockCall(
            makeAddr("blsApkRegistry"), abi.encodeCall(IBLSApkRegistry.getApkHistoryLength, (0)), abi.encode(uint32(3))
        );

        for (uint256 i = 0; i < 3; i++) {
            _vm_expectMockCall(
                makeAddr("blsApkRegistry"),
                abi.encodeCall(IBLSApkRegistry.apkHistory, (0, i)),
                abi.encode(updates[i].apkHash, updates[i].updateBlockNumber, updates[i].nextUpdateBlockNumber)
            );
        }

        // Get APK updates at block 250 - should only return first two updates
        ApkUpdate[] memory result =
            middlewareShim.harness_getQuorumApkUpdates(ISlashingRegistryCoordinator(registryCoordinator), 250);

        // Verify length
        assertEq(result.length, 2, "Expected 2 APK updates");

        // Verify contents
        // Check first APK update matches expected values
        assertEq(uint192(bytes24(result[0].apkHash)), 1, "First APK hash should be 1");
        assertEq(result[0].updateBlockNumber, 100, "First update block number should be 100");
        assertEq(result[0].nextUpdateBlockNumber, 200, "First next update block number should be 200");

        // Check second APK update matches expected values
        assertEq(uint192(bytes24(result[1].apkHash)), 2, "Second APK hash should be 2");
        assertEq(result[1].updateBlockNumber, 200, "Second update block number should be 200");
        assertEq(result[1].nextUpdateBlockNumber, 300, "Second next update block number should be 300");
    }

    function test_getTotalStakeHistory_cutsOffHistory() public {
        // Create some test stake updates
        StakeUpdate[] memory updates = new StakeUpdate[](3);
        updates[0] = StakeUpdate({updateBlockNumber: 100, nextUpdateBlockNumber: 200, stake: 100});
        updates[1] = StakeUpdate({updateBlockNumber: 200, nextUpdateBlockNumber: 300, stake: 200});
        updates[2] = StakeUpdate({updateBlockNumber: 300, nextUpdateBlockNumber: 0, stake: 300});

        // Mock the coordinator calls
        _vm_expectMockCall(
            address(registryCoordinator),
            abi.encodeCall(ISlashingRegistryCoordinator.stakeRegistry, ()),
            abi.encode(makeAddr("stakeRegistry"))
        );

        // Mock the stake registry to return these updates
        _vm_expectMockCall(
            makeAddr("stakeRegistry"),
            abi.encodeCall(IStakeRegistry.getTotalStakeHistoryLength, (0)),
            abi.encode(uint32(3))
        );

        for (uint256 i = 0; i < 3; i++) {
            _vm_expectMockCall(
                makeAddr("stakeRegistry"),
                abi.encodeCall(IStakeRegistry.getTotalStakeUpdateAtIndex, (0, i)),
                abi.encode(updates[i].updateBlockNumber, updates[i].nextUpdateBlockNumber, updates[i].stake)
            );
        }

        // Get stake updates at block 250 - should only return first two updates
        StakeUpdate[] memory result =
            middlewareShim.harness_getTotalStakeHistory(ISlashingRegistryCoordinator(registryCoordinator), 250);

        // Verify length
        assertEq(result.length, 2, "Result should only contain first two updates before block 250");

        // Verify contents of first update
        assertEq(result[0].stake, 100, "First update stake should be 100");
        assertEq(result[0].updateBlockNumber, 100, "First update block number should be 100");
        assertEq(result[0].nextUpdateBlockNumber, 200, "First update next block number should be 200");

        // Verify contents of second update
        assertEq(result[1].stake, 200, "Second update stake should be 200");
        assertEq(result[1].updateBlockNumber, 200, "Second update block number should be 200");
        assertEq(result[1].nextUpdateBlockNumber, 300, "Second update next block number should be 300");
    }

    function _vm_expectMockCall(address target, bytes memory args, bytes memory returndata) internal {
        vm.mockCall(target, args, returndata);
        vm.expectCall(target, args);
    }
}
