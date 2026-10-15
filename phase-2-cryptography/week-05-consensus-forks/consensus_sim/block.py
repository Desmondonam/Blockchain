"""Blocks for the consensus simulator, with optional proof-of-work."""

import hashlib
import json
from dataclasses import dataclass, replace

ZERO_HASH = "0" * 64


@dataclass(frozen=True)
class Block:
    height: int
    parent_hash: str
    producer: str
    records: tuple[str, ...]
    timestamp: int
    difficulty_bits: int = 0  # PoW: required leading zero bits in the hash
    nonce: int = 0

    def header(self) -> dict[str, object]:
        return {
            "height": self.height,
            "parent_hash": self.parent_hash,
            "producer": self.producer,
            "records": list(self.records),
            "timestamp": self.timestamp,
            "difficulty_bits": self.difficulty_bits,
            "nonce": self.nonce,
        }

    @property
    def hash(self) -> str:
        data = json.dumps(self.header(), sort_keys=True, separators=(",", ":")).encode()
        return hashlib.sha256(data).hexdigest()

    @property
    def work(self) -> int:
        """Expected hashes needed to find this block: 2^difficulty_bits."""
        return 2**self.difficulty_bits


GENESIS = Block(height=0, parent_hash=ZERO_HASH, producer="genesis", records=(), timestamp=0)


def meets_target(block: Block) -> bool:
    """True if the block hash has at least ``difficulty_bits`` leading zero bits."""
    return int(block.hash, 16) < 2 ** (256 - block.difficulty_bits)


@dataclass(frozen=True)
class MiningResult:
    block: Block
    attempts: int


def mine(template: Block, max_attempts: int = 10_000_000) -> MiningResult:
    """Brute-force nonces until the hash meets the target. This *is* proof of work."""
    for nonce in range(max_attempts):
        candidate = replace(template, nonce=nonce)
        if meets_target(candidate):
            return MiningResult(candidate, nonce + 1)
    raise RuntimeError("no valid nonce found; lower the difficulty")
