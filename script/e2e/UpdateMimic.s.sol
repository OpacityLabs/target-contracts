// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script, console} from "forge-std/Script.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RegistryCoordinatorMimic} from "../../src/RegistryCoordinatorMimic.sol";
import {SP1Helios} from "@sp1-helios/SP1Helios.sol";
import {BLSSignatureChecker} from "@eigenlayer-middleware/BLSSignatureChecker.sol";
import {IMiddlewareShim, IMiddlewareShimTypes} from "../../src/interfaces/IMiddlewareShim.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {SP1HeliosMock} from "./SP1HeliosMock.sol";


contract UpdateMimic is Script {
    struct Proof {
        uint256 middlewareBlockNumber;
        uint256 slotNumber;
        bytes32 storageHash;
        bytes32 executionStateRoot;
        bytes[] storageProof;
        bytes[] accountProof;
    }

    function setUp() public {}

    function run() public {
        string memory proofFile = vm.envString("PROOF_FILE");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address registryCoordinatorMimic = vm.envAddress("REGISTRY_COORDINATOR_MIMIC_ADDRESS");
        address blsSignatureChecker = vm.envAddress("BLS_SIGNATURE_CHECKER_ADDRESS");
        address middlewareShimAddress = vm.envAddress("MIDDLEWARE_SHIM_ADDRESS");
        bool isMockSP1Helios = vm.envBool("IS_SP1HELIOS_MOCK");

        Proof memory proof = _constructProof(proofFile);

        vm.createSelectFork(vm.envString("L1_RPC_URL"));
        IMiddlewareShim middlewareShim = IMiddlewareShim(middlewareShimAddress);
        IMiddlewareShim.MiddlewareData memory middlewareData = middlewareShim.getMiddlewareData(middlewareShim.registryCoordinator(), uint32(proof.middlewareBlockNumber));

        vm.createSelectFork(vm.envString("L2_RPC_URL"));
        vm.startBroadcast(deployerPrivateKey);

        if (isMockSP1Helios) {
            SP1HeliosMock sp1helios = SP1HeliosMock(address(RegistryCoordinatorMimic(registryCoordinatorMimic).LITE_CLIENT()));
            sp1helios.setExecutionStateRoot(proof.slotNumber, proof.executionStateRoot);
        }

        // TODO: run proof verification in script before calling update state

        RegistryCoordinatorMimic.StateUpdateProof memory stateUpdateProof = RegistryCoordinatorMimic.StateUpdateProof({
            slotNumber: proof.slotNumber,
            storageHash: proof.storageHash,
            storageProof: proof.storageProof,
            accountProof: proof.accountProof
        });
        RegistryCoordinatorMimic(registryCoordinatorMimic).updateState(middlewareData, abi.encode(stateUpdateProof));

        vm.stopBroadcast();
    }

    function _constructProof(string memory proofFile) internal view returns (Proof memory proof) {
        string memory json = vm.readFile(proofFile);
        proof.middlewareBlockNumber = stdJson.readUint(json, ".middlewareBlockNumber");
        proof.slotNumber = stdJson.readUint(json, ".slotNumber");
        proof.storageHash = stdJson.readBytes32(json, ".storageHash");
        proof.executionStateRoot = stdJson.readBytes32(json, ".executionStateRoot");
        proof.storageProof = stdJson.readBytesArray(json, ".storageProof");
        proof.accountProof = stdJson.readBytesArray(json, ".accountProof");
    }
}