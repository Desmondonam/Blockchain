"""Pure domain model: no I/O, no clocks, no printing.

Everything in this package is deterministic given its inputs, which is what
makes it easy to test. Infrastructure (files, CLI, real time) lives elsewhere
and depends on this package, never the other way round.
"""
