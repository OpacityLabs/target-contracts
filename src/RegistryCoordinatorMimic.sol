// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {
    IBLSApkRegistry,
    IBLSApkRegistryTypes,
    IBLSApkRegistryErrors
} from "@eigenlayer-middleware/interfaces/IBLSApkRegistry.sol";
import {
    IStakeRegistry,
    IStakeRegistryTypes,
    IStakeRegistryErrors,
    IDelegationManager
} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "@eigenlayer-middleware/interfaces/IIndexRegistry.sol";
import {ISlashingRegistryCoordinatorTypes} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {QuorumBitmapHistoryLib} from "@eigenlayer-middleware/libraries/QuorumBitmapHistoryLib.sol";
import {IMiddlewareShimTypes} from "./interfaces/IMiddlewareShim.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SP1Helios} from "@sp1-helios/SP1Helios.sol";
import {SecureMerkleTrie} from "@optimism/libraries/trie/SecureMerkleTrie.sol";
import {RLPWriter} from "@optimism/libraries/rlp/RLPWriter.sol";
import {RLPReader} from "@optimism/libraries/rlp/RLPReader.sol";
// TODO: QuorumBitmapHistoryLib is an external library, we don't want to deploy it so we either need to link it or create a library that just has the internal functions

// I cannot inherit both error interfaces because both of them have an error definition `QuorumAlreadyExists()`
contract RegistryCoordinatorMimic is
    Ownable,
    ISlashingRegistryCoordinatorTypes,
    IBLSApkRegistryTypes,
    IBLSApkRegistryErrors,
    IStakeRegistryTypes,
    IMiddlewareShimTypes
{
    struct AccountProof {
        uint256 nonce;
        uint256 balance;
        bytes32 storageHash;
        bytes32 codeHash; // TODO: review when relevant: can theoretically be hard-coded
        bytes[] accoutProof;
    }

    uint256 public constant MIDDLEWARE_DATA_HASH_SLOT = 0;

    SP1Helios public immutable LITE_CLIENT;
    address public immutable MIDDLEWARE_SHIM;

    uint256 public lastBlockNumber;

    uint256 internal quorum0UpdateBlockNumber;
    ApkUpdate[] internal quorumApkUpdates;
    StakeUpdate[] internal totalStakeHistory;
    mapping(bytes32 => StakeUpdate[]) internal operatorStakeHistory;
    /// @notice maps operator id => historical quorums they registered for
    mapping(bytes32 => QuorumBitmapUpdate[]) internal operatorBitmapHistory;

    constructor(SP1Helios _liteClient, address _middlewareShim) Ownable() {
        LITE_CLIENT = _liteClient;
        MIDDLEWARE_SHIM = _middlewareShim;
    }

    // I really hope the usage of modifying the storage array lengths through assembly is not a problem for audits
    // TODO: make this incremental (update only the added elements)
    function updateState(MiddlewareData calldata middlewareData, bytes calldata proof) external onlyOwner {
        bytes32 middlewareDataHash = keccak256(abi.encode(middlewareData));
        _verifyProof(middlewareDataHash, middlewareData.blockNumber, proof);

        // set the storage array lengths
        {
            uint256 quorumApkUpdatesLength = middlewareData.quorumApkUpdates.length;
            uint256 totalStakeHistoryLength = middlewareData.totalStakeHistory.length;
            assembly {
                sstore(quorumApkUpdates.slot, quorumApkUpdatesLength)
                sstore(totalStakeHistory.slot, totalStakeHistoryLength)
            }
        }

        quorum0UpdateBlockNumber = middlewareData.quorumUpdateBlockNumber;
        for (uint256 i = 0; i < middlewareData.quorumApkUpdates.length; i++) {
            quorumApkUpdates[i] = middlewareData.quorumApkUpdates[i];
        }
        for (uint256 i = 0; i < middlewareData.totalStakeHistory.length; i++) {
            totalStakeHistory[i] = middlewareData.totalStakeHistory[i];
        }
        for (uint256 i = 0; i < middlewareData.operatorStakeHistory.length; i++) {
            bytes32 operatorId = middlewareData.operatorStakeHistory[i].operatorId;
            StakeUpdate[] memory stakeHistory = middlewareData.operatorStakeHistory[i].stakeHistory;
            uint256 stakeHistoryLength = stakeHistory.length;
            StakeUpdate[] storage operatorStakeHistoryEntry = operatorStakeHistory[operatorId];
            // set the storage array length
            assembly {
                sstore(operatorStakeHistoryEntry.slot, stakeHistoryLength)
            }
            for (uint256 j = 0; j < stakeHistoryLength; j++) {
                operatorStakeHistoryEntry[j] = stakeHistory[j];
            }
        }
        for (uint256 i = 0; i < middlewareData.operatorBitmapHistory.length; i++) {
            bytes32 operatorId = middlewareData.operatorBitmapHistory[i].operatorId;
            QuorumBitmapUpdate[] memory bitmapHistory = middlewareData.operatorBitmapHistory[i].bitmapHistory;
            uint256 bitmapHistoryLength = bitmapHistory.length;
            QuorumBitmapUpdate[] storage operatorBitmapHistoryEntry = operatorBitmapHistory[operatorId];
            // set the storage array length
            assembly {
                sstore(operatorBitmapHistoryEntry.slot, bitmapHistoryLength)
            }
            for (uint256 j = 0; j < bitmapHistoryLength; j++) {
                operatorBitmapHistoryEntry[j] = bitmapHistory[j];
            }
        }
    }

    /**
     * @notice Reference to the BLSApkRegistry contract.
     * @return The BLSApkRegistry contract interface.
     */
    function blsApkRegistry() external view returns (IBLSApkRegistry) {
        return IBLSApkRegistry(address(this));
    }

    /**
     * @notice Reference to the StakeRegistry contract.
     * @return The StakeRegistry contract interface.
     */
    function stakeRegistry() external view returns (IStakeRegistry) {
        return IStakeRegistry(address(this));
    }

    /**
     * @notice Reference to the IndexRegistry contract.
     * @return The IndexRegistry contract interface.
     */
    function indexRegistry() external view returns (IIndexRegistry) {
        return IIndexRegistry(address(this));
    }

    /**
     * @notice Returns the EigenLayer delegation manager contract.
     */
    function delegation() external view returns (IDelegationManager) {
        return IDelegationManager(address(this));
    }

    /**
     * @notice The total number of quorums that have been created.
     * @return The count of quorums.
     */
    function quorumCount() external pure returns (uint8) {
        return 1;
    }

    // TODO: possible to optimize because we know there is only 1 quorum
    function getQuorumBitmapAtBlockNumberByIndex(bytes32 operatorId, uint32 blockNumber, uint256 index)
        external
        view
        returns (uint192)
    {
        return QuorumBitmapHistoryLib.getQuorumBitmapAtBlockNumberByIndex(
            operatorBitmapHistory, operatorId, blockNumber, index
        );
    }

    /// @dev https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-002.md
    /// @dev in ELIP-002 it's called WITHDRAWAL_DELAY - MIN_WITHDRAWAL_DELAY_BLOCKS is old name
    /// @dev around 2 weeks
    function minWithdrawalDelayBlocks() external pure returns (uint32) {
        return 100_800;
    }

    /// @notice mapping from quorum number to the latest block that all quorums were updated all at once
    function quorumUpdateBlockNumber(uint8 /* quorumNumber */ ) external view returns (uint256) {
        return quorum0UpdateBlockNumber;
    }

    /*
     * @notice Gets the 24-byte hash of `quorumNumber`'s APK at `blockNumber` and `index`.
     * @ param quorumNumber The quorum to query.
     * @param blockNumber The block number to get the APK hash for.
     * @param index The index in the APK history.
     * @return The 24-byte APK hash.
     * @dev Called by checkSignatures in BLSSignatureChecker.sol.
     */
    function getApkHashAtBlockNumberAndIndex(uint8, /* quorumNumber */ uint32 blockNumber, uint256 index)
        external
        view
        returns (bytes24)
    {
        // NOTICE: this line is modified from original implementation because of only 0 quorum
        // ApkUpdate memory quorumApkUpdate = apkHistory[quorumNumber][index];
        ApkUpdate memory quorumApkUpdate = quorumApkUpdates[index];

        /**
         * Validate that the update is valid for the given blockNumber:
         * - blockNumber should be >= the update block number
         * - the next update block number should be either 0 or strictly greater than blockNumber
         */
        require(blockNumber >= quorumApkUpdate.updateBlockNumber, BlockNumberTooRecent());
        require(
            quorumApkUpdate.nextUpdateBlockNumber == 0 || blockNumber < quorumApkUpdate.nextUpdateBlockNumber,
            BlockNumberNotLatest()
        );

        return quorumApkUpdate.apkHash;
    }

    /**
     * @notice Returns the total stake at the specified block number and index for a quorum.
     * @ param quorumNumber The quorum number to query.
     * @param blockNumber The block number to query.
     * @param index The index to query.
     * @return The total stake amount.
     * @dev Function will revert if `index` is out-of-bounds.
     * @dev Used by the BLSSignatureChecker to get past stakes of signing operators.
     */
    function getTotalStakeAtBlockNumberFromIndex(uint8, /* quorumNumber */ uint32 blockNumber, uint256 index)
        external
        view
        returns (uint96)
    {
        // NOTICE: this line is modified from original implementation because of only 0 quorum
        // StakeUpdate memory totalStakeUpdate = totalStakeHistory[quorumNumber][index];
        StakeUpdate memory totalStakeUpdate = totalStakeHistory[index];
        _validateStakeUpdateAtBlockNumber(totalStakeUpdate, blockNumber);
        return totalStakeUpdate.stake;
    }

    /**
     * @notice Returns the stake at the specified block number and index for an operator in a quorum.
     * @ param quorumNumber The quorum number to query.
     * @param blockNumber The block number to query.
     * @param operatorId The id of the operator to query.
     * @param index The index to query.
     * @return The stake amount.
     * @dev Function will revert if `index` is out-of-bounds.
     * @dev Used by the BLSSignatureChecker to get past stakes of signing operators.
     */
    function getStakeAtBlockNumberAndIndex(
        uint8, /* quorumNumber */
        uint32 blockNumber,
        bytes32 operatorId,
        uint256 index
    ) external view returns (uint96) {
        // NOTICE: this line is modified from original implementation because of only 0 quorum
        // StakeUpdate memory operatorStakeUpdate = operatorStakeHistory[operatorId][quorumNumber][index];
        StakeUpdate memory operatorStakeUpdate = operatorStakeHistory[operatorId][index];
        _validateStakeUpdateAtBlockNumber(operatorStakeUpdate, blockNumber);
        return operatorStakeUpdate.stake;
    }

    //--------------------//
    // INTERNAL FUNCTIONS //
    //--------------------//

    /// @notice Checks that the `stakeUpdate` was valid at the given `blockNumber`
    function _validateStakeUpdateAtBlockNumber(StakeUpdate memory stakeUpdate, uint32 blockNumber) internal pure {
        /**
         * Check that the update is valid for the given blockNumber:
         * - blockNumber should be >= the update block number
         * - the next update block number should be either 0 or strictly greater than blockNumber
         */
        require(blockNumber >= stakeUpdate.updateBlockNumber, IStakeRegistryErrors.InvalidBlockNumber());
        require(
            stakeUpdate.nextUpdateBlockNumber == 0 || blockNumber < stakeUpdate.nextUpdateBlockNumber,
            IStakeRegistryErrors.InvalidBlockNumber()
        );
    }

    // I hate making this function virtual but I need to do so I can mock it in tests
    function _verifyProof(bytes32 middlewareDataHash, uint256 blockNumber, bytes calldata proof) internal virtual {
        (AccountProof memory accountProof, bytes[] memory storageProof) = abi.decode(proof, (AccountProof, bytes[]));
        require(blockNumber > lastBlockNumber, BlockNumberTooOld());
        require(blockNumber <= LITE_CLIENT.head(), BlockNumberTooNew());

        // verify the storage proof
        bytes memory key = abi.encode(MIDDLEWARE_DATA_HASH_SLOT);
        bytes memory value = abi.encodePacked(middlewareDataHash);
        // NOTICE: storage values in proofs of eth_getProof are RLP encoded
        // https://www.quicknode.com/docs/ethereum/eth_getProof
        // TODO: This burned me a lot of time - this needs to be heavily tested
        bytes memory result = SecureMerkleTrie.get(key, storageProof, accountProof.storageHash);
        result = RLPReader.readBytes(result);
        require(
            keccak256(abi.encodePacked(result)) == keccak256(abi.encodePacked(value)), StorageProofVerificationFailed()
        );

        // verify the account proof
        bytes32 executionStateRoot = LITE_CLIENT.executionStateRoots(blockNumber);
        key = abi.encodePacked(MIDDLEWARE_SHIM);
        value = _computeAccountProofValue(accountProof);
        // result is RLP encoded list of [nonce, balance, storageHash, codeHash]
        result = SecureMerkleTrie.get(key, accountProof.accoutProof, executionStateRoot);
        require(
            keccak256(abi.encodePacked(result)) == keccak256(abi.encodePacked(value)), AccountProofVerificationFailed()
        );
    }

    function _computeAccountProofValue(AccountProof memory accountProof) internal pure returns (bytes memory) {
        bytes[] memory listItems = new bytes[](4);
        listItems[0] = RLPWriter.writeUint(accountProof.nonce);
        listItems[1] = RLPWriter.writeUint(accountProof.balance);
        listItems[2] = RLPWriter.writeBytes(abi.encodePacked(accountProof.storageHash));
        listItems[3] = RLPWriter.writeBytes(abi.encodePacked(accountProof.codeHash));
        return RLPWriter.writeList(listItems);
    }

    error BlockNumberTooOld();
    error BlockNumberTooNew();
    error StorageProofVerificationFailed();
    error AccountProofVerificationFailed();
}
