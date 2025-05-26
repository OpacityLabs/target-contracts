// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {SecureMerkleTrie} from "@optimism/libraries/trie/SecureMerkleTrie.sol";
import {RLPWriter} from "@optimism/libraries/rlp/RLPWriter.sol";
import {stdJson} from "forge-std/StdJson.sol";

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

    struct AccountClaimed {
        uint256 nonce;
        uint256 balance;
        bytes32 storageHash;
        bytes32 codeHash;
    }

    function test_account_proof_verification() public {
        // to compute the proof again:
        // cast proof -B 3575746 0x8dA342Bf25Ea6A930Cd0b08D0Ad09A95C9C2A1FB 0 --rpc-url https://ethereum-holesky-rpc.publicnode.com
        // ------------------------------------------------------------
        // execution state root of block 3675746
        // keccak256(proof[0]) == executionStateRoot
        // ------------------------------------------------------------
        bytes32 executionStateRoot = 0xd8a47a715c1617711ccfc19aef862fb73d5e113927f11a53b14a89d3528000c7;

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/test/fixtures/counterProof_3675746.json");
        string memory json = vm.readFile(path);
        address counterContract = stdJson.readAddress(json, ".address");
        AccountClaimed memory accountClaimed = AccountClaimed({
            nonce: stdJson.readUint(json, ".nonce"),
            balance: stdJson.readUint(json, ".balance"),
            storageHash: stdJson.readBytes32(json, ".storageHash"),
            codeHash: stdJson.readBytes32(json, ".codeHash")
        });
        bytes[] memory proof = stdJson.readBytesArray(json, ".accountProof");
        bytes memory key = abi.encodePacked(counterContract);

        // reference code for computing value in tree (account_proof.go)
        // ------------------------------------------------------------
        // accountClaimed := []any{uint64(res.Nonce), res.Balance.ToInt().Bytes(), res.StorageHash, res.CodeHash}
        // accountClaimedValue, err := rlp.EncodeToBytes(accountClaimed)
        // ------------------------------------------------------------
        bytes[] memory listItems = new bytes[](4);
        listItems[0] = RLPWriter.writeUint(accountClaimed.nonce);
        listItems[1] = RLPWriter.writeUint(accountClaimed.balance);
        listItems[2] = RLPWriter.writeBytes(abi.encodePacked(accountClaimed.storageHash));
        listItems[3] = RLPWriter.writeBytes(abi.encodePacked(accountClaimed.codeHash));
        bytes memory val = RLPWriter.writeList(listItems);

        bytes memory result = SecureMerkleTrie.get(key, proof, executionStateRoot);

        assertEq(val, result);
    }
}
