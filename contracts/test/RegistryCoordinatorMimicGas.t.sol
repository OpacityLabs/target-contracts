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
import {console2} from "forge-std/console2.sol";

contract RegistryCoordinatorMimicGasTest is Test {
    RegistryCoordinatorMimicHarness registryCoordinatorMimic;
    
    uint256 constant BLOCK_GAS_LIMIT = 30_000_000; // Ethereum mainnet block gas limit
    
    function setUp() public {
        registryCoordinatorMimic =
            new RegistryCoordinatorMimicHarness(SP1Helios(makeAddr("LITE_CLIENT")), makeAddr("MIDDLEWARE_SHIM"));
        registryCoordinatorMimic.harness_setMockVerifyProof(true);
    }
    
    function test_gasUsage_varyingOperatorCounts() public {
        console2.log("=== Gas Usage Analysis for updateState function ===");
        console2.log("Block gas limit:", BLOCK_GAS_LIMIT);
        console2.log("");
        
        // Test with different operator counts
        uint256[] memory operatorCounts = new uint256[](7);
        operatorCounts[0] = 10;
        operatorCounts[1] = 50;
        operatorCounts[2] = 100;
        operatorCounts[3] = 200;
        operatorCounts[4] = 500;
        operatorCounts[5] = 1000;
        operatorCounts[6] = 2000;
        
        for (uint256 i = 0; i < operatorCounts.length; i++) {
            uint256 operatorCount = operatorCounts[i];
            uint256 historyLength = 10; // Fixed history length for this test
            
            IMiddlewareShimTypes.MiddlewareData memory middlewareData = _createMiddlewareData(
                operatorCount,
                historyLength
            );
            
            uint256 gasBefore = gasleft();
            registryCoordinatorMimic.updateState(middlewareData, "mock proof");
            uint256 gasUsed = gasBefore - gasleft();
            
            uint256 percentageOfBlockLimit = (gasUsed * 100) / BLOCK_GAS_LIMIT;
            
            console2.log("Operators:", operatorCount);
            console2.log("  History Length:", historyLength);
            console2.log("  Gas Used:", gasUsed);
            console2.log("  Percentage of Block (%):", percentageOfBlockLimit);
            
            // Reset state for next iteration
            setUp();
        }
    }
    
    function test_gasUsage_varyingHistoryLength() public {
        console2.log("");
        console2.log("=== Gas Usage with Varying History Length ===");
        console2.log("");
        
        uint256 fixedOperatorCount = 100;
        uint256[] memory historyLengths = new uint256[](6);
        historyLengths[0] = 10;
        historyLengths[1] = 50;
        historyLengths[2] = 100;
        historyLengths[3] = 200;
        historyLengths[4] = 500;
        historyLengths[5] = 1000;
        
        for (uint256 i = 0; i < historyLengths.length; i++) {
            uint256 historyLength = historyLengths[i];
            
            IMiddlewareShimTypes.MiddlewareData memory middlewareData = _createMiddlewareData(
                fixedOperatorCount,
                historyLength
            );
            
            uint256 gasBefore = gasleft();
            registryCoordinatorMimic.updateState(middlewareData, "mock proof");
            uint256 gasUsed = gasBefore - gasleft();
            
            uint256 percentageOfBlockLimit = (gasUsed * 100) / BLOCK_GAS_LIMIT;
            
            console2.log("Operators:", fixedOperatorCount);
            console2.log("  History Length:", historyLength);
            console2.log("  Gas Used:", gasUsed);
            console2.log("  Percentage of Block (%):", percentageOfBlockLimit);
            
            // Reset state for next iteration
            setUp();
        }
    }
    
    function test_gasUsage_worstCase() public {
        console2.log("");
        console2.log("=== Worst Case Scenario Analysis ===");
        console2.log("");
        
        // Test combinations that might approach gas limits
        uint256[3] memory operatorCounts = [uint256(500), 1000, 2000];
        uint256[3] memory historyLengths = [uint256(100), 200, 500];
        
        for (uint256 i = 0; i < operatorCounts.length; i++) {
            for (uint256 j = 0; j < historyLengths.length; j++) {
                uint256 operatorCount = operatorCounts[i];
                uint256 historyLength = historyLengths[j];
                
                IMiddlewareShimTypes.MiddlewareData memory middlewareData = _createMiddlewareData(
                    operatorCount,
                    historyLength
                );
                
                uint256 gasBefore = gasleft();
                try registryCoordinatorMimic.updateState(middlewareData, "mock proof") {
                    uint256 gasUsed = gasBefore - gasleft();
                    uint256 percentageOfBlockLimit = (gasUsed * 100) / BLOCK_GAS_LIMIT;
                    
                    console2.log("Operators:", operatorCount);
                    console2.log("  History:", historyLength); 
                    console2.log("  Gas:", gasUsed);
                    console2.log("  Block %:", percentageOfBlockLimit);
                    
                    if (percentageOfBlockLimit > 80) {
                        console2.log("  WARNING: Approaching block gas limit!");
                    }
                } catch {
                    console2.log("Operators:", operatorCount);
                    console2.log("  History:", historyLength);
                    console2.log("  FAILED - Out of gas or error");
                }
                
                // Reset state for next iteration
                setUp();
            }
        }
    }
    
    function test_gasUsage_breakdown() public {
        console2.log("");
        console2.log("=== Gas Usage Breakdown by Component ===");
        console2.log("");
        
        uint256 operatorCount = 100;
        uint256 historyLength = 50;
        
        // Test individual components
        console2.log("Testing with operators:", operatorCount);
        console2.log("  and history length:", historyLength);
        
        // Measure APK updates only
        {
            IMiddlewareShimTypes.MiddlewareData memory middlewareData = _createMiddlewareDataApkOnly(historyLength);
            uint256 gasBefore = gasleft();
            registryCoordinatorMimic.updateState(middlewareData, "mock proof");
            uint256 gasUsed = gasBefore - gasleft();
            console2.log("APK Updates only (gas):", gasUsed);
            setUp();
        }
        
        // Measure stake history only
        {
            IMiddlewareShimTypes.MiddlewareData memory middlewareData = _createMiddlewareDataStakeOnly(operatorCount, historyLength);
            uint256 gasBefore = gasleft();
            registryCoordinatorMimic.updateState(middlewareData, "mock proof");
            uint256 gasUsed = gasBefore - gasleft();
            console2.log("Stake History only (gas):", gasUsed);
            setUp();
        }
        
        // Measure bitmap history only
        {
            IMiddlewareShimTypes.MiddlewareData memory middlewareData = _createMiddlewareDataBitmapOnly(operatorCount, historyLength);
            uint256 gasBefore = gasleft();
            registryCoordinatorMimic.updateState(middlewareData, "mock proof");
            uint256 gasUsed = gasBefore - gasleft();
            console2.log("Bitmap History only (gas):", gasUsed);
            setUp();
        }
        
        // Full update
        {
            IMiddlewareShimTypes.MiddlewareData memory middlewareData = _createMiddlewareData(operatorCount, historyLength);
            uint256 gasBefore = gasleft();
            registryCoordinatorMimic.updateState(middlewareData, "mock proof");
            uint256 gasUsed = gasBefore - gasleft();
            console2.log("Full update (gas):", gasUsed);
        }
    }
    
    // Helper functions to create test data
    
    function _createMiddlewareData(
        uint256 operatorCount,
        uint256 historyLength
    ) internal pure returns (IMiddlewareShimTypes.MiddlewareData memory) {
        // Create APK updates
        IBLSApkRegistryTypes.ApkUpdate[] memory apkUpdates = new IBLSApkRegistryTypes.ApkUpdate[](historyLength);
        for (uint256 i = 0; i < historyLength; i++) {
            apkUpdates[i] = IBLSApkRegistryTypes.ApkUpdate({
                apkHash: bytes24(uint192(i + 1)),
                updateBlockNumber: uint32(100 + i * 100),
                nextUpdateBlockNumber: i == historyLength - 1 ? 0 : uint32(200 + i * 100)
            });
        }
        
        // Create total stake history
        IStakeRegistryTypes.StakeUpdate[] memory totalStakeHistory = new IStakeRegistryTypes.StakeUpdate[](historyLength);
        for (uint256 i = 0; i < historyLength; i++) {
            totalStakeHistory[i] = IStakeRegistryTypes.StakeUpdate({
                updateBlockNumber: uint32(100 + i * 100),
                nextUpdateBlockNumber: i == historyLength - 1 ? 0 : uint32(200 + i * 100),
                stake: uint96(1000 * (i + 1))
            });
        }
        
        // Create operator stake history
        IMiddlewareShimTypes.OperatorStakeHistoryEntry[] memory operatorStakeHistory = 
            new IMiddlewareShimTypes.OperatorStakeHistoryEntry[](operatorCount);
        
        for (uint256 i = 0; i < operatorCount; i++) {
            bytes32 operatorId = bytes32(uint256(i + 1));
            IStakeRegistryTypes.StakeUpdate[] memory stakeHistory = new IStakeRegistryTypes.StakeUpdate[](historyLength);
            
            for (uint256 j = 0; j < historyLength; j++) {
                stakeHistory[j] = IStakeRegistryTypes.StakeUpdate({
                    updateBlockNumber: uint32(100 + j * 100),
                    nextUpdateBlockNumber: j == historyLength - 1 ? 0 : uint32(200 + j * 100),
                    stake: uint96(100 * (j + 1))
                });
            }
            
            operatorStakeHistory[i] = IMiddlewareShimTypes.OperatorStakeHistoryEntry({
                operatorId: operatorId,
                stakeHistory: stakeHistory
            });
        }
        
        // Create operator bitmap history
        IMiddlewareShimTypes.OperatorBitmapHistoryEntry[] memory operatorBitmapHistory = 
            new IMiddlewareShimTypes.OperatorBitmapHistoryEntry[](operatorCount);
        
        for (uint256 i = 0; i < operatorCount; i++) {
            bytes32 operatorId = bytes32(uint256(i + 1));
            ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate[] memory bitmapHistory = 
                new ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate[](historyLength);
            
            for (uint256 j = 0; j < historyLength; j++) {
                bitmapHistory[j] = ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                    quorumBitmap: uint192(1),
                    updateBlockNumber: uint32(100 + j * 100),
                    nextUpdateBlockNumber: j == historyLength - 1 ? 0 : uint32(200 + j * 100)
                });
            }
            
            operatorBitmapHistory[i] = IMiddlewareShimTypes.OperatorBitmapHistoryEntry({
                operatorId: operatorId,
                bitmapHistory: bitmapHistory
            });
        }
        
        // Create operator keys (1 quorum)
        IMiddlewareShimTypes.OperatorKeys[][] memory operatorKeys = new IMiddlewareShimTypes.OperatorKeys[][](1);
        operatorKeys[0] = new IMiddlewareShimTypes.OperatorKeys[](operatorCount);
        for (uint256 i = 0; i < operatorCount; i++) {
            operatorKeys[0][i] = IMiddlewareShimTypes.OperatorKeys({
                pkG1: BN254.G1Point({X: uint256(i * 2 + 1), Y: uint256(i * 2 + 2)}),
                pkG2: BN254.G2Point({
                    X: [uint256(i * 4 + 1), uint256(i * 4 + 2)], 
                    Y: [uint256(i * 4 + 3), uint256(i * 4 + 4)]
                }),
                stake: 100
            });
        }
        
        return IMiddlewareShimTypes.MiddlewareData({
            blockNumber: 10000,
            quorumUpdateBlockNumber: 100,
            operatorKeys: operatorKeys,
            quorumApkUpdates: apkUpdates,
            totalStakeHistory: totalStakeHistory,
            operatorStakeHistory: operatorStakeHistory,
            operatorBitmapHistory: operatorBitmapHistory
        });
    }
    
    function _createMiddlewareDataApkOnly(
        uint256 historyLength
    ) internal pure returns (IMiddlewareShimTypes.MiddlewareData memory) {
        IBLSApkRegistryTypes.ApkUpdate[] memory apkUpdates = new IBLSApkRegistryTypes.ApkUpdate[](historyLength);
        for (uint256 i = 0; i < historyLength; i++) {
            apkUpdates[i] = IBLSApkRegistryTypes.ApkUpdate({
                apkHash: bytes24(uint192(i + 1)),
                updateBlockNumber: uint32(100 + i * 100),
                nextUpdateBlockNumber: i == historyLength - 1 ? 0 : uint32(200 + i * 100)
            });
        }
        
        return IMiddlewareShimTypes.MiddlewareData({
            blockNumber: 10000,
            quorumUpdateBlockNumber: 100,
            operatorKeys: new IMiddlewareShimTypes.OperatorKeys[][](0),
            quorumApkUpdates: apkUpdates,
            totalStakeHistory: new IStakeRegistryTypes.StakeUpdate[](0),
            operatorStakeHistory: new IMiddlewareShimTypes.OperatorStakeHistoryEntry[](0),
            operatorBitmapHistory: new IMiddlewareShimTypes.OperatorBitmapHistoryEntry[](0)
        });
    }
    
    function _createMiddlewareDataStakeOnly(
        uint256 operatorCount,
        uint256 historyLength
    ) internal pure returns (IMiddlewareShimTypes.MiddlewareData memory) {
        IStakeRegistryTypes.StakeUpdate[] memory totalStakeHistory = new IStakeRegistryTypes.StakeUpdate[](historyLength);
        for (uint256 i = 0; i < historyLength; i++) {
            totalStakeHistory[i] = IStakeRegistryTypes.StakeUpdate({
                updateBlockNumber: uint32(100 + i * 100),
                nextUpdateBlockNumber: i == historyLength - 1 ? 0 : uint32(200 + i * 100),
                stake: uint96(1000 * (i + 1))
            });
        }
        
        IMiddlewareShimTypes.OperatorStakeHistoryEntry[] memory operatorStakeHistory = 
            new IMiddlewareShimTypes.OperatorStakeHistoryEntry[](operatorCount);
        
        for (uint256 i = 0; i < operatorCount; i++) {
            bytes32 operatorId = bytes32(uint256(i + 1));
            IStakeRegistryTypes.StakeUpdate[] memory stakeHistory = new IStakeRegistryTypes.StakeUpdate[](historyLength);
            
            for (uint256 j = 0; j < historyLength; j++) {
                stakeHistory[j] = IStakeRegistryTypes.StakeUpdate({
                    updateBlockNumber: uint32(100 + j * 100),
                    nextUpdateBlockNumber: j == historyLength - 1 ? 0 : uint32(200 + j * 100),
                    stake: uint96(100 * (j + 1))
                });
            }
            
            operatorStakeHistory[i] = IMiddlewareShimTypes.OperatorStakeHistoryEntry({
                operatorId: operatorId,
                stakeHistory: stakeHistory
            });
        }
        
        return IMiddlewareShimTypes.MiddlewareData({
            blockNumber: 10000,
            quorumUpdateBlockNumber: 100,
            operatorKeys: new IMiddlewareShimTypes.OperatorKeys[][](0),
            quorumApkUpdates: new IBLSApkRegistryTypes.ApkUpdate[](0),
            totalStakeHistory: totalStakeHistory,
            operatorStakeHistory: operatorStakeHistory,
            operatorBitmapHistory: new IMiddlewareShimTypes.OperatorBitmapHistoryEntry[](0)
        });
    }
    
    function _createMiddlewareDataBitmapOnly(
        uint256 operatorCount,
        uint256 historyLength
    ) internal pure returns (IMiddlewareShimTypes.MiddlewareData memory) {
        IMiddlewareShimTypes.OperatorBitmapHistoryEntry[] memory operatorBitmapHistory = 
            new IMiddlewareShimTypes.OperatorBitmapHistoryEntry[](operatorCount);
        
        for (uint256 i = 0; i < operatorCount; i++) {
            bytes32 operatorId = bytes32(uint256(i + 1));
            ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate[] memory bitmapHistory = 
                new ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate[](historyLength);
            
            for (uint256 j = 0; j < historyLength; j++) {
                bitmapHistory[j] = ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                    quorumBitmap: uint192(1),
                    updateBlockNumber: uint32(100 + j * 100),
                    nextUpdateBlockNumber: j == historyLength - 1 ? 0 : uint32(200 + j * 100)
                });
            }
            
            operatorBitmapHistory[i] = IMiddlewareShimTypes.OperatorBitmapHistoryEntry({
                operatorId: operatorId,
                bitmapHistory: bitmapHistory
            });
        }
        
        return IMiddlewareShimTypes.MiddlewareData({
            blockNumber: 10000,
            quorumUpdateBlockNumber: 100,
            operatorKeys: new IMiddlewareShimTypes.OperatorKeys[][](0),
            quorumApkUpdates: new IBLSApkRegistryTypes.ApkUpdate[](0),
            totalStakeHistory: new IStakeRegistryTypes.StakeUpdate[](0),
            operatorStakeHistory: new IMiddlewareShimTypes.OperatorStakeHistoryEntry[](0),
            operatorBitmapHistory: operatorBitmapHistory
        });
    }
}