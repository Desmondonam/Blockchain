import dataclasses

import pytest

from minichain.domain.block import Block
from minichain.domain.blockchain import Blockchain
from minichain.domain.errors import (
    InsufficientFundsError,
    InvalidBlockError,
    InvalidNonceError,
    MinichainError,
)
from minichain.domain.transaction import Transaction

from .conftest import GENESIS


# ---------------------------------------------------------------- happy path
def test_genesis_block(chain: Blockchain):
    assert len(chain.blocks) == 1
    assert chain.head.index == 0
    assert chain.balance_of("alice") == 100
    assert chain.is_valid()


def test_transfer_moves_value_and_pays_fee(chain: Blockchain):
    chain.submit(Transaction("alice", "bob", 30, 2, 0))
    block = chain.produce_block("val")

    assert block.index == 1
    assert block.previous_hash == chain.blocks[0].hash
    assert chain.balance_of("alice") == 68
    assert chain.balance_of("bob") == 50
    assert chain.balance_of("val") == 2
    assert chain.nonce_of("alice") == 1
    assert chain.mempool == ()


def test_receipt_available_after_inclusion(chain: Blockchain):
    tx_id = chain.submit(Transaction("alice", "bob", 1, 0, 0))
    assert chain.receipt(tx_id) is None  # pending
    block = chain.produce_block("val")
    receipt = chain.receipt(tx_id)
    assert receipt is not None
    assert (receipt.block_index, receipt.block_hash) == (1, block.hash)


def test_sender_can_queue_sequential_nonces(chain: Blockchain):
    for nonce in range(3):
        chain.submit(Transaction("alice", "bob", 10, 1, nonce))
    chain.produce_block("val")
    assert chain.nonce_of("alice") == 3
    assert chain.balance_of("alice") == 100 - 3 * 11


def test_higher_fee_first_but_nonce_order_respected(chain: Blockchain):
    # alice's nonce-1 tx pays the most, but it can't go before her nonce 0.
    chain.submit(Transaction("alice", "bob", 1, 1, 0))
    chain.submit(Transaction("alice", "bob", 1, 50, 1))
    chain.submit(Transaction("bob", "alice", 1, 5, 0))
    block = chain.produce_block("val")
    order = [(tx.sender, tx.nonce) for tx in block.transactions]
    assert order.index(("alice", 0)) < order.index(("alice", 1))
    assert order[0] == ("bob", 0)  # highest-fee tx that is valid right now


def test_max_txs_limits_block_size(chain: Blockchain):
    for nonce in range(5):
        chain.submit(Transaction("alice", "bob", 1, 0, nonce))
    block = chain.produce_block("val", max_txs=2)
    assert len(block.transactions) == 2
    assert len(chain.mempool) == 3


# --------------------------------------------------------------- rejections
def test_rejects_overspend(chain: Blockchain):
    with pytest.raises(InsufficientFundsError):
        chain.submit(Transaction("bob", "alice", 20, 1, 0))  # 21 > 20


def test_rejects_overspend_across_pending_txs(chain: Blockchain):
    chain.submit(Transaction("bob", "alice", 15, 0, 0))
    with pytest.raises(InsufficientFundsError):
        chain.submit(Transaction("bob", "alice", 10, 0, 1))


@pytest.mark.parametrize("nonce", [1, 5])
def test_rejects_nonce_gap(chain: Blockchain, nonce: int):
    with pytest.raises(InvalidNonceError):
        chain.submit(Transaction("alice", "bob", 1, 0, nonce))


def test_rejects_replayed_transaction(chain: Blockchain):
    tx = Transaction("alice", "bob", 1, 0, 0)
    chain.submit(tx)
    chain.produce_block("val")
    with pytest.raises(MinichainError):
        chain.submit(tx)  # same bytes again: duplicate, and the nonce is used


def test_rejects_block_with_wrong_parent(chain: Blockchain):
    bad = Block(1, "f" * 64, 2000, "val", ())
    with pytest.raises(InvalidBlockError, match="previous_hash"):
        chain.add_block(bad)


def test_rejects_block_with_invalid_tx_and_leaves_state_untouched(chain: Blockchain):
    overspend = Transaction("bob", "alice", 999, 0, 0)
    bad = Block(1, chain.head.hash, 2000, "val", (overspend,))
    with pytest.raises(InvalidBlockError):
        chain.add_block(bad)
    assert chain.balance_of("bob") == 20
    assert len(chain.blocks) == 1


def test_rejects_timestamp_going_backwards(chain: Blockchain):
    bad = Block(1, chain.head.hash, chain.head.timestamp - 1, "val", ())
    with pytest.raises(InvalidBlockError, match="timestamp"):
        chain.add_block(bad)


# ------------------------------------------------------ integrity & invariants
def _build_chain(chain: Blockchain) -> Blockchain:
    chain.submit(Transaction("alice", "bob", 30, 2, 0))
    chain.produce_block("val")
    chain.submit(Transaction("bob", "carol", 10, 1, 0))
    chain.produce_block("val")
    chain.produce_block("val")  # empty blocks are allowed
    return chain


def test_tampering_any_historic_tx_breaks_the_chain(chain: Blockchain):
    _build_chain(chain)
    blocks = list(chain.blocks)
    original = blocks[1].transactions[0]
    forged = dataclasses.replace(original, amount=99)  # alice "sent" 99 instead of 30
    blocks[1] = dataclasses.replace(blocks[1], transactions=(forged,))

    from minichain.domain.blockchain import verify_chain

    assert verify_chain(chain.blocks, GENESIS) is True
    assert verify_chain(blocks, GENESIS) is False  # block 2's previous_hash no longer matches


def test_total_supply_is_conserved(chain: Blockchain):
    """Invariant: transfers and fees move value, they never create or destroy it."""
    _build_chain(chain)
    assert chain.total_supply() == sum(GENESIS.values())


def test_sum_of_nonces_equals_number_of_included_txs(chain: Blockchain):
    _build_chain(chain)
    included = sum(len(b.transactions) for b in chain.blocks)
    assert sum(chain.nonce_of(a) for a in ("alice", "bob", "carol")) == included
