// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    IAccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";

contract RoleRegistryTest is Test {
    RoleRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal registrar = makeAddr("registrar");
    address internal pauser = makeAddr("pauser");
    address internal stranger = makeAddr("stranger");

    uint48 internal constant DELAY = 1 days;
    bytes32 internal constant DOC = keccak256("salt|transcript");

    bytes32 internal registrarRole;
    bytes32 internal pauserRole;
    bytes32 internal adminRole;

    function setUp() public {
        vm.warp(1_700_000_000);
        registry = new RoleRegistry(DELAY, admin);
        registrarRole = registry.REGISTRAR_ROLE();
        pauserRole = registry.PAUSER_ROLE();
        adminRole = registry.DEFAULT_ADMIN_ROLE();

        vm.startPrank(admin);
        registry.grantRole(registrarRole, registrar);
        registry.grantRole(pauserRole, pauser);
        vm.stopPrank();
    }

    function _unauthorized(address who, bytes32 role) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, who, role
            );
    }

    // ============================================================ ROLE MATRIX
    //
    //               register   revoke   pause   unpause   grantRole
    //  admin           ✘         ✘        ✘        ✔          ✔
    //  registrar       ✔         ✔        ✘        ✘          ✘
    //  pauser          ✘         ✘        ✔        ✘          ✘
    //  stranger        ✘         ✘        ✘        ✘          ✘
    //
    // Note the admin can't register. Least privilege: governance doesn't do daily operations.

    function test_Matrix_Register() public {
        address[3] memory denied = [admin, pauser, stranger];
        for (uint256 i; i < denied.length; ++i) {
            vm.prank(denied[i]);
            vm.expectRevert(_unauthorized(denied[i], registrarRole));
            registry.register(DOC);
        }
        vm.prank(registrar);
        registry.register(DOC);
        assertTrue(registry.isValid(DOC));
    }

    function test_Matrix_Revoke() public {
        vm.prank(registrar);
        registry.register(DOC);

        address[3] memory denied = [admin, pauser, stranger];
        for (uint256 i; i < denied.length; ++i) {
            vm.prank(denied[i]);
            vm.expectRevert(_unauthorized(denied[i], registrarRole));
            registry.revoke(DOC, "FRAUD");
        }
        vm.prank(registrar);
        registry.revoke(DOC, "FRAUD");
        assertFalse(registry.isValid(DOC));
    }

    function test_Matrix_Pause() public {
        address[3] memory denied = [admin, registrar, stranger];
        for (uint256 i; i < denied.length; ++i) {
            vm.prank(denied[i]);
            vm.expectRevert(_unauthorized(denied[i], pauserRole));
            registry.pause();
        }
        vm.prank(pauser);
        registry.pause();
        assertTrue(registry.paused());
    }

    function test_Matrix_Unpause() public {
        vm.prank(pauser);
        registry.pause();

        address[3] memory denied = [pauser, registrar, stranger];
        for (uint256 i; i < denied.length; ++i) {
            vm.prank(denied[i]);
            vm.expectRevert(_unauthorized(denied[i], adminRole));
            registry.unpause();
        }
        vm.prank(admin);
        registry.unpause();
        assertFalse(registry.paused());
    }

    function test_Matrix_GrantRole() public {
        address[3] memory denied = [registrar, pauser, stranger];
        for (uint256 i; i < denied.length; ++i) {
            vm.prank(denied[i]);
            vm.expectRevert(_unauthorized(denied[i], adminRole));
            registry.grantRole(registrarRole, stranger);
        }
    }

    // ========================================================= PAUSE BEHAVIOUR

    function test_PauseBlocksWrites() public {
        vm.prank(pauser);
        registry.pause();

        vm.startPrank(registrar);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        registry.register(DOC);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        registry.revoke(DOC, "X");
        vm.stopPrank();
    }

    function test_ReadsWorkWhilePaused() public {
        vm.prank(registrar);
        registry.register(DOC);
        vm.prank(pauser);
        registry.pause();

        assertTrue(registry.isValid(DOC), "verification keeps working during an incident");
        assertEq(registry.getDocument(DOC).registrar, registrar);
    }

    function test_RevertWhen_PauseTwice() public {
        vm.startPrank(pauser);
        registry.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        registry.pause();
        vm.stopPrank();
    }

    function test_RevertWhen_UnpauseWhileRunning() public {
        vm.prank(admin);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        registry.unpause();
    }

    // ===================================================== DOCUMENT LIFECYCLE

    function test_RegisterRecordsAccountability() public {
        vm.prank(registrar);
        registry.register(DOC);
        RoleRegistry.Document memory d = registry.getDocument(DOC);
        assertEq(d.registrar, registrar);
        assertEq(d.registeredAt, 1_700_000_000);
        assertEq(registry.activeCount(), 1);
    }

    function test_RevokeRecordsTimeAndReason() public {
        vm.prank(registrar);
        registry.register(DOC);
        vm.warp(1_700_000_500);

        vm.expectEmit(true, true, false, true, address(registry));
        emit RoleRegistry.DocumentRevoked(DOC, registrar, "DEGREE_RESCINDED");
        vm.prank(registrar);
        registry.revoke(DOC, "DEGREE_RESCINDED");

        assertEq(registry.getDocument(DOC).revokedAt, 1_700_000_500);
        assertEq(registry.activeCount(), 0);
    }

    function test_RevertWhen_RegisterTwiceEvenAfterRevoke() public {
        vm.startPrank(registrar);
        registry.register(DOC);
        registry.revoke(DOC, "X");
        vm.expectRevert(abi.encodeWithSelector(RoleRegistry.AlreadyRegistered.selector, DOC));
        registry.register(DOC); // revoked hashes can't be "un-revoked" by re-registering
        vm.stopPrank();
    }

    function test_RevertWhen_RevokeUnknownOrTwice() public {
        vm.startPrank(registrar);
        vm.expectRevert(abi.encodeWithSelector(RoleRegistry.NotRegistered.selector, DOC));
        registry.revoke(DOC, "X");
        registry.register(DOC);
        registry.revoke(DOC, "X");
        vm.expectRevert(abi.encodeWithSelector(RoleRegistry.AlreadyRevoked.selector, DOC));
        registry.revoke(DOC, "X");
        vm.stopPrank();
    }

    function test_RevertWhen_EmptyHash() public {
        vm.prank(registrar);
        vm.expectRevert(RoleRegistry.EmptyHash.selector);
        registry.register(bytes32(0));
    }

    // ======================================================= ROLE MANAGEMENT

    function test_RevokedRegistrarLosesAccess() public {
        vm.prank(admin);
        registry.revokeRole(registrarRole, registrar);
        vm.prank(registrar);
        vm.expectRevert(_unauthorized(registrar, registrarRole));
        registry.register(DOC);
    }

    function test_RegistrarCanRenounceOwnRole() public {
        vm.prank(registrar);
        registry.renounceRole(registrarRole, registrar); // e.g. a staff member leaving
        assertFalse(registry.hasRole(registrarRole, registrar));
    }

    function test_AdminRoleCannotBeGrantedDirectly() public {
        // DefaultAdminRules forbids grantRole(DEFAULT_ADMIN_ROLE): there's exactly ONE admin,
        // and it can only change through the delayed two-step transfer.
        vm.prank(admin);
        vm.expectRevert(
            IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminRules.selector
        );
        registry.grantRole(adminRole, stranger);
    }

    function test_AdminTransferIsTwoStepAndDelayed() public {
        address newAdmin = makeAddr("new-multisig");
        vm.prank(admin);
        registry.beginDefaultAdminTransfer(newAdmin);

        (, uint48 schedule) = registry.pendingDefaultAdmin();
        assertEq(schedule, block.timestamp + DELAY);

        // Too early: the delay gives everyone time to notice a malicious or mistaken transfer.
        vm.warp(schedule - 1);
        vm.prank(newAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminDelay.selector,
                schedule
            )
        );
        registry.acceptDefaultAdminTransfer();

        // Someone other than the nominee can never accept.
        vm.warp(schedule + 1);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlInvalidDefaultAdmin.selector, stranger
            )
        );
        registry.acceptDefaultAdminTransfer();

        vm.prank(newAdmin);
        registry.acceptDefaultAdminTransfer();
        assertEq(registry.defaultAdmin(), newAdmin);
        assertFalse(registry.hasRole(adminRole, admin), "old admin is out");
    }

    function test_AdminCanCancelTransfer() public {
        address newAdmin = makeAddr("typo-address");
        vm.startPrank(admin);
        registry.beginDefaultAdminTransfer(newAdmin);
        registry.cancelDefaultAdminTransfer();
        vm.stopPrank();
        (address pending,) = registry.pendingDefaultAdmin();
        assertEq(pending, address(0));
    }

    // ================================================================= FUZZ

    function testFuzz_OnlyRegistrarsRegister(address caller, bytes32 doc) public {
        vm.assume(doc != bytes32(0));
        bool allowed = registry.hasRole(registrarRole, caller);
        vm.prank(caller);
        if (!allowed) vm.expectRevert(_unauthorized(caller, registrarRole));
        registry.register(doc);
        assertEq(registry.isValid(doc), allowed);
    }

    function testFuzz_ActiveCountMatchesOperations(uint8 registrations, uint8 revocations) public {
        uint256 regs = bound(registrations, 0, 30);
        uint256 revs = bound(revocations, 0, regs);
        vm.startPrank(registrar);
        for (uint256 i; i < regs; ++i) {
            registry.register(keccak256(abi.encode(i)));
        }
        for (uint256 i; i < revs; ++i) {
            registry.revoke(keccak256(abi.encode(i)), "X");
        }
        vm.stopPrank();
        assertEq(registry.activeCount(), regs - revs);
    }
}
