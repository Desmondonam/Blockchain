"""Domain-specific exceptions.

Callers catch *specific* errors, which makes it explicit which failures are
expected and which are bugs. Never raise a bare ``Exception``.
"""


class MinichainError(Exception):
    """Base class for every error this package raises on purpose."""


class InvalidTransactionError(MinichainError):
    """The transaction is malformed (bad amount, empty address, ...)."""


class InsufficientFundsError(MinichainError):
    """The sender cannot cover amount + fee."""


class InvalidNonceError(MinichainError):
    """The nonce is not the sender's next expected nonce."""


class InvalidBlockError(MinichainError):
    """The block does not extend the chain correctly."""
