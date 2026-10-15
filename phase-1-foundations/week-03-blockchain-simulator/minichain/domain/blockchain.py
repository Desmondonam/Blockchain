"""The chain: mempool, block production, validation and state queries."""

from collections.abc import Callable, Sequence
from dataclasses import dataclass

from .block import GENESIS_PREVIOUS_HASH, Block
from .errors import InvalidBlockError, MinichainError
from .state import State
from .transaction import Transaction

Clock = Callable[[], int]


@dataclass(frozen=True)
class Receipt:
    tx_id: str
    block_index: int
    block_hash: str


class Blockchain:
    """An in-memory, single-node chain.

    The clock is *injected* instead of calling ``time.time()`` directly, so
    tests are deterministic and reproducible. This is a core testing practice.
    """

    def __init__(self, genesis_balances: dict[str, int], clock: Clock) -> None:
        if any(v < 0 for v in genesis_balances.values()):
            raise ValueError("genesis balances must be non-negative")
        self._clock = clock
        self._genesis_balances = dict(genesis_balances)
        genesis = Block(0, GENESIS_PREVIOUS_HASH, clock(), "genesis", ())
        self._blocks: list[Block] = [genesis]
        self._state = State(balances=dict(genesis_balances))
        self._mempool: dict[str, Transaction] = {}
        self._receipts: dict[str, Receipt] = {}

    # ----------------------------------------------------------------- queries
    @property
    def blocks(self) -> tuple[Block, ...]:
        return tuple(self._blocks)

    @property
    def head(self) -> Block:
        return self._blocks[-1]

    @property
    def genesis_balances(self) -> dict[str, int]:
        return dict(self._genesis_balances)

    @property
    def mempool(self) -> tuple[Transaction, ...]:
        return tuple(self._mempool.values())

    def balance_of(self, account: str) -> int:
        return self._state.balance_of(account)

    def nonce_of(self, account: str) -> int:
        return self._state.nonce_of(account)

    def receipt(self, tx_id: str) -> Receipt | None:
        """``None`` means the tx is pending or unknown, not that it failed."""
        return self._receipts.get(tx_id)

    def total_supply(self) -> int:
        return self._state.total_supply()

    # ------------------------------------------------------------- submission
    def submit(self, tx: Transaction) -> str:
        """Add ``tx`` to the mempool after checking it against *pending* state.

        Pending state means confirmed state plus every tx already in the
        mempool. That lets a user queue nonce 0, 1, 2 before any block exists.
        """
        if tx.tx_id in self._mempool or tx.tx_id in self._receipts:
            raise MinichainError(f"duplicate transaction {tx.tx_id[:10]}")
        pending = self._state.copy()
        for queued in self._ordered_mempool():
            pending.apply(queued, proposer="pending")
        pending.validate(tx)
        self._mempool[tx.tx_id] = tx
        return tx.tx_id

    def _ordered_mempool(self) -> list[Transaction]:
        """Highest fee first, but always respecting each sender's nonce order.

        Real block builders face the same constraint: a tx with nonce 5 cannot
        come before nonce 4 from the same sender, even if it pays more.
        """
        remaining = sorted(self._mempool.values(), key=lambda t: (-t.fee, t.tx_id))
        ordered: list[Transaction] = []
        state = self._state.copy()
        progress = True
        while remaining and progress:
            progress = False
            for tx in remaining:
                try:
                    state.apply(tx, proposer="ordering")
                except MinichainError:
                    continue
                ordered.append(tx)
                remaining.remove(tx)
                progress = True
                break  # restart, so a higher-fee tx that just became valid goes first
        return ordered

    # -------------------------------------------------------- block production
    def produce_block(self, proposer: str, max_txs: int = 10) -> Block:
        """Build a block from the mempool and append it."""
        selected = tuple(self._ordered_mempool()[:max_txs])
        block = Block(
            index=self.head.index + 1,
            previous_hash=self.head.hash,
            timestamp=self._clock(),
            proposer=proposer,
            transactions=selected,
        )
        self.add_block(block)
        return block

    def add_block(self, block: Block) -> None:
        """Validate ``block`` against the current head, then apply it atomically."""
        if block.index != self.head.index + 1:
            raise InvalidBlockError(f"expected index {self.head.index + 1}, got {block.index}")
        if block.previous_hash != self.head.hash:
            raise InvalidBlockError("previous_hash does not match head")
        if block.timestamp < self.head.timestamp:
            raise InvalidBlockError("timestamp earlier than parent")

        # Apply to a copy first. If any tx fails, the real state is untouched
        # (all-or-nothing, just like a rejected block).
        candidate = self._state.copy()
        try:
            for tx in block.transactions:
                candidate.apply(tx, block.proposer)
        except MinichainError as exc:
            raise InvalidBlockError(f"block contains invalid tx: {exc}") from exc

        self._state = candidate
        self._blocks.append(block)
        for tx in block.transactions:
            self._mempool.pop(tx.tx_id, None)
            self._receipts[tx.tx_id] = Receipt(tx.tx_id, block.index, block.hash)

    # ------------------------------------------------------------ verification
    def is_valid(self) -> bool:
        """Re-verify the whole chain from genesis, as a new full node would."""
        return verify_chain(self._blocks, self._genesis_balances)


def verify_chain(blocks: Sequence[Block], genesis_balances: dict[str, int]) -> bool:
    """Return True if every link, timestamp and transaction is valid."""
    if not blocks or blocks[0].index != 0 or blocks[0].previous_hash != GENESIS_PREVIOUS_HASH:
        return False
    state = State(balances=dict(genesis_balances))
    for parent, block in zip(blocks, blocks[1:]):
        if block.index != parent.index + 1 or block.previous_hash != parent.hash:
            return False
        if block.timestamp < parent.timestamp:
            return False
        try:
            for tx in block.transactions:
                state.apply(tx, block.proposer)
        except MinichainError:
            return False
    return True
