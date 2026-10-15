// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title SimpleRegistry: Week 6, Solidity fundamentals
/// @author Blockchain Engineering Course
/// @notice Lets anyone register a document fingerprint (a hash) with a short label,
///         retire it, or hand ownership to someone else.
/// @dev Uses `require` with string messages on purpose. Week 7 refactors to custom
///      errors and measures the gas saved. Never store personal data here: everything
///      on a public chain is readable by anyone, including `private` variables.
contract SimpleRegistry {
    // ------------------------------------------------------------------ types

    /// @notice Lifecycle of a record. `None` (= 0) is the default for missing entries.
    enum Status {
        None,
        Active,
        Retired
    }

    /// @notice One registered document.
    /// @dev Field order matters for storage packing: `owner` (20 bytes) + `status`
    ///      (1 byte) + `registeredAt` (8 bytes) share one 32-byte slot. See Week 8.
    struct Record {
        address owner;
        Status status;
        uint64 registeredAt;
        bytes32 documentHash;
        string label;
    }

    // -------------------------------------------------------------- constants

    /// @notice Maximum label length in bytes. A `constant` costs no storage.
    uint256 public constant MAX_LABEL_LENGTH = 64;

    // ------------------------------------------------------------------ state

    /// @notice Address that deployed the contract. `immutable` is set once in the constructor.
    address public immutable DEPLOYER;

    /// @notice Number of records ever registered. IDs run from 1 to recordCount.
    uint256 public recordCount;

    /// @dev id => record. `private` only stops OTHER CONTRACTS reading it directly.
    ///      Anyone can still read the raw storage off-chain.
    mapping(uint256 => Record) private _records;

    /// @notice documentHash => id (0 means not registered). Prevents duplicates.
    mapping(bytes32 => uint256) public idByHash;

    /// @dev owner => list of record ids they currently or previously owned.
    mapping(address => uint256[]) private _recordsByOwner;

    // ----------------------------------------------------------------- events

    /// @notice Emitted when a record is created. `indexed` params can be filtered off-chain.
    event RecordRegistered(
        uint256 indexed id, address indexed owner, bytes32 indexed documentHash, string label
    );

    /// @notice Emitted when the owner retires a record.
    event RecordRetired(uint256 indexed id, address indexed owner);

    /// @notice Emitted when ownership of a record moves to a new address.
    event RecordTransferred(uint256 indexed id, address indexed from, address indexed to);

    // ------------------------------------------------------------ constructor

    constructor() {
        DEPLOYER = msg.sender;
    }

    // ------------------------------------------------------- write functions

    /// @notice Register a new document fingerprint.
    /// @param documentHash keccak256 of the (salted) document. Must be non-zero and unused.
    /// @param label Short public description, 1..MAX_LABEL_LENGTH bytes. No personal data!
    /// @return id The new record's id (starts at 1).
    function register(bytes32 documentHash, string calldata label) external returns (uint256 id) {
        // 1. CHECKS: validate every input before touching state.
        require(documentHash != bytes32(0), "SimpleRegistry: empty hash");
        require(idByHash[documentHash] == 0, "SimpleRegistry: already registered");
        uint256 labelLength = bytes(label).length;
        require(labelLength > 0 && labelLength <= MAX_LABEL_LENGTH, "SimpleRegistry: bad label");

        // 2. EFFECTS: update state.
        id = ++recordCount; // pre-increment: the first id is 1, so 0 can mean "missing"
        _records[id] = Record({
            owner: msg.sender,
            status: Status.Active,
            registeredAt: uint64(block.timestamp),
            documentHash: documentHash,
            label: label
        });
        idByHash[documentHash] = id;
        _recordsByOwner[msg.sender].push(id);

        // 3. Emit an event so off-chain apps can index the change cheaply.
        emit RecordRegistered(id, msg.sender, documentHash, label);
    }

    /// @notice Permanently retire a record you own. Retired records stay readable.
    function retire(uint256 id) external {
        Record storage record = _records[id]; // `storage` = a pointer, so writes persist
        require(record.status != Status.None, "SimpleRegistry: unknown id");
        require(record.owner == msg.sender, "SimpleRegistry: not owner");
        require(record.status == Status.Active, "SimpleRegistry: already retired");

        record.status = Status.Retired;
        emit RecordRetired(id, msg.sender);
    }

    /// @notice Give a record you own to another address.
    function transferRecord(uint256 id, address to) external {
        Record storage record = _records[id];
        require(record.status != Status.None, "SimpleRegistry: unknown id");
        require(record.owner == msg.sender, "SimpleRegistry: not owner");
        require(to != address(0), "SimpleRegistry: zero address");
        require(to != msg.sender, "SimpleRegistry: self transfer");

        record.owner = to;
        _recordsByOwner[to].push(id);
        emit RecordTransferred(id, msg.sender, to);
    }

    // -------------------------------------------------------- view functions

    /// @notice Full record by id. Reverts for unknown ids, so callers never get a fake zero record.
    function getRecord(uint256 id) external view returns (Record memory) {
        Record memory record = _records[id]; // `memory` = a copy
        require(record.status != Status.None, "SimpleRegistry: unknown id");
        return record;
    }

    /// @notice True if `documentHash` is registered and not retired.
    function isActive(bytes32 documentHash) external view returns (bool) {
        uint256 id = idByHash[documentHash];
        return id != 0 && _records[id].status == Status.Active;
    }

    /// @notice Record ids an address has ever received. Some may since have been transferred away.
    /// @dev Unbounded arrays are fine in VIEW functions (eth_call is free), but never loop
    ///      over one inside a state-changing function: that's a gas DoS risk (Week 14).
    function recordsOf(address owner) external view returns (uint256[] memory) {
        return _recordsByOwner[owner];
    }
}
