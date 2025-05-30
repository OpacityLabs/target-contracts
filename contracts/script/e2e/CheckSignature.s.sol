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

    struct Operator {
        address operator;
        uint256 blsPrivateKey;
        BN254.G1Point pk1;
        BN254.G2Point pk2;
    }

    // does all these weird structs to avoid stack too deep errors
    struct ContractAddresses {
        address registryCoordinator;
        address stateRetriever;
        address signatureConsumer;
    }

    struct OperatorData {
        Operator operator1;
        Operator operator2;
        Operator operator3;
        address[] operatorAddresses;
    }

    struct SignatureData {
        bytes32 messageHash;
        BN254.G1Point s1;
        BN254.G1Point s2;
        BN254.G1Point s3;
        BN254.G1Point sigma;
    }

    struct ScriptConfig {
        string operatorKeysDir;
        uint32 blockNumber;
    }

    // TODO: does not support dynamic operator counts
    function run() external {
        ContractAddresses memory contracts = ContractAddresses({
            registryCoordinator: vm.envAddress("REGISTRY_COORDINATOR_ADDRESS"),
            stateRetriever: vm.envAddress("STATE_RETRIEVER_ADDRESS"),
            signatureConsumer: vm.envAddress("SIGNATURE_CONSUMER_ADDRESS")
        });

        ScriptConfig memory config = ScriptConfig({
            operatorKeysDir: vm.envString("OPERATOR_KEYS_DIR"),
            blockNumber: 0 // Will be set later
        });

        // Read operator keys from files
        OperatorData memory operatorData;
        operatorData.operator1 = _readOperatorFromFile("testacc1", config.operatorKeysDir);
        operatorData.operator2 = _readOperatorFromFile("testacc2", config.operatorKeysDir);
        operatorData.operator3 = _readOperatorFromFile("testacc3", config.operatorKeysDir);

        // Create a message to sign
        SignatureData memory sigData;
        sigData.messageHash = bytes32(uint256(0x1234));

        // Sign the message with BLS
        sigData.s1 = _signBLSMessage(operatorData.operator1, sigData.messageHash);
        sigData.s2 = _signBLSMessage(operatorData.operator2, sigData.messageHash);
        sigData.s3 = _signBLSMessage(operatorData.operator3, sigData.messageHash);

        sigData.sigma = sigData.s1.plus(sigData.s2).plus(sigData.s3);

        vm.createSelectFork(vm.envString("L1_RPC_URL"));
        
        operatorData.operatorAddresses = new address[](3);
        operatorData.operatorAddresses[0] = operatorData.operator1.operator;
        operatorData.operatorAddresses[1] = operatorData.operator2.operator;
        operatorData.operatorAddresses[2] = operatorData.operator3.operator;

        config.blockNumber = uint32(block.number - 1);

        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory nonSignerStakesAndSignature = 
            _getNonSignerStakesAndSignature(contracts, sigData, operatorData, config);

        _verifySignatureOnL2(contracts, sigData, config, nonSignerStakesAndSignature);
    }

    function _getNonSignerStakesAndSignature(
        ContractAddresses memory contracts,
        SignatureData memory sigData,
        OperatorData memory operatorData,
        ScriptConfig memory config
    ) internal returns (IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory) {
        return BLSSigCheckOperatorStateRetriever(contracts.stateRetriever).getNonSignerStakesAndSignature(
            ISlashingRegistryCoordinator(contracts.registryCoordinator),
            hex"00",
            sigData.sigma,
            operatorData.operatorAddresses,
            config.blockNumber
        );
    }

    function _verifySignatureOnL2(
        ContractAddresses memory contracts,
        SignatureData memory sigData,
        ScriptConfig memory config,
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
    ) internal {
        vm.createSelectFork(vm.envString("L2_RPC_URL"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        
        IBLSSignatureCheckerTypes.QuorumStakeTotals memory quorumStakeTotals = 
            SignatureConsumer(contracts.signatureConsumer).verifySignatureAndEmit(
                sigData.messageHash,
                hex"00",
                config.blockNumber,
                nonSignerStakesAndSignature
            );
        
        vm.stopBroadcast();
        
        console.log("Signature check passed");
        console.log("Quorum stake totals:");
        console.log("Signed stake for quorum 0:", quorumStakeTotals.signedStakeForQuorum[0]);
        console.log("Total stake for quorum 0:", quorumStakeTotals.totalStakeForQuorum[0]);
    }

    function _readOperatorFromFile(string memory operatorName, string memory operatorKeysDir) internal view returns (Operator memory) {
        uint256 blsPrivateKey;
        BN254.G1Point memory pk1;
        BN254.G2Point memory pk2;
        address operatorAddress;

        // Read private BLS key in its own scope
        {
            string memory privateKeyPath = string.concat(operatorKeysDir, operatorName, ".private.bls.key.json");
            string memory privateKeyJson = vm.readFile(privateKeyPath);
            blsPrivateKey = privateKeyJson.readUint(".privateKey");
        }

        // Read and parse public BLS key in its own scope
        {
            string memory publicKeyPath = string.concat(operatorKeysDir, operatorName, ".bls.key.json");
            string memory publicKeyJson = vm.readFile(publicKeyPath);
            string memory pubKeyStr = publicKeyJson.readString(".pubKey");

            // Parse the public key string to get G1 point
            // The format is "E([x,y])" where x,y are the coordinates in decimal
            uint256 commaIndex = bytes(pubKeyStr).indexOf(bytes1(uint8(44)));
            uint256 x = pubKeyStr.parseUint(3, commaIndex);
            uint256 y = pubKeyStr.parseUint(commaIndex + 1, bytes(pubKeyStr).length - 2);

            pk1 = BN254.G1Point(x, y);
        }
        
        // Generate G2 point from private key in its own scope
        {
            BN254.G2Point memory g2 = BN254.generatorG2();
            (pk2.X[1], pk2.X[0], pk2.Y[1], pk2.Y[0]) = BN256G2.ECTwistMul(blsPrivateKey, g2.X[1], g2.X[0], g2.Y[1], g2.Y[0]);
        }

        // Read operator address from ECDSA key file in its own scope
        {
            string memory ecdsaKeyPath = string.concat(operatorKeysDir, operatorName, ".ecdsa.key.json");
            string memory ecdsaKeyJson = vm.readFile(ecdsaKeyPath);
            operatorAddress = ecdsaKeyJson.readAddress(".address");
        }

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
