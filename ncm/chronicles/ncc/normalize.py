"""Canonical NCM rows -> Facts.

One function per table, all fed by `Normalizer.ingest(table, rows)`. The normalizer is stateful only in what it must
remember to interpret later rows (names, which races the player entered, gate crossings so far); it never invents a
field. Where NCM keeps a value hidden from players (the Week's tolerance, a verdict's probability), the key is put in
`Fact.secret` so no station can ever speak it.

Tables read (all keyed by server_id = the Tape):
    paddock_event       the tape ledger (doc 44 §8): kind, facts, public_summary, salience, provenance
    paddock_news        WIRE stories: NCM's own public headline/body for a paddock_event
    paddock_person      names
    paddock_entry       the player's entries (human drivers) and their outcome
    paddock_result      classified results (positions, grid, DNF) -- the player's race end
    paddock_live_crossing  gate crossings in a live race -- the player's passes and losses
    chrome_event        the quickhack truth ledger (who really did what) -- canonical only
    racing_week_run     a run opens / ends (the Week)
    racing_week_event   announced steps (public PA text) -- tolerance stays secret
    racing_week_moody   Moody's public D20 rolls
    racing_week_verdict the possible-end verdicts -- probability stays secret
"""
from __future__ import annotations

import json
import os
import re
from typing import Any, Dict, Iterable, List, Optional

from .facts import Fact

# Tape kinds that put a named person on the WIRE. Salience is NCM's, carried through.
SANCTIONED = {"pro", "premier"}
TECHNICAL_KINDS = {"rnd_release"}


def _dec(v: Any) -> Any:
    if isinstance(v, (dict, list)) or v is None:
        return v
    try:
        return json.loads(v)
    except (TypeError, ValueError):
        return v


def _int(v: Any, d: int = 0) -> int:
    try:
        return int(v)
    except (TypeError, ValueError):
        return d


def _prominence(v: Any) -> int:
    """WIRE prominence -> 0..100. Small values (the R&D writer uses 4) are a 1-6 scale; larger ones are already salience."""
    p = _int(v, 1)
    return max(0, min(100, p * 15 if p <= 6 else p))


def load_week_steps(core_root: str) -> Dict[str, str]:
    """The public PA text of each Racing Week step, read from ncm/core/week/curve.lua so it never drifts."""
    path = os.path.join(core_root, "week", "curve.lua")
    out: Dict[str, str] = {}
    try:
        with open(path, encoding="utf-8") as f:
            src = f.read()
    except OSError:
        return out
    for m in re.finditer(r'\{\s*id\s*=\s*"([a-z_]+)".*?pa\s*=\s*"([^"]+)"', src, re.S):
        out[m.group(1)] = m.group(2)
    return out


def ordinal(n: int) -> str:
    n = int(n)
    if 10 <= n % 100 <= 20:
        suf = "th"
    else:
        suf = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suf}"


class Normalizer:
    def __init__(self, tape: str, player_driver_ids: Iterable[str] = (), player_name: str = "V",
                 week_steps: Optional[Dict[str, str]] = None, source_prefix: str = ""):
        self.tape = tape
        self.player_driver_ids = {str(x) for x in player_driver_ids if x}
        self.player_keys: set = set()           # person_key(s) the player races under (learned from paddock_entry)
        self.player_name = player_name
        self.names: Dict[str, str] = {}
        self.series: Dict[str, str] = {}
        self.player_races: Dict[str, Dict[str, Any]] = {}   # race_id -> entry
        self.crossings: Dict[str, Dict[int, List[tuple]]] = {}  # race -> gate -> [(t_ms, person)]
        self.player_gate_rank: Dict[str, Dict[int, int]] = {}
        self.player_gate_ahead: Dict[str, Dict[int, set]] = {}
        self.week_steps = week_steps or {}
        self.runs_seen: Dict[int, Dict[str, Any]] = {}
        self.prefix = source_prefix

    # ------------------------------------------------------------------ helpers
    def src(self, table: str) -> str:
        return self.prefix + table

    def name(self, pid: Any) -> str:
        pid = str(pid)
        if pid in self.player_keys or pid in self.player_driver_ids or pid.startswith("player:"):
            return self.player_name
        return self.names.get(pid, pid)

    def series_name(self, sid: Any) -> Any:
        return self.series.get(str(sid), sid)

    def is_player(self, pid: Any) -> bool:
        pid = str(pid)
        return pid in self.player_keys or pid in self.player_driver_ids

    def ingest(self, table: str, rows: List[Dict[str, Any]]) -> List[Fact]:
        fn = getattr(self, "_" + table, None)
        if fn is None or not rows:
            return []
        out = fn(rows)
        return [f for f in out if f is not None]

    # ------------------------------------------------------------------ names / entries
    def _paddock_person(self, rows):
        for r in rows:
            self.names[str(r["person_id"])] = r.get("display") or f"{r.get('first', '')} {r.get('last', '')}".strip()
        return []

    def _paddock_series(self, rows):
        for r in rows:
            self.series[str(r["series_id"])] = r.get("name") or r["series_id"]
        return []

    def _paddock_entry(self, rows):
        out = []
        for r in rows:
            if str(r.get("ncm_driver_id")) not in self.player_driver_ids and not self.player_driver_ids == {"*"}:
                continue
            key = str(r.get("person_key"))
            self.player_keys.add(key)
            race = str(r["race_id"])
            first = race not in self.player_races
            self.player_races[race] = dict(r)
            if first and r.get("state", "entered") == "entered":
                out.append(Fact(
                    id=f"paddock_entry:{race}:{r['ncm_driver_id']}", kind="player_entered", at=_int(r.get("entered_at")),
                    tape=self.tape, source=self.src("paddock_entry"),
                    truth={"race": race, "series": self.series_name(r.get("series_id")), "quali_ms": r.get("quali_ms"),
                           "driver": self.player_name},
                    knowers={"canonical", "player", "officials"}, salience=30, provenance="physical",
                    entities=[["human", str(r["ncm_driver_id"])], ["race", race]], involves_player=True))
        return out

    # ------------------------------------------------------------------ the tape ledger
    def _paddock_event(self, rows):
        out = []
        for r in rows:
            kind = r["kind"]
            facts = _dec(r.get("facts")) or {}
            ents = _dec(r.get("entities")) or []
            involves = any(len(e) >= 2 and self.is_player(e[1]) for e in ents if isinstance(e, list))
            knowers = {"canonical", "public"}
            if kind == "chrome_attack":
                knowers.add("officials")
            if kind in ("vehicle_destroyed", "crash_out") or (isinstance(facts, dict) and facts.get("x") is not None):
                knowers.add("local")
            if kind in TECHNICAL_KINDS:
                knowers.add("technical")
            truth = dict(facts) if isinstance(facts, dict) else {"facts": facts}
            # resolve the people named by id so the language layer never sees bare ids
            for e in ents:
                if isinstance(e, list) and len(e) >= 2 and e[0] == "person":
                    truth.setdefault("person", self.name(e[1]))
            truth.pop("x", None), truth.pop("y", None), truth.pop("z", None)   # coordinates are not speech
            if "raceId" in truth:
                truth["race"] = truth.pop("raceId")      # kept for linking stories, never in a statement
            out.append(Fact(
                id=f"paddock_event:{r['event_id']}", kind=kind, at=_int(r.get("at")), tape=self.tape,
                source=self.src("paddock_event"), truth=truth, public=r.get("public_summary") or None,
                knowers=knowers, salience=_int(r.get("salience"), 20), provenance=r.get("provenance") or "simulated",
                entities=ents, place=truth.get("route"), involves_player=involves,
                causes=list(_dec(r.get("cause_refs")) or [])))
        return out

    def _paddock_news(self, rows):
        out = []
        for r in rows:
            kind = r.get("kind") or "story"
            knowers = {"canonical", "public"}
            if kind in TECHNICAL_KINDS:
                knowers.add("technical")
            out.append(Fact(
                id=f"paddock_news:{r['story_id']}", kind="wire_" + kind, at=_int(r.get("at")), tape=self.tape,
                source=self.src("paddock_news"),
                truth={"headline": r.get("headline"), "body": r.get("body"), "story_kind": kind},
                public=f"{r.get('headline', '')}. {r.get('body', '')}".strip(". "),
                knowers=knowers, salience=_prominence(r.get("prominence")), provenance="reported",
                causes=[f"paddock_event:{r.get('event_id')}"] if r.get("event_id") else []))
        return out

    # ------------------------------------------------------------------ the player's race
    def _paddock_result(self, rows):
        by_race: Dict[str, List[Dict[str, Any]]] = {}
        for r in rows:
            by_race.setdefault(str(r["race_id"]), []).append(r)
        out = []
        for race, rs in by_race.items():
            mine = [r for r in rs if self.is_player(r.get("person_id"))]
            if not mine:
                continue
            me = mine[0]
            rs.sort(key=lambda r: _int(r.get("position"), 99))
            winner = rs[0]
            pos, grid = _int(me.get("position")), _int(me.get("grid"))
            dnf = me.get("state") == "dnf"
            # who finished directly ahead / behind the player: the rivals of this race
            ahead = next((r for r in rs if _int(r.get("position")) == pos - 1), None)
            behind = next((r for r in rs if _int(r.get("position")) == pos + 1), None)
            truth = {
                "race": race, "series": self.series_name(me.get("series_id")), "driver": self.player_name,
                "position": None if dnf else pos, "grid": grid, "field_size": len(rs),
                "positions_gained": None if dnf else grid - pos,
                "state": me.get("state"), "dnf_reason": me.get("dnf_reason"),
                "winner": None if self.is_player(winner.get("person_id")) else self.name(winner.get("person_id")),
                "finished_ahead": self.name(ahead["person_id"]) if ahead and not dnf else None,
                "finished_behind": self.name(behind["person_id"]) if behind and not dnf else None,
                "purse": me.get("purse"), "points": me.get("points"),
            }
            sal = 45 + (25 if pos == 1 and not dnf else 15 if pos <= 3 and not dnf else 0) + (15 if dnf else 0)
            out.append(Fact(
                id=f"paddock_result:{race}:player", kind="player_dnf" if dnf else "player_result", at=_int(me.get("at")),
                tape=self.tape, source=self.src("paddock_result"), truth=truth,
                knowers={"canonical", "player", "officials", "public"}, salience=sal, provenance="physical",
                entities=[["person", str(me.get("person_id"))], ["race", race]]
                + ([["person", str(ahead["person_id"])]] if ahead else []) + ([["person", str(behind["person_id"])]] if behind else []),
                involves_player=True))
        return out

    def _paddock_live_crossing(self, rows):
        """Position changes of the player between consecutive gates, from server/Pace crossings (canonical)."""
        out = []
        rows = sorted(rows, key=lambda r: (_int(r.get("gate")), _int(r.get("t_ms"))))
        for r in rows:
            race, gate, t, who = str(r["race_id"]), _int(r["gate"]), _int(r["t_ms"]), str(r["person_id"])
            gates = self.crossings.setdefault(race, {})
            lst = gates.setdefault(gate, [])
            if any(p == who for _, p in lst):
                continue
            lst.append((t, who))
            if not self.is_player(who):
                continue
            ahead = {p for tt, p in lst if tt < t and p != who}
            rank = len(ahead) + 1
            ranks = self.player_gate_rank.setdefault(race, {})
            aheads = self.player_gate_ahead.setdefault(race, {})
            ranks[gate], aheads[gate] = rank, ahead
            prev_gate = max((g for g in ranks if g < gate), default=None)
            if prev_gate is None:
                continue
            prev = ranks[prev_gate]
            if prev == rank:
                continue
            passed = sorted(self.name(p) for p in aheads[prev_gate] - ahead)
            passed_by = sorted(self.name(p) for p in ahead - aheads[prev_gate])
            delta = prev - rank
            out.append(Fact(
                id=f"paddock_live_crossing:{race}:{who}:{gate}", kind="player_position", at=_int(r.get("at"), 0),
                tape=self.tape, source=self.src("paddock_live_crossing"),
                truth={"race": race, "gate": gate, "from_position": prev, "to_position": rank, "change": delta,
                       "passed": passed, "passed_by": passed_by, "race_ms": t, "driver": self.player_name,
                       "gate_source": r.get("source")},
                knowers={"canonical", "player"}, salience=30 + 8 * abs(delta) + (12 if rank <= 3 or prev <= 3 else 0),
                provenance="physical", entities=[["race", race]], involves_player=True))
        return out

    # ------------------------------------------------------------------ the truth ledger
    def _chrome_event(self, rows):
        out = []
        for r in rows:
            att, tgt = r.get("attacker_driver_id"), r.get("target_driver_id")
            involves = self.is_player(att) or self.is_player(tgt)
            knowers = {"canonical"}
            if involves:
                knowers.add("player")
            out.append(Fact(
                id=f"chrome_event:{r['event_id']}", kind="chrome_truth", at=_int(r.get("occurred_at")), tape=self.tape,
                source=self.src("chrome_event"),
                truth={"attacker": self.name(att) if att else None, "target": self.name(tgt) if tgt else None,
                       "hack": r.get("hack"), "outcome": r.get("outcome"), "catastrophic": bool(_int(r.get("catastrophic"))),
                       "player_was_attacker": self.is_player(att), "player_was_target": self.is_player(tgt)},
                knowers=knowers, salience=55 if _int(r.get("catastrophic")) else 25, provenance="physical",
                involves_player=involves))
        return out

    # ------------------------------------------------------------------ the Week
    def _racing_week_run(self, rows):
        out = []
        for r in rows:
            idx = _int(r["run_index"])
            seen = self.runs_seen.get(idx)
            if seen is None:
                self.runs_seen[idx] = dict(r)
                out.append(Fact(
                    id=f"racing_week_run:{idx}:open", kind="week_open", at=_int(r.get("start_utc") or r.get("opened_at")),
                    tape=self.tape, source=self.src("racing_week_run"),
                    truth={"week": idx, "previous_weeks": max(0, idx - 1)},
                    knowers={"canonical", "public"}, salience=70, provenance="simulated", run=idx, hours=0.0))
            if r.get("end_utc") and not (seen or {}).get("end_utc"):
                self.runs_seen[idx] = dict(r)
                st = _dec(r.get("state_json")) or {}
                out.append(Fact(
                    id=f"racing_week_run:{idx}:end", kind="week_end", at=_int(r.get("end_utc")), tape=self.tape,
                    source=self.src("racing_week_run"),
                    truth={"week": idx, "end_kind": r.get("end_kind"), "survived_days": r.get("survived"),
                           "deviation": st.get("deviation") if isinstance(st, dict) else None},
                    secret={"deviation"}, knowers={"canonical", "public"}, salience=90, provenance="simulated", run=idx))
        return out

    def _racing_week_event(self, rows):
        out = []
        for r in rows:
            ref = str(r["ref"])
            if r.get("kind") == "sample":
                if not ref.startswith("radio:"):
                    continue        # hourly samples are meter readings: never published (doc 47 §1.6)
                d = _dec(r.get("data_json")) or {}
                hours = float(r.get("hours") or 0)
                out.append(Fact(
                    id=f"racing_week_event:{r['run_index']}:{ref}", kind="week_vibe", at=_int(r.get("at")), tape=self.tape,
                    source=self.src("racing_week_event"),
                    truth={"mood": d.get("mood"), "cause": d.get("cause"), "surprise": d.get("surprise"),
                           "off_map": bool(d.get("offMap")), "line": d.get("line"), "day": int(hours // 24) + 1},
                    public=d.get("line"), knowers={"canonical", "public", "local"}, salience=55, provenance="simulated",
                    run=_int(r["run_index"]), hours=hours))
                continue
            data = _dec(r.get("data_json")) or {}
            hours = float(r.get("hours") or 0)
            out.append(Fact(
                id=f"racing_week_event:{r['run_index']}:{ref}", kind="week_step", at=_int(r.get("at")), tape=self.tape,
                source=self.src("racing_week_event"),
                truth={"step": ref, "announcement": self.week_steps.get(ref), "day": int(hours // 24) + 1,
                       "early": data.get("early"), "tolerance": data.get("tolerance")},
                secret={"tolerance"}, public=self.week_steps.get(ref),
                knowers={"canonical", "public", "officials"}, salience=65, provenance="simulated",
                run=_int(r["run_index"]), hours=hours))
        return out

    def _racing_week_moody(self, rows):
        out = []
        for r in rows:
            data = _dec(r.get("data_json")) or {}
            hours = float(r.get("hours") or 0)
            line = data.get("line")
            name = data.get("name") or r.get("face")
            out.append(Fact(
                id=f"racing_week_moody:{r['run_index']}:{r['roll_n']}", kind="week_moody", at=_int(r.get("at")),
                tape=self.tape, source=self.src("racing_week_moody"),
                truth={"face": name, "d20": r.get("d20"), "line": line, "target": data.get("target"),
                       "becomes": data.get("into"), "day": int(hours // 24) + 1},
                public=f"{name}: {line}" if line else name, knowers={"canonical", "public", "officials"},
                salience=50, provenance="simulated", run=_int(r["run_index"]), hours=hours))
        return out

    def _racing_week_verdict(self, rows):
        out = []
        for r in rows:
            out.append(Fact(
                id=f"racing_week_verdict:{r['run_index']}:{r['boundary_h']}", kind="week_verdict", at=_int(r.get("at")),
                tape=self.tape, source=self.src("racing_week_verdict"),
                truth={"verdict": r.get("kind"), "day": _int(r.get("boundary_h")) // 24 + 1, "p": r.get("p"),
                       "z": r.get("z"), "u": r.get("u")},
                secret={"p", "z", "u"}, knowers={"canonical"}, salience=40, provenance="simulated",
                run=_int(r["run_index"]), hours=float(r.get("boundary_h") or 0)))
        return out
