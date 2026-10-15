// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRegistry} from "./interfaces/IRegistry.sol";
import {Owned} from "./access/Owned.sol";
import {LabelLib} from "./libraries/LabelLib.sol";

/// @title ModularRegistry: Week 6's registry refactored into reusable parts
/// @notice Same user features as SimpleRegistry, plus an admin `freeze` for disputes.
/// @dev Composition map:
///      - IRegistry  → public API, errors, events (what)
///      - Owned      → admin authorization (who)
///      - LabelLib   → input validation (rules)
///      - this file  → state and business logic (how)
contract ModularRegistry is IRegistry, Owned {
    using LabelLib for string; // enables `label.validate()` syntax

    uint256 public recordCount;
    mapping(uint256 => Record) private _records;
    mapping(bytes32 => uint256) public override idByHash;

    constructor(address initialOwner) Owned(initialOwner) {}

    // -------------------------------------------------------------- modifiers

    modifier onlyRecordOwner(uint256 id) {
        _checkRecordOwner(id);
        _;
    }

    modifier inStatus(uint256 id, Status required) {
        _checkStatus(id, required);
        _;
    }

    // ------------------------------------------------------- user functions

    /// @inheritdoc IRegistry
    function register(bytes32 documentHash, string calldata label)
        external
        override
        returns (uint256 id)
    {
        if (documentHash == bytes32(0)) revert EmptyHash();
        uint256 existing = idByHash[documentHash];
        if (existing != 0) revert AlreadyRegistered(documentHash, existing);
        label.validate();

        id = ++recordCount;
        _records[id] = Record({
            owner: msg.sender,
            status: Status.Active,
            registeredAt: uint64(block.timestamp),
            documentHash: documentHash,
            label: label
        });
        idByHash[documentHash] = id;
        emit RecordRegistered(id, msg.sender, documentHash, label);
    }

    /// @inheritdoc IRegistry
    function retire(uint256 id) external override onlyRecordOwner(id) inStatus(id, Status.Active) {
        _records[id].status = Status.Retired;
        emit RecordRetired(id, msg.sender);
    }

    /// @inheritdoc IRegistry
    /// @dev Frozen records can't be transferred: `inStatus(Active)` blocks it.
    function transferRecord(uint256 id, address to)
        external
        override
        onlyRecordOwner(id)
        inStatus(id, Status.Active)
    {
        if (to == address(0) || to == msg.sender) revert InvalidRecipient(to);
        _records[id].owner = to;
        emit RecordTransferred(id, msg.sender, to);
    }

    // ------------------------------------------------------ admin functions

    /// @notice Freeze a disputed record. Only the contract owner can do this.
    /// @dev This is a PRIVILEGED power. Document it as a trust assumption for users.
    function freeze(uint256 id) external onlyOwner inStatus(id, Status.Active) {
        _records[id].status = Status.Frozen;
        emit RecordFrozen(id, msg.sender);
    }

    function unfreeze(uint256 id) external onlyOwner inStatus(id, Status.Frozen) {
        _records[id].status = Status.Active;
        emit RecordUnfrozen(id, msg.sender);
    }

    // ----------------------------------------------------------------- views

    /// @inheritdoc IRegistry
    function getRecord(uint256 id) external view override returns (Record memory) {
        Record storage record = _records[id];
        if (record.status == Status.None) revert UnknownRecord(id);
        return record; // copied from storage to memory for return
    }

    /// @inheritdoc IRegistry
    function isActive(bytes32 documentHash) external view override returns (bool) {
        uint256 id = idByHash[documentHash];
        return id != 0 && _records[id].status == Status.Active;
    }

    // -------------------------------------------------------------- internal

    function _checkRecordOwner(uint256 id) internal view {
        Record storage record = _records[id];
        if (record.status == Status.None) revert UnknownRecord(id);
        if (record.owner != msg.sender) revert NotRecordOwner(id, msg.sender);
    }

    function _checkStatus(uint256 id, Status required) internal view {
        Status current = _records[id].status;
        if (current == Status.None) revert UnknownRecord(id);
        if (current != required) revert InvalidStatus(id, current);
    }
}
