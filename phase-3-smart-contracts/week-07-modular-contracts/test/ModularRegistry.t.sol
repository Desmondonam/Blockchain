// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ModularRegistry} from "../src/ModularRegistry.sol";
import {IRegistry} from "../src/interfaces/IRegistry.sol";
import {Owned} from "../src/access/Owned.sol";
import {LabelLib} from "../src/libraries/LabelLib.sol";

contract ModularRegistryTest is Test {
    ModularRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal constant HASH = keccak256("salt|doc");

    function setUp() public {
        registry = new ModularRegistry(admin);
    }

    function _registerAsAlice() internal returns (uint256 id) {
        vm.prank(alice);
        id = registry.register(HASH, "Diploma 2026");
    }

    // ------------------------------------------------------------ register

    function test_Register() public {
        uint256 id = _registerAsAlice();
        IRegistry.Record memory r = registry.getRecord(id);
        assertEq(r.owner, alice);
        assertEq(uint8(r.status), uint8(IRegistry.Status.Active));
        assertTrue(registry.isActive(HASH));
    }

    function test_RevertWhen_EmptyHash() public {
        vm.expectRevert(IRegistry.EmptyHash.selector); // error with no args: selector only
        registry.register(bytes32(0), "x");
    }

    function test_RevertWhen_Duplicate_ReportsExistingId() public {
        uint256 id = _registerAsAlice();
        // Errors with arguments: encode the selector AND the expected values.
        vm.expectRevert(abi.encodeWithSelector(IRegistry.AlreadyRegistered.selector, HASH, id));
        registry.register(HASH, "again");
    }

    function test_RevertWhen_LabelHasControlCharacter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LabelLib.InvalidLabelCharacter.selector, uint256(3), bytes1(0x0a)
            )
        );
        registry.register(HASH, "abc\ndef");
    }

    // -------------------------------------------------------------- retire

    function test_OwnerRetires() public {
        uint256 id = _registerAsAlice();
        vm.prank(alice);
        registry.retire(id);
        assertFalse(registry.isActive(HASH));
    }

    function test_RevertWhen_StrangerRetires() public {
        uint256 id = _registerAsAlice();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IRegistry.NotRecordOwner.selector, id, bob));
        registry.retire(id);
    }

    function test_RevertWhen_RetireUnknown() public {
        vm.expectRevert(abi.encodeWithSelector(IRegistry.UnknownRecord.selector, 7));
        registry.retire(7);
    }

    function test_RevertWhen_RetireTwice() public {
        uint256 id = _registerAsAlice();
        vm.startPrank(alice);
        registry.retire(id);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistry.InvalidStatus.selector, id, IRegistry.Status.Retired)
        );
        registry.retire(id);
        vm.stopPrank();
    }

    // ------------------------------------------------------------ transfer

    function test_Transfer() public {
        uint256 id = _registerAsAlice();
        vm.prank(alice);
        registry.transferRecord(id, bob);
        assertEq(registry.getRecord(id).owner, bob);
    }

    function test_RevertWhen_TransferToZeroOrSelf() public {
        uint256 id = _registerAsAlice();
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IRegistry.InvalidRecipient.selector, address(0)));
        registry.transferRecord(id, address(0));
        vm.expectRevert(abi.encodeWithSelector(IRegistry.InvalidRecipient.selector, alice));
        registry.transferRecord(id, alice);
        vm.stopPrank();
    }

    // ---------------------------------------------------------- admin powers

    function test_AdminFreezeBlocksOwnerActions() public {
        uint256 id = _registerAsAlice();
        vm.prank(admin);
        registry.freeze(id);
        assertFalse(registry.isActive(HASH));

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistry.InvalidStatus.selector, id, IRegistry.Status.Frozen)
        );
        registry.transferRecord(id, bob);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistry.InvalidStatus.selector, id, IRegistry.Status.Frozen)
        );
        registry.retire(id);
        vm.stopPrank();

        vm.prank(admin);
        registry.unfreeze(id);
        assertTrue(registry.isActive(HASH));
    }

    function test_RevertWhen_NonAdminFreezes() public {
        uint256 id = _registerAsAlice();
        vm.prank(alice); // even the record owner is not the contract owner
        vm.expectRevert(abi.encodeWithSelector(Owned.NotOwner.selector, alice));
        registry.freeze(id);
    }

    // ------------------------------------------------- two-step ownership

    function test_TwoStepOwnershipTransfer() public {
        vm.prank(admin);
        registry.transferOwnership(bob);
        assertEq(registry.owner(), admin, "nothing changes until accepted");
        assertEq(registry.pendingOwner(), bob);

        vm.prank(bob);
        registry.acceptOwnership();
        assertEq(registry.owner(), bob);
        assertEq(registry.pendingOwner(), address(0));
    }

    function test_RevertWhen_WrongAccountAccepts() public {
        vm.prank(admin);
        registry.transferOwnership(bob);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Owned.NotPendingOwner.selector, alice));
        registry.acceptOwnership();
    }

    function test_RevertWhen_DeployWithZeroOwner() public {
        vm.expectRevert(Owned.ZeroAddressOwner.selector);
        new ModularRegistry(address(0));
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_OnlyOwnerCanFreeze(address caller) public {
        vm.assume(caller != admin);
        uint256 id = _registerAsAlice();
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Owned.NotOwner.selector, caller));
        registry.freeze(id);
    }
}
