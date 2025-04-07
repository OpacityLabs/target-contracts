// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IRegistryCoordinator, ISignatureUtilsMixinTypes} from "@eigenlayer-middleware/interfaces/IRegistryCoordinator.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
// NOTICE: importing ISignatureUtilsMixin through this file so won't have to add eigenlayer-contracts as a dependency
import {IBLSApkRegistryTypes} from "@eigenlayer-middleware/interfaces/IBLSApkRegistry.sol";
import {IServiceManager} from "@eigenlayer-middleware/interfaces/IServiceManager.sol";
import {BN254} from "@eigenlayer-middleware/libraries/BN254.sol";
import {Strings} from "@openzeppelin-utils/Strings.sol";
import {SignatureChecker} from "@openzeppelin-utils/cryptography/SignatureChecker.sol";

import {BN256G2} from "src/libraries/BN256G2.sol";

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

// Works with M2 eignelayer version in order to be able to fork EigenDA and not do a full deployment.
// This means that migrating to M3 requires migrating the operator registration flow to go throught the new AllocationManager.

// April 7, 2025 LOG:
// I became aware of OperatorLib only towards the end of the day.
// Regardless, I could not get `registerOperatorToAVS_M2` to compile because of stack too deep errors (as far as I aware it's not even tested in Eigen's codebase).
//
// Current issue: AVSDirectory computes a different digest than the one computed locally. Need to investigate.

// Uses `opacity-local` for reference. See:
// https://github.com/OpacityLabs/opacity-local/blob/13e3af8c01e10c3a5a79049b44565b6053b56952/docker/eigenlayer/register.sh
// https://github.com/OpacityLabs/opacity-local/blob/13e3af8c01e10c3a5a79049b44565b6053b56952/docker/eigenlayer/eject.sh
contract EigenDAForkTest is Test {
    address constant DELEGATION_MANAGER_ADDRESS_HOLESKY = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address constant STRATEGY_MANAGER_ADDRESS_HOLESKY = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
    address constant REGISTRY_COORDINATOR_ADDRESS_HOLESKY = 0x3e43AA225b5cB026C5E8a53f62572b10D526a50B;
    address constant LST_CONTRACT_ADDRESS_HOLESKY = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address constant LST_STRATEGY_ADDRESS_HOLESKY = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;
    address constant EIGENDA_AVS_ADDRESS_HOLESKY = 0xD4A7E1Bd8015057293f0D0A557088c286942e84b;
    // I don't really like having these signatures written as static strings
    string constant DEPOSIT_FUNCTION_SIGNATURE = "depositIntoStrategy(address,address,uint256)";
    string constant APPROVE_FUNCTION_SIGNATURE = "approve(address,uint256)";
    string constant REGISTER_FUNCTION_SIGNATURE = "registerAsOperator(address,uint32,string)";

    struct Operator {
        address operator;
        uint256 ecdsaPrivateKey;
        uint256 blsPrivateKey;
        BN254.G1Point pk1;
        BN254.G2Point pk2;
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

        Operator memory operator0 =_createOperator(0);
        _registerOperator(registryCoordinator, EIGENDA_AVS_ADDRESS_HOLESKY, operator0);
    }

    function _createOperator(uint256 seed) internal returns(Operator memory) {
        string memory operatorName = string.concat("Operator ", Strings.toString(seed));
        StdCheats.Account memory account = makeAccount(operatorName);
        address operatorAddress = account.addr;
        uint256 ecdsaPrivateKey = account.key;
        (uint256 blsPrivateKey, BN254.G1Point memory pk1, BN254.G2Point memory pk2) = _generateBLSKeys(ecdsaPrivateKey);

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
            operator: operatorAddress,
            ecdsaPrivateKey: ecdsaPrivateKey,
            blsPrivateKey: blsPrivateKey,
            pk1: pk1,
            pk2: pk2
        });
    }

    function _registerOperator(ISlashingRegistryCoordinator registryCoordinator, address avs, Operator memory operator) internal {
        bytes memory quorumNumbers = hex"00";
        string memory socket = "foo.bar";

        BN254.G1Point memory h = registryCoordinator.pubkeyRegistrationMessageHash(operator.operator);
        BN254.G1Point memory sig = BN254.scalar_mul(h, operator.blsPrivateKey);

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params = IBLSApkRegistryTypes.PubkeyRegistrationParams({
            pubkeyG1: operator.pk1,
            pubkeyG2: operator.pk2,
            pubkeyRegistrationSignature: sig
        });

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature = _newOperatorRegistrationSignature(operator.ecdsaPrivateKey, avs, bytes32(0), block.timestamp + 1 days);

        vm.prank(operator.operator);
        IRegistryCoordinator(address(registryCoordinator)).registerOperator(quorumNumbers, socket, params, operatorSignature);
    }

    function _generateBLSKeys(uint256 seed) internal view returns(uint256, BN254.G1Point memory, BN254.G2Point memory) {
        uint256 sk = uint256(keccak256(abi.encodePacked(seed)));
        BN254.G1Point memory pk1 = BN254.scalar_mul(BN254.generatorG1(), sk);
        BN254.G2Point memory g2 = BN254.generatorG2();
        BN254.G2Point memory pk2;
        (pk2.X[1], pk2.X[0], pk2.Y[1], pk2.Y[0]) = BN256G2.ECTwistMul(sk, g2.X[1], g2.X[0], g2.Y[1], g2.Y[0]);

        // ensure correct encoding by checking pairing
        bool result = BN254.pairing(pk1, BN254.negGeneratorG2(), BN254.generatorG1(), pk2);
        require(result, "Pairing check on BLS key generation failed");

        return (sk, pk1, pk2);
    }

    // copied from AVSDirectoryUnit.t.sol
    function _newOperatorRegistrationSignature(uint operatorSk, address avs, bytes32 salt, uint expiry)
        internal
        view
        returns (ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory)
    {
        // Holesky AVS directory (M2)
        address avsDirectory = 0x055733000064333CaDDbC92763c58BF0192fFeBf;
        string memory functionSignature = "calculateOperatorAVSRegistrationDigestHash(address,address,bytes32,uint256)";

        (bool success, bytes memory data) = avsDirectory.staticcall(abi.encodeWithSignature(functionSignature, vm.addr(operatorSk), avs, salt, expiry));
        require(success, "calculateOperatorAVSRegistrationDigestHash call failed");
        bytes32 digest = abi.decode(data, (bytes32));
        // console.log("digest");
        // console.logBytes32(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorSk, digest);
        return ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({signature: abi.encodePacked(r, s, v), salt: salt, expiry: expiry});
    }
}
