"""A network partition, a fork, a heal and a reorg, narrated.

Run from the week-05 folder:  python -m demos.fork_story
"""

from consensus_sim import bft
from consensus_sim.block import GENESIS, Block, mine
from consensus_sim.network import Network


def show(net: Network, label: str) -> None:
    print(f"\n{label}")
    for name, node in net.nodes.items():
        chain = " -> ".join(f"#{b.height}({b.producer})" for b in node.tree.canonical_chain()[1:])
        print(f"  {name}: genesis -> {chain}")


net = Network(["n1", "n2", "n3", "n4", "n5"])
net.produce("n1", ("deploy registry",))
show(net, "1) All 5 nodes connected, one block produced:")

net.partition(["n1", "n2"], ["n3", "n4", "n5"])
net.produce("n1", ("alice pays bob 10",))
net.produce("n3", ("carol pays dan 4",))
net.produce("n4", ("erin pays fay 1",))
show(net, "2) Partition {n1,n2} | {n3,n4,n5}: both sides keep building = FORK")

net.heal()
show(net, "3) Partition heals; heaviest chain wins:")
for name, node in net.nodes.items():
    for r in node.reorg_log:
        print(f"  {name} REORG depth={r.depth}: dropped {[b.records for b in r.removed]}")
print("  'alice pays bob 10' confirmed?", net.nodes["n1"].tree.find_record("alice pays bob 10") is not None,
      "-> wallet must re-broadcast it")

print("\n4) Cost of rewriting history with PoW (difficulty 14 bits):")
parent, total = GENESIS, 0
for depth in range(1, 6):
    result = mine(Block(parent.height + 1, parent.hash, "attacker", (), parent.timestamp + 12, 14))
    parent, total = result.block, total + result.attempts
    print(f"  rewrite {depth} block(s): ~{total:>7,} hashes")

print("\n5) BFT: how many validators do we need?")
for n in (3, 4, 7, 10):
    f = bft.max_faulty(n)
    print(f"  n={n:<3} tolerates f={f}  quorum={bft.quorum(n)}  overlap={bft.quorum_overlap(n)}")
