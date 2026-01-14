// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script, console} from "forge-std/Script.sol";

contract VerifyL2Contracts is Script {
    function run() public view {
        string memory l2OutPath = vm.envString("L2_OUT_PATH");
        string memory l2RpcUrl = vm.envString("L2_RPC_URL");
        string memory l2EtherscanApiKey = vm.envString("L2_ETHERSCAN_API_KEY");
        
        // Read the deployment addresses from the output file
        string memory deploymentData = vm.readFile(l2OutPath);
        
        console.log("=====================================");
        console.log("L2 Contract Verification Instructions");
        console.log("=====================================");
        console.log("");
        console.log("The QuorumBitmapHistoryLib is an external library that needs special handling.");
        console.log("");
        console.log("To verify the contracts on Gnosisscan, run the following commands:");
        console.log("");
        
        // Parse JSON to get addresses (this is pseudo-code, actual implementation would need proper JSON parsing)
        console.log("1. First, verify the QuorumBitmapHistoryLib if deployed separately:");
        console.log("   forge verify-contract <LIBRARY_ADDRESS> QuorumBitmapHistoryLib \\");
        console.log("     --rpc-url", l2RpcUrl, "\\");
        console.log("     --etherscan-api-key", l2EtherscanApiKey, "\\");
        console.log("     --compiler-version v0.8.27+commit.40a35a09");
        console.log("");
        
        console.log("2. Then verify the main contracts with library linking:");
        console.log("   forge verify-contract <CONTRACT_ADDRESS> <CONTRACT_NAME> \\");
        console.log("     --rpc-url", l2RpcUrl, "\\");
        console.log("     --etherscan-api-key", l2EtherscanApiKey, "\\");
        console.log("     --libraries QuorumBitmapHistoryLib:<LIBRARY_ADDRESS> \\");
        console.log("     --constructor-args <ENCODED_ARGS>");
        console.log("");
        
        console.log("Note: Replace placeholders with actual addresses from", l2OutPath);
        console.log("");
        console.log("Alternative: Use forge's built-in verification during deployment:");
        console.log("   forge script DeployL2 --broadcast --verify \\");
        console.log("     --rpc-url", l2RpcUrl, "\\");
        console.log("     --etherscan-api-key", l2EtherscanApiKey);
    }
}