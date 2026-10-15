// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title LabelLib: reusable validation for short public labels
/// @notice A library with only `internal` functions is inlined into the calling contract
///         at compile time, so there's no separate deployment and no external call.
library LabelLib {
    uint256 internal constant MAX_LENGTH = 64;

    error InvalidLabelLength(uint256 length, uint256 max);
    error InvalidLabelCharacter(uint256 position, bytes1 character);

    /// @notice Revert unless `label` is 1..MAX_LENGTH bytes of printable ASCII (0x20..0x7E).
    /// @dev Restricting the character set blocks invisible/control characters and
    ///      look-alike Unicode in labels that frontends will display.
    function validate(string calldata label) internal pure {
        bytes calldata raw = bytes(label);
        uint256 length = raw.length;
        if (length == 0 || length > MAX_LENGTH) revert InvalidLabelLength(length, MAX_LENGTH);
        for (uint256 i; i < length; ++i) {
            bytes1 c = raw[i];
            if (c < 0x20 || c > 0x7E) revert InvalidLabelCharacter(i, c);
        }
    }

    /// @notice True if `label` would pass `validate`. Callable from other contracts' views.
    /// @dev Takes `memory` (not `calldata`) so callers can pass strings built in memory.
    function isValid(string memory label) internal pure returns (bool) {
        bytes memory raw = bytes(label);
        if (raw.length == 0 || raw.length > MAX_LENGTH) return false;
        for (uint256 i; i < raw.length; ++i) {
            if (raw[i] < 0x20 || raw[i] > 0x7E) return false;
        }
        return true;
    }
}
