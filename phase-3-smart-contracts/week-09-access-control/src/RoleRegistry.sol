// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title RoleRegistry: a role-controlled document registry with an emergency pause
/// @notice Only accounts with REGISTRAR_ROLE can register or revoke documents. A PAUSER can
///         halt all writes instantly in an emergency, but only the ADMIN can resume them.
/// @dev Trust model (keep it in sync with docs/THREAT_MODEL in the capstone):
///      - DEFAULT_ADMIN (multisig): grants/revokes roles, unpauses. Transfer is 2-step + delayed.
///      - REGISTRAR (institution hot wallet): registers and revokes documents.
///      - PAUSER (monitoring bot or on-call engineer): can ONLY pause. Low privilege, fast.
///      - Everyone: can read. Reads keep working while paused, so verification never stops.
contract RoleRegistry is AccessControlDefaultAdminRules, Pausable {
    // ------------------------------------------------------------------ roles
    // Role ids are keccak256 hashes of names: cheap to compare, impossible to collide by accident.

    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ------------------------------------------------------------------ types

    enum Status {
        None,
        Active,
        Revoked
    }

    struct Document {
        address registrar; // who registered it (accountability)
        Status status;
        uint64 registeredAt;
        uint64 revokedAt;
    }

    // ----------------------------------------------------------------- errors

    error EmptyHash();
    error AlreadyRegistered(bytes32 documentHash);
    error NotRegistered(bytes32 documentHash);
    error AlreadyRevoked(bytes32 documentHash);

    // ----------------------------------------------------------------- events

    event DocumentRegistered(bytes32 indexed documentHash, address indexed registrar);
    event DocumentRevoked(bytes32 indexed documentHash, address indexed registrar, bytes32 reason);

    // ------------------------------------------------------------------ state

    mapping(bytes32 => Document) private _documents;
    uint256 public activeCount;

    /// @param adminTransferDelay Seconds a new admin must wait before accepting (e.g. 1 day).
    /// @param admin Initial DEFAULT_ADMIN. Use a multisig (Safe) outside of local testing.
    constructor(uint48 adminTransferDelay, address admin)
        AccessControlDefaultAdminRules(adminTransferDelay, admin)
    {}

    // ------------------------------------------------------- registrar actions

    /// @notice Register a document fingerprint. REGISTRAR only, and not while paused.
    function register(bytes32 documentHash) external onlyRole(REGISTRAR_ROLE) whenNotPaused {
        if (documentHash == bytes32(0)) revert EmptyHash();
        Document storage doc = _documents[documentHash];
        if (doc.status != Status.None) revert AlreadyRegistered(documentHash);

        doc.registrar = msg.sender;
        doc.status = Status.Active;
        doc.registeredAt = uint64(block.timestamp);
        ++activeCount;
        emit DocumentRegistered(documentHash, msg.sender);
    }

    /// @notice Revoke a document. Any registrar can revoke (e.g. an institution's staff rotate).
    /// @param reason A short machine-readable code such as bytes32("FRAUD"). Never personal data.
    function revoke(bytes32 documentHash, bytes32 reason)
        external
        onlyRole(REGISTRAR_ROLE)
        whenNotPaused
    {
        Document storage doc = _documents[documentHash];
        if (doc.status == Status.None) revert NotRegistered(documentHash);
        if (doc.status == Status.Revoked) revert AlreadyRevoked(documentHash);

        doc.status = Status.Revoked;
        doc.revokedAt = uint64(block.timestamp);
        --activeCount;
        emit DocumentRevoked(documentHash, msg.sender, reason);
    }

    // -------------------------------------------------------- emergency stop

    /// @notice Halt all writes. Deliberately low-friction: one PAUSER key, no delay.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resume writes. Deliberately high-friction: only the DEFAULT_ADMIN (multisig).
    /// @dev Asymmetry on purpose. A compromised pauser key can cause downtime, but it can't
    ///      undo a pause the admins decided on, and it can't change any data.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ----------------------------------------------------------------- views
    // No `whenNotPaused` here: verification must keep working during an incident.

    function getDocument(bytes32 documentHash) external view returns (Document memory) {
        return _documents[documentHash];
    }

    function isValid(bytes32 documentHash) external view returns (bool) {
        return _documents[documentHash].status == Status.Active;
    }
}
