// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";

/// @notice Environment-driven deployment: the same script serves local, testnet and production
///         configurations. Only the .env file changes.
///
///   cp .env.example .env            # then edit it
///   source .env
///   forge script script/DeployRoleRegistry.s.sol --rpc-url $RPC_URL --broadcast \
///       --private-key <anvil-key>     # local only; use --account <keystore> on testnets
///
/// @dev The deployer must equal ADMIN_ADDRESS to grant roles in the same run. In production,
///      deploy with the admin set to a Safe multisig and grant roles through Safe transactions.
contract DeployRoleRegistry is Script {
    function run() external returns (RoleRegistry registry) {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address registrar = vm.envAddress("REGISTRAR_ADDRESS");
        address pauser = vm.envAddress("PAUSER_ADDRESS");
        uint48 delay = uint48(vm.envUint("ADMIN_TRANSFER_DELAY"));

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers(); // the account actually signing the txs
        registry = new RoleRegistry(delay, admin);
        if (deployer == admin) {
            registry.grantRole(registry.REGISTRAR_ROLE(), registrar);
            registry.grantRole(registry.PAUSER_ROLE(), pauser);
        } else {
            console.log("Deployer is not admin: grant roles from the admin account afterwards.");
        }
        vm.stopBroadcast();

        console.log("RoleRegistry:", address(registry));
        console.log("admin:       ", admin);
        console.log("registrar:   ", registrar);
        console.log("pauser:      ", pauser);
    }
}
