"""Proof of Stake: stake-weighted proposer selection, equivocation and slashing.

In PoS, the right to propose comes from **locked stake**, not computation.
Misbehaviour is punished by destroying (slashing) part of that stake.
"""

import hashlib
from collections.abc import Iterable
from dataclasses import dataclass


class StakeError(ValueError):
    pass


def select_proposer(stakes: dict[str, int], seed: bytes, slot: int) -> str:
    """Pick a proposer with probability proportional to stake.

    Deterministic given ``(seed, slot)``, so every honest node computes the
    same answer without talking to the others. Ethereum derives its seed
    from RANDAO; here the caller supplies it.
    """
    active = {v: s for v, s in stakes.items() if s > 0}
    if not active:
        raise StakeError("no validator has stake")
    total = sum(active.values())
    digest = hashlib.sha256(seed + slot.to_bytes(8, "big")).digest()
    ticket = int.from_bytes(digest, "big") % total
    for validator in sorted(active):  # sorted, so every node walks the same order
        ticket -= active[validator]
        if ticket < 0:
            return validator
    raise AssertionError("unreachable")


@dataclass(frozen=True)
class SignedHeader:
    """A validator's signed claim: 'at ``slot`` I proposed/voted for ``block_hash``'."""

    validator: str
    slot: int
    block_hash: str


def find_equivocations(headers: Iterable[SignedHeader]) -> set[str]:
    """Validators who signed two DIFFERENT blocks for the same slot: slashable."""
    seen: dict[tuple[str, int], str] = {}
    offenders: set[str] = set()
    for h in headers:
        key = (h.validator, h.slot)
        if key in seen and seen[key] != h.block_hash:
            offenders.add(h.validator)
        seen.setdefault(key, h.block_hash)
    return offenders


def slash(stakes: dict[str, int], offenders: Iterable[str], penalty_bps: int) -> dict[str, int]:
    """Return new stakes with ``penalty_bps`` (basis points, 10000 = 100%) burned from offenders."""
    if not 0 <= penalty_bps <= 10_000:
        raise StakeError("penalty must be between 0 and 10000 basis points")
    updated = dict(stakes)
    for v in offenders:
        updated[v] -= updated[v] * penalty_bps // 10_000  # integer maths, rounding down
    return updated
