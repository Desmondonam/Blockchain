import pytest

from minichain.domain.errors import InvalidTransactionError
from minichain.domain.transaction import Transaction


def test_tx_id_is_deterministic():
    a = Transaction("alice", "bob", 5, 1, 0)
    b = Transaction("alice", "bob", 5, 1, 0)
    assert a.tx_id == b.tx_id
    assert len(a.tx_id) == 64


def test_any_field_change_changes_tx_id():
    base = Transaction("alice", "bob", 5, 1, 0)
    variants = [
        Transaction("alice", "bob", 6, 1, 0),
        Transaction("alice", "bob", 5, 2, 0),
        Transaction("alice", "bob", 5, 1, 1),
        Transaction("alice", "carol", 5, 1, 0),
    ]
    assert all(v.tx_id != base.tx_id for v in variants)


def test_round_trip_serialization():
    tx = Transaction("alice", "bob", 5, 1, 0)
    assert Transaction.from_dict(tx.to_dict()) == tx


@pytest.mark.parametrize(
    "kwargs, message",
    [
        ({"amount": 0}, "amount must be positive"),
        ({"amount": -1}, "amount must be positive"),
        ({"fee": -1}, "fee must be non-negative"),
        ({"nonce": -1}, "nonce must be non-negative"),
        ({"amount": 1.5}, "amount must be an int"),
        ({"amount": True}, "amount must be an int"),
        ({"recipient": "alice"}, "must differ"),
        ({"sender": ""}, "non-empty"),
    ],
)
def test_invalid_transactions_are_rejected(kwargs, message):
    fields = {"sender": "alice", "recipient": "bob", "amount": 5, "fee": 1, "nonce": 0, **kwargs}
    with pytest.raises(InvalidTransactionError, match=message):
        Transaction(**fields)
