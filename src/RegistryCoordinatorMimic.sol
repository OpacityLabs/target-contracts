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
import {RLPReader} from "@optimism/libraries/rlp/RLPReader.sol";
// TODO: QuorumBitmapHistoryLib is an external library, we don't want to deploy it so we either need to link it or create a library that just has the internal functions
// Considering this contract is already bloated, it may be better to just link it

// I cannot inherit both error interfaces because both of them have an error definition `QuorumAlreadyExists()`
contract RegistryCoordinatorMimic is
    Ownable,
    ISlashingRegistryCoordinatorTypes,
    IBLSApkRegistryTypes,
    IBLSApkRegistryErrors,
    IStakeRegistryTypes,
    IMiddlewareShimTypes
{
    struct StateUpdateProof {
        uint256 blockNumber;
        bytes32 storageHash;
        bytes[] storageProof;
        bytes[] accountProof;
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

    // NOTE: I really hope the usage of modifying the storage array lengths through assembly is not a problem for audits
    // TODO: make this incremental (update only the added elements)
    function updateState(MiddlewareData calldata middlewareData, bytes calldata proof) external onlyOwner {
        require(middlewareData.blockNumber > lastBlockNumber, MiddlewareDataBlockNumberTooOld());

        // REVIEW: It's possible to update the middleware data to a newer one that's not necessarily the newest one
        // E.g.: MiddlewareData transtitions: S1 (block:100) -> S2 (block:200) -> S3 (block:300)
        // If S1 is the latest registered middleware data, and S3 is the latest update on the L1, a proof for S2 will be accepted
        // -----------------------------------------------------------------------------------------------------------------
        // This matters if we want a recent state update to imply the middlewareData is not stale,
        // but it's still isn't clear if it's relevant for the AVS use case
        bytes32 middlewareDataHash = keccak256(abi.encode(middlewareData));
        _verifyProof(middlewareDataHash, proof);

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
        lastBlockNumber = middlewareData.blockNumber;
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
    function _verifyProof(bytes32 middlewareDataHash, bytes calldata proof) internal virtual {
        StateUpdateProof memory stateUpdateProof = abi.decode(proof, (StateUpdateProof));
        bytes32 executionStateRoot = LITE_CLIENT.executionStateRoots(stateUpdateProof.blockNumber);
        require(executionStateRoot != bytes32(0), MissingExecutionStateRoot(stateUpdateProof.blockNumber));

        // verify the storage proof
        bytes memory key = abi.encode(MIDDLEWARE_DATA_HASH_SLOT);
        bytes memory value = abi.encodePacked(middlewareDataHash);
        bytes memory result = SecureMerkleTrie.get(key, stateUpdateProof.storageProof, stateUpdateProof.storageHash);
        result = RLPReader.readBytes(result);
        require(
            keccak256(abi.encodePacked(result)) == keccak256(abi.encodePacked(value)), StorageProofVerificationFailed()
        );

        // verify the account proof
        key = abi.encodePacked(MIDDLEWARE_SHIM);
        // result is RLP encoded list of [nonce, balance, storageHash, codeHash]
        result = SecureMerkleTrie.get(key, stateUpdateProof.accountProof, executionStateRoot);
        RLPReader.RLPItem[] memory resultItems = RLPReader.readList(result);
        require(resultItems.length == 4, InvalidAccountProofLeafNode());
        // REVIEW: I'm 99% sure it's sound to just check the storageHash and ignore the rest, but a second eye is needed
        bytes memory storageHash = RLPReader.readBytes(resultItems[2]);
        require(
            keccak256(storageHash) == keccak256(abi.encodePacked(stateUpdateProof.storageHash)),
            AccountProofVerificationFailed()
        );
    }

    error MiddlewareDataBlockNumberTooOld();
    error MissingExecutionStateRoot(uint256 blockNumber);
    error StorageProofVerificationFailed();
    error InvalidAccountProofLeafNode();
    error AccountProofVerificationFailed();
}
