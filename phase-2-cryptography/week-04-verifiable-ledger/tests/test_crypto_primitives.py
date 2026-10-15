"""Known-answer tests: compare against published vectors, not our own output."""

import hashlib

import pytest

from ledger.hashing import keccak256, sha256
from ledger.keys import (
    SECP256K1_N,
    InvalidAddressError,
    KeyPair,
    Signature,
    is_checksum_valid,
    to_checksum_address,
    verify_signature,
)

# Anvil / Hardhat default account #0. PUBLIC test key: never send real funds to it.
ANVIL_KEY_0 = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ANVIL_ADDR_0 = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"


def test_keccak256_known_vector():
    assert keccak256(b"").hex() == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"


def test_keccak_is_not_nist_sha3():
    assert keccak256(b"") != hashlib.sha3_256(b"").digest()


def test_sha256_known_vector():
    assert sha256(b"abc").hex() == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"


def test_avalanche_effect():
    """One changed input bit flips about half of the 256 output bits."""
    a, b = sha256(b"pay bob 10"), sha256(b"pay bob 11")
    differing_bits = sum(bin(x ^ y).count("1") for x, y in zip(a, b))
    assert 80 < differing_bits < 176


def test_address_derivation_matches_anvil():
    assert KeyPair.from_hex(ANVIL_KEY_0).address == ANVIL_ADDR_0


@pytest.mark.parametrize(
    "address",
    [  # vectors from the EIP-55 specification
        "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
        "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
        "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
        "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb",
    ],
)
def test_eip55_checksum_vectors(address):
    assert to_checksum_address(address.lower()) == address
    assert is_checksum_valid(address)


def test_checksum_catches_typo():
    good = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
    assert not is_checksum_valid(good.replace("aA", "Aa", 1))


def test_rejects_malformed_address():
    with pytest.raises(InvalidAddressError):
        to_checksum_address("0x1234")


def test_sign_and_verify():
    keys = KeyPair.generate()
    digest = keccak256(b"message")
    sig = keys.sign_digest(digest)
    assert verify_signature(keys.public_key, digest, sig)
    assert not verify_signature(keys.public_key, keccak256(b"other"), sig)
    assert not verify_signature(KeyPair.generate().public_key, digest, sig)


def test_signatures_are_low_s():
    keys = KeyPair.generate()
    for i in range(20):
        assert keys.sign_digest(keccak256(bytes([i]))).s <= SECP256K1_N // 2


def test_high_s_malleated_signature_is_rejected():
    """(r, N-s) is mathematically valid too. We reject it so each tx has exactly one encoding."""
    keys = KeyPair.generate()
    digest = keccak256(b"message")
    sig = keys.sign_digest(digest)
    malleated = Signature(sig.r, SECP256K1_N - sig.s)
    assert not verify_signature(keys.public_key, digest, malleated)


def test_repr_never_leaks_private_key():
    keys = KeyPair.from_hex(ANVIL_KEY_0)
    assert ANVIL_KEY_0[2:] not in repr(keys)
