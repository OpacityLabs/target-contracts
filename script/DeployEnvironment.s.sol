// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script, console} from "forge-std/Script.sol";
import {MiddlewareShim} from "../src/MiddlewareShim.sol";
import {RegistryCoordinatorMimic} from "../src/RegistryCoordinatorMimic.sol";
import {Strings} from "@openzeppelin-utils/Strings.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {SP1Helios} from "@sp1-helios/SP1Helios.sol";

contract DeployEnvironment is Script {
    address constant OPACITY_REGISTRY_COORDINATOR_ADDRESS_HOLESKY = 0x3e43AA225b5cB026C5E8a53f62572b10D526a50B;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MiddlewareShim middlewareShim = new MiddlewareShim(ISlashingRegistryCoordinator(OPACITY_REGISTRY_COORDINATOR_ADDRESS_HOLESKY));
        console.log("MiddlewareShim deployed at:", address(middlewareShim));

        RegistryCoordinatorMimic registryCoordinatorMimic = new RegistryCoordinatorMimic(SP1Helios(address(0)), address(middlewareShim));
        console.log("RegistryCoordinatorMimic deployed at:", address(registryCoordinatorMimic));

        MiddlewareShim.MiddlewareData memory middlewareData = middlewareShim.updateMiddlewareDataHash();
        console.log("MiddlewareData update block number:", middlewareData.blockNumber);
        // // I'm only storing the block number because serializing the getMiddlewareData() output is a pain
        // string memory json = string.concat("{\"blockNumber\": ", Strings.toString(middlewareData.blockNumber), "}");
        // vm.writeJson(json, "middlewareData.json");

        vm.stopBroadcast();
    }
}
