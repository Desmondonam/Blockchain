"""Build a signed ledger, tamper with it, and watch the audit pinpoint the change.

Run from the week-04 folder:  python -m demos.tamper_audit
"""

import dataclasses

from ledger import KeyPair, Ledger, Transaction, audit, prove_inclusion

CHAIN_ID = 31337
alice, bob, carol = KeyPair.generate(), KeyPair.generate(), KeyPair.generate()


def tx(sender: KeyPair, to: KeyPair, amount: int, nonce: int) -> Transaction:
    return Transaction(sender.address, to.address, amount, nonce, CHAIN_ID).signed_by(sender)


ledger = Ledger(CHAIN_ID)
ledger.append([tx(alice, bob, 50, 0), tx(bob, carol, 5, 0)], timestamp=100)
ledger.append([tx(alice, carol, 20, 1)], timestamp=112)
ledger.append([tx(carol, alice, 1, 0), tx(alice, bob, 2, 2), tx(bob, alice, 3, 1)], timestamp=124)

print("Ledger:")
for b in ledger.blocks:
    print(f"  #{b.index} hash={b.hash[:12]} prev={b.previous_hash[:12]} root={b.merkle_root[:12]} txs={len(b.transactions)}")
print("Audit findings:", audit(ledger.blocks, CHAIN_ID) or "none ✔")

print("\n--- Light client: prove tx #1 of block 3 is included, using 2 hashes instead of 3 txs")
block = ledger.blocks[3]
proof = block.inclusion_proof(1)
print("  proof:", [f"{s.side}:{s.sibling.hex()[:10]}" for s in proof])
print("  included?", prove_inclusion(block.transactions[1], proof, block.merkle_root))

print("\n--- Attack: change Alice's 20 -> 2000 in block 2")
blocks = list(ledger.blocks)
forged = dataclasses.replace(blocks[2].transactions[0], amount=2000)
blocks[2] = dataclasses.replace(blocks[2], transactions=(forged,))
for f in audit(blocks, CHAIN_ID):
    where = f"block {f.block_index}" + (f", tx {f.tx_index}" if f.tx_index is not None else "")
    print(f"  ✘ {where}: {f.problem}")

print("\n--- Smarter attack: also recompute block 2's Merkle root")
blocks[2] = dataclasses.replace(blocks[2], merkle_root=blocks[2].compute_merkle_root(blocks[2].transactions))
for f in audit(blocks, CHAIN_ID):
    where = f"block {f.block_index}" + (f", tx {f.tx_index}" if f.tx_index is not None else "")
    print(f"  ✘ {where}: {f.problem}")
print("  -> The signature still fails (only Alice's key could fix that), and block 3's link breaks.")
