"""Blocks: batches of transactions linked by the previous block's hash."""

from dataclasses import dataclass
from typing import Any

from .hashing import hash_object
from .transaction import Transaction

GENESIS_PREVIOUS_HASH = "0" * 64


@dataclass(frozen=True)
class Block:
    index: int
    previous_hash: str
    timestamp: int
    proposer: str
    transactions: tuple[Transaction, ...]

    @property
    def tx_root(self) -> str:
        """Commitment to all transactions, in order.

        Week 3 hashes the list of tx IDs. Week 4 replaces this with a
        Merkle root so we can prove that one tx is included without sending
        the whole block.
        """
        return hash_object([tx.tx_id for tx in self.transactions])

    def header(self) -> dict[str, Any]:
        # The header commits to the transactions through tx_root, so the block
        # hash covers everything in the block.
        return {
            "index": self.index,
            "previous_hash": self.previous_hash,
            "timestamp": self.timestamp,
            "proposer": self.proposer,
            "tx_root": self.tx_root,
        }

    @property
    def hash(self) -> str:
        return hash_object(self.header())

    def to_dict(self) -> dict[str, Any]:
        return {
            **self.header(),
            "hash": self.hash,
            "transactions": [tx.to_dict() for tx in self.transactions],
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Block":
        return cls(
            index=data["index"],
            previous_hash=data["previous_hash"],
            timestamp=data["timestamp"],
            proposer=data["proposer"],
            transactions=tuple(Transaction.from_dict(t) for t in data["transactions"]),
        )
