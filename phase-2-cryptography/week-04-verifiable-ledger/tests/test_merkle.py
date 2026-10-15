from hypothesis import given
from hypothesis import strategies as st

from ledger.merkle import EMPTY_ROOT, MerkleTree, hash_node, verify_proof

leaves_strategy = st.lists(st.binary(min_size=1, max_size=40), min_size=1, max_size=40)


def test_empty_tree_has_fixed_root():
    assert MerkleTree([]).root == EMPTY_ROOT


def test_proof_size_is_logarithmic():
    tree = MerkleTree([i.to_bytes(2, "big") for i in range(1024)])
    assert len(tree.proof(517)) == 10  # log2(1024)


@given(leaves_strategy, st.data())
def test_every_leaf_has_a_valid_proof(leaves, data):
    """Property: for ANY list of leaves, every leaf's proof verifies."""
    tree = MerkleTree(leaves)
    i = data.draw(st.integers(0, len(leaves) - 1))
    assert verify_proof(leaves[i], tree.proof(i), tree.root)


@given(leaves_strategy, st.data())
def test_altered_leaf_fails_proof(leaves, data):
    tree = MerkleTree(leaves)
    i = data.draw(st.integers(0, len(leaves) - 1))
    altered = leaves[i] + b"!"
    assert not verify_proof(altered, tree.proof(i), tree.root)


@given(leaves_strategy)
def test_root_changes_when_any_leaf_changes(leaves):
    root = MerkleTree(leaves).root
    for i in range(len(leaves)):
        changed = list(leaves)
        changed[i] = changed[i] + b"x"
        assert MerkleTree(changed).root != root


def test_no_duplicate_last_leaf_collision():
    """CVE-2012-2459: with duplication, [a,b,c] and [a,b,c,c] share a root."""
    a, b, c = b"a", b"b", b"c"
    assert MerkleTree([a, b, c]).root != MerkleTree([a, b, c, c]).root


def test_inner_node_cannot_pass_as_leaf():
    """Without domain separation, H(left||right) of an inner node could be 'proven' as a leaf."""
    leaves = [b"a", b"b", b"c", b"d"]
    tree = MerkleTree(leaves)
    level1 = tree._levels[1]  # noqa: SLF001 (white-box test)
    fake_leaf = level1[0] + level1[1]
    assert hash_node(level1[0], level1[1]) == tree.root
    assert not verify_proof(fake_leaf, [], tree.root)
