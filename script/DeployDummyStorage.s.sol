// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script, console} from "forge-std/Script.sol";

contract DeployDummyStorage is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Counter counter = new Counter();
        counter.increment();
        console.log("Counter deployed at", address(counter));

        vm.stopBroadcast();
    }
}

contract Counter {
    uint256 public count;

    function increment() external {
        count++;
    }

    function decrement() external {
        count--;
    }
}
