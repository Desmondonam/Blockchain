# Week 1 — Blockchain Concepts

> **Goal:** explain, in your own words and with a diagram, how a transaction
> moves from a user's wallet into a block that everyone agrees on.

**Time budget:** 8–12 h · **Prerequisites:** none

---

## 1.1 The problem a blockchain solves

Picture three banks that keep their own ledgers of who owes whom. Each night
they reconcile. When the numbers disagree, people spend days working out
whose copy is right.

```mermaid
flowchart LR
    subgraph Centralized["Centralized: one ledger, one owner"]
        direction TB
        U1[Alice] --> DB[(Bank DB)]
        U2[Bob] --> DB
        U3[Carol] --> DB
    end
    subgraph Distributed["Distributed ledger: many copies, one agreed history"]
        direction TB
        N1[(Node A)] <--> N2[(Node B)]
        N2 <--> N3[(Node C)]
        N3 <--> N1
    end
```

| | Centralized database | Distributed ledger / blockchain |
|---|---|---|
| Who can write? | The operator | Anyone following the protocol (public) or approved members (permissioned) |
| Who do you trust? | The operator | The protocol + an honest majority of validators |
| Single point of failure? | Yes | No (many replicas) |
| Can history be quietly rewritten? | Yes, by the admin | Not without detection, and economically very hard |
| Throughput | Very high | Lower (agreement costs time) |
| Privacy | Easy | Hard (public by default) |

**Key insight:** a blockchain **trades efficiency for not having to trust a
single party**. It's only worth that cost when the parties writing shared
state don't fully trust each other *and* no acceptable intermediary exists.

## 1.2 Vocabulary you must own

| Term | One-sentence definition |
|------|------------------------|
| **Ledger** | An append-only record of transactions. |
| **Transaction (tx)** | A signed instruction from an account to change state ("send 5 to Bob", "call `issue()`"). |
| **Block** | A batch of transactions plus a header that contains the **hash of the previous block**. |
| **Chain** | Blocks linked by those previous-hash pointers. Change any block and every later link breaks. |
| **Node** | A computer running the protocol software that stores the chain and checks the rules. |
| **Full node** | Checks every block and transaction itself. |
| **Light client** | Checks headers and proofs, and trusts full nodes for the rest. |
| **Miner (PoW)** | A node that competes to find a hash below a target to earn the right to add a block. |
| **Validator (PoS)** | A node that locks up (stakes) coins to earn the right to propose and attest to blocks. |
| **Mempool** | Each node's waiting room of valid transactions that aren't in a block yet. |
| **Consensus** | The rules by which nodes agree on *which* block comes next. |
| **State** | The current snapshot (balances, contract storage) you get by replaying every transaction. |

## 1.3 Anatomy of a block

```mermaid
flowchart LR
    subgraph B0["Block 41"]
        H0["Header<br/>prev: 0x9a1f...<br/>merkle root: 0x55c2...<br/>timestamp<br/>nonce / proposer"]
        T0["Transactions<br/>tx1, tx2, tx3"]
    end
    subgraph B1["Block 42"]
        H1["Header<br/>prev: hash(Block 41)<br/>merkle root: 0x7be0...<br/>timestamp<br/>nonce / proposer"]
        T1["Transactions<br/>tx4, tx5"]
    end
    subgraph B2["Block 43"]
        H2["Header<br/>prev: hash(Block 42)<br/>merkle root: 0x0d3a...<br/>timestamp<br/>nonce / proposer"]
        T2["Transactions<br/>tx6"]
    end
    B0 --> B1 --> B2
```

The **Merkle root** is a single hash that commits to every transaction in the
block (Week 4 covers it in depth). Because the next block's header contains
this block's hash, changing tx2 changes Block 41's Merkle root, which changes
its header hash, which breaks Block 42's `prev` pointer, and so on to the tip.

## 1.4 The journey of a transaction (the Week 1 assignment diagram)

```mermaid
sequenceDiagram
    autonumber
    actor Alice
    participant W as Wallet
    participant RPC as RPC node
    participant P2P as P2P network (mempools)
    participant V as Validator / miner
    participant Chain as All full nodes

    Alice->>W: "Send 1 ETH to Bob"
    W->>W: Build tx {to, value, nonce, gas, chainId}
    W->>W: Sign with Alice's private key
    W->>RPC: eth_sendRawTransaction(signedTx)
    RPC->>RPC: Validate signature, nonce, balance, gas
    RPC-->>W: txHash (the tx is pending, not confirmed)
    RPC->>P2P: Gossip tx to peers
    P2P->>V: tx arrives in the validator's mempool
    V->>V: Pick txs (usually by fee), execute, build block
    V->>Chain: Propose / broadcast block
    Chain->>Chain: Every node re-executes and validates the block
    Chain-->>W: Receipt available (1 confirmation)
    Note over Chain: More blocks build on top → finality
    W-->>Alice: "Confirmed ✔"
```

### The same journey as a state machine

```mermaid
stateDiagram-v2
    [*] --> Created: wallet builds tx
    Created --> Signed: private key signs
    Signed --> Pending: broadcast to RPC
    Pending --> Dropped: fee too low / replaced / expired
    Pending --> Included: validator puts it in a block
    Included --> Reverted: execution failed (still costs gas!)
    Included --> Succeeded: execution OK
    Succeeded --> Reorged: block replaced by competing fork
    Reorged --> Pending: tx returns to mempool
    Succeeded --> Finalized: enough confirmations / finality checkpoint
    Finalized --> [*]
```

> ⚠️ **Common misconceptions**
> - *"I got a txHash, so it worked."* No. A txHash only means the node
>   **accepted** the transaction. It can still be dropped, revert, or be
>   reorged out.
> - *"Reverted transactions are free."* No. On Ethereum you pay for the gas
>   used up to the point of revert.
> - *"Blockchains store files."* Mostly not. They store small, essential state
>   and hashes. Big data lives off-chain.

## 1.5 Miners vs validators

| | Proof of Work (Bitcoin) | Proof of Stake (Ethereum since 2022) |
|---|---|---|
| Right to propose comes from | Computing work (hashes) | Locked stake + random selection |
| Cost of attacking | Electricity + hardware | Your stake gets slashed |
| Block time | ~10 min | 12 s slots |
| Finality | Probabilistic (wait ~6 blocks) | Economic finality after ~2 epochs (~13 min) |

Week 5 has you simulate both.

## 1.6 Hands-on: watch a real chain (30 min, read-only)

1. Open <https://etherscan.io> (Ethereum) and <https://mempool.space> (Bitcoin).
2. Click the latest block. Find: block number, parent hash, number of txs,
   gas used, fee recipient or miner.
3. Click any transaction. Find: from, to, value, nonce, gas price, status.
4. On mempool.space, watch unconfirmed transactions waiting in the mempool.

Write down which field links a block to its parent.

## 1.7 Assignment

Create `my-work/week-01/transaction-journey.md` containing:

1. **A diagram** (Mermaid, draw.io, or a photo of paper) showing a
   transaction's path from wallet to finality. Label every actor.
2. **A 300-word explanation** that answers:
   - What does the signature prove, and what doesn't it prove?
   - Why does a node check the nonce?
   - What is the difference between *included*, *confirmed* and *finalized*?
   - Why can't a single validator change an old transaction?
3. **Centralized vs decentralized**: describe one system you use daily that
   should stay centralized, and explain why.

A worked solution is in [SOLUTION.md](SOLUTION.md). Try it yourself first.

## ✅ Week 1 checklist

- [ ] I can define all the terms in §1.2 without looking.
- [ ] I can draw the transaction sequence diagram from memory.
- [ ] I explored a real block and transaction on an explorer.
- [ ] My assignment is committed: `git commit -m "docs(week-01): transaction journey diagram"`
- [ ] Journal entry written.

**Next:** [Week 2 — Chain types, consensus & finality](../week-02-chain-types-consensus/)
