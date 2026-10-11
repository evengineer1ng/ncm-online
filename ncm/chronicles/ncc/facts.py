"""The fact model: what NCM's canonical state says happened, and who could know it.

A Fact is built ONLY from canonical NCM rows (normalize.py). Nothing downstream may add to `truth`; the editorial
and language layers may only select, withhold and rephrase.

Knowledge domains (who can know a fact, before any permission rule):
    canonical  - the simulation's truth ledger (everything, including chrome_event and hidden meters)
    public     - what Night City can see or was told (WIRE, public_summary, announcements, Moody's rolls)
    officials  - what race officials have established (schedules, classifications, attributions, penalties)
    player     - what the player experienced first hand (their entries, results, crossings in their race)
    local      - what people on the street at a place could have seen (physical incidents with a location)
    technical  - observed engineering evidence (machines, parts, R&D runs)
Stations draw from domains (stations.py); the Narrator additionally has permission rules (epistemics.py).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Set

DOMAINS = ("canonical", "public", "officials", "player", "local", "technical")


@dataclass
class Fact:
    id: str                          # stable: "<table>:<natural key>" -- dedup and provenance key
    kind: str                        # e.g. race_result, vehicle_destroyed, week_step, player_position
    at: int                          # unix seconds when it happened (canonical time, not when we read it)
    tape: str                        # server_id: the Tape (continuity) this fact belongs to
    source: str                      # table (or 'fixture:<table>' when replayed from a fixture)
    truth: Dict[str, Any]            # canonical fields; may contain secrets (see `secret`)
    public: Optional[str] = None     # the canonical public statement, when NCM wrote one (public_summary, PA text)
    knowers: Set[str] = field(default_factory=lambda: {"canonical"})
    salience: int = 20               # NCM's own salience where it has one (paddock.tape), else ours
    provenance: str = "simulated"    # simulated | physical | reported -- NCM's provenance, preserved
    entities: List[List[str]] = field(default_factory=list)
    run: Optional[int] = None        # Racing Week run index, when known
    hours: Optional[float] = None    # run hour, when known
    place: Optional[str] = None      # route / district, when known
    secret: Set[str] = field(default_factory=set)      # truth keys NEVER spoken by anyone (hidden meters)
    involves_player: bool = False
    causes: List[str] = field(default_factory=list)    # canonical cause refs (fact ids or NCM event ids)

    def short(self) -> str:
        return f"{self.id} kind={self.kind} sal={self.salience} prov={self.provenance} src={self.source}"

    def speakable_truth(self) -> Dict[str, Any]:
        return {k: v for k, v in self.truth.items() if k not in self.secret and v not in (None, "")}
