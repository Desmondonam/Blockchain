// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Owned: minimal two-step ownership (built by hand for learning)
/// @notice In production, prefer OpenZeppelin's `Ownable2Step` or `AccessControl`
///         (Week 9). We write it once ourselves to understand modifiers and inheritance.
/// @dev `abstract`: it can't be deployed alone and is meant to be inherited.
abstract contract Owned {
    error NotOwner(address caller);
    error NotPendingOwner(address caller);
    error ZeroAddressOwner();

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    address public owner;
    address public pendingOwner;

    /// @param initialOwner Usually a multisig in production, never a hot wallet.
    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddressOwner();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @dev A modifier wraps a function body. `_;` marks where the body runs.
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /// @dev Putting the logic in an internal function (not inline in the modifier) keeps
    ///      bytecode small, because modifier code is copied into every function using it.
    function _checkOwner() internal view {
        if (msg.sender != owner) revert NotOwner(msg.sender);
    }

    /// @notice Step 1: nominate a new owner. Nothing changes until they accept.
    /// @dev Two steps stop you handing control to a mistyped address forever.
    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @notice Step 2: the nominee proves they control the address by calling this.
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner(msg.sender);
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }
}
