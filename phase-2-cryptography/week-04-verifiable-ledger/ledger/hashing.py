"""Hash functions used by the ledger.

We use well-vetted library implementations. Never write your own hash or
signature algorithm for production.
"""

import hashlib
import json
from typing import Any

from Crypto.Hash import keccak


def sha256(data: bytes) -> bytes:
    """SHA-256 (Bitcoin's hash). Returns 32 raw bytes."""
    return hashlib.sha256(data).digest()


def keccak256(data: bytes) -> bytes:
    """Keccak-256 (Ethereum's hash). Returns 32 raw bytes.

    WARNING: this is NOT ``hashlib.sha3_256``. NIST changed the padding when
    it standardized SHA-3, so the two give different outputs. Ethereum uses
    the original Keccak. Using sha3_256 by mistake produces wrong addresses
    and wrong function selectors.
    """
    h = keccak.new(digest_bits=256)
    h.update(data)
    return h.digest()


def canonical_json(data: Any) -> bytes:
    """Deterministic serialization: sorted keys, no whitespace."""
    return json.dumps(data, sort_keys=True, separators=(",", ":")).encode()
