// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title GasLab: pairs of functions that do the same thing at different gas costs
/// @notice Run `forge test --match-contract GasLabTest -vv` to see the numbers.
contract GasLab {
    // ------------------------------------------------------- storage packing
    // Each storage slot is 32 bytes. The compiler packs adjacent small fields together.

    struct Unpacked {
        uint64 issuedAt; // slot 0 (24 bytes wasted)
        uint256 amount; // slot 1
        uint64 expiresAt; // slot 2 (24 bytes wasted)
        address owner; // slot 3
    }

    struct PartlyPacked {
        uint64 issuedAt; // slot 0: 8 bytes
        uint64 expiresAt; //        + 8 bytes = 16 bytes
        address owner; // slot 1: 16 + 20 = 36 > 32, so it can't share slot 0
        uint256 amount; // slot 2
    }
    // Better: `address owner; uint64 issuedAt; uint32 expiresAt` = 32 bytes in ONE slot.

    struct TightlyPacked {
        address owner; // slot 0: 20 bytes
        uint64 issuedAt; //       + 8 bytes
        uint32 expiresAt; //      + 4 bytes = 32 bytes exactly
        uint256 amount; // slot 1
    }

    mapping(uint256 => Unpacked) public unpacked;
    mapping(uint256 => PartlyPacked) public partlyPacked;
    mapping(uint256 => TightlyPacked) public tight;

    function writeUnpacked(uint256 id) external {
        unpacked[id] = Unpacked({
            issuedAt: uint64(block.timestamp),
            amount: 1,
            expiresAt: uint64(block.timestamp + 1),
            owner: msg.sender
        });
    }

    function writePartlyPacked(uint256 id) external {
        partlyPacked[id] = PartlyPacked({
            issuedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + 1),
            owner: msg.sender,
            amount: 1
        });
    }

    function writeTight(uint256 id) external {
        tight[id] = TightlyPacked({
            owner: msg.sender,
            issuedAt: uint64(block.timestamp),
            expiresAt: uint32(block.timestamp + 1),
            amount: 1
        });
    }

    // --------------------------------------------------- caching storage reads
    uint256[] public values;
    uint256 public total;

    function seed(uint256 n) external {
        for (uint256 i; i < n; ++i) {
            values.push(i);
        }
    }

    /// @dev Reads `values.length` from storage every iteration and writes `total` every time.
    function sumNaive() external {
        for (uint256 i = 0; i < values.length; i++) {
            total += values[i];
        }
    }

    /// @dev Caches the length, accumulates in memory (the stack), writes storage ONCE.
    function sumCached() external {
        uint256[] storage v = values;
        uint256 length = v.length;
        uint256 acc;
        for (uint256 i; i < length;) {
            acc += v[i];
            unchecked {
                ++i; // can't overflow: i < length <= 2^256-1
            }
        }
        total += acc;
    }
}
