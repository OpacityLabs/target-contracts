// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {Strings} from "@openzeppelin-utils/Strings.sol";

// Mainnet
// DELEGATION_MANAGER_ADDRESS=0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A
// Holesky 
// DELEGATION_MANAGER_ADDRESS=0xA44151489861Fe9e3055d95adC98FbD462B948e7
// Mainnet
// STRATEGY_MANAGER_ADDRESS=0x858646372CC42E1A627fcE94aa7A7033e7CF075A
// Holesky 
// STRATEGY_MANAGER_ADDRESS=0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6
// Holesky stETH 
// LST_CONTRACT_ADDRESS=0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034
// Mainnet stETH
// LST_CONTRACT_ADDRESS=0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
// Holesky stETH strategy 
// LST_STRATEGY_ADDRESS=0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3
// Mainnet stETH strategy 
// LST_STRATEGY_ADDRESS=0x93c4b944D05dfe6df7645A86cd2206016c51564D

// Uses `opacity-local` for reference. See:
// https://github.com/OpacityLabs/opacity-local/blob/13e3af8c01e10c3a5a79049b44565b6053b56952/docker/eigenlayer/register.sh
// https://github.com/OpacityLabs/opacity-local/blob/13e3af8c01e10c3a5a79049b44565b6053b56952/docker/eigenlayer/eject.sh
contract EigenDAForkTest is Test {
    address constant DELEGATION_MANAGER_ADDRESS_HOLESKY = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address constant STRATEGY_MANAGER_ADDRESS_HOLESKY = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
    address constant REGISTRY_COORDINATOR_ADDRESS_HOLESKY = 0x3e43AA225b5cB026C5E8a53f62572b10D526a50B;
    address constant LST_CONTRACT_ADDRESS_HOLESKY = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address constant LST_STRATEGY_ADDRESS_HOLESKY = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;
    // I don't really like having these signatures written as static strings
    string constant DEPOSIT_FUNCTION_SIGNATURE = "depositIntoStrategy(address,address,uint256)";
    string constant APPROVE_FUNCTION_SIGNATURE = "approve(address,uint256)";
    string constant REGISTER_FUNCTION_SIGNATURE = "registerAsOperator(address,uint32,string)";

    struct Operator {
        address operator;
    }

    function setUp() public { }

    function test_fullFlow() public {
        // setup
        vm.createSelectFork("holesky");
        ISlashingRegistryCoordinator registryCoordinator = ISlashingRegistryCoordinator(REGISTRY_COORDINATOR_ADDRESS_HOLESKY);

        // eject all operators in quorum 0 in order to register new ones
        address ejector = registryCoordinator.ejector();
        bytes32[] memory operatorIds = registryCoordinator.indexRegistry().getOperatorListAtBlockNumber(0, uint32(3633000));
        for (uint256 i = 0; i < operatorIds.length; i++) {
            address operator = registryCoordinator.getOperatorFromId(operatorIds[i]);
            vm.prank(ejector);
            registryCoordinator.ejectOperator(operator, hex"00");
        }

        _createOperator(0);
    }

    function _createOperator(uint256 seed) internal returns(Operator memory) {
        string memory operatorName = string.concat("Operator ", Strings.toString(seed));
        address operatorAddress = makeAddr(operatorName);

        // mint 7 stETH to operator
        hoax(operatorAddress, 7 ether);
        (bool success, ) = LST_CONTRACT_ADDRESS_HOLESKY.call{value: 7 ether}("");
        require(success, string.concat("Mint failed for ", operatorName));

        // approve 7 stETH to strategy
        vm.prank(operatorAddress);
        (success, ) = LST_CONTRACT_ADDRESS_HOLESKY.call(abi.encodeWithSignature(APPROVE_FUNCTION_SIGNATURE, STRATEGY_MANAGER_ADDRESS_HOLESKY, 7 ether));
        require(success, string.concat("Approve failed for ", operatorName));

        // deposit 7 stETH to strategy
        vm.prank(operatorAddress);
        (success, ) = STRATEGY_MANAGER_ADDRESS_HOLESKY.call(abi.encodeWithSignature(DEPOSIT_FUNCTION_SIGNATURE, LST_STRATEGY_ADDRESS_HOLESKY, LST_CONTRACT_ADDRESS_HOLESKY, 7 ether));
        require(success, string.concat("Deposit failed for ", operatorName));

        // register operator in delegation manager
        vm.prank(operatorAddress);
        (success, ) = DELEGATION_MANAGER_ADDRESS_HOLESKY.call(abi.encodeWithSignature(REGISTER_FUNCTION_SIGNATURE, address(0), uint32(0), "foo.bar"));
        require(success, string.concat("Register failed for ", operatorName));

        return Operator({
            operator: operatorAddress
        });
    }

    // Redundant test to make sure environment is setup correctly
    //
    // function test_makeSureExists() public {
    //     vm.createSelectFork("holesky");
    //
    //     uint256 codeSize;
    //     assembly {
    //         codeSize := extcodesize(REGISTRY_COORDINATOR_ADDRESS_HOLESKY)
    //     }
    //     console.log("codeSize", codeSize);
    // }
}
