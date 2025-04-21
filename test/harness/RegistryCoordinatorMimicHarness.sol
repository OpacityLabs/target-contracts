// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {RegistryCoordinatorMimic} from "../../src/RegistryCoordinatorMimic.sol";
import {SP1Helios} from "@sp1-helios/SP1Helios.sol";
import {console} from "forge-std/console.sol";

contract RegistryCoordinatorMimicHarness is RegistryCoordinatorMimic {
    bool internal mockVerifyProof = false;

    constructor(SP1Helios _liteClient, address _middlewareShim)
        RegistryCoordinatorMimic(_liteClient, _middlewareShim)
    {}

    function _verifyProof(bytes32 middlewareDataHash, bytes calldata proof) internal virtual override {
        if (mockVerifyProof) {
            return;
        }
        super._verifyProof(middlewareDataHash, proof);
    }

    function harness_setMockVerifyProof(bool _mockVerifyProof) external {
        mockVerifyProof = _mockVerifyProof;
    }

    function harness_getQuorumApkUpdates() external view returns (ApkUpdate[] memory) {
        return quorumApkUpdates;
    }

    function harness_getTotalStakeHistory() external view returns (StakeUpdate[] memory) {
        return totalStakeHistory;
    }

    function harness_getOperatorStakeHistory(bytes32 operatorId) external view returns (StakeUpdate[] memory) {
        return operatorStakeHistory[operatorId];
    }

    function harness_getOperatorBitmapHistory(bytes32 operatorId) external view returns (QuorumBitmapUpdate[] memory) {
        return operatorBitmapHistory[operatorId];
    }

    function harness_getQuorum0UpdateBlockNumber() external view returns (uint256) {
        return quorum0UpdateBlockNumber;
    }
}
