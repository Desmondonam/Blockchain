// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRegistry} from "./interfaces/IRegistry.sol";

/// @title RegistryGatekeeper: a consumer that depends only on the IRegistry interface
/// @notice Example: an access gate that lets an address in only if it presents a
///         document hash that is active in the registry and owned by that address.
/// @dev Dependency inversion: this contract never imports ModularRegistry. Any IRegistry
///      works, including a mock in tests.
contract RegistryGatekeeper {
    error DocumentNotActive(bytes32 documentHash);
    error NotDocumentOwner(bytes32 documentHash, address caller);

    event Admitted(address indexed account, bytes32 indexed documentHash);

    IRegistry public immutable REGISTRY;
    mapping(address => bool) public admitted;

    constructor(IRegistry registry) {
        REGISTRY = registry;
    }

    function enter(bytes32 documentHash) external {
        // External call to a contract we treat as trusted. Review that assumption in Week 14.
        if (!REGISTRY.isActive(documentHash)) revert DocumentNotActive(documentHash);
        uint256 id = REGISTRY.idByHash(documentHash);
        if (REGISTRY.getRecord(id).owner != msg.sender) {
            revert NotDocumentOwner(documentHash, msg.sender);
        }
        admitted[msg.sender] = true;
        emit Admitted(msg.sender, documentHash);
    }
}
