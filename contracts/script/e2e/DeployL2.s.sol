// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script, console} from "forge-std/Script.sol";
import {RegistryCoordinatorMimic} from "../../src/RegistryCoordinatorMimic.sol";
import {SP1Helios} from "@sp1-helios/SP1Helios.sol";
import {BLSSignatureChecker} from "@eigenlayer-middleware/BLSSignatureChecker.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {SP1HeliosMock} from "./contracts/SP1HeliosMock.sol";
import {SignatureConsumer} from "./contracts/SignatureConsumer.sol";

contract DeployL2 is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address middlewareShim = vm.envAddress("MIDDLEWARE_SHIM_ADDRESS");
        address sp1heliosAddress = vm.envAddress("SP1HELIOS_ADDRESS");
        bool isSp1HeliosMock = vm.envBool("IS_SP1HELIOS_MOCK");
        string memory outPath = vm.envString("L2_OUT_PATH");

        vm.startBroadcast(deployerPrivateKey);
        if (isSp1HeliosMock) {
            console.log("SP1Helios is mocked, deploying mock...");
            SP1HeliosMock sp1heliosMock = new SP1HeliosMock();
            sp1heliosAddress = address(sp1heliosMock);
            console.log("SP1HeliosMock deployed at:", sp1heliosAddress);
        }

        RegistryCoordinatorMimic registryCoordinatorMimic =
            new RegistryCoordinatorMimic(SP1Helios(sp1heliosAddress), address(middlewareShim));
        console.log("RegistryCoordinatorMimic deployed at:", address(registryCoordinatorMimic));

        BLSSignatureChecker blsSignatureChecker =
            new BLSSignatureChecker(ISlashingRegistryCoordinator(address(registryCoordinatorMimic)));
        console.log("BLSSignatureChecker deployed at:", address(blsSignatureChecker));

        SignatureConsumer signatureConsumer = new SignatureConsumer(address(blsSignatureChecker));
        console.log("SignatureConsumer deployed at:", address(signatureConsumer));

        string memory json =
            vm.serializeAddress("object key", "registryCoordinatorMimic", address(registryCoordinatorMimic));
        json = vm.serializeAddress("object key", "blsSignatureChecker", address(blsSignatureChecker));
        json = vm.serializeAddress("object key", "signatureConsumer", address(signatureConsumer));
        vm.writeFile(outPath, json);
        console.log("Deployment info written to", outPath);

        vm.stopBroadcast();
    }
}
