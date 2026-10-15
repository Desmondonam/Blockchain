// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IRegistry: the public contract surface of a document registry
/// @notice Other contracts and the frontend depend on THIS interface, not on a concrete
///         implementation. That lets you swap, mock, or upgrade the implementation.
interface IRegistry {
    // ------------------------------------------------------------------ types

    enum Status {
        None,
        Active,
        Retired,
        Frozen
    }

    struct Record {
        address owner;
        Status status;
        uint64 registeredAt;
        bytes32 documentHash;
        string label;
    }

    // ----------------------------------------------------------------- errors
    // Custom errors (since 0.8.4) are cheaper than revert strings and carry typed data.

    error EmptyHash();
    error AlreadyRegistered(bytes32 documentHash, uint256 existingId);
    error UnknownRecord(uint256 id);
    error NotRecordOwner(uint256 id, address caller);
    error InvalidStatus(uint256 id, Status current);
    error InvalidRecipient(address to);

    // ----------------------------------------------------------------- events

    event RecordRegistered(
        uint256 indexed id, address indexed owner, bytes32 indexed documentHash, string label
    );
    event RecordRetired(uint256 indexed id, address indexed owner);
    event RecordTransferred(uint256 indexed id, address indexed from, address indexed to);
    event RecordFrozen(uint256 indexed id, address indexed by);
    event RecordUnfrozen(uint256 indexed id, address indexed by);

    // -------------------------------------------------------------- functions

    function register(bytes32 documentHash, string calldata label) external returns (uint256 id);
    function retire(uint256 id) external;
    function transferRecord(uint256 id, address to) external;
    function getRecord(uint256 id) external view returns (Record memory);
    function isActive(bytes32 documentHash) external view returns (bool);
    function idByHash(bytes32 documentHash) external view returns (uint256);
}
