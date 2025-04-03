// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

contract RegistryCoordinatorMimic {

    /**
     * @notice The total number of quorums that have been created.
     * @return The count of quorums.
     */
    function quorumCount() external view returns (uint8) {
        return 1;
    }

    // we only have one quorum, we just need to determine if the operator was in the quorum at the given block number
    // index is an index into a quorum bitmap history of the operator and is computed off-chain
    // I think it's impractical to implement the quorum bitmap history in full, so this is a big TODO
    //
    function getQuorumBitmapAtBlockNumberByIndex(
        bytes32 operatorId,
        uint32 blockNumber,
        uint256 index
    ) external view returns (uint192) {
        // TODO: make sure eigenlayer bitmaps are left-aligned
        return 1;
    }

    function minWithdrawalDelayBlocks() external view returns (uint32) {
        // TODO: bridge from on-chain? theoretically should not be different over time
        // TODO: didn't find MIN_WITHDRAWAL_DELAY_BLOCKS value in Eigen's docs
        return 80_000;
    }

    /// @notice mapping from quorum number to the latest block that all quorums were updated all at once
    function quorumUpdateBlockNumber(uint8 quorumNumber) external view returns (uint256) {
        // TODO: needs to be bridges from Shim?
        return 0;
    }

    /*
     * @notice Gets the 24-byte hash of `quorumNumber`'s APK at `blockNumber` and `index`.
     * @param quorumNumber The quorum to query.
     * @param blockNumber The block number to get the APK hash for.
     * @param index The index in the APK history.
     * @return The 24-byte APK hash.
     * @dev Called by checkSignatures in BLSSignatureChecker.sol.
     */
    function getApkHashAtBlockNumberAndIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        uint256 index
    ) external view returns (bytes24) {
        // TODO: bridge from Shim
        // TODO: should we implement an ApkUpdate, or track ourselves the apk hashes?
        return bytes24(0);


        // Original implementation:
        // ------------------------
        // ApkUpdate memory quorumApkUpdate = apkHistory[quorumNumber][index];

        // /**
        //  * Validate that the update is valid for the given blockNumber:
        //  * - blockNumber should be >= the update block number
        //  * - the next update block number should be either 0 or strictly greater than blockNumber
        //  */
        // require(blockNumber >= quorumApkUpdate.updateBlockNumber, BlockNumberTooRecent());
        // require(
        //     quorumApkUpdate.nextUpdateBlockNumber == 0
        //         || blockNumber < quorumApkUpdate.nextUpdateBlockNumber,
        //     BlockNumberNotLatest()
        // );

        // return quorumApkUpdate.apkHash;
    }

    /**
     * @notice Returns the total stake at the specified block number and index for a quorum.
     * @param quorumNumber The quorum number to query.
     * @param blockNumber The block number to query.
     * @param index The index to query.
     * @return The total stake amount.
     * @dev Function will revert if `index` is out-of-bounds.
     * @dev Used by the BLSSignatureChecker to get past stakes of signing operators.
     */
    function getTotalStakeAtBlockNumberFromIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        uint256 index
    ) external view returns (uint96) {
        // TODO: bridge from Shim
        return 0;
        // StakeUpdate memory totalStakeUpdate = _totalStakeHistory[quorumNumber][index];
        // _validateStakeUpdateAtBlockNumber(totalStakeUpdate, blockNumber);
        // return totalStakeUpdate.stake;
    }

    /**
     * @notice Returns the stake at the specified block number and index for an operator in a quorum.
     * @param quorumNumber The quorum number to query.
     * @param blockNumber The block number to query.
     * @param operatorId The id of the operator to query.
     * @param index The index to query.
     * @return The stake amount.
     * @dev Function will revert if `index` is out-of-bounds.
     * @dev Used by the BLSSignatureChecker to get past stakes of signing operators.
     */
    function getStakeAtBlockNumberAndIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        bytes32 operatorId,
        uint256 index
    ) external view returns (uint96) {
        // TODO: bridge from Shim
        return 0;
        // StakeUpdate memory operatorStakeUpdate =
        //     operatorStakeHistory[operatorId][quorumNumber][index];
        // _validateStakeUpdateAtBlockNumber(operatorStakeUpdate, blockNumber);
        // return operatorStakeUpdate.stake;
    }
}
    