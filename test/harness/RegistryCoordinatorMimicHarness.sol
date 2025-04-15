// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {RegistryCoordinatorMimic} from "../../src/RegistryCoordinatorMimic.sol";
import {SP1Helios} from "@sp1-helios/SP1Helios.sol";

contract RegistryCoordinatorMimicHarness is RegistryCoordinatorMimic {
    bool internal mockVerifyProof = false;

    constructor(SP1Helios _liteClient, address _middlewareShim)
        RegistryCoordinatorMimic(_liteClient, _middlewareShim)
    {}

    function _verifyProof(bytes32 middlewareDataHash, uint256 blockNumber, bytes calldata proof)
        internal
        virtual
        override
    {
        if (mockVerifyProof) {
            return;
        }
        super._verifyProof(middlewareDataHash, blockNumber, proof);
    }

    function harness_setMockVerifyProof(bool _mockVerifyProof) external {
        mockVerifyProof = _mockVerifyProof;
    }
}
