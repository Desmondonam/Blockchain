// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DocumentRegistry} from "../src/DocumentRegistry.sol";

/// @notice Deploys DocumentRegistry and writes a deployment manifest that the frontend and
///         indexer read, so nobody copy-pastes addresses by hand.
///
///   forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast \
///       --private-key <anvil key #0>
contract Deploy is Script {
    function run() external returns (DocumentRegistry registry) {
        vm.startBroadcast();
        registry = new DocumentRegistry();
        vm.stopBroadcast();

        string memory key = "deployment";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeUint(key, "startBlock", block.number); // the indexer starts scanning here
        string memory json = vm.serializeAddress(key, "DocumentRegistry", address(registry));
        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);

        console.log("DocumentRegistry:", address(registry));
        console.log("manifest written to", path);
    }
}
