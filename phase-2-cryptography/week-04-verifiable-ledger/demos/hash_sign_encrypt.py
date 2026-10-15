"""Hashing vs signing vs encrypting: three tools for three different problems.

Run from the week-04 folder:  python -m demos.hash_sign_encrypt
"""

import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from ledger.hashing import keccak256, sha256
from ledger.keys import KeyPair, verify_signature

message = b"Certificate #42: BSc Computer Science, 2026"

print("=" * 70)
print("1. HASHING: integrity fingerprint. One-way, no key, anyone can compute it")
print("=" * 70)
print("sha256   :", sha256(message).hex())
print("keccak256:", keccak256(message).hex())
print("1-char change ->", sha256(message.replace(b"42", b"43")).hex(), "(totally different)")
print("Can you get the message back from the hash?  NO. It's not encryption.\n")

print("=" * 70)
print("2. SIGNING: authenticity + integrity. Private key signs, public key verifies")
print("=" * 70)
issuer = KeyPair.generate()
digest = keccak256(message)
sig = issuer.sign_digest(digest)
print("issuer address :", issuer.address)
print("signature r||s :", sig.to_hex()[:48], "...")
print("valid?         :", verify_signature(issuer.public_key, digest, sig))
print("valid if forged:", verify_signature(issuer.public_key, keccak256(message + b"!"), sig))
print("Is the message secret?  NO. Signing proves WHO, not privacy.\n")

print("=" * 70)
print("3. ENCRYPTION: confidentiality. Only key holders can read")
print("=" * 70)
key = AESGCM.generate_key(bit_length=256)
nonce = os.urandom(12)  # must never repeat for the same key
ciphertext = AESGCM(key).encrypt(nonce, message, None)
print("ciphertext:", ciphertext.hex()[:48], "...")
print("decrypted :", AESGCM(key).decrypt(nonce, ciphertext, None).decode())
print("Use it for off-chain certificate files (Week 12), NEVER as a substitute for a hash.\n")

print("=" * 70)
print("4. WHY A PLAIN HASH OF GUESSABLE DATA IS NOT PRIVATE")
print("=" * 70)
target = sha256(b"student-id:2026-0457")
for guess in range(450, 460):
    candidate = f"student-id:2026-{guess:04d}".encode()
    if sha256(candidate) == target:
        print(f"brute-forced in {guess - 449} guesses -> {candidate.decode()}")
salt = os.urandom(16)
print("fix: hash(salt || data) with a random 16-byte salt ->", sha256(salt + b"student-id:2026-0457").hex()[:32], "...")
