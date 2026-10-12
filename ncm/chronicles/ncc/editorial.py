"""Editorial: what is worth saying, by whom, and what stays silent.

For each fact the editor builds one candidate per station whose epistemic view permits it, scores it, and selects
or suppresses it WITH A REASON (the trace prints every reason). Silence is a valid outcome and the common one.

Scoring starts from NCM's own salience and adds editorial weight (player involvement, milestones, recurring rivals,
the Week's structure). Suppression reasons: already judged, stale, below threshold, station cooldown, topic already
told by this station, topic already told by two stations, global spacing.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional

from .epistemics import View, view
from .facts import Fact
from .memory import Chronicle
from .stations import STATIONS, Station

# How long a fact stays worth saying (seconds of canonical time). Live racing goes stale fast; the Week does not.
MAX_AGE = {"player_position": 90, "player_result": 1800, "player_dnf": 1800, "player_entered": 900,
           "week_step": 7200, "week_moody": 7200, "week_open": 6 * 3600, "week_end": 6 * 3600, "week_verdict": 3600,
           "chrome_truth": 900}
DEFAULT_MAX_AGE = 3 * 3600
GLOBAL_GAP_S = 6.0
MAX_STATIONS_PER_TOPIC = 2


@dataclass
class Candidate:
    fact: Fact
    station: Station
    view: Optional[View]
    score: int = 0
    selected: bool = False
    reason: str = ""
    recall: List[Dict[str, str]] = field(default_factory=list)
    milestones: List[Dict[str, str]] = field(default_factory=list)


def _score(f: Fact, st: Station, recall: List, milestones: List, followup: bool = False) -> int:
    s = max(0, min(100, f.salience)) + (25 if followup else 0)
    if st.id == "narrator":
        s += 30 if f.involves_player else (0 if f.kind.startswith("week_") else -10)
        s += 15 * len(milestones)
        s += 10 if any("raced each other" in r["text"] for r in recall) else 0
        if f.kind in ("week_open", "week_end"):
            s += 10
        if f.kind == "player_position":
            # top-three changes and big swings matter; a single place mid-pack mostly does not
            a, b = f.truth.get("from_position", 0), f.truth.get("to_position", 0)
            s += 10 if min(a, b) <= 3 else -5
            if f.truth.get("reversal"):
                s += 20        # gained it and threw it away (or the reverse) inside one beat
        if f.kind == "week_verdict":
            s += 20
    elif st.id == "news":
        if f.kind.startswith("wire_"):
            s += 20
        if f.kind == "vehicle_destroyed":
            s += 15
        if f.kind in ("week_open", "week_end"):
            s += 5
        if f.kind == "week_step":
            s -= 20           # race control carries the PA; locals react to it
    elif st.id == "race_control":
        if f.kind in ("week_step", "chrome_attack"):
            s += 5
        if f.kind == "player_result":
            s -= 10           # the classification is functional; the narrator usually has it
    elif st.id == "street":
        if f.kind == "vehicle_destroyed":
            s += 20
        if f.kind == "week_step" and f.truth.get("step") in ("back_to_sane", "clampdown"):
            s += 0
        elif f.kind == "week_step":
            s -= 30
        if f.kind.startswith("wire_"):
            s -= 40           # locals do not read the WIRE out loud
    elif st.id == "garage":
        s = max(s, 50)        # NCM gives R&D releases low news salience; for the garage they are the story
    return s


class Editor:
    def __init__(self, chronicle: Chronicle, speak_after: float = 0.0, stations=None):
        self.chron = chronicle
        self.stations = stations or STATIONS
        self.speak_after = speak_after          # facts older than this (unix s) are backfill: learned, silent
        self.last_spoken: Dict[str, float] = {}
        self.last_any = -1e18
        self.topic_stations: Dict[str, set] = {}
        self.told_races: Dict[str, str] = {}     # race id -> topic first told about it (stories develop)

    def judge(self, f: Fact, now: float) -> List[Candidate]:
        disc = self.chron.discovery()
        out: List[Candidate] = []
        if self.chron.was_seen(f.id):
            return [Candidate(f, STATIONS["narrator"], None, reason="DEDUP: already judged on this Tape (re-poll/restart)")]
        age = now - f.at
        max_age = MAX_AGE.get(f.kind, DEFAULT_MAX_AGE)
        milestones_new = self.chron.learn(f)
        milestones = [m for m in (self.chron.milestone_text(k) for k in milestones_new) if m]
        recall = self.chron.recall(f)
        if f.at < self.speak_after:
            self.chron.mark_seen(f.id, "backfill")
            return [Candidate(f, STATIONS["narrator"], None, recall=recall,
                              reason=f"backfill: happened {now - f.at:.0f}s ago, before this session (learned, silent)")]
        narrator_first = f.involves_player or f.kind in ("week_open", "week_end", "week_verdict")
        order = sorted(self.stations.values(),
                       key=lambda s: (-(100 if narrator_first and s.id == "narrator" else 0), -s.priority))
        for st in order:
            v, why = view(f, st, disc)
            c = Candidate(f, st, v, recall=recall if st.id == "narrator" else [],
                          milestones=milestones if st.id == "narrator" else [])
            out.append(c)
            if v is None:
                c.reason = "epistemic: " + why
                continue
            race = f.truth.get("race")
            followup = (bool(race) and race in self.told_races and self.told_races[race] != v.topic
                        and not f.kind.startswith("player_"))
            c.score = _score(f, st, recall, milestones, followup)
            if age > max_age:
                c.reason = f"stale: {age:.0f}s old > {max_age}s for {f.kind}"
                continue
            if c.score < st.threshold:
                c.reason = f"below threshold ({c.score} < {st.threshold})"
                continue
            told = self.topic_stations.get(v.topic, set())
            if st.id in told or self.chron.topic_spoken(v.topic) == st.id:
                c.reason = f"topic already told by {st.id}"
                continue
            if len(told) >= MAX_STATIONS_PER_TOPIC:
                c.reason = f"topic already told by {', '.join(sorted(told))}"
                continue
            since = now - self.last_spoken.get(st.id, -1e18)
            urgent = c.score >= st.threshold + 30 or f.kind == "week_pulse"
            if since < st.cooldown_s and not urgent:
                c.reason = f"cooldown: {st.id} spoke {since:.0f}s ago (< {st.cooldown_s:.0f}s)"
                continue
            c.selected = True
            if f.truth.get("race"):
                self.told_races.setdefault(f.truth["race"], v.topic)
            c.reason = f"selected: score {c.score} >= {st.threshold}" + (" (urgent, through cooldown)" if urgent and since < st.cooldown_s else "")
            told = self.topic_stations.setdefault(v.topic, set())
            told.add(st.id)
        # one fact rarely deserves more than two voices; keep the two best, the rest is silence
        sel = sorted([c for c in out if c.selected], key=lambda c: (-c.score, -c.station.priority))
        for c in sel[MAX_STATIONS_PER_TOPIC:]:
            c.selected = False
            c.reason = "dropped: two stations already carry this fact"
            self.topic_stations.get(c.view.topic, set()).discard(c.station.id)
        for c in out:
            if c.selected:
                self.last_spoken[c.station.id] = now
        self.chron.mark_seen(f.id, ",".join(c.station.id for c in out if c.selected) or "silence")
        return out


def coalesce_positions(facts: List[Fact]) -> Fact:
    """Merge consecutive in-race position changes of one race into one story beat.

    P5 -> P3 then P3 -> P4 within the window becomes: from 5th to 3rd, then back to 4th -- a reversal. The merged fact
    keeps every source id (provenance) and only canonical fields.
    """
    if len(facts) == 1:
        return facts[0]
    facts = sorted(facts, key=lambda f: f.truth.get("race_ms", 0))
    first, last = facts[0], facts[-1]
    best = min(f.truth["to_position"] for f in facts)
    start, end = first.truth["from_position"], last.truth["to_position"]
    passed = sorted({p for f in facts for p in f.truth.get("passed") or []})
    passed_by = sorted({p for f in facts for p in f.truth.get("passed_by") or []})
    reversal = best < start and end > best
    truth = {"race": first.truth["race"], "from_position": start, "best_position": best, "to_position": end,
             "change": start - end, "passed": passed, "passed_by": passed_by, "reversal": reversal,
             "steps": [(f.truth["from_position"], f.truth["to_position"]) for f in facts],
             "race_ms": last.truth.get("race_ms"), "driver": first.truth.get("driver")}
    return Fact(id="+".join(f.id for f in facts), kind="player_position", at=last.at, tape=first.tape,
                source=first.source, truth=truth, knowers=set(first.knowers),
                salience=max(f.salience for f in facts) + 5 * (len(facts) - 1), provenance=first.provenance,
                entities=first.entities, involves_player=True, causes=[f.id for f in facts])
