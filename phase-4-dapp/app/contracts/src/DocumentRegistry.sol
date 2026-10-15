// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title DocumentRegistry: the on-chain half of the Phase 4 dApp
/// @notice Stores a fingerprint of each document plus a pointer to where the (encrypted)
///         document lives off-chain. The chain answers "is this authentic and current?";
///         the off-chain indexer answers "show me everything Alice registered".
/// @dev There are deliberately NO per-owner arrays: listing and searching is the indexer's
///      job (Week 12). On-chain storage holds only what verification needs.
contract DocumentRegistry {
    enum Status {
        None,
        Active,
        Retired
    }

    struct Record {
        address owner;
        Status status;
        uint64 registeredAt;
        bytes32 documentHash;
        string label;
        string uri; // e.g. "ipfs://bafy..." or "docstore://<content-id>". Never a plain-text URL with PII.
    }

    error EmptyHash();
    error AlreadyRegistered(bytes32 documentHash, uint256 existingId);
    error UnknownRecord(uint256 id);
    error NotRecordOwner(uint256 id, address caller);
    error RecordNotActive(uint256 id);
    error InvalidRecipient(address to);
    error InvalidLabel(uint256 length);
    error InvalidUri(uint256 length);

    event RecordRegistered(
        uint256 indexed id, address indexed owner, bytes32 indexed documentHash, string label, string uri
    );
    event RecordRetired(uint256 indexed id, address indexed owner);
    event RecordTransferred(uint256 indexed id, address indexed from, address indexed to);

    uint256 public constant MAX_LABEL_LENGTH = 64;
    uint256 public constant MAX_URI_LENGTH = 128;

    uint256 public recordCount;
    mapping(uint256 => Record) private _records;
    mapping(bytes32 => uint256) public idByHash;

    /// @notice Register a document fingerprint with a label and an off-chain pointer.
    function register(bytes32 documentHash, string calldata label, string calldata uri) external returns (uint256 id) {
        if (documentHash == bytes32(0)) revert EmptyHash();
        uint256 existing = idByHash[documentHash];
        if (existing != 0) revert AlreadyRegistered(documentHash, existing);
        uint256 labelLength = bytes(label).length;
        if (labelLength == 0 || labelLength > MAX_LABEL_LENGTH) revert InvalidLabel(labelLength);
        if (bytes(uri).length > MAX_URI_LENGTH) revert InvalidUri(bytes(uri).length);

        id = ++recordCount;
        _records[id] = Record({
            owner: msg.sender,
            status: Status.Active,
            registeredAt: uint64(block.timestamp),
            documentHash: documentHash,
            label: label,
            uri: uri
        });
        idByHash[documentHash] = id;
        emit RecordRegistered(id, msg.sender, documentHash, label, uri);
    }

    /// @notice Retire a record you own. It stays readable, with status Retired.
    function retire(uint256 id) external {
        Record storage r = _ownedActive(id);
        r.status = Status.Retired;
        emit RecordRetired(id, msg.sender);
    }

    /// @notice Transfer an active record you own.
    function transferRecord(uint256 id, address to) external {
        Record storage r = _ownedActive(id);
        if (to == address(0) || to == msg.sender) revert InvalidRecipient(to);
        r.owner = to;
        emit RecordTransferred(id, msg.sender, to);
    }

    function getRecord(uint256 id) external view returns (Record memory) {
        Record storage r = _records[id];
        if (r.status == Status.None) revert UnknownRecord(id);
        return r;
    }

    /// @notice One-call verification for the frontend: (exists, active, id).
    function verify(bytes32 documentHash) external view returns (bool exists, bool active, uint256 id) {
        id = idByHash[documentHash];
        exists = id != 0;
        active = exists && _records[id].status == Status.Active;
    }

    function _ownedActive(uint256 id) private view returns (Record storage r) {
        r = _records[id];
        if (r.status == Status.None) revert UnknownRecord(id);
        if (r.owner != msg.sender) revert NotRecordOwner(id, msg.sender);
        if (r.status != Status.Active) revert RecordNotActive(id);
    }
}
