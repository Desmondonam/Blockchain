import dataclasses

import pytest

from ledger import KeyPair, Ledger, Transaction, TransactionError, audit, prove_inclusion

CHAIN_ID = 31337


@pytest.fixture(scope="module")
def alice() -> KeyPair:
    return KeyPair.generate()


@pytest.fixture(scope="module")
def bob() -> KeyPair:
    return KeyPair.generate()


def make_tx(sender: KeyPair, recipient: KeyPair, amount: int, nonce: int,
            chain_id: int = CHAIN_ID) -> Transaction:
    return Transaction(sender.address, recipient.address, amount, nonce, chain_id).signed_by(sender)


@pytest.fixture
def ledger(alice, bob) -> Ledger:
    led = Ledger(CHAIN_ID)
    led.append([make_tx(alice, bob, 10, 0), make_tx(bob, alice, 3, 0)], timestamp=100)
    led.append([make_tx(alice, bob, 7, 1)], timestamp=112)
    led.append([make_tx(alice, bob, 1, 2), make_tx(bob, alice, 1, 1), make_tx(alice, bob, 2, 3)],
               timestamp=124)
    return led


# ------------------------------------------------------------- transactions
def test_signed_tx_verifies(alice, bob):
    assert make_tx(alice, bob, 5, 0).verify()


def test_unsigned_tx_does_not_verify(alice, bob):
    assert not Transaction(alice.address, bob.address, 5, 0, CHAIN_ID).verify()


@pytest.mark.parametrize("field, value", [("amount", 500), ("nonce", 9), ("chain_id", 1)])
def test_altering_any_signed_field_breaks_signature(alice, bob, field, value):
    tx = make_tx(alice, bob, 5, 0)
    assert not dataclasses.replace(tx, **{field: value}).verify()


def test_redirecting_recipient_breaks_signature(alice, bob):
    mallory = KeyPair.generate()
    tx = make_tx(alice, bob, 5, 0)
    assert not dataclasses.replace(tx, recipient=mallory.address).verify()


def test_cannot_sign_for_someone_else(alice, bob):
    with pytest.raises(TransactionError, match="another account"):
        Transaction(alice.address, bob.address, 5, 0, CHAIN_ID).signed_by(bob)


def test_swapping_in_attackers_key_fails(alice, bob):
    """Mallory signs a tx claiming to be from Alice and attaches her own public key."""
    mallory = KeyPair.generate()
    forged = Transaction(alice.address, bob.address, 5, 0, CHAIN_ID)
    sig = mallory.sign_digest(forged.signing_hash()).to_hex()
    forged = dataclasses.replace(forged, public_key=mallory.public_key.hex(), signature=sig)
    assert not forged.verify()  # Mallory's key doesn't hash to Alice's address


@pytest.mark.parametrize("bad", [{"amount": 0}, {"amount": -1}, {"nonce": True}])
def test_invalid_fields_rejected(alice, bob, bad):
    fields = {"sender": alice.address, "recipient": bob.address, "amount": 1, "nonce": 0,
              "chain_id": CHAIN_ID, **bad}
    with pytest.raises(TransactionError):
        Transaction(**fields)


def test_lowercase_address_rejected(alice, bob):
    with pytest.raises(TransactionError, match="checksummed"):
        Transaction(alice.address.lower(), bob.address, 1, 0, CHAIN_ID)


# --------------------------------------------------------------- ledger rules
def test_clean_ledger_has_no_findings(ledger):
    assert audit(ledger.blocks, CHAIN_ID) == []


def test_rejects_cross_chain_replay(alice, bob):
    led = Ledger(CHAIN_ID)
    with pytest.raises(TransactionError, match="chain_id"):
        led.append([make_tx(alice, bob, 5, 0, chain_id=1)], timestamp=1)


def test_rejects_same_chain_replay(alice, bob):
    led = Ledger(CHAIN_ID)
    tx = make_tx(alice, bob, 5, 0)
    led.append([tx], timestamp=1)
    with pytest.raises(TransactionError, match="nonce"):
        led.append([tx], timestamp=2)


def test_failed_append_is_atomic(alice, bob):
    led = Ledger(CHAIN_ID)
    good, bad = make_tx(alice, bob, 1, 0), make_tx(alice, bob, 1, 5)
    with pytest.raises(TransactionError):
        led.append([good, bad], timestamp=1)
    assert len(led.blocks) == 1
    assert led.next_nonce(alice.address) == 0


# ------------------------------------------------------------ tamper detection
def test_detects_altered_transaction(ledger):
    blocks = list(ledger.blocks)
    target = blocks[2].transactions[0]
    tampered_tx = dataclasses.replace(target, amount=7000)
    blocks[2] = dataclasses.replace(blocks[2], transactions=(tampered_tx,))

    problems = {(f.block_index, f.tx_index, f.problem.split(" ")[0]) for f in audit(blocks, CHAIN_ID)}
    assert (2, 0, "signature") in problems  # the tx itself
    assert (2, None, "merkle_root") in problems  # the block's commitment


def test_detects_recomputed_merkle_root_via_hash_link(ledger):
    """A smarter attacker re-signs nothing but fixes the Merkle root. The next block's link still breaks."""
    blocks = list(ledger.blocks)
    victim = blocks[2]
    kept = victim.transactions[:0]  # delete Alice's tx entirely
    blocks[2] = dataclasses.replace(victim, transactions=kept,
                                    merkle_root=victim.compute_merkle_root(kept))
    findings = audit(blocks, CHAIN_ID)
    assert [f.block_index for f in findings] == [3]
    assert "previous_hash" in findings[0].problem


def test_detects_reordered_blocks(ledger):
    blocks = list(ledger.blocks)
    blocks[1], blocks[2] = blocks[2], blocks[1]
    assert audit(blocks, CHAIN_ID)


# ---------------------------------------------------------- light-client proof
def test_inclusion_proof_against_header(ledger):
    block = ledger.blocks[3]
    for i, tx in enumerate(block.transactions):
        assert prove_inclusion(tx, block.inclusion_proof(i), block.merkle_root)


def test_inclusion_proof_fails_for_tx_not_in_block(ledger, alice, bob):
    block = ledger.blocks[3]
    outsider = make_tx(alice, bob, 999, 99)
    assert not prove_inclusion(outsider, block.inclusion_proof(0), block.merkle_root)
