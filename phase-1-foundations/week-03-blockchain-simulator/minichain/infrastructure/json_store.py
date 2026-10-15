"""Persist a chain to a JSON file.

This is infrastructure: it depends on the domain, and the domain does not
know it exists. Swapping JSON for SQLite later touches only this file.
"""

import json
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from ..domain.block import Block


class TamperedFileError(ValueError):
    """A stored block's recorded hash does not match its recomputed hash."""


def save_blocks(path: Path, blocks: Sequence[Block], genesis_balances: dict[str, int]) -> None:
    payload: dict[str, Any] = {
        "genesis_balances": genesis_balances,
        "blocks": [b.to_dict() for b in blocks],
    }
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def load_blocks(path: Path) -> tuple[list[Block], dict[str, int]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    blocks = [Block.from_dict(b) for b in payload["blocks"]]
    # Never trust a stored hash: always recompute it from the contents.
    for stored, block in zip(payload["blocks"], blocks):
        if stored["hash"] != block.hash:
            raise TamperedFileError(f"block {block.index}: stored hash does not match contents")
    return blocks, payload["genesis_balances"]
