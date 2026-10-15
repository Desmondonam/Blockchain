"""Canonical serialization and hashing.

Two nodes must compute the *same* hash for the *same* data, so serialization
must be canonical: sorted keys, no whitespace, UTF-8. If one node writes
``{"a":1,"b":2}`` and another ``{"b": 2, "a": 1}``, their hashes differ and
the network can't agree.
"""

import hashlib
import json
from typing import Any


def canonical_json(data: Any) -> bytes:
    """Serialize ``data`` deterministically."""
    return json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def sha256_hex(data: bytes) -> str:
    """Return the SHA-256 digest of ``data`` as a 64-char hex string."""
    return hashlib.sha256(data).hexdigest()


def hash_object(data: Any) -> str:
    """Hash any JSON-serializable object canonically."""
    return sha256_hex(canonical_json(data))
