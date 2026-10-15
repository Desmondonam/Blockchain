from dataclasses import replace

import pytest

from consensus_sim.block import GENESIS, Block, meets_target, mine
from consensus_sim.blocktree import AddStatus, BlockTree, InvalidBlock


def child(parent: Block, producer: str = "m", records: tuple[str, ...] = (), bits: int = 0) -> Block:
    template = Block(parent.height + 1, parent.hash, producer, records, parent.timestamp + 12, bits)
    return mine(template).block


def chain_of(n: int, start: Block = GENESIS, producer: str = "m", bits: int = 0) -> list[Block]:
    blocks, parent = [], start
    for i in range(n):
        parent = child(parent, producer, (f"{producer}-{i}",), bits)
        blocks.append(parent)
    return blocks


# ----------------------------------------------------------------- PoW
def test_mined_block_meets_target():
    result = mine(Block(1, GENESIS.hash, "m", (), 12, difficulty_bits=10))
    assert meets_target(result.block)
    assert result.block.hash.startswith("00")  # 10 bits => at least 2 zero hex digits


def test_changing_mined_block_invalidates_pow():
    mined = mine(Block(1, GENESIS.hash, "m", ("pay bob 5",), 12, difficulty_bits=12)).block
    tampered = replace(mined, records=("pay bob 500",))
    assert not meets_target(tampered)


def test_expected_work_grows_exponentially():
    attempts = [sum(mine(Block(1, GENESIS.hash, f"m{i}", (), 12, bits)).attempts for i in range(20)) / 20
                for bits in (4, 8)]
    assert attempts[1] > 4 * attempts[0]  # 16x expected; allow wide randomness margin


# ---------------------------------------------------------- tree basics
def test_extends_head():
    tree = BlockTree()
    blocks = chain_of(3)
    statuses = [tree.add(b).status for b in blocks]
    assert statuses == [AddStatus.EXTENDED] * 3
    assert tree.head == blocks[-1].hash
    assert [b.height for b in tree.canonical_chain()] == [0, 1, 2, 3]


def test_duplicate_is_ignored():
    tree = BlockTree()
    b = child(GENESIS)
    tree.add(b)
    assert tree.add(b).status is AddStatus.DUPLICATE


@pytest.mark.parametrize(
    "mutate, message",
    [
        (lambda b: replace(b, height=5), "height"),
        (lambda b: replace(b, timestamp=-1), "timestamp"),
    ],
)
def test_rejects_invalid_blocks(mutate, message):
    tree = BlockTree()
    with pytest.raises(InvalidBlock, match=message):
        tree.add(mutate(child(GENESIS)))


def test_rejects_insufficient_pow():
    tree = BlockTree(min_difficulty_bits=8)
    weak = Block(1, GENESIS.hash, "m", (), 12, difficulty_bits=2)
    with pytest.raises(InvalidBlock, match="difficulty"):
        tree.add(mine(weak).block)
    # Deterministically find a nonce that does NOT meet a 16-bit target.
    unmined = next(blk for n in range(100)
                   if not meets_target(blk := Block(1, GENESIS.hash, "m", (), 12, 16, nonce=n)))
    with pytest.raises(InvalidBlock, match="proof of work"):
        tree.add(unmined)


# --------------------------------------------------------- forks & reorgs
def test_competing_block_creates_side_branch_first_seen_wins_tie():
    tree = BlockTree()
    a1, b1 = child(GENESIS, "alice"), child(GENESIS, "bob")
    assert tree.add(a1).status is AddStatus.EXTENDED
    assert tree.add(b1).status is AddStatus.SIDE_BRANCH  # equal work: keep first-seen
    assert tree.head == a1.hash


def test_heavier_branch_triggers_reorg():
    tree = BlockTree()
    a = chain_of(2, producer="alice")
    b = chain_of(3, producer="bob")
    for blk in a:
        tree.add(blk)
    results = [tree.add(blk) for blk in b]
    assert [r.status for r in results] == [AddStatus.SIDE_BRANCH, AddStatus.SIDE_BRANCH, AddStatus.REORG]
    reorg = results[-1].reorgs[0]
    assert reorg.common_ancestor == GENESIS.hash
    assert reorg.depth == 2
    assert [blk.hash for blk in reorg.removed] == [blk.hash for blk in a]
    assert [blk.hash for blk in reorg.added] == [blk.hash for blk in b]


def test_fork_choice_is_by_work_not_length():
    """A shorter chain with MORE work beats a longer chain with less."""
    tree = BlockTree()
    light = chain_of(3, producer="light", bits=0)  # work 1 each = 3
    heavy = chain_of(1, producer="heavy", bits=3)  # work 8
    for blk in light:
        tree.add(blk)
    assert tree.add(heavy[0]).status is AddStatus.REORG
    assert tree.head == heavy[0].hash


def test_record_in_reorged_block_loses_confirmations():
    tree = BlockTree()
    a1 = child(GENESIS, "alice", ("pay carol 10",))
    tree.add(a1)
    assert tree.confirmations(a1.hash) == 1
    assert tree.find_record("pay carol 10") == a1

    for blk in chain_of(2, producer="bob"):
        tree.add(blk)
    assert tree.confirmations(a1.hash) == 0  # back to "pending"
    assert tree.find_record("pay carol 10") is None


def test_orphans_connect_when_parent_arrives():
    tree = BlockTree()
    b1, b2, b3 = chain_of(3)
    assert tree.add(b3).status is AddStatus.ORPHAN
    assert tree.add(b2).status is AddStatus.ORPHAN
    assert tree.add(b1).status is AddStatus.EXTENDED
    assert tree.head == b3.hash


# ------------------------------------------------------------- finality
def test_probabilistic_finality_after_k_confirmations():
    tree = BlockTree()
    blocks = chain_of(6)
    for blk in blocks:
        tree.add(blk)
    assert tree.is_final(blocks[0].hash, depth=6)
    assert not tree.is_final(blocks[1].hash, depth=6)


def test_tampering_cost_grows_with_depth():
    """To change block k you must re-mine it AND every block after it."""
    bits = 8
    honest = chain_of(5, bits=bits)
    target_index = 1  # change the 2nd block
    rewritten_parent = honest[target_index - 1]
    attempts = 0
    for i in range(target_index, len(honest)):
        tpl = replace(honest[i], parent_hash=rewritten_parent.hash, nonce=0,
                      records=("forged",) if i == target_index else honest[i].records)
        result = mine(tpl)
        attempts += result.attempts
        rewritten_parent = result.block
    assert attempts > (len(honest) - target_index)  # re-mined 4 blocks, not 1
