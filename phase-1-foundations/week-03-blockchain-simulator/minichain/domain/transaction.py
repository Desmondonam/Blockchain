"""Transactions: signed-later, value-moving instructions.

Week 3 transactions are *unsigned*: anyone could forge one. Week 4 fixes
this with ECDSA signatures. Keep that weakness in mind.
"""

from dataclasses import dataclass
from typing import Any

from .errors import InvalidTransactionError
from .hashing import hash_object


@dataclass(frozen=True)
class Transaction:
    """An account-model transfer, similar to an Ethereum value transfer.

    Attributes:
        sender: Account paying ``amount + fee``.
        recipient: Account receiving ``amount``.
        amount: Units transferred. Integers only, because floats lose precision.
        fee: Paid to the block proposer (a simplified stand-in for gas).
        nonce: The sender's transaction counter, which prevents replay.
    """

    sender: str
    recipient: str
    amount: int
    fee: int
    nonce: int

    def __post_init__(self) -> None:
        # Preconditions are checked when the object is created, so an invalid
        # Transaction can never exist.
        if not self.sender or not self.recipient:
            raise InvalidTransactionError("sender and recipient must be non-empty")
        if self.sender == self.recipient:
            raise InvalidTransactionError("sender and recipient must differ")
        for name in ("amount", "fee", "nonce"):
            value = getattr(self, name)
            # bool is a subclass of int in Python, so reject it explicitly.
            if not isinstance(value, int) or isinstance(value, bool):
                raise InvalidTransactionError(f"{name} must be an int, got {type(value).__name__}")
        if self.amount <= 0:
            raise InvalidTransactionError("amount must be positive")
        if self.fee < 0:
            raise InvalidTransactionError("fee must be non-negative")
        if self.nonce < 0:
            raise InvalidTransactionError("nonce must be non-negative")

    def to_dict(self) -> dict[str, Any]:
        return {
            "sender": self.sender,
            "recipient": self.recipient,
            "amount": self.amount,
            "fee": self.fee,
            "nonce": self.nonce,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Transaction":
        return cls(**data)

    @property
    def tx_id(self) -> str:
        """Content-addressed ID: identical transactions have identical IDs."""
        return hash_object(self.to_dict())
