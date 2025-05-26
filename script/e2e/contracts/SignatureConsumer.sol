// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {BN254} from "@eigenlayer-middleware/libraries/BN254.sol";
import {BLSSignatureChecker} from "@eigenlayer-middleware/BLSSignatureChecker.sol";
import {IBLSSignatureCheckerTypes} from "@eigenlayer-middleware/interfaces/IBLSSignatureChecker.sol";

contract SignatureConsumer {
    using BN254 for BN254.G1Point;

    BLSSignatureChecker public immutable signatureChecker;

    event SignatureVerified(bytes32 indexed messageHash, uint256 signedStake, uint256 totalStake);

    constructor(address _signatureChecker) {
        signatureChecker = BLSSignatureChecker(_signatureChecker);
    }

    function verifySignatureAndEmit(
        bytes32 messageHash,
        bytes calldata quorumNumbers,
        uint32 blockNumber,
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature calldata nonSignerStakesAndSignature
    ) external returns (IBLSSignatureCheckerTypes.QuorumStakeTotals memory) {
        (IBLSSignatureCheckerTypes.QuorumStakeTotals memory quorumStakeTotals,) = signatureChecker.checkSignatures(
            messageHash,
            quorumNumbers,
            blockNumber,
            nonSignerStakesAndSignature
        );

        emit SignatureVerified(
            messageHash,
            quorumStakeTotals.signedStakeForQuorum[0],
            quorumStakeTotals.totalStakeForQuorum[0]
        );

        return quorumStakeTotals;
    }
}
