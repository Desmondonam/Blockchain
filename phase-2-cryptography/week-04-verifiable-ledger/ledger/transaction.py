"""Signed transactions.

The signature covers every field that matters, *including the chain ID*.
If any byte changes, verification fails.
"""

from dataclasses import dataclass, replace
from typing import Any

from .hashing import canonical_json, keccak256
from .keys import KeyPair, Signature, address_from_public_key, is_checksum_valid, verify_signature


class TransactionError(ValueError):
    pass


@dataclass(frozen=True)
class Transaction:
    sender: str
    recipient: str
    amount: int
    nonce: int
    chain_id: int
    public_key: str = ""  # hex, 64 bytes. Ethereum recovers it from (v, r, s) instead.
    signature: str = ""  # hex, r || s

    def __post_init__(self) -> None:
        for name in ("sender", "recipient"):
            if not is_checksum_valid(getattr(self, name)):
                raise TransactionError(f"{name} is not an EIP-55 checksummed address")
        if self.sender == self.recipient:
            raise TransactionError("sender and recipient must differ")
        for name in ("amount", "nonce", "chain_id"):
            value = getattr(self, name)
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                raise TransactionError(f"{name} must be a non-negative int")
        if self.amount == 0:
            raise TransactionError("amount must be positive")

    def payload(self) -> dict[str, Any]:
        """The fields that get signed."""
        return {
            "sender": self.sender,
            "recipient": self.recipient,
            "amount": self.amount,
            "nonce": self.nonce,
            "chain_id": self.chain_id,
        }

    def signing_hash(self) -> bytes:
        return keccak256(canonical_json(self.payload()))

    def signed_by(self, keys: KeyPair) -> "Transaction":
        if keys.address != self.sender:
            raise TransactionError("cannot sign for another account")
        sig = keys.sign_digest(self.signing_hash())
        return replace(self, public_key=keys.public_key.hex(), signature=sig.to_hex())

    @property
    def tx_hash(self) -> bytes:
        """The ID covers the payload AND the signature."""
        return keccak256(canonical_json(self.to_dict()))

    def verify(self) -> bool:
        """True only if the signature is valid and was made by ``sender``'s key."""
        if not self.public_key or not self.signature:
            return False
        try:
            pub = bytes.fromhex(self.public_key)
            if address_from_public_key(pub) != self.sender:
                return False  # someone else's key signed it
            return verify_signature(pub, self.signing_hash(), Signature.from_hex(self.signature))
        except ValueError:
            return False

    def to_dict(self) -> dict[str, Any]:
        return {**self.payload(), "public_key": self.public_key, "signature": self.signature}

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Transaction":
        return cls(**data)
