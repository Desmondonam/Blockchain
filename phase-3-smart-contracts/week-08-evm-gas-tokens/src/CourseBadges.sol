// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CourseBadges: ERC-1155 multi-token. Many token TYPES in one contract
/// @notice id 1 = "Phase 1 complete" (fungible: many holders), id 1000+ = unique awards.
///         One contract, one approval, and batch transfers save gas against many ERC-721s.
contract CourseBadges is ERC1155, Ownable {
    uint256 public constant PHASE_1 = 1;
    uint256 public constant PHASE_2 = 2;
    uint256 public constant PHASE_3 = 3;
    uint256 public constant CAPSTONE_DISTINCTION = 1000;

    /// @param uri_ Metadata URI template, e.g. "ipfs://<cid>/{id}.json" (clients replace {id}).
    constructor(address initialOwner, string memory uri_) ERC1155(uri_) Ownable(initialOwner) {}

    function award(address to, uint256 id, uint256 amount) external onlyOwner {
        _mint(to, id, amount, "");
    }

    /// @notice Award several badge types to one learner in a single transaction.
    function awardBatch(address to, uint256[] calldata ids, uint256[] calldata amounts)
        external
        onlyOwner
    {
        _mintBatch(to, ids, amounts, "");
    }
}
