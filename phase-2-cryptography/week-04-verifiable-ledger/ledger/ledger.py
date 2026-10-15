"""A verifiable, append-only ledger of signed transactions.

``audit()`` doesn't just answer "valid?". It reports **where** and **why**
verification failed, so an operator can investigate.
"""

from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Any

from .hashing import canonical_json, keccak256
from .merkle import MerkleTree, ProofStep, verify_proof
from .transaction import Transaction, TransactionError

ZERO_HASH = "00" * 32


@dataclass(frozen=True)
class Block:
    index: int
    previous_hash: str
    timestamp: int
    transactions: tuple[Transaction, ...]
    merkle_root: str = field(default="")

    @staticmethod
    def compute_merkle_root(txs: Sequence[Transaction]) -> str:
        return MerkleTree([tx.tx_hash for tx in txs]).root.hex()

    @classmethod
    def create(cls, index: int, previous_hash: str, timestamp: int,
               transactions: Sequence[Transaction]) -> "Block":
        txs = tuple(transactions)
        return cls(index, previous_hash, timestamp, txs, cls.compute_merkle_root(txs))

    def header(self) -> dict[str, Any]:
        return {
            "index": self.index,
            "previous_hash": self.previous_hash,
            "timestamp": self.timestamp,
            "merkle_root": self.merkle_root,
        }

    @property
    def hash(self) -> str:
        return keccak256(canonical_json(self.header())).hex()

    def inclusion_proof(self, tx_index: int) -> list[ProofStep]:
        return MerkleTree([tx.tx_hash for tx in self.transactions]).proof(tx_index)


@dataclass(frozen=True)
class Finding:
    block_index: int
    tx_index: int | None
    problem: str


class Ledger:
    def __init__(self, chain_id: int) -> None:
        self.chain_id = chain_id
        self._blocks: list[Block] = [Block.create(0, ZERO_HASH, 0, ())]
        self._nonces: dict[str, int] = {}

    @property
    def blocks(self) -> tuple[Block, ...]:
        return tuple(self._blocks)

    def next_nonce(self, address: str) -> int:
        return self._nonces.get(address, 0)

    def append(self, transactions: Sequence[Transaction], timestamp: int) -> Block:
        """Validate every transaction (preconditions), then seal a new block."""
        nonces = dict(self._nonces)
        for tx in transactions:
            if not tx.verify():
                raise TransactionError(f"bad signature on tx from {tx.sender}")
            if tx.chain_id != self.chain_id:
                raise TransactionError(f"wrong chain_id {tx.chain_id} (replay from another chain?)")
            expected = nonces.get(tx.sender, 0)
            if tx.nonce != expected:
                raise TransactionError(f"{tx.sender}: expected nonce {expected}, got {tx.nonce}")
            nonces[tx.sender] = expected + 1
        head = self._blocks[-1]
        if timestamp < head.timestamp:
            raise ValueError("timestamp earlier than parent")
        block = Block.create(head.index + 1, head.hash, timestamp, transactions)
        self._blocks.append(block)
        self._nonces = nonces
        return block


def audit(blocks: Sequence[Block], chain_id: int) -> list[Finding]:
    """Check every signature, Merkle root and hash link. Empty list = clean."""
    findings: list[Finding] = []
    for i, block in enumerate(blocks):
        if block.index != i:
            findings.append(Finding(i, None, f"index is {block.index}, expected {i}"))
        expected_prev = ZERO_HASH if i == 0 else blocks[i - 1].hash
        if block.previous_hash != expected_prev:
            findings.append(Finding(i, None, "previous_hash does not match parent (history rewritten)"))
        if Block.compute_merkle_root(block.transactions) != block.merkle_root:
            findings.append(Finding(i, None, "merkle_root does not match transactions"))
        for j, tx in enumerate(block.transactions):
            if not tx.verify():
                findings.append(Finding(i, j, "signature invalid (tx altered or forged)"))
            if tx.chain_id != chain_id:
                findings.append(Finding(i, j, f"chain_id {tx.chain_id} != {chain_id}"))
    return findings


def prove_inclusion(tx: Transaction, proof: Sequence[ProofStep], merkle_root: str) -> bool:
    """What a light client does: verify one tx against a header it trusts."""
    return verify_proof(tx.tx_hash, proof, bytes.fromhex(merkle_root))
