"""Fixture transition table — the same public shape as the real
skills/_lattice-lib/scripts/lib/transition_table.py (Transition.from_ / .to,
LEGAL_EDGES tuple); four edges only."""
from typing import NamedTuple, Tuple


class Transition(NamedTuple):
    from_: str
    to: str


LEGAL_EDGES: Tuple[Transition, ...] = (
    Transition("init", "queued"),
    Transition("queued", "in-progress"),
    Transition("in-progress", "pr-open"),
    Transition("pr-open", "closed"),
)
