"""A node's view of the chain: every known block, plus a fork-choice rule.

Nodes don't store "the chain". They store a **tree** of blocks and pick
the branch with the most cumulative work as canonical. When a heavier branch
shows up, the node **reorganizes**: it rolls back to the common ancestor and
applies the new branch.
"""

from dataclasses import dataclass, field
from enum import Enum

from .block import GENESIS, Block, meets_target


class AddStatus(Enum):
    EXTENDED = "extended"  # new block on top of our head
    SIDE_BRANCH = "side-branch"  # valid but on a lighter fork
    REORG = "reorg"  # a different branch became heavier: head switched
    ORPHAN = "orphan"  # parent unknown; stored until the parent arrives
    DUPLICATE = "duplicate"


class InvalidBlock(ValueError):
    pass


@dataclass(frozen=True)
class Reorg:
    common_ancestor: str
    removed: tuple[Block, ...]  # old canonical blocks, now abandoned
    added: tuple[Block, ...]  # new canonical blocks

    @property
    def depth(self) -> int:
        return len(self.removed)


@dataclass
class AddResult:
    status: AddStatus
    reorgs: list[Reorg] = field(default_factory=list)


class BlockTree:
    def __init__(self, genesis: Block = GENESIS, min_difficulty_bits: int = 0) -> None:
        self.min_difficulty_bits = min_difficulty_bits
        self._blocks: dict[str, Block] = {genesis.hash: genesis}
        self._total_work: dict[str, int] = {genesis.hash: 0}
        self._orphans: dict[str, list[Block]] = {}
        self._genesis = genesis.hash
        self.head = genesis.hash

    # ----------------------------------------------------------------- queries
    def __contains__(self, block_hash: str) -> bool:
        return block_hash in self._blocks

    def get(self, block_hash: str) -> Block:
        return self._blocks[block_hash]

    @property
    def head_block(self) -> Block:
        return self._blocks[self.head]

    def all_blocks(self) -> list[Block]:
        return list(self._blocks.values())

    def total_work(self, block_hash: str) -> int:
        return self._total_work[block_hash]

    def canonical_chain(self) -> list[Block]:
        chain, cursor = [], self.head
        while True:
            block = self._blocks[cursor]
            chain.append(block)
            if cursor == self._genesis:
                return chain[::-1]
            cursor = block.parent_hash

    def is_canonical(self, block_hash: str) -> bool:
        return any(b.hash == block_hash for b in self.canonical_chain())

    def confirmations(self, block_hash: str) -> int:
        """1 = in the head block; 0 = not on the canonical chain (pending or reorged out)."""
        if not self.is_canonical(block_hash):
            return 0
        return self.head_block.height - self._blocks[block_hash].height + 1

    def is_final(self, block_hash: str, depth: int) -> bool:
        """Probabilistic finality: accept once buried under ``depth`` blocks."""
        return self.confirmations(block_hash) >= depth

    def find_record(self, record: str) -> Block | None:
        """Canonical block containing ``record``, if any."""
        return next((b for b in self.canonical_chain() if record in b.records), None)

    # ---------------------------------------------------------------- mutation
    def add(self, block: Block) -> AddResult:
        if block.hash in self._blocks:
            return AddResult(AddStatus.DUPLICATE)
        if block.parent_hash not in self._blocks:
            self._orphans.setdefault(block.parent_hash, []).append(block)
            return AddResult(AddStatus.ORPHAN)

        result = self._connect(block)
        # The new block may be the missing parent of orphans we stored earlier.
        pending = list(self._orphans.pop(block.hash, []))
        while pending:
            child = pending.pop(0)
            try:
                child_result = self._connect(child)
            except InvalidBlock:
                continue  # drop invalid orphans (and, implicitly, their descendants)
            result.reorgs.extend(child_result.reorgs)
            if result.reorgs:
                result.status = AddStatus.REORG
            elif child_result.status is AddStatus.EXTENDED:
                result.status = AddStatus.EXTENDED
            pending.extend(self._orphans.pop(child.hash, []))
        return result

    def _validate(self, block: Block, parent: Block) -> None:
        if block.height != parent.height + 1:
            raise InvalidBlock(f"height {block.height} does not follow parent {parent.height}")
        if block.timestamp < parent.timestamp:
            raise InvalidBlock("timestamp earlier than parent")
        if block.difficulty_bits < self.min_difficulty_bits:
            raise InvalidBlock("difficulty below network minimum")
        if not meets_target(block):
            raise InvalidBlock("proof of work does not meet target")

    def _connect(self, block: Block) -> AddResult:
        parent = self._blocks[block.parent_hash]
        self._validate(block, parent)
        self._blocks[block.hash] = block
        self._total_work[block.hash] = self._total_work[parent.hash] + block.work

        # Fork choice: strictly more work wins. Ties keep the first-seen head,
        # which is what Bitcoin Core does.
        if self._total_work[block.hash] <= self._total_work[self.head]:
            return AddResult(AddStatus.SIDE_BRANCH)
        if block.parent_hash == self.head:
            self.head = block.hash
            return AddResult(AddStatus.EXTENDED)
        reorg = self._reorg_to(block.hash)
        return AddResult(AddStatus.REORG, [reorg])

    def _ancestors(self, block_hash: str) -> list[str]:
        path = [block_hash]
        while path[-1] != self._genesis:
            path.append(self._blocks[path[-1]].parent_hash)
        return path

    def _reorg_to(self, new_head: str) -> Reorg:
        old_path = self._ancestors(self.head)
        new_path = self._ancestors(new_head)
        old_set = set(old_path)
        ancestor = next(h for h in new_path if h in old_set)
        removed = tuple(self._blocks[h] for h in old_path[: old_path.index(ancestor)])[::-1]
        added = tuple(self._blocks[h] for h in new_path[: new_path.index(ancestor)])[::-1]
        self.head = new_head
        return Reorg(ancestor, removed, added)
