"""Command-line adapter: ``python -m minichain demo`` / ``python -m minichain verify FILE``."""

import argparse
import itertools
import sys
from pathlib import Path

from .domain.blockchain import Blockchain, verify_chain
from .domain.errors import MinichainError
from .domain.transaction import Transaction
from .infrastructure.json_store import TamperedFileError, load_blocks, save_blocks


def demo(out: Path | None) -> int:
    ticks = itertools.count(1_700_000_000, 12)  # a fake clock with 12-second "slots"
    chain = Blockchain({"alice": 100, "bob": 20}, clock=lambda: next(ticks))

    print("Genesis:", {"alice": chain.balance_of("alice"), "bob": chain.balance_of("bob")})
    chain.submit(Transaction("alice", "bob", amount=30, fee=2, nonce=0))
    chain.submit(Transaction("alice", "carol", amount=10, fee=1, nonce=1))
    chain.submit(Transaction("bob", "carol", amount=5, fee=3, nonce=0))
    print(f"Mempool: {len(chain.mempool)} pending txs")

    try:
        chain.submit(Transaction("carol", "alice", amount=500, fee=0, nonce=0))
    except MinichainError as exc:
        print(f"Rejected (expected): {exc}")

    block = chain.produce_block(proposer="validator-1")
    print(f"\nBlock #{block.index}  hash={block.hash[:16]}...  prev={block.previous_hash[:16]}...")
    for tx in block.transactions:
        print(f"  {tx.sender:>6} -> {tx.recipient:<6} amount={tx.amount:<3} "
              f"fee={tx.fee} nonce={tx.nonce}")

    for who in ("alice", "bob", "carol", "validator-1"):
        print(f"  {who:<12} balance={chain.balance_of(who)}")
    print("Total supply conserved:", chain.total_supply() == 120)
    print("Chain valid:", chain.is_valid())

    if out:
        save_blocks(out, chain.blocks, chain.genesis_balances)
        print(f"\nSaved to {out}")
    return 0


def verify(path: Path) -> int:
    try:
        blocks, genesis = load_blocks(path)
    except TamperedFileError as exc:
        print(f"TAMPERED: {exc}")
        return 1
    ok = verify_chain(blocks, genesis)
    print("VALID" if ok else "INVALID")
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="minichain")
    sub = parser.add_subparsers(dest="cmd", required=True)
    demo_cmd = sub.add_parser("demo", help="run a scripted demo")
    demo_cmd.add_argument("--out", type=Path, help="save the chain to a JSON file")
    verify_cmd = sub.add_parser("verify", help="verify a saved chain file")
    verify_cmd.add_argument("path", type=Path)
    args = parser.parse_args(argv)
    return demo(args.out) if args.cmd == "demo" else verify(args.path)


if __name__ == "__main__":
    sys.exit(main())
