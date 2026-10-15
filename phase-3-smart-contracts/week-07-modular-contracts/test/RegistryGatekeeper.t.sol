// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IRegistry} from "../src/interfaces/IRegistry.sol";
import {ModularRegistry} from "../src/ModularRegistry.sol";
import {RegistryGatekeeper} from "../src/RegistryGatekeeper.sol";

/// @dev A hand-written mock: implements the interface with controllable answers.
///      It lets us test the gatekeeper in isolation (a unit test), without the real registry.
contract MockRegistry is IRegistry {
    bool public activeAnswer;
    address public ownerAnswer;

    function setAnswers(bool active, address owner_) external {
        activeAnswer = active;
        ownerAnswer = owner_;
    }

    function isActive(bytes32) external view returns (bool) {
        return activeAnswer;
    }

    function idByHash(bytes32) external pure returns (uint256) {
        return 1;
    }

    function getRecord(uint256) external view returns (Record memory r) {
        r.owner = ownerAnswer;
        r.status = Status.Active;
    }

    function register(bytes32, string calldata) external pure returns (uint256) {
        revert("not used");
    }

    function retire(uint256) external pure {
        revert("not used");
    }

    function transferRecord(uint256, address) external pure {
        revert("not used");
    }
}

contract RegistryGatekeeperUnitTest is Test {
    MockRegistry internal mock;
    RegistryGatekeeper internal gate;
    address internal alice = makeAddr("alice");
    bytes32 internal constant DOC = keccak256("salt|doc");

    function setUp() public {
        mock = new MockRegistry();
        gate = new RegistryGatekeeper(mock);
    }

    function test_AdmitsActiveOwner() public {
        mock.setAnswers(true, alice);
        vm.prank(alice);
        gate.enter(DOC);
        assertTrue(gate.admitted(alice));
    }

    function test_RevertWhen_Inactive() public {
        mock.setAnswers(false, alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RegistryGatekeeper.DocumentNotActive.selector, DOC));
        gate.enter(DOC);
    }

    function test_RevertWhen_NotOwner() public {
        mock.setAnswers(true, makeAddr("someone-else"));
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(RegistryGatekeeper.NotDocumentOwner.selector, DOC, alice)
        );
        gate.enter(DOC);
    }
}

/// @dev Integration test: the gatekeeper wired to the REAL registry.
contract RegistryGatekeeperIntegrationTest is Test {
    function test_EndToEndWithRealRegistry() public {
        address alice = makeAddr("alice");
        ModularRegistry registry = new ModularRegistry(address(this));
        RegistryGatekeeper gate = new RegistryGatekeeper(registry);
        bytes32 h = keccak256("salt|ticket");

        vm.startPrank(alice);
        registry.register(h, "Event ticket");
        gate.enter(h);
        vm.stopPrank();
        assertTrue(gate.admitted(alice));

        // Admin freezes the record: no new entries with it.
        registry.freeze(1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RegistryGatekeeper.DocumentNotActive.selector, h));
        gate.enter(h);
    }
}
