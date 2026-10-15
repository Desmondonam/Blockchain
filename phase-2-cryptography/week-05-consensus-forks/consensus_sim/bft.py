"""Byzantine Fault Tolerance arithmetic (PBFT / Tendermint style).

With n validators of which up to f are Byzantine (arbitrarily malicious),
safety requires n >= 3f + 1, and a block commits with a quorum of
floor(2n/3) + 1 votes. Any two quorums then overlap in at least f + 1
validators, so at least one honest validator is in both, and an honest
validator never votes for two conflicting blocks.
"""

from collections import Counter


def max_faulty(n: int) -> int:
    """Largest f such that n >= 3f + 1."""
    if n < 1:
        raise ValueError("need at least one validator")
    return (n - 1) // 3


def quorum(n: int) -> int:
    return (2 * n) // 3 + 1


def quorum_overlap(n: int) -> int:
    """Minimum number of validators shared by any two quorums."""
    return 2 * quorum(n) - n


def is_safe(n: int, f: int) -> bool:
    """Two conflicting commits are impossible if quorums overlap in > f validators."""
    return quorum_overlap(n) > f


def is_live(n: int, f: int) -> bool:
    """The n - f honest validators can still form a quorum if the f faulty ones go silent."""
    return quorum(n) <= n - f


def tolerates(n: int, f: int) -> bool:
    """Safe AND live. Holds exactly when n >= 3f + 1 (property-tested)."""
    return is_safe(n, f) and is_live(n, f)


def committed_block(votes: dict[str, str], n: int) -> str | None:
    """The block hash with >= quorum(n) votes, or None (no decision yet: liveness, not safety)."""
    if not votes:
        return None
    block, count = Counter(votes.values()).most_common(1)[0]
    return block if count >= quorum(n) else None
