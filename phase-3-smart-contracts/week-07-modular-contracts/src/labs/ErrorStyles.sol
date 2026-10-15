// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Two identical contracts that differ only in HOW they revert.
///         Compare their deployment size and revert gas in test/GasComparison.t.sol.
contract RequireStrings {
    address public immutable OWNER = msg.sender;

    function guarded() external view {
        require(msg.sender == OWNER, "RequireStrings: caller is not the owner of this contract");
    }
}

contract CustomErrors {
    error NotOwner(address caller);

    address public immutable OWNER = msg.sender;

    function guarded() external view {
        if (msg.sender != OWNER) revert NotOwner(msg.sender);
    }
}
