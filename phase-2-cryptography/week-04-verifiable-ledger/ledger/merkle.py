"""Merkle trees with inclusion proofs.

Two security details that naive implementations get wrong:

1. **Domain separation.** Leaves are hashed as H(0x00 || data) and inner
   nodes as H(0x01 || left || right). Without the prefixes, an attacker can
   pass off an inner node (64 bytes) as a leaf: a second-preimage attack.
2. **Odd levels.** Bitcoin duplicates the last node on odd levels, which let
   two different tx lists produce the same root (CVE-2012-2459). Here we
   *promote* the lone node to the next level instead.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Literal

from .hashing import sha256

LEAF_PREFIX = b"\x00"
NODE_PREFIX = b"\x01"


def hash_leaf(data: bytes) -> bytes:
    return sha256(LEAF_PREFIX + data)


def hash_node(left: bytes, right: bytes) -> bytes:
    return sha256(NODE_PREFIX + left + right)


EMPTY_ROOT = sha256(b"")


@dataclass(frozen=True)
class ProofStep:
    sibling: bytes
    side: Literal["left", "right"]  # which side the SIBLING is on


class MerkleTree:
    def __init__(self, leaves: Sequence[bytes]) -> None:
        self._levels: list[list[bytes]] = [[hash_leaf(leaf) for leaf in leaves]]
        while len(self._levels[-1]) > 1:
            current = self._levels[-1]
            nxt = [hash_node(current[i], current[i + 1]) for i in range(0, len(current) - 1, 2)]
            if len(current) % 2 == 1:
                nxt.append(current[-1])  # promote the lone node unchanged
            self._levels.append(nxt)

    @property
    def root(self) -> bytes:
        return self._levels[-1][0] if self._levels[0] else EMPTY_ROOT

    def proof(self, index: int) -> list[ProofStep]:
        """Sibling hashes from leaf ``index`` up to the root: O(log n) of them."""
        if not 0 <= index < len(self._levels[0]):
            raise IndexError(f"leaf index {index} out of range")
        steps: list[ProofStep] = []
        for level in self._levels[:-1]:
            sibling_index = index ^ 1  # flip the last bit: 4<->5, 6<->7
            if sibling_index < len(level):
                side: Literal["left", "right"] = "left" if sibling_index < index else "right"
                steps.append(ProofStep(level[sibling_index], side))
            # if there's no sibling, the node was promoted, so add no step
            index //= 2
        return steps


def verify_proof(leaf: bytes, proof: Sequence[ProofStep], root: bytes) -> bool:
    """Recompute the root from one leaf and its proof. Needs no other leaves."""
    node = hash_leaf(leaf)
    for step in proof:
        node = hash_node(step.sibling, node) if step.side == "left" else hash_node(node, step.sibling)
    return node == root
