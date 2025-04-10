// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IRegistryCoordinator, ISignatureUtilsMixinTypes} from "@eigenlayer-middleware/interfaces/IRegistryCoordinator.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistryTypes} from "@eigenlayer-middleware/interfaces/IBLSApkRegistry.sol";
import {IServiceManager} from "@eigenlayer-middleware/interfaces/IServiceManager.sol";
import {BN254} from "@eigenlayer-middleware/libraries/BN254.sol";
import {Strings} from "@openzeppelin-utils/Strings.sol";
import {SignatureChecker} from "@openzeppelin-utils/cryptography/SignatureChecker.sol";
// import {OperatorLib} from "@eigenlayer-middleware-test/utils/OperatorLib.sol";

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

interface IAVSDirectory {
    /**
     *  @notice Calculates the digest hash to be signed by an operator to register with an AVS.
     *
     *  @param operator The account registering as an operator.
     *  @param avs The AVS the operator is registering with.
     *  @param salt A unique and single-use value associated with the approver's signature.
     *  @param expiry The time after which the approver's signature becomes invalid.
     */
    function calculateOperatorAVSRegistrationDigestHash(
        address operator,
        address avs,
        bytes32 salt,
        uint256 expiry
    ) external view returns (bytes32);
}

// Uses `opacity-local` for reference. See:
// https://github.com/OpacityLabs/opacity-local/blob/13e3af8c01e10c3a5a79049b44565b6053b56952/docker/eigenlayer/register.sh
// https://github.com/OpacityLabs/opacity-local/blob/13e3af8c01e10c3a5a79049b44565b6053b56952/docker/eigenlayer/eject.sh
contract EigenDAForkTest is Test {
    using BN254 for BN254.G1Point;

    // Core contracts
    address constant DELEGATION_MANAGER_ADDRESS_HOLESKY = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address constant AVS_DIRECTORY_ADDRESS_HOLESKY = 0x055733000064333CaDDbC92763c58BF0192fFeBf;
    address constant STRATEGY_MANAGER_ADDRESS_HOLESKY = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
    // LST contracts
    address constant LST_CONTRACT_ADDRESS_HOLESKY = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address constant LST_STRATEGY_ADDRESS_HOLESKY = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;
    // EigenDA middleware contracts
    // address constant REGISTRY_COORDINATOR_ADDRESS_HOLESKY = 0x53012C69A189cfA2D9d29eb6F19B32e0A2EA3490;
    // address constant EIGENDA_AVS_ADDRESS_HOLESKY = 0xD4A7E1Bd8015057293f0D0A557088c286942e84b;

    address constant OPACITY_REGISTRY_COORDINATOR_ADDRESS_HOLESKY = 0x3e43AA225b5cB026C5E8a53f62572b10D526a50B;
    address constant OPACTIY_AVS_ADDRESS_HOLESKY = 0xbfc5d26C6eEb46475eB3960F5373edC5341eE535;

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
        ISlashingRegistryCoordinator registryCoordinator = ISlashingRegistryCoordinator(OPACITY_REGISTRY_COORDINATOR_ADDRESS_HOLESKY);

        // eject all operators in quorum 0 in order to register new ones
        address ejector = registryCoordinator.ejector();
        bytes32[] memory operatorIds = registryCoordinator.indexRegistry().getOperatorListAtBlockNumber(0, uint32(3633000));
        for (uint256 i = 0; i < operatorIds.length; i++) {
            address operator = registryCoordinator.getOperatorFromId(operatorIds[i]);
            vm.prank(ejector);
            registryCoordinator.ejectOperator(operator, hex"00");
        }

        Operator memory operator0 =_createOperator(0);

        // OperatorLib.Operator memory operator0 = OperatorLib.createOperator("Operator 0");
        // _setupOperatorStake(operator0, "Operator 0");
        // // bytes32 salt = keccak256(abi.encodePacked(block.timestamp, operator.key.addr));
        bytes32 salt = 0x0;
        uint256 expiry = block.timestamp + 1 hours;

        bytes32 operatorRegistrationDigestHash = IAVSDirectory(AVS_DIRECTORY_ADDRESS_HOLESKY)
            .calculateOperatorAVSRegistrationDigestHash(operator0.operator, OPACTIY_AVS_ADDRESS_HOLESKY, salt, expiry);

            // signableDigest: calculateOperatorAVSRegistrationDigestHash({
            //     operator: operator,
            //     avs: msg.sender,
            //     salt: operatorSignature.salt,
            //     expiry: operatorSignature.expiry
            // }),

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator0.ecdsaPrivateKey, operatorRegistrationDigestHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        BN254.G1Point memory messagePoint =
            registryCoordinator.pubkeyRegistrationMessageHash(operator0.operator);
        
        // 3438439655704084527071467086324552379130330660475024697494246900319381673110
        // 17877859171884945105759362226681688423805256664784025745013889966226019757148
        console.log("messagePoint X", messagePoint.X);
        console.log("messagePoint Y", messagePoint.Y);

        // Sign by multiplying the hashed message point with the private key
        BN254.G1Point memory blsSig = messagePoint.scalar_mul(operator0.blsPrivateKey);

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params = IBLSApkRegistryTypes
            .PubkeyRegistrationParams({
            pubkeyG1: operator0.pk1,
            pubkeyG2: operator0.pk2,
            pubkeyRegistrationSignature: blsSig
        });

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature =
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({
            signature: signature,
            salt: salt,
            expiry: expiry
        });
        
        vm.prank(operator0.operator);
        IRegistryCoordinator(address(registryCoordinator)).registerOperator(hex"00", "foo.bar", params, operatorSignature);
    }

    // function _setupOperatorStake(OperatorLib.Operator memory operator, string memory name) internal {
    //     address addr = operator.key.addr;
    //     hoax(addr, 7 ether);
    //     (bool success, ) = LST_CONTRACT_ADDRESS_HOLESKY.call{value: 7 ether}("");
    //     require(success, string.concat("Mint failed for ", name));

    //     // TODO: I think will replace these calls with partial interfaces, I hate this syntax 
    //     // approve 7 stETH to strategy
    //     vm.prank(addr);
    //     (success, ) = LST_CONTRACT_ADDRESS_HOLESKY.call(abi.encodeWithSignature(APPROVE_FUNCTION_SIGNATURE, STRATEGY_MANAGER_ADDRESS_HOLESKY, 7 ether));
    //     require(success, string.concat("Approve failed for ", name));

    //     // deposit 7 stETH to strategy
    //     vm.prank(addr);
    //     (success, ) = STRATEGY_MANAGER_ADDRESS_HOLESKY.call(abi.encodeWithSignature(DEPOSIT_FUNCTION_SIGNATURE, LST_STRATEGY_ADDRESS_HOLESKY, LST_CONTRACT_ADDRESS_HOLESKY, 7 ether));
    //     require(success, string.concat("Deposit failed for ", name));

    //     // register operator in delegation manager
    //     vm.prank(addr);
    //     (success, ) = DELEGATION_MANAGER_ADDRESS_HOLESKY.call(abi.encodeWithSignature(REGISTER_FUNCTION_SIGNATURE, address(0), uint32(0), "foo.bar"));
    //     require(success, string.concat("Register failed for ", name));
    // }

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
