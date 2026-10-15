// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DocumentRegistry} from "../src/DocumentRegistry.sol";

contract DocumentRegistryTest is Test {
    DocumentRegistry internal reg;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    bytes32 internal constant H = keccak256("salt|doc");
    string internal constant URI = "docstore://5f2b9c0e";

    function setUp() public {
        reg = new DocumentRegistry();
    }

    function _register() internal returns (uint256 id) {
        vm.prank(alice);
        id = reg.register(H, "Lease agreement", URI);
    }

    function test_RegisterAndVerify() public {
        vm.expectEmit(true, true, true, true, address(reg));
        emit DocumentRegistry.RecordRegistered(1, alice, H, "Lease agreement", URI);
        uint256 id = _register();

        (bool exists, bool active, uint256 found) = reg.verify(H);
        assertTrue(exists && active);
        assertEq(found, id);
        DocumentRegistry.Record memory r = reg.getRecord(id);
        assertEq(r.uri, URI);
        assertEq(r.owner, alice);
    }

    function test_VerifyUnknownHash() public view {
        (bool exists, bool active, uint256 id) = reg.verify(keccak256("nope"));
        assertFalse(exists || active);
        assertEq(id, 0);
    }

    function test_RevertWhen_Duplicate() public {
        _register();
        vm.expectRevert(abi.encodeWithSelector(DocumentRegistry.AlreadyRegistered.selector, H, 1));
        reg.register(H, "again", "");
    }

    function test_RevertWhen_BadInputs() public {
        vm.expectRevert(DocumentRegistry.EmptyHash.selector);
        reg.register(bytes32(0), "x", "");
        vm.expectRevert(abi.encodeWithSelector(DocumentRegistry.InvalidLabel.selector, 0));
        reg.register(H, "", "");
        string memory longUri = string(new bytes(129));
        vm.expectRevert(abi.encodeWithSelector(DocumentRegistry.InvalidUri.selector, 129));
        reg.register(H, "x", longUri);
    }

    function test_RetireAndTransferRules() public {
        uint256 id = _register();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(DocumentRegistry.NotRecordOwner.selector, id, bob));
        reg.retire(id);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(DocumentRegistry.InvalidRecipient.selector, alice));
        reg.transferRecord(id, alice);
        reg.transferRecord(id, bob);
        vm.stopPrank();

        vm.startPrank(bob);
        reg.retire(id);
        vm.expectRevert(abi.encodeWithSelector(DocumentRegistry.RecordNotActive.selector, id));
        reg.transferRecord(id, alice);
        vm.stopPrank();

        (, bool active,) = reg.verify(H);
        assertFalse(active);
    }

    function test_RevertWhen_UnknownRecord() public {
        vm.expectRevert(abi.encodeWithSelector(DocumentRegistry.UnknownRecord.selector, 9));
        reg.getRecord(9);
    }

    function testFuzz_RegisterAnyHash(bytes32 h, address caller) public {
        vm.assume(h != bytes32(0));
        vm.prank(caller);
        uint256 id = reg.register(h, "fuzz", "");
        (bool exists, bool active, uint256 found) = reg.verify(h);
        assertTrue(exists && active);
        assertEq(found, id);
    }
}
