"""Key pairs, Ethereum-style addresses and ECDSA signatures on secp256k1.

The elliptic-curve maths comes from the ``cryptography`` library. This module
only adds the Ethereum conventions on top: address derivation, EIP-55
checksums, and low-s signature normalization.
"""

from dataclasses import dataclass

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import (
    Prehashed,
    decode_dss_signature,
    encode_dss_signature,
)

from .hashing import keccak256

# Order of the secp256k1 group. Signatures with s > N/2 are "high-s".
SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
_PREHASHED = ec.ECDSA(Prehashed(hashes.SHA256()))  # 32-byte digest supplied by us


class InvalidAddressError(ValueError):
    pass


def public_key_bytes(public_key: ec.EllipticCurvePublicKey) -> bytes:
    """64-byte uncompressed public key X || Y (without the 0x04 prefix)."""
    raw = public_key.public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )
    return raw[1:]


def address_from_public_key(pub64: bytes) -> str:
    """Ethereum address: last 20 bytes of keccak256(X || Y), EIP-55 checksummed."""
    if len(pub64) != 64:
        raise ValueError("expected a 64-byte uncompressed public key")
    return to_checksum_address("0x" + keccak256(pub64)[-20:].hex())


def to_checksum_address(address: str) -> str:
    """EIP-55: capitalize hex letters wherever the matching hash nibble is >= 8.

    This catches typos. A mistyped character almost certainly breaks the
    capitalization pattern.
    """
    hex_part = address.lower().removeprefix("0x")
    if len(hex_part) != 40 or any(c not in "0123456789abcdef" for c in hex_part):
        raise InvalidAddressError(f"not a 20-byte hex address: {address!r}")
    digest = keccak256(hex_part.encode()).hex()
    return "0x" + "".join(
        c.upper() if c.isalpha() and int(digest[i], 16) >= 8 else c
        for i, c in enumerate(hex_part)
    )


def is_checksum_valid(address: str) -> bool:
    try:
        return to_checksum_address(address) == address
    except InvalidAddressError:
        return False


@dataclass(frozen=True)
class Signature:
    r: int
    s: int

    def to_hex(self) -> str:
        return self.r.to_bytes(32, "big").hex() + self.s.to_bytes(32, "big").hex()

    @classmethod
    def from_hex(cls, value: str) -> "Signature":
        raw = bytes.fromhex(value)
        if len(raw) != 64:
            raise ValueError("signature must be 64 bytes (r || s)")
        return cls(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))


class KeyPair:
    """A secp256k1 private key and helpers. Keep instances out of logs and files."""

    def __init__(self, private_key: ec.EllipticCurvePrivateKey) -> None:
        self._sk = private_key

    @classmethod
    def generate(cls) -> "KeyPair":
        """Uses the OS's cryptographically secure random number generator."""
        return cls(ec.generate_private_key(ec.SECP256K1()))

    @classmethod
    def from_hex(cls, private_hex: str) -> "KeyPair":
        """For TEST VECTORS ONLY. Real keys belong in a wallet or keystore, not in code."""
        secret = int(private_hex.removeprefix("0x"), 16)
        return cls(ec.derive_private_key(secret, ec.SECP256K1()))

    @property
    def public_key(self) -> bytes:
        return public_key_bytes(self._sk.public_key())

    @property
    def address(self) -> str:
        return address_from_public_key(self.public_key)

    def sign_digest(self, digest: bytes) -> Signature:
        """Sign a 32-byte digest and normalize to low-s (as Ethereum's EIP-2 requires)."""
        if len(digest) != 32:
            raise ValueError("digest must be 32 bytes")
        r, s = decode_dss_signature(self._sk.sign(digest, _PREHASHED))
        if s > SECP256K1_N // 2:
            s = SECP256K1_N - s  # (r, s) and (r, N-s) are both valid: pick one canonical form
        return Signature(r, s)

    def __repr__(self) -> str:  # never print the secret
        return f"KeyPair(address={self.address})"


def verify_signature(pub64: bytes, digest: bytes, sig: Signature) -> bool:
    """True if ``sig`` is a valid, canonical (low-s) signature over ``digest``."""
    if not (0 < sig.r < SECP256K1_N and 0 < sig.s <= SECP256K1_N // 2):
        return False  # reject high-s to prevent signature malleability
    try:
        point = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256K1(), b"\x04" + pub64)
        point.verify(encode_dss_signature(sig.r, sig.s), digest, _PREHASHED)
        return True
    except (InvalidSignature, ValueError):
        return False
