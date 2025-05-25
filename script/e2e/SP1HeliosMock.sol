// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SP1HeliosMock is Ownable {
    mapping(uint256 slotNumber => bytes32 executionStateRoot) public executionStateRoots;

    function setExecutionStateRoot(uint256 slotNumber, bytes32 executionStateRoot) external onlyOwner {
        executionStateRoots[slotNumber] = executionStateRoot;
    }
}