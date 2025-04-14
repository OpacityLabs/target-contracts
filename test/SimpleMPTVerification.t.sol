// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {SecureMerkleTrie} from "@optimism/libraries/trie/SecureMerkleTrie.sol";

contract SimpleMPTVerificationTest is Test {
    // see script/DeployDummyStorage.s.sol
    address constant COUNTER_ADDRESS_HOLESKY = 0x8dA342Bf25Ea6A930Cd0b08D0Ad09A95C9C2A1FB;

    function setUp() public {}

    function test_single_slot_proof_verification() public {
        // cast proof 0x8dA342Bf25Ea6A930Cd0b08D0Ad09A95C9C2A1FB 0 --rpc-url https://ethereum-holesky-rpc.publicnode.com
        bytes32 storageHash = 0x821e2556a290c86405f8160a2d662042a431ba456b9db265c79bb837c04be5f0;
        bytes memory key = abi.encode(0);
        bytes memory val = hex"01";
        bytes[] memory proof = new bytes[](1);
        proof[0] = hex"e3a120290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e56301";

        assertEq(val, SecureMerkleTrie.get(key, proof, storageHash));
    }

    function test_account_proof_verification() public {
        // TODO: Implement this
        // need to verify the account proof for a given execution state root,
        // and then verify the storage proof is part of the account state
    }
}
