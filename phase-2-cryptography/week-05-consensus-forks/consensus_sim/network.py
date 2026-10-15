"""A deterministic peer-to-peer network with partitions.

Real networks have latency and partitions. While nodes can't hear each other,
each side keeps producing blocks: a **fork**. When the partition heals, the
lighter side **reorganizes** onto the heavier side.
"""

from dataclasses import dataclass, field

from .block import Block, mine
from .blocktree import AddResult, BlockTree, Reorg


@dataclass
class Node:
    name: str
    tree: BlockTree = field(default_factory=BlockTree)
    reorg_log: list[Reorg] = field(default_factory=list)

    def receive(self, block: Block) -> AddResult:
        result = self.tree.add(block)
        self.reorg_log.extend(result.reorgs)
        return result


class Network:
    def __init__(self, node_names: list[str], min_difficulty_bits: int = 0) -> None:
        self.nodes = {n: Node(n, BlockTree(min_difficulty_bits=min_difficulty_bits)) for n in node_names}
        self._groups: list[set[str]] = [set(node_names)]

    # ---------------------------------------------------------- topology
    def partition(self, *groups: list[str]) -> None:
        flat = [n for g in groups for n in g]
        if sorted(flat) != sorted(self.nodes):
            raise ValueError("a partition must place every node in exactly one group")
        self._groups = [set(g) for g in groups]

    def heal(self) -> None:
        """Reconnect everyone, and let nodes sync the blocks they missed."""
        self._groups = [set(self.nodes)]
        everything: dict[str, Block] = {}
        for node in self.nodes.values():
            for block in node.tree.all_blocks():
                everything[block.hash] = block
        ordered = sorted(everything.values(), key=lambda b: b.height)
        for node in self.nodes.values():
            for block in ordered:
                node.receive(block)

    def peers_of(self, name: str) -> set[str]:
        return next(g for g in self._groups if name in g)

    # -------------------------------------------------------- block flow
    def produce(self, producer: str, records: tuple[str, ...] = (), difficulty_bits: int = 0) -> Block:
        """``producer`` mines on top of ITS OWN head, then gossips to reachable peers."""
        node = self.nodes[producer]
        parent = node.tree.head_block
        template = Block(
            height=parent.height + 1,
            parent_hash=parent.hash,
            producer=producer,
            records=records,
            timestamp=parent.timestamp + 12,
            difficulty_bits=difficulty_bits,
        )
        block = mine(template).block
        for peer in self.peers_of(producer):
            self.nodes[peer].receive(block)
        return block

    def heads(self) -> dict[str, str]:
        return {name: node.tree.head for name, node in self.nodes.items()}

    def in_consensus(self) -> bool:
        return len(set(self.heads().values())) == 1
