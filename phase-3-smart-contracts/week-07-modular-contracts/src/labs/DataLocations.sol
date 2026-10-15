// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title DataLocations: storage vs memory vs calldata, demonstrated
/// @notice Each function shows one behaviour. The tests prove what happens.
contract DataLocations {
    struct Item {
        uint256 value;
        string name;
    }

    Item public item = Item({value: 1, name: "original"});
    uint256[] public numbers;

    /// @notice `storage` reference: a POINTER to the contract's persistent state.
    function updateViaStoragePointer(uint256 newValue) external {
        Item storage ref = item;
        ref.value = newValue; // ✅ persists
    }

    /// @notice `memory` copy: a temporary copy that disappears after the call.
    function updateViaMemoryCopy(uint256 newValue) external view returns (uint256 copyValue) {
        Item memory copy = item;
        copy.value = newValue; // ❌ does NOT touch storage
        return copy.value;
    }

    /// @notice `calldata`: read-only view of the transaction input. The cheapest for externals.
    function sumCalldata(uint256[] calldata input) external pure returns (uint256 total) {
        for (uint256 i; i < input.length; ++i) {
            total += input[i];
        }
        // input[0] = 5;  ← compile error: calldata is read-only
    }

    /// @notice Same logic with `memory`: the input is first COPIED from calldata (more gas).
    function sumMemory(uint256[] memory input) external pure returns (uint256 total) {
        for (uint256 i; i < input.length; ++i) {
            total += input[i];
        }
    }

    /// @notice Assigning a storage array to memory copies it. Mutating the copy doesn't persist.
    function pushThenCopy(uint256 x)
        external
        returns (uint256 storageLength, uint256 memoryLength)
    {
        numbers.push(x);
        uint256[] memory snapshot = numbers;
        // snapshot.push(1);  ← compile error: memory arrays have fixed length
        snapshot[0] = 999; // only the copy changes
        return (numbers.length, snapshot.length);
    }
}
