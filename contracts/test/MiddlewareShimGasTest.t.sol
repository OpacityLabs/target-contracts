// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/MiddlewareShim.sol";
import {IMiddlewareShimTypes} from "../src/interfaces/IMiddlewareShim.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistry} from "@eigenlayer-middleware/interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry, IStakeRegistryTypes} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "@eigenlayer-middleware/interfaces/IIndexRegistry.sol";
import {BN254} from "@eigenlayer-middleware/libraries/BN254.sol";

contract MiddlewareShimGasTest is Test, IMiddlewareShimTypes {
    MiddlewareShim public middlewareShim;
    ISlashingRegistryCoordinator public registryCoordinator;
    IBLSApkRegistry public blsApkRegistry;
    IStakeRegistry public stakeRegistry;
    IIndexRegistry public indexRegistry;

    uint256 constant BLOCK_GAS_LIMIT = 30_000_000; // Ethereum mainnet block gas limit
    uint256 constant SAFETY_MARGIN = 0.8e18; // 80% safety margin

    struct GasReport {
        uint256 operatorCount;
        uint256 historyLength;
        uint256 gasUsed;
        bool exceedsLimit;
        uint256 percentOfLimit;
    }

    function setUp() public {
        registryCoordinator = ISlashingRegistryCoordinator(address(0x1234));
        blsApkRegistry = IBLSApkRegistry(address(0x5678));
        stakeRegistry = IStakeRegistry(address(0x9ABC));
        indexRegistry = IIndexRegistry(address(0xDEF0));
        
        middlewareShim = new MiddlewareShim(registryCoordinator);
    }

    function testGasUsageWithVaryingOperatorCounts() public {
        uint256[] memory operatorCounts = new uint256[](7);
        operatorCounts[0] = 10;
        operatorCounts[1] = 25;
        operatorCounts[2] = 50;
        operatorCounts[3] = 100;
        operatorCounts[4] = 250;
        operatorCounts[5] = 500;
        operatorCounts[6] = 1000;

        uint256 historyLength = 10; // Standard history length

        console.log("=== Gas Usage Report: Varying Operator Counts ===");
        console.log("Block Gas Limit: %s", BLOCK_GAS_LIMIT);
        console.log("Safety Threshold (80%): %s", (BLOCK_GAS_LIMIT * 80) / 100);
        console.log("");
        
        for (uint256 i = 0; i < operatorCounts.length; i++) {
            GasReport memory report = _measureGasUsage(operatorCounts[i], historyLength);
            _printGasReport(report);
            
            if (report.exceedsLimit) {
                console.log("WARNING: Gas limit exceeded at %s operators!", operatorCounts[i]);
                break;
            }
        }
    }

    function testGasUsageWithVaryingHistoryLengths() public {
        uint256 operatorCount = 100; // Fixed operator count
        
        uint256[] memory historyLengths = new uint256[](6);
        historyLengths[0] = 5;
        historyLengths[1] = 10;
        historyLengths[2] = 25;
        historyLengths[3] = 50;
        historyLengths[4] = 100;
        historyLengths[5] = 200;

        console.log("=== Gas Usage Report: Varying History Lengths ===");
        console.log("Fixed Operator Count: %s", operatorCount);
        console.log("Block Gas Limit: %s", BLOCK_GAS_LIMIT);
        console.log("");
        
        for (uint256 i = 0; i < historyLengths.length; i++) {
            GasReport memory report = _measureGasUsage(operatorCount, historyLengths[i]);
            _printGasReport(report);
            
            if (report.exceedsLimit) {
                console.log("WARNING: Gas limit exceeded at history length %s!", historyLengths[i]);
                break;
            }
        }
    }

    function testWorstCaseScenario() public {
        console.log("=== Worst Case Scenario Test ===");
        
        // Test progressively worse scenarios
        uint256[3] memory operatorCounts = [uint256(250), 500, 750];
        uint256[3] memory historyLengths = [uint256(50), 100, 150];
        
        for (uint256 i = 0; i < operatorCounts.length; i++) {
            for (uint256 j = 0; j < historyLengths.length; j++) {
                GasReport memory report = _measureGasUsage(operatorCounts[i], historyLengths[j]);
                console.log("Operators: %s | History: %s", operatorCounts[i], historyLengths[j]);
                _printGasReport(report);
                
                if (report.percentOfLimit > 80e16) { // More than 80%
                    console.log("CRITICAL: Approaching gas limit danger zone!");
                }
                
                if (report.exceedsLimit) {
                    console.log("FAILURE: Configuration exceeds block gas limit!");
                    return;
                }
                console.log("");
            }
        }
    }

    function testGasGrowthRate() public {
        console.log("=== Gas Growth Rate Analysis ===");
        
        uint256 baseOperators = 50;
        uint256 baseHistory = 10;
        
        GasReport memory baseReport = _measureGasUsage(baseOperators, baseHistory);
        console.log("Baseline - Operators: %s History: %s Gas: %s", baseOperators, baseHistory, baseReport.gasUsed);
        
        // Test operator scaling
        GasReport memory doubleOpsReport = _measureGasUsage(baseOperators * 2, baseHistory);
        uint256 opsGrowthFactor = (doubleOpsReport.gasUsed * 100) / baseReport.gasUsed;
        console.log("2x Operators - Gas: %s Growth: %s%%", doubleOpsReport.gasUsed, opsGrowthFactor);
        
        // Test history scaling
        GasReport memory doubleHistReport = _measureGasUsage(baseOperators, baseHistory * 2);
        uint256 histGrowthFactor = (doubleHistReport.gasUsed * 100) / baseReport.gasUsed;
        console.log("2x History - Gas: %s Growth: %s%%", doubleHistReport.gasUsed, histGrowthFactor);
        
        // Test combined scaling
        GasReport memory doubleBothReport = _measureGasUsage(baseOperators * 2, baseHistory * 2);
        uint256 combinedGrowthFactor = (doubleBothReport.gasUsed * 100) / baseReport.gasUsed;
        console.log("2x Both - Gas: %s Growth: %s%%", doubleBothReport.gasUsed, combinedGrowthFactor);
        
        console.log("");
        console.log("Analysis:");
        if (opsGrowthFactor > 150) {
            console.log("- Operator count has super-linear gas growth (>1.5x for 2x operators)");
        } else {
            console.log("- Operator count has sub-linear or linear gas growth");
        }
        
        if (histGrowthFactor > 150) {
            console.log("- History length has super-linear gas growth (>1.5x for 2x history)");
        } else {
            console.log("- History length has sub-linear or linear gas growth");
        }
    }

    function _measureGasUsage(uint256 operatorCount, uint256 historyLength) 
        internal 
        returns (GasReport memory) 
    {
        _setupMocksForOperatorCount(operatorCount, historyLength);
        
        uint256 startGas = gasleft();
        middlewareShim.updateMiddlewareDataHash();
        uint256 gasUsed = startGas - gasleft();
        
        // Add overhead for transaction costs
        gasUsed += 25000;
        
        return GasReport({
            operatorCount: operatorCount,
            historyLength: historyLength,
            gasUsed: gasUsed,
            exceedsLimit: gasUsed > BLOCK_GAS_LIMIT,
            percentOfLimit: (gasUsed * 1e18) / BLOCK_GAS_LIMIT
        });
    }

    function _setupMocksForOperatorCount(uint256 operatorCount, uint256 historyLength) internal {
        // Mock registry coordinator
        vm.mockCall(
            address(registryCoordinator),
            abi.encodeWithSelector(ISlashingRegistryCoordinator.blsApkRegistry.selector),
            abi.encode(blsApkRegistry)
        );
        
        vm.mockCall(
            address(registryCoordinator),
            abi.encodeWithSelector(ISlashingRegistryCoordinator.stakeRegistry.selector),
            abi.encode(stakeRegistry)
        );
        
        vm.mockCall(
            address(registryCoordinator),
            abi.encodeWithSelector(ISlashingRegistryCoordinator.indexRegistry.selector),
            abi.encode(indexRegistry)
        );
        
        // Mock quorumUpdateBlockNumber
        vm.mockCall(
            address(registryCoordinator),
            abi.encodeWithSelector(ISlashingRegistryCoordinator.quorumUpdateBlockNumber.selector, 0),
            abi.encode(block.number)
        );
        
        // Mock operator IDs
        bytes32[] memory operatorIds = new bytes32[](operatorCount);
        for (uint256 i = 0; i < operatorCount; i++) {
            operatorIds[i] = bytes32(i + 1);
        }
        
        vm.mockCall(
            address(indexRegistry),
            abi.encodeWithSelector(IIndexRegistry.getOperatorListAtBlockNumber.selector, 0, uint32(block.number)),
            abi.encode(operatorIds)
        );
        
        // Mock operator keys and stakes
        for (uint256 i = 0; i < operatorCount; i++) {
            // Mock operator address
            address operatorAddress = address(uint160(i + 1));
            vm.mockCall(
                address(blsApkRegistry),
                abi.encodeWithSelector(IBLSApkRegistry.getOperatorFromPubkeyHash.selector, operatorIds[i]),
                abi.encode(operatorAddress)
            );
            
            // Mock operator G1 public key
            vm.mockCall(
                address(blsApkRegistry),
                abi.encodeWithSelector(IBLSApkRegistry.operatorToPubkey.selector, operatorAddress),
                abi.encode(uint256(keccak256(abi.encode(i, "x"))), uint256(keccak256(abi.encode(i, "y"))))
            );
            
            // Mock operator G2 public key
            vm.mockCall(
                address(blsApkRegistry),
                abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, operatorAddress),
                abi.encode(BN254.G2Point([uint256(keccak256(abi.encode(i, "x0"))), uint256(keccak256(abi.encode(i, "x1")))], 
                                        [uint256(keccak256(abi.encode(i, "y0"))), uint256(keccak256(abi.encode(i, "y1")))]))
            );
            
            // Mock stake
            vm.mockCall(
                address(stakeRegistry),
                abi.encodeWithSelector(IStakeRegistry.getStakeAtBlockNumber.selector, operatorIds[i], 0, uint32(block.number)),
                abi.encode(uint96(1000 * 1e18 * (i + 1)))
            );
        }
        
        // Mock APK history  
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getApkHistoryLength.selector, 0),
            abi.encode(historyLength)
        );
        for (uint256 i = 0; i < historyLength; i++) {
            uint32 updateBlock = uint32(block.number > (historyLength - i) * 100 ? block.number - (historyLength - i) * 100 : 1);
            uint32 nextUpdateBlock = i < historyLength - 1 
                ? uint32(block.number > (historyLength - i - 1) * 100 ? block.number - (historyLength - i - 1) * 100 : updateBlock + 100)
                : 0;
            vm.mockCall(
                address(blsApkRegistry),
                abi.encodeWithSelector(IBLSApkRegistry.apkHistory.selector, 0, i),
                abi.encode(
                    bytes24(keccak256(abi.encode("apk", i))),
                    updateBlock,
                    nextUpdateBlock
                )
            );
        }
        
        // Mock total stake history
        IStakeRegistryTypes.StakeUpdate[] memory stakeHistory = new IStakeRegistryTypes.StakeUpdate[](historyLength);
        for (uint256 i = 0; i < historyLength; i++) {
            uint32 updateBlock = uint32(block.number > (historyLength - i) * 100 ? block.number - (historyLength - i) * 100 : 1);
            uint32 nextUpdateBlock = i < historyLength - 1 
                ? uint32(block.number > (historyLength - i - 1) * 100 ? block.number - (historyLength - i - 1) * 100 : updateBlock + 100)
                : 0;
            stakeHistory[i] = IStakeRegistryTypes.StakeUpdate({
                updateBlockNumber: updateBlock,
                nextUpdateBlockNumber: nextUpdateBlock,
                stake: uint96(1000000 * 1e18 * (i + 1))
            });
        }
        vm.mockCall(
            address(stakeRegistry),
            abi.encodeWithSelector(IStakeRegistry.getTotalStakeHistoryLength.selector, 0),
            abi.encode(historyLength)
        );
        for (uint256 i = 0; i < historyLength; i++) {
            vm.mockCall(
                address(stakeRegistry),
                abi.encodeWithSelector(IStakeRegistry.getTotalStakeUpdateAtIndex.selector, 0, i),
                abi.encode(stakeHistory[i])
            );
        }
        
        // Mock operator stake history (smaller history per operator to be realistic)
        uint256 operatorHistoryLength = historyLength / 2 + 1;
        for (uint256 j = 0; j < operatorCount; j++) {
            IStakeRegistryTypes.StakeUpdate[] memory operatorHistory = new IStakeRegistryTypes.StakeUpdate[](operatorHistoryLength);
            for (uint256 i = 0; i < operatorHistoryLength; i++) {
                uint32 updateBlock = uint32(block.number > (operatorHistoryLength - i) * 200 ? block.number - (operatorHistoryLength - i) * 200 : 1);
                uint32 nextUpdateBlock = i < operatorHistoryLength - 1 
                    ? uint32(block.number > (operatorHistoryLength - i - 1) * 200 ? block.number - (operatorHistoryLength - i - 1) * 200 : updateBlock + 200)
                    : 0;
                operatorHistory[i] = IStakeRegistryTypes.StakeUpdate({
                    updateBlockNumber: updateBlock,
                    nextUpdateBlockNumber: nextUpdateBlock,
                    stake: uint96(1000 * 1e18 * (j + 1) * (i + 1))
                });
            }
            vm.mockCall(
                address(stakeRegistry),
                abi.encodeWithSelector(IStakeRegistry.getStakeHistory.selector, operatorIds[j], 0),
                abi.encode(operatorHistory)
            );
        }
        
        // Mock operator bitmap history
        for (uint256 j = 0; j < operatorCount; j++) {
            vm.mockCall(
                address(registryCoordinator),
                abi.encodeWithSelector(ISlashingRegistryCoordinator.getQuorumBitmapHistoryLength.selector, operatorIds[j]),
                abi.encode(operatorHistoryLength)
            );
            
            for (uint256 i = 0; i < operatorHistoryLength; i++) {
                uint32 updateBlock = uint32(block.number > (operatorHistoryLength - i) * 200 ? block.number - (operatorHistoryLength - i) * 200 : 1);
                uint32 nextUpdateBlock = i < operatorHistoryLength - 1 
                    ? uint32(block.number > (operatorHistoryLength - i - 1) * 200 ? block.number - (operatorHistoryLength - i - 1) * 200 : updateBlock + 200)
                    : 0;
                QuorumBitmapUpdate memory bitmapUpdate = QuorumBitmapUpdate({
                    updateBlockNumber: updateBlock,
                    nextUpdateBlockNumber: nextUpdateBlock,
                    quorumBitmap: uint192(1) // Operator in quorum 0
                });
                vm.mockCall(
                    address(registryCoordinator),
                    abi.encodeWithSelector(ISlashingRegistryCoordinator.getQuorumBitmapUpdateByIndex.selector, operatorIds[j], i),
                    abi.encode(bitmapUpdate)
                );
            }
        }
    }

    function _printGasReport(GasReport memory report) internal view {
        console.log("Operators: %s | History: %s", report.operatorCount, report.historyLength);
        console.log("  Gas Used: %s", report.gasUsed);
        console.log("  %% of Block Limit: %s%%", report.percentOfLimit / 1e16);
        
        if (report.percentOfLimit > 80e16) {
            console.log("  Status: DANGER - Exceeds 80% safety threshold");
        } else if (report.percentOfLimit > 50e16) {
            console.log("  Status: WARNING - Over 50% of block limit");
        } else {
            console.log("  Status: SAFE");
        }
        console.log("");
    }

    function testEstimateMaxSafeOperatorCount() public {
        console.log("=== Estimating Maximum Safe Operator Count ===");
        console.log("Target: 80% of block gas limit");
        console.log("");
        
        uint256 historyLength = 20; // Reasonable history length
        uint256 targetGas = (BLOCK_GAS_LIMIT * 80) / 100;
        
        // Binary search for max safe operator count
        uint256 low = 0;
        uint256 high = 2000;
        uint256 maxSafe = 0;
        
        while (low <= high) {
            uint256 mid = (low + high) / 2;
            GasReport memory report = _measureGasUsage(mid, historyLength);
            
            if (report.gasUsed <= targetGas) {
                maxSafe = mid;
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }
        
        console.log("Maximum Safe Operator Count (with history length %s): %s", historyLength, maxSafe);
        
        GasReport memory finalReport = _measureGasUsage(maxSafe, historyLength);
        console.log("Gas at max: %s", finalReport.gasUsed);
        console.log("%% of limit: %s%%", finalReport.percentOfLimit / 1e16);
    }
}