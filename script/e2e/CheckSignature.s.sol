// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script, console} from "forge-std/Script.sol";
import {BN254} from "@eigenlayer-middleware/libraries/BN254.sol";
import {BN256G2} from "../../src/libraries/BN256G2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BLSSigCheckOperatorStateRetriever} from "@eigenlayer-middleware/unaudited/BLSSigCheckOperatorStateRetriever.sol";
import {Bytes} from "@openzeppelin-utils/Bytes.sol";
import {Strings} from "@openzeppelin-utils/Strings.sol";
import {IBLSSignatureCheckerTypes} from "@eigenlayer-middleware/interfaces/IBLSSignatureChecker.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {SignatureConsumer} from "./contracts/SignatureConsumer.sol";

contract CheckSignature is Script {
    using BN254 for BN254.G1Point;
    using stdJson for string;
    using Bytes for bytes;
    using Strings for string;

    // TODO: replace with Operator struct I have somewhere else 
    struct Operator {
        address operator;
        uint256 blsPrivateKey;
        BN254.G1Point pk1;
        BN254.G2Point pk2;
    }

    // TODO: move to env
    string constant OPERATOR_KEYS_DIR = "test/e2e/docker/.nodes/operator_keys/";

    // TODO: does not support dynamic operator counts
    function run() external {
        address registryCoordinator = vm.envAddress("REGISTRY_COORDINATOR_ADDRESS");
        address stateRetriever = vm.envAddress("STATE_RETRIEVER_ADDRESS");
        address signatureConsumer = vm.envAddress("SIGNATURE_CONSUMER_ADDRESS");

        // Read operator keys from files
        Operator memory operator1 = _readOperatorFromFile("testacc1");
        Operator memory operator2 = _readOperatorFromFile("testacc2");
        Operator memory operator3 = _readOperatorFromFile("testacc3");

        // Create a message to sign
        bytes32 messageHash = bytes32(uint256(0x1234));

        // Sign the message with BLS
        BN254.G1Point memory s1 = _signBLSMessage(operator1, messageHash);
        BN254.G1Point memory s2 = _signBLSMessage(operator2, messageHash);
        BN254.G1Point memory s3 = _signBLSMessage(operator3, messageHash);

        BN254.G1Point memory sigma = s1.plus(s2).plus(s3);

        vm.createSelectFork(vm.envString("L1_RPC_URL"));
        address[] memory operators = new address[](3);
        operators[0] = operator1.operator;
        operators[1] = operator2.operator;
        operators[2] = operator3.operator;

        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory nonSignerStakesAndSignature = BLSSigCheckOperatorStateRetriever(stateRetriever).getNonSignerStakesAndSignature(
            ISlashingRegistryCoordinator(registryCoordinator),
            hex"00",
            sigma,
            operators,
            uint32(block.number - 1)
        );

        vm.createSelectFork(vm.envString("L2_RPC_URL"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        IBLSSignatureCheckerTypes.QuorumStakeTotals memory quorumStakeTotals = SignatureConsumer(signatureConsumer).verifySignatureAndEmit(
            messageHash,
            hex"00",
            uint32(block.number - 1),
            nonSignerStakesAndSignature
        );
        vm.stopBroadcast();
        console.log("Signature check passed");
        console.log("Quorum stake totals:");
        console.log("Signed stake for quorum 0:", quorumStakeTotals.signedStakeForQuorum[0]);
        console.log("Total stake for quorum 0:", quorumStakeTotals.totalStakeForQuorum[0]);
    }

    function _readOperatorFromFile(string memory operatorName) internal view returns (Operator memory) {
        // Read private BLS key
        string memory privateKeyPath = string.concat(OPERATOR_KEYS_DIR, operatorName, ".private.bls.key.json");
        string memory privateKeyJson = vm.readFile(privateKeyPath);
        uint256 blsPrivateKey = privateKeyJson.readUint(".privateKey");

        // Read public BLS key
        string memory publicKeyPath = string.concat(OPERATOR_KEYS_DIR, operatorName, ".bls.key.json");
        string memory publicKeyJson = vm.readFile(publicKeyPath);
        string memory pubKeyStr = publicKeyJson.readString(".pubKey");

        // Parse the public key string to get G1 point
        // The format is "E([x,y])" where x,y are the coordinates in decimal
        uint256 commaIndex = bytes(pubKeyStr).indexOf(bytes1(uint8(44)));
        uint256 x = pubKeyStr.parseUint(3, commaIndex);
        uint256 y = pubKeyStr.parseUint(commaIndex + 1, bytes(pubKeyStr).length - 2);

        BN254.G1Point memory pk1 = BN254.G1Point(x, y);
        
        // Generate G2 point from private key
        BN254.G2Point memory g2 = BN254.generatorG2();
        BN254.G2Point memory pk2;
        (pk2.X[1], pk2.X[0], pk2.Y[1], pk2.Y[0]) = BN256G2.ECTwistMul(blsPrivateKey, g2.X[1], g2.X[0], g2.Y[1], g2.Y[0]);

        // Read operator address from ECDSA key file
        string memory ecdsaKeyPath = string.concat(OPERATOR_KEYS_DIR, operatorName, ".ecdsa.key.json");
        string memory ecdsaKeyJson = vm.readFile(ecdsaKeyPath);
        address operatorAddress = ecdsaKeyJson.readAddress(".address");

        return Operator({
            operator: operatorAddress,
            blsPrivateKey: blsPrivateKey,
            pk1: pk1,
            pk2: pk2
        });
    }

    function _signBLSMessage(Operator memory operator, bytes32 messageHash)
        internal
        view
        returns (BN254.G1Point memory)
    {
        BN254.G1Point memory h = BN254.hashToG1(messageHash);
        BN254.G1Point memory sig = BN254.scalar_mul(h, operator.blsPrivateKey);
        return sig;
    }
}
