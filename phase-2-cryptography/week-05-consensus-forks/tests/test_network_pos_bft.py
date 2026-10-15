from collections import Counter

import pytest
from hypothesis import given
from hypothesis import strategies as st

from consensus_sim import bft
from consensus_sim.network import Network
from consensus_sim.pos import SignedHeader, StakeError, find_equivocations, select_proposer, slash


# ------------------------------------------------------------------ network
def test_partition_creates_fork_and_heal_reorgs_minority():
    net = Network(["n1", "n2", "n3", "n4", "n5"])
    net.produce("n1", ("tx-common",))
    assert net.in_consensus()

    net.partition(["n1", "n2"], ["n3", "n4", "n5"])
    minority = net.produce("n1", ("tx-A: alice pays bob",))
    for _ in range(3):  # the majority side keeps producing
        net.produce("n3", ("tx-B",))
    assert not net.in_consensus()

    net.heal()
    assert net.in_consensus()
    n1 = net.nodes["n1"]
    assert n1.reorg_log and n1.reorg_log[-1].depth == 1
    assert minority.hash in [b.hash for b in n1.reorg_log[-1].removed]
    # The minority's tx is no longer confirmed anywhere. A wallet must re-broadcast it.
    assert n1.tree.find_record("tx-A: alice pays bob") is None
    assert n1.tree.find_record("tx-common") is not None


def test_majority_side_does_not_reorg():
    net = Network(["a", "b", "c"])
    net.partition(["a"], ["b", "c"])
    net.produce("a")
    net.produce("b")
    net.produce("b")
    net.heal()
    assert net.nodes["b"].reorg_log == []
    assert len(net.nodes["a"].reorg_log) == 1


def test_partition_must_cover_all_nodes():
    net = Network(["a", "b", "c"])
    with pytest.raises(ValueError):
        net.partition(["a"], ["b"])


# ---------------------------------------------------------------------- PoS
STAKES = {"v1": 32, "v2": 32, "v3": 64, "v4": 128}


def test_proposer_selection_is_deterministic():
    assert select_proposer(STAKES, b"seed", 7) == select_proposer(STAKES, b"seed", 7)


def test_proposer_frequency_tracks_stake():
    counts = Counter(select_proposer(STAKES, b"epoch-1", slot) for slot in range(8000))
    total = sum(STAKES.values())
    for v, stake in STAKES.items():
        assert abs(counts[v] / 8000 - stake / total) < 0.03


def test_zero_stake_never_selected():
    stakes = {"v1": 10, "lazy": 0}
    assert {select_proposer(stakes, b"s", i) for i in range(200)} == {"v1"}


def test_no_stake_raises():
    with pytest.raises(StakeError):
        select_proposer({"v1": 0}, b"s", 0)


def test_equivocation_detected_and_slashed():
    headers = [
        SignedHeader("v1", 10, "0xaaa"),
        SignedHeader("v2", 10, "0xaaa"),
        SignedHeader("v1", 10, "0xbbb"),  # v1 signed two different blocks for slot 10
        SignedHeader("v2", 11, "0xccc"),
        SignedHeader("v2", 11, "0xccc"),  # re-broadcasting the SAME block is fine
    ]
    offenders = find_equivocations(headers)
    assert offenders == {"v1"}
    after = slash(STAKES, offenders, penalty_bps=5000)
    assert after["v1"] == 16 and after["v2"] == 32


def test_slash_rejects_bad_penalty():
    with pytest.raises(StakeError):
        slash(STAKES, ["v1"], 10_001)


# ---------------------------------------------------------------------- BFT
@pytest.mark.parametrize("n, f, q", [(4, 1, 3), (7, 2, 5), (10, 3, 7), (100, 33, 67)])
def test_classic_bft_numbers(n, f, q):
    assert bft.max_faulty(n) == f
    assert bft.quorum(n) == q
    assert bft.tolerates(n, f)


def test_three_nodes_cannot_tolerate_one_fault():
    assert bft.is_safe(3, 1)  # still safe...
    assert not bft.is_live(3, 1)  # ...but one silent node halts the chain


@given(st.integers(1, 300), st.integers(0, 100))
def test_tolerates_iff_n_at_least_3f_plus_1(n, f):
    """Property: the quorum rule is safe and live exactly when n >= 3f + 1."""
    assert bft.tolerates(n, f) == (n >= 3 * f + 1)


def test_commit_requires_quorum():
    votes = {"v1": "A", "v2": "A", "v3": "B"}
    assert bft.committed_block(votes, n=4) is None  # 2 < 3: no decision (liveness wait)
    votes["v4"] = "A"
    assert bft.committed_block(votes, n=4) == "A"
    assert bft.committed_block({}, n=4) is None
