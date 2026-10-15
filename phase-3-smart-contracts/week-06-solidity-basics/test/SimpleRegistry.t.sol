// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SimpleRegistry} from "../src/SimpleRegistry.sol";

/// @dev Naming convention: test_<behaviour> for success paths, test_RevertWhen_<condition>
///      for failure paths, testFuzz_<property> for fuzz tests.
contract SimpleRegistryTest is Test {
    SimpleRegistry internal registry;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal constant HASH_A = keccak256("salt-1|diploma-pdf-bytes");
    bytes32 internal constant HASH_B = keccak256("salt-2|transcript-pdf-bytes");

    // Events must be redeclared (or imported) to use vm.expectEmit.
    event RecordRegistered(
        uint256 indexed id, address indexed owner, bytes32 indexed documentHash, string label
    );
    event RecordRetired(uint256 indexed id, address indexed owner);
    event RecordTransferred(uint256 indexed id, address indexed from, address indexed to);

    function setUp() public {
        registry = new SimpleRegistry();
        vm.warp(1_700_000_000); // deterministic block.timestamp
    }

    // ----------------------------------------------------------- register

    function test_RegisterStoresRecord() public {
        vm.prank(alice); // the NEXT call comes from alice
        uint256 id = registry.register(HASH_A, "Diploma 2026");

        assertEq(id, 1, "first id is 1");
        assertEq(registry.recordCount(), 1);
        assertEq(registry.idByHash(HASH_A), 1);
        assertTrue(registry.isActive(HASH_A));

        SimpleRegistry.Record memory r = registry.getRecord(id);
        assertEq(r.owner, alice);
        assertEq(uint8(r.status), uint8(SimpleRegistry.Status.Active));
        assertEq(r.registeredAt, 1_700_000_000);
        assertEq(r.documentHash, HASH_A);
        assertEq(r.label, "Diploma 2026");
    }

    function test_RegisterEmitsEvent() public {
        // check topic1, topic2, topic3 and data
        vm.expectEmit(true, true, true, true, address(registry));
        emit RecordRegistered(1, alice, HASH_A, "Diploma 2026");

        vm.prank(alice);
        registry.register(HASH_A, "Diploma 2026");
    }

    function test_IdsIncrementAndTrackOwner() public {
        vm.startPrank(alice);
        registry.register(HASH_A, "A");
        registry.register(HASH_B, "B");
        vm.stopPrank();

        uint256[] memory ids = registry.recordsOf(alice);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
    }

    function test_DeployerIsRecorded() public view {
        assertEq(registry.DEPLOYER(), address(this));
    }

    function test_RevertWhen_HashIsZero() public {
        vm.expectRevert(bytes("SimpleRegistry: empty hash"));
        registry.register(bytes32(0), "label");
    }

    function test_RevertWhen_HashAlreadyRegistered() public {
        vm.prank(alice);
        registry.register(HASH_A, "first");

        vm.prank(bob); // even a different user can't re-register the same document
        vm.expectRevert(bytes("SimpleRegistry: already registered"));
        registry.register(HASH_A, "second");
    }

    function test_RevertWhen_LabelEmpty() public {
        vm.expectRevert(bytes("SimpleRegistry: bad label"));
        registry.register(HASH_A, "");
    }

    function test_LabelAtMaxLengthIsAccepted() public {
        string memory label = string(new bytes(registry.MAX_LABEL_LENGTH())); // boundary: exactly 64
        registry.register(HASH_A, label);
        assertEq(registry.recordCount(), 1);
    }

    function test_RevertWhen_LabelTooLong() public {
        string memory label = string(new bytes(registry.MAX_LABEL_LENGTH() + 1)); // boundary + 1
        vm.expectRevert(bytes("SimpleRegistry: bad label"));
        registry.register(HASH_A, label);
    }

    // ------------------------------------------------------------- retire

    function test_OwnerCanRetire() public {
        vm.startPrank(alice);
        uint256 id = registry.register(HASH_A, "A");

        vm.expectEmit(true, true, false, false, address(registry));
        emit RecordRetired(id, alice);
        registry.retire(id);
        vm.stopPrank();

        assertFalse(registry.isActive(HASH_A));
        assertEq(uint8(registry.getRecord(id).status), uint8(SimpleRegistry.Status.Retired));
    }

    function test_RevertWhen_NonOwnerRetires() public {
        vm.prank(alice);
        uint256 id = registry.register(HASH_A, "A");

        vm.prank(bob);
        vm.expectRevert(bytes("SimpleRegistry: not owner"));
        registry.retire(id);
    }

    function test_RevertWhen_RetireTwice() public {
        vm.startPrank(alice);
        uint256 id = registry.register(HASH_A, "A");
        registry.retire(id);
        vm.expectRevert(bytes("SimpleRegistry: already retired"));
        registry.retire(id);
        vm.stopPrank();
    }

    function test_RevertWhen_RetireUnknownId() public {
        vm.expectRevert(bytes("SimpleRegistry: unknown id"));
        registry.retire(42);
    }

    // ----------------------------------------------------------- transfer

    function test_OwnerCanTransfer() public {
        vm.prank(alice);
        uint256 id = registry.register(HASH_A, "A");

        vm.expectEmit(true, true, true, false, address(registry));
        emit RecordTransferred(id, alice, bob);
        vm.prank(alice);
        registry.transferRecord(id, bob);

        assertEq(registry.getRecord(id).owner, bob);
        assertEq(registry.recordsOf(bob).length, 1);

        // the old owner has lost control
        vm.prank(alice);
        vm.expectRevert(bytes("SimpleRegistry: not owner"));
        registry.retire(id);
    }

    function test_RevertWhen_TransferToZeroAddress() public {
        vm.startPrank(alice);
        uint256 id = registry.register(HASH_A, "A");
        vm.expectRevert(bytes("SimpleRegistry: zero address"));
        registry.transferRecord(id, address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_TransferToSelf() public {
        vm.startPrank(alice);
        uint256 id = registry.register(HASH_A, "A");
        vm.expectRevert(bytes("SimpleRegistry: self transfer"));
        registry.transferRecord(id, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_NonOwnerTransfers() public {
        vm.prank(alice);
        uint256 id = registry.register(HASH_A, "A");
        vm.prank(bob);
        vm.expectRevert(bytes("SimpleRegistry: not owner"));
        registry.transferRecord(id, bob);
    }

    // -------------------------------------------------------------- views

    function test_RevertWhen_GetUnknownRecord() public {
        vm.expectRevert(bytes("SimpleRegistry: unknown id"));
        registry.getRecord(0); // id 0 is never valid
    }

    function test_IsActiveFalseForUnknownHash() public view {
        assertFalse(registry.isActive(HASH_B));
    }

    // --------------------------------------------------------------- fuzz

    /// @dev Foundry calls this with 1000 random (hash, caller) pairs.
    function testFuzz_RegisterAnyNonZeroHash(bytes32 documentHash, address caller) public {
        vm.assume(documentHash != bytes32(0)); // skip inputs we know are invalid
        vm.prank(caller);
        uint256 id = registry.register(documentHash, "fuzz");

        assertEq(registry.idByHash(documentHash), id);
        assertEq(registry.getRecord(id).owner, caller);
        assertTrue(registry.isActive(documentHash));
    }

    function testFuzz_LabelLengthBoundary(uint8 length) public {
        string memory label = string(new bytes(length));
        if (length == 0 || length > registry.MAX_LABEL_LENGTH()) {
            vm.expectRevert(bytes("SimpleRegistry: bad label"));
        }
        registry.register(HASH_A, label);
    }
}
