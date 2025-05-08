// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script, console} from "forge-std/Script.sol";
import {RegistryCoordinatorMimic} from "../../src/RegistryCoordinatorMimic.sol";
import {SP1Helios} from "@sp1-helios/SP1Helios.sol";

contract DeployL2 is Script {
    function setUp() public {}

    function run() public {
        string memory rpcUrl = vm.envString("L2_RPC_URL");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address middlewareShim = vm.envAddress("MIDDLEWARE_SHIM_ADDRESS");

        vm.createSelectFork(rpcUrl);
        vm.startBroadcast(deployerPrivateKey);
        // TODO: add SP1Helios address
        RegistryCoordinatorMimic registryCoordinatorMimic =
            new RegistryCoordinatorMimic(SP1Helios(address(0)), address(middlewareShim));
        console.log("RegistryCoordinatorMimic deployed at:", address(registryCoordinatorMimic));

        vm.stopBroadcast();
    }
}
