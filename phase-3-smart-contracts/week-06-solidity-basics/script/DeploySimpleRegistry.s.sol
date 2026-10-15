// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SimpleRegistry} from "../src/SimpleRegistry.sol";

/// @notice Deploy with:
///   forge script script/DeploySimpleRegistry.s.sol --rpc-url http://127.0.0.1:8545 \
///     --broadcast --private-key $ANVIL_PRIVATE_KEY
/// @dev The deploying key comes from the CLI or a keystore, never from source code.
contract DeploySimpleRegistry is Script {
    function run() external returns (SimpleRegistry registry) {
        vm.startBroadcast();
        registry = new SimpleRegistry();
        vm.stopBroadcast();
        console.log("SimpleRegistry deployed at", address(registry));
    }
}
