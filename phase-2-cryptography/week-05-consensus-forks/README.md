# Week 5 — Consensus, Forks, Reorganizations & Finality

> **Goal:** understand how independent nodes agree on one history, why forks
> happen, what a reorg does to "confirmed" transactions, and when a block is
> truly final. You'll simulate all of it.

---

## Part A — Concepts

### 5.1 Peer-to-peer networks

There's no central server. Each node connects to a handful of peers and
**gossips** new transactions and blocks to them.

```mermaid
flowchart LR
    n1((n1)) --- n2((n2))
    n1 --- n3((n3))
    n2 --- n4((n4))
    n3 --- n4
    n3 --- n5((n5))
    n4 --- n5
    n2 -. "gossip: new block" .-> n4
```

Messages arrive at **different times** at different nodes, and sometimes not
at all (partitions). Consensus has to work anyway.

### 5.2 Consensus mechanisms compared

| | Proof of Work | Proof of Stake | Classical BFT |
|---|---|---|---|
| Who proposes | Whoever first finds `hash < target` | Pseudo-random, weighted by stake | Rotating leader among known validators |
| Sybil resistance | Hardware + energy | Locked capital | Permissioned membership |
| Fork choice | Most cumulative **work** | LMD-GHOST (most attestation weight) | No forks: commit needs 2/3 |
| Finality | Probabilistic | Economic (Casper FFG checkpoints) | Instant on commit |
| Punishment | Wasted electricity | **Slashing** of stake | Removal from validator set |
| Example | Bitcoin | Ethereum | Tendermint/CometBFT, Hyperledger BFT |
| In this repo | [block.py](consensus_sim/block.py) `mine()` | [pos.py](consensus_sim/pos.py) | [bft.py](consensus_sim/bft.py) |

### 5.3 How a fork happens and resolves

```mermaid
gitGraph
    commit id: "genesis"
    commit id: "#1 (n1)"
    branch minority
    checkout minority
    commit id: "#2 (n1) alice→bob"
    checkout main
    commit id: "#2 (n3)"
    commit id: "#3 (n4)"
    checkout minority
    commit id: "partition heals" type: REVERSE
```

1. A **partition** (or just two miners finding blocks at the same moment)
   splits the network.
2. Each side extends its own tip. There are now **two valid chains**.
3. When the sides reconnect, every node applies the **fork-choice rule**:
   pick the branch with the most cumulative work (or stake weight).
4. Nodes on the losing branch **reorganize**: they roll back to the
   **common ancestor** and apply the winning blocks.
5. Transactions only in the dropped blocks go **back to the mempool**. If
   they conflict with the new chain (a double-spend!), they're gone for good.

```mermaid
sequenceDiagram
    participant W as Wallet
    participant N1 as Node n1 (minority)
    participant N3 as Majority nodes
    W->>N1: alice pays bob 10
    N1->>N1: block #2 includes it (1 confirmation)
    W-->>W: shows "Confirmed (1)"
    Note over N1,N3: partition heals
    N3->>N1: blocks #2', #3' (heavier)
    N1->>N1: REORG depth 1: drop #2
    N1-->>W: receipt gone, 0 confirmations
    W->>N1: re-broadcast (if still valid)
```

> 🔑 **Engineering lesson for dApps (Weeks 11, 17):** a transaction with one
> confirmation can disappear. Your indexer and UI must handle that: wait for
> enough confirmations or the `finalized` tag, and roll back indexed data
> on reorg.

### 5.4 Fork choice: by work, not length

A "longest chain" is really the **heaviest** chain. `test_fork_choice_is_by_work_not_length`
shows a 1-block chain at difficulty 3 (work 8) beating a 3-block chain at
difficulty 0 (work 3). Without this rule, an attacker could cheaply mine
lots of easy blocks.

### 5.5 Finality

```mermaid
flowchart LR
    subgraph PoW["Bitcoin: probabilistic"]
        direction LR
        c1["1 conf<br/>risky"] --> c3["3 conf"] --> c6["6 conf<br/>≈ final in practice"]
    end
    subgraph PoS["Ethereum: economic"]
        direction LR
        u["unsafe head"] --> s["safe<br/>(justified)"] --> f["finalized<br/>reverting it burns ≥ 1/3 of stake"]
    end
    subgraph BFT["BFT: deterministic"]
        direction LR
        p["proposed"] --> cmt["committed with 2f+1 votes<br/>final immediately"]
    end
```

The cost of rewriting history grows with depth: the demo shows the
attacker must re-mine **every block after** the one they change.

### 5.6 Byzantine fault tolerance: why n ≥ 3f + 1?

```mermaid
flowchart TB
    subgraph n4["n = 4, f = 1, quorum = 3"]
        Q1["Quorum A: v1 v2 v3"]
        Q2["Quorum B: v2 v3 v4"]
        O["Overlap: v2, v3 (2 > f)<br/>⇒ ≥ 1 honest validator in both<br/>⇒ can't commit two conflicting blocks"]
        Q1 --> O
        Q2 --> O
    end
```

Two properties must **both** hold:

- **Safety:** two quorums overlap in more than *f* validators, so an
  honest one is always in both.
- **Liveness:** if the *f* faulty validators go silent, the honest
  `n − f` can still form a quorum.

Surprise from the tests: with n = 3 and f = 1, the system is still *safe*,
but **not live**. One silent node stops the chain. The property test
`test_tolerates_iff_n_at_least_3f_plus_1` checks, over hundreds of random
`(n, f)` pairs, that both properties hold *exactly* when n ≥ 3f + 1.

### 5.7 Proof of Stake mechanics

- **Proposer selection** ([`select_proposer`](consensus_sim/pos.py)) is
  deterministic given `(seed, slot)`, so every node agrees without
  messaging. Over 8,000 slots, selection frequency matches stake share
  within 3%.
- **Equivocation** means signing two different blocks for the same slot.
  It's provable from two signed headers, so it's **slashable**.
- Slashing uses **integer basis points**, never floats.

---

## Part B — Architecture

```mermaid
classDiagram
    class Block {
      height, parent_hash, producer
      records, timestamp
      difficulty_bits, nonce
      +hash
      +work = 2^bits
    }
    class BlockTree {
      +head
      +add(block) AddResult
      +canonical_chain()
      +confirmations(hash)
      +is_final(hash, depth)
      -_reorg_to(hash) Reorg
    }
    class Reorg {
      common_ancestor
      removed[]
      added[]
      +depth
    }
    class Network {
      +partition(groups...)
      +heal()
      +produce(node, records)
    }
    class Node {
      name
      tree: BlockTree
      reorg_log: Reorg[]
    }
    Network o-- Node
    Node --> BlockTree
    BlockTree o-- Block
    BlockTree ..> Reorg : emits
```

### `BlockTree.add()` decision flow

```mermaid
flowchart TD
    A["add(block)"] --> D{"already known?"}
    D -- yes --> DUP["DUPLICATE"]
    D -- no --> P{"parent known?"}
    P -- no --> ORP["ORPHAN (store, wait for parent)"]
    P -- yes --> V{"height, timestamp,<br/>difficulty, PoW valid?"}
    V -- no --> INV["raise InvalidBlock"]
    V -- yes --> W{"total work ><br/>head's work?"}
    W -- no --> SIDE["SIDE_BRANCH<br/>(kept, in case it wins later)"]
    W -- yes --> E{"parent == head?"}
    E -- yes --> EXT["EXTENDED"]
    E -- no --> RE["REORG<br/>find common ancestor,<br/>report removed/added"]
    EXT --> ORPH["connect any orphans<br/>waiting on this block"]
    RE --> ORPH
```

---

## Part C — Step by step

```bash
cd phase-2-cryptography/week-05-consensus-forks
pip install -r requirements-dev.txt
python -m pytest --cov=consensus_sim
python -m demos.fork_story
```

1. **PoW** ([block.py](consensus_sim/block.py)): `meets_target` checks
   `int(hash) < 2^(256 − bits)`. `mine` brute-forces the nonce. Tests show
   tampering invalidates PoW and that expected work doubles per bit.
2. **Block tree** ([blocktree.py](consensus_sim/blocktree.py)): store
   *every* valid block, track cumulative work, and switch heads only on
   **strictly** more work (ties keep the first-seen block).
3. **Reorg detection**: walk both tips back to the common ancestor and
   report what was removed and added. The `Reorg` record is exactly what an
   indexer needs to roll back its database (Week 17).
4. **Network** ([network.py](consensus_sim/network.py)): each producer mines
   on its *own* head and gossips only to reachable peers. `heal()` syncs
   everything.
5. **PoS + BFT** ([pos.py](consensus_sim/pos.py), [bft.py](consensus_sim/bft.py)):
   pure functions, easy to property-test.

Demo output (abridged):

```text
2) Partition {n1,n2} | {n3,n4,n5}: both sides keep building = FORK
  n1: genesis -> #1(n1) -> #2(n1)
  n3: genesis -> #1(n1) -> #2(n3) -> #3(n4)

3) Partition heals; heaviest chain wins:
  n1 REORG depth=1: dropped [('alice pays bob 10',)]
  'alice pays bob 10' confirmed? False -> wallet must re-broadcast it

5) BFT: how many validators do we need?
  n=3   tolerates f=0  quorum=3  overlap=3
  n=4   tolerates f=1  quorum=3  overlap=2
```

## Assignment

1. **Double-spend experiment:** during a partition, have Alice spend the same
   coins on *both* sides (`"alice pays bob 10"` on the minority,
   `"alice pays carol 10"` on the majority). After healing, which payment
   survives? Write a test.
2. Add `BlockTree.finalize(hash)` that makes a block **irreversible**: any
   reorg that would remove it raises an error. This is how PoS checkpoints
   behave.
3. Journal: explain to a non-technical stakeholder why "1 confirmation" isn't
   safe for a high-value payment.

## ✅ Week 5 checklist

- [ ] I can draw a fork, identify the common ancestor and the reorg depth.
- [ ] I can explain heaviest-chain vs longest-chain.
- [ ] I can explain probabilistic vs economic vs BFT finality.
- [ ] I can explain why BFT needs n ≥ 3f + 1 (safety **and** liveness).
- [ ] I know what my dApp must do when a reorg removes a transaction.

**Next:** [Phase 3 — Week 6: Solidity basics](../../phase-3-smart-contracts/week-06-solidity-basics/)
