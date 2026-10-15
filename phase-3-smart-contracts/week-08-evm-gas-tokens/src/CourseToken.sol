// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CourseToken: an ERC-20 fungible token with a hard supply cap
/// @notice Every unit is interchangeable, like money or reward points.
/// @dev We INHERIT audited OpenZeppelin code instead of re-implementing ERC-20.
///      Our own code is ~10 lines, which is about the size you can review properly.
contract CourseToken is ERC20Capped, Ownable {
    /// @param initialOwner Account allowed to mint (use a multisig in production).
    /// @param cap_ Maximum total supply, in the smallest unit (18 decimals).
    constructor(address initialOwner, uint256 cap_)
        ERC20("Course Token", "CRS")
        ERC20Capped(cap_)
        Ownable(initialOwner)
    {}

    /// @notice Create new tokens. Reverts with `ERC20ExceededCap` past the cap.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
