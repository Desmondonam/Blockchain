import itertools

import pytest

from minichain.domain.blockchain import Blockchain

GENESIS = {"alice": 100, "bob": 20}


@pytest.fixture
def clock():
    """Deterministic clock: 1000, 1012, 1024, ... (12 s slots)."""
    ticks = itertools.count(1000, 12)
    return lambda: next(ticks)


@pytest.fixture
def chain(clock) -> Blockchain:
    return Blockchain(dict(GENESIS), clock=clock)
