// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script, console} from "forge-std/Script.sol";
import {MiddlewareShim} from "../../src/MiddlewareShim.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";

contract DeployL1 is Script {
    function setUp() public {}

    function run() public {
        string memory outPath = vm.envString("L1_OUT_PATH");
        address REGISTRY_COORDINATOR_ADDRESS = vm.envAddress("REGISTRY_COORDINATOR_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("RegistryCoordinatorAddress:", REGISTRY_COORDINATOR_ADDRESS);

        vm.startBroadcast(deployerPrivateKey);
        MiddlewareShim middlewareShim = 
            new MiddlewareShim(ISlashingRegistryCoordinator(REGISTRY_COORDINATOR_ADDRESS));
        console.log("MiddlewareShim deployed at:", address(middlewareShim));

        vm.writeFile(outPath, vm.serializeAddress("object key", "middlewareShim", address(middlewareShim)));
        console.log("Deployment info written to", outPath);

        vm.stopBroadcast();
    }
}
