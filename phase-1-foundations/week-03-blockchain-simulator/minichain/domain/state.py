"""World state: balances and nonces, derived by replaying transactions."""

from dataclasses import dataclass, field

from .errors import InsufficientFundsError, InvalidNonceError
from .transaction import Transaction


@dataclass
class State:
    balances: dict[str, int] = field(default_factory=dict)
    nonces: dict[str, int] = field(default_factory=dict)

    def copy(self) -> "State":
        return State(dict(self.balances), dict(self.nonces))

    def balance_of(self, account: str) -> int:
        return self.balances.get(account, 0)

    def nonce_of(self, account: str) -> int:
        """The next nonce ``account`` must use."""
        return self.nonces.get(account, 0)

    def validate(self, tx: Transaction) -> None:
        """Raise if ``tx`` cannot be applied to this state."""
        expected = self.nonce_of(tx.sender)
        if tx.nonce != expected:
            raise InvalidNonceError(f"{tx.sender}: expected nonce {expected}, got {tx.nonce}")
        cost = tx.amount + tx.fee
        if self.balance_of(tx.sender) < cost:
            raise InsufficientFundsError(
                f"{tx.sender}: balance {self.balance_of(tx.sender)} < cost {cost}"
            )

    def apply(self, tx: Transaction, proposer: str) -> None:
        """Validate, then mutate. Checks come before effects."""
        self.validate(tx)
        self.balances[tx.sender] = self.balance_of(tx.sender) - tx.amount - tx.fee
        self.balances[tx.recipient] = self.balance_of(tx.recipient) + tx.amount
        self.balances[proposer] = self.balance_of(proposer) + tx.fee
        self.nonces[tx.sender] = tx.nonce + 1

    def total_supply(self) -> int:
        return sum(self.balances.values())
