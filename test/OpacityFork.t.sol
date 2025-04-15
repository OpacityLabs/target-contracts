// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
// Importing ISignatureUtilsMixinTypes from IRegistryCoordinator.sol in order to not depend on eigenlayer-core
import {
    IRegistryCoordinator, ISignatureUtilsMixinTypes
} from "@eigenlayer-middleware/interfaces/IRegistryCoordinator.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistry, IBLSApkRegistryTypes} from "@eigenlayer-middleware/interfaces/IBLSApkRegistry.sol";
import {IBLSSignatureCheckerTypes} from "@eigenlayer-middleware/interfaces/IBLSSignatureChecker.sol";
import {BLSSignatureChecker} from "@eigenlayer-middleware/BLSSignatureChecker.sol";
import {OperatorStateRetriever} from "@eigenlayer-middleware/OperatorStateRetriever.sol";
import {BN254} from "@eigenlayer-middleware/libraries/BN254.sol";
import {Strings} from "@openzeppelin-utils/Strings.sol";

import {BN256G2} from "src/libraries/BN256G2.sol";
import {MiddlewareShim} from "src/MiddlewareShim.sol";
import {RegistryCoordinatorMimicHarness} from "test/harness/RegistryCoordinatorMimicHarness.sol";
import {SP1Helios} from "@sp1-helios/SP1Helios.sol";
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

// Works with M2 eignelayer version in order to be able to fork Opacity and not do a full deployment.
// This means that migrating to M3 requires migrating the operator registration flow to go throught the new AllocationManager.

// Uses `opacity-local` for reference. See:
// https://github.com/OpacityLabs/opacity-local/blob/13e3af8c01e10c3a5a79049b44565b6053b56952/docker/eigenlayer/register.sh
// https://github.com/OpacityLabs/opacity-local/blob/13e3af8c01e10c3a5a79049b44565b6053b56952/docker/eigenlayer/eject.sh
contract OpacityForkTest is Test {
    using BN254 for BN254.G1Point;

    // Core contracts
    address constant DELEGATION_MANAGER_ADDRESS_HOLESKY = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address constant AVS_DIRECTORY_ADDRESS_HOLESKY = 0x055733000064333CaDDbC92763c58BF0192fFeBf;
    address constant STRATEGY_MANAGER_ADDRESS_HOLESKY = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
    // LST contracts
    address constant LST_CONTRACT_ADDRESS_HOLESKY = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address constant LST_STRATEGY_ADDRESS_HOLESKY = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;
    // Opacity middleware contracts
    address constant OPACITY_REGISTRY_COORDINATOR_ADDRESS_HOLESKY = 0x3e43AA225b5cB026C5E8a53f62572b10D526a50B;
    address constant OPACTIY_AVS_ADDRESS_HOLESKY = 0xbfc5d26C6eEb46475eB3960F5373edC5341eE535;

    address registryCoordinatorMimicOwner = makeAddr("registryCoordinatorMimicOwner");

    // TODO(chore): I don't really like having these signatures written as static strings
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

    function setUp() public {}

    function test_fullFlow_mockProofVerification() public {
        // setup
        vm.createSelectFork("holesky");
        ISlashingRegistryCoordinator registryCoordinator =
            ISlashingRegistryCoordinator(OPACITY_REGISTRY_COORDINATOR_ADDRESS_HOLESKY);

        // eject all operators in quorum 0 in order to register new ones
        // stack-too-deep
        {
            address ejector = registryCoordinator.ejector();
            bytes32[] memory operatorIds =
                registryCoordinator.indexRegistry().getOperatorListAtBlockNumber(0, uint32(3633000));
            for (uint256 i = 0; i < operatorIds.length; i++) {
                address operator = registryCoordinator.getOperatorFromId(operatorIds[i]);
                vm.prank(ejector);
                registryCoordinator.ejectOperator(operator, hex"00");
            }
        }

        Operator memory operator0 = _createOperator(0);
        _registerOperator(registryCoordinator, OPACTIY_AVS_ADDRESS_HOLESKY, operator0);
        Operator memory operator1 = _createOperator(1);
        _registerOperator(registryCoordinator, OPACTIY_AVS_ADDRESS_HOLESKY, operator1);
        Operator memory operator2 = _createOperator(2);
        _registerOperator(registryCoordinator, OPACTIY_AVS_ADDRESS_HOLESKY, operator2);
        // forward the blocknumber by 1 so we can reference a block where the operators are registered
        vm.roll(block.number + 1);
        uint32 referenceBlockNumber = uint32(block.number - 1);

        // 1. Create arbitrary message to be signed with BLS, and sign with signer set
        // 2. Retreive checkSignatures params through operator state retriever, and verify them in the BLSSignatureChecker
        // 3. Deploy middleware shim, read the middleware data, and update its data hash
        // 4. Deploy registry coordinator mimic, and call updateState with the middleware data (proof verification is WIP)
        // 5. Deploy another BLSSignatureChecker, this time with the registry coordinator mimic
        // 6. Call checkSignatures with the same original message

        // dummy message
        bytes32 messageHash = bytes32(uint256(0x1234));
        BN254.G1Point memory sigma;
        // stack-too-deep
        {
            BN254.G1Point memory sig1 = _signBLSMessage(operator1, messageHash);
            BN254.G1Point memory sig2 = _signBLSMessage(operator2, messageHash);
            sigma = sigma.plus(sig1);
            sigma = sigma.plus(sig2);
        }

        // stack-too-deep
        {
            IBLSApkRegistry blsApkRegistry = registryCoordinator.blsApkRegistry();
            vm.mockCall(
                address(blsApkRegistry),
                abi.encodeCall(IBLSApkRegistry.getOperatorPubkeyG2, (operator0.operator)),
                abi.encode(operator0.pk2)
            );
            vm.mockCall(
                address(blsApkRegistry),
                abi.encodeCall(IBLSApkRegistry.getOperatorPubkeyG2, (operator1.operator)),
                abi.encode(operator1.pk2)
            );
            vm.mockCall(
                address(blsApkRegistry),
                abi.encodeCall(IBLSApkRegistry.getOperatorPubkeyG2, (operator2.operator)),
                abi.encode(operator2.pk2)
            );
        }

        // Deploy operator state retriever
        OperatorStateRetriever retriever = new OperatorStateRetriever();
        // Deploy bls signature checker
        BLSSignatureChecker checker = new BLSSignatureChecker(registryCoordinator);

        // Compute the non-signer stakes and signature
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory nonSignerStakesAndSignature;
        // stack-too-deep
        {
            address[] memory signers = new address[](2);
            signers[0] = operator1.operator;
            signers[1] = operator2.operator;
            nonSignerStakesAndSignature = retriever.getNonSignerStakesAndSignature(
                registryCoordinator, hex"00", sigma, signers, referenceBlockNumber
            );
        }

        // Check that the signature passes
        (IBLSSignatureCheckerTypes.QuorumStakeTotals memory quorumStakeTotals,) =
            checker.checkSignatures(messageHash, hex"00", referenceBlockNumber, nonSignerStakesAndSignature);
        console.log("quorumStakeTotals");
        console.log(quorumStakeTotals.signedStakeForQuorum[0]);
        console.log(quorumStakeTotals.totalStakeForQuorum[0]);

        // Deploy middleware shim
        MiddlewareShim shim = new MiddlewareShim(registryCoordinator);
        shim.updateMiddlewareDataHash();
        console.log("middlewareDataHash");
        console.logBytes32(shim.middlewareDataHash());
        MiddlewareShim.MiddlewareData memory middlewareData =
            shim.getMiddlewareData(registryCoordinator, referenceBlockNumber);

        // Deploy registry coordinator mimic
        vm.prank(registryCoordinatorMimicOwner);
        RegistryCoordinatorMimicHarness mimic =
            new RegistryCoordinatorMimicHarness(SP1Helios(makeAddr("SP1Helios")), address(shim));
        mimic.harness_setMockVerifyProof(true);
        vm.prank(registryCoordinatorMimicOwner);
        mimic.updateState(middlewareData, "mock proof");

        // Deploy another BLSSignatureChecker
        BLSSignatureChecker checker2 = new BLSSignatureChecker(ISlashingRegistryCoordinator(address(mimic)));
        (IBLSSignatureCheckerTypes.QuorumStakeTotals memory quorumStakeTotals2,) =
            checker2.checkSignatures(messageHash, hex"00", referenceBlockNumber, nonSignerStakesAndSignature);
        console.log("quorumStakeTotals2");
        console.log(quorumStakeTotals2.signedStakeForQuorum[0]);
        console.log(quorumStakeTotals2.totalStakeForQuorum[0]);

        assertEq(quorumStakeTotals.signedStakeForQuorum.length, 1, "Expected 1 quorum");
        assertEq(quorumStakeTotals.totalStakeForQuorum.length, 1, "Expected 1 quorum");
        assertEq(
            quorumStakeTotals.signedStakeForQuorum.length,
            quorumStakeTotals2.signedStakeForQuorum.length,
            "Quorum signed stake length mismatch"
        );
        assertEq(
            quorumStakeTotals.totalStakeForQuorum.length,
            quorumStakeTotals2.totalStakeForQuorum.length,
            "Quorum total stake length mismatch"
        );
        assertEq(
            quorumStakeTotals.signedStakeForQuorum[0],
            quorumStakeTotals2.signedStakeForQuorum[0],
            "Quorum signed stake mismatch"
        );
        assertEq(
            quorumStakeTotals.totalStakeForQuorum[0],
            quorumStakeTotals2.totalStakeForQuorum[0],
            "Quorum total stake mismatch"
        );
    }

    function _createOperator(uint256 seed) internal returns (Operator memory) {
        string memory operatorName = string.concat("Operator ", Strings.toString(seed));
        StdCheats.Account memory account = makeAccount(operatorName);
        address operatorAddress = account.addr;
        uint256 ecdsaPrivateKey = account.key;
        (uint256 blsPrivateKey, BN254.G1Point memory pk1, BN254.G2Point memory pk2) = _generateBLSKeys(ecdsaPrivateKey);

        // mint 7 stETH to operator
        hoax(operatorAddress, 7 ether);
        (bool success,) = LST_CONTRACT_ADDRESS_HOLESKY.call{value: 7 ether}("");
        require(success, string.concat("Mint failed for ", operatorName));

        // approve 7 stETH to strategy
        vm.prank(operatorAddress);
        (success,) = LST_CONTRACT_ADDRESS_HOLESKY.call(
            abi.encodeWithSignature(APPROVE_FUNCTION_SIGNATURE, STRATEGY_MANAGER_ADDRESS_HOLESKY, 7 ether)
        );
        require(success, string.concat("Approve failed for ", operatorName));

        // deposit 7 stETH to strategy
        vm.prank(operatorAddress);
        (success,) = STRATEGY_MANAGER_ADDRESS_HOLESKY.call(
            abi.encodeWithSignature(
                DEPOSIT_FUNCTION_SIGNATURE, LST_STRATEGY_ADDRESS_HOLESKY, LST_CONTRACT_ADDRESS_HOLESKY, 7 ether
            )
        );
        require(success, string.concat("Deposit failed for ", operatorName));

        // register operator in delegation manager
        vm.prank(operatorAddress);
        (success,) = DELEGATION_MANAGER_ADDRESS_HOLESKY.call(
            abi.encodeWithSignature(REGISTER_FUNCTION_SIGNATURE, address(0), uint32(0), "foo.bar")
        );
        require(success, string.concat("Register failed for ", operatorName));

        return Operator({
            operator: operatorAddress,
            ecdsaPrivateKey: ecdsaPrivateKey,
            blsPrivateKey: blsPrivateKey,
            pk1: pk1,
            pk2: pk2
        });
    }

    function _registerOperator(ISlashingRegistryCoordinator registryCoordinator, address avs, Operator memory operator)
        internal
    {
        bytes memory quorumNumbers = hex"00";
        string memory socket = "foo.bar";

        BN254.G1Point memory h = registryCoordinator.pubkeyRegistrationMessageHash(operator.operator);
        BN254.G1Point memory sig = BN254.scalar_mul(h, operator.blsPrivateKey);

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params = IBLSApkRegistryTypes.PubkeyRegistrationParams({
            pubkeyG1: operator.pk1,
            pubkeyG2: operator.pk2,
            pubkeyRegistrationSignature: sig
        });

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature =
            _newOperatorRegistrationSignature(operator, avs, bytes32(0), block.timestamp + 1 days);

        vm.prank(operator.operator);
        IRegistryCoordinator(address(registryCoordinator)).registerOperator(
            quorumNumbers, socket, params, operatorSignature
        );
    }

    function _generateBLSKeys(uint256 seed)
        internal
        view
        returns (uint256, BN254.G1Point memory, BN254.G2Point memory)
    {
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

    function _signBLSMessage(Operator memory operator, bytes32 messageHash)
        internal
        view
        returns (BN254.G1Point memory)
    {
        BN254.G1Point memory h = BN254.hashToG1(messageHash);
        BN254.G1Point memory sig = BN254.scalar_mul(h, operator.blsPrivateKey);
        return sig;
    }

    function _newOperatorRegistrationSignature(Operator memory operator, address avs, bytes32 salt, uint256 expiry)
        internal
        view
        returns (ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory)
    {
        bytes32 operatorRegistrationDigestHash = IAVSDirectory(AVS_DIRECTORY_ADDRESS_HOLESKY)
            .calculateOperatorAVSRegistrationDigestHash(operator.operator, avs, salt, expiry);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator.ecdsaPrivateKey, operatorRegistrationDigestHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        return ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({signature: signature, salt: salt, expiry: expiry});
    }
}

// Imported only relevant IAVSDirectory functions in order to not depend on eigenlayer-core
interface IAVSDirectory {
    /**
     *  @notice Calculates the digest hash to be signed by an operator to register with an AVS.
     *
     *  @param operator The account registering as an operator.
     *  @param avs The AVS the operator is registering with.
     *  @param salt A unique and single-use value associated with the approver's signature.
     *  @param expiry The time after which the approver's signature becomes invalid.
     */
    function calculateOperatorAVSRegistrationDigestHash(address operator, address avs, bytes32 salt, uint256 expiry)
        external
        view
        returns (bytes32);
}
