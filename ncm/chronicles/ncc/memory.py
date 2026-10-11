"""The Chronicle: the Narrator's memory, isolated per Tape (one SQLite file per server_id).

Not a transcript. It keeps what lets history resurface without replaying it:
    spoken      every item that played (fact id, topic, station, copy) -- dedup and provenance
    seen        every fact id the editor judged (so a restart never re-narrates the past)
    people      named people met in V's races: meetings, who finished ahead, last seen -- recurring rivals
    milestones  firsts (first finish, first podium, first win, first DNF) and other once-per-Tape facts
    weeks       per Racing Week: V's results, notable incidents, how it ended -- the obituary's material
    discovery   what the player has discovered (loop_named, chrome_attribution) -- the permission state
    cursors     per-table read positions for the fact source

`recall(fact)` returns a few canonical context lines for the Narrator's packet: only things this Tape already
recorded from earlier canonical facts, each tagged with the fact it came from.
"""
from __future__ import annotations

import json
import os
import sqlite3
import time
from typing import Any, Dict, List, Optional

from .facts import Fact
from .normalize import ordinal

SCHEMA = """
CREATE TABLE IF NOT EXISTS spoken (id INTEGER PRIMARY KEY, at REAL, fact_id TEXT, topic TEXT, station TEXT,
    copy TEXT, outcome TEXT);
CREATE INDEX IF NOT EXISTS ix_spoken_topic ON spoken(topic);
CREATE TABLE IF NOT EXISTS seen (fact_id TEXT PRIMARY KEY, at REAL, decision TEXT);
CREATE TABLE IF NOT EXISTS people (name TEXT PRIMARY KEY, meetings INTEGER, ahead_of_v INTEGER, behind_v INTEGER,
    first_fact TEXT, last_fact TEXT, last_at INTEGER);
CREATE TABLE IF NOT EXISTS met (name TEXT, race TEXT, PRIMARY KEY (name, race));
CREATE TABLE IF NOT EXISTS milestones (key TEXT PRIMARY KEY, fact_id TEXT, at INTEGER, text TEXT);
CREATE TABLE IF NOT EXISTS weeks (week INTEGER PRIMARY KEY, opened_at INTEGER, closed_at INTEGER, end_kind TEXT,
    data TEXT);
CREATE TABLE IF NOT EXISTS discovery (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS cursors (source TEXT PRIMARY KEY, value TEXT);
"""


class Chronicle:
    def __init__(self, data_dir: str, tape: str):
        os.makedirs(data_dir, exist_ok=True)
        safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in tape)
        self.path = os.path.join(data_dir, f"tape-{safe}.sqlite")
        self.db = sqlite3.connect(self.path, check_same_thread=False)
        self.db.executescript(SCHEMA)
        self.tape = tape
        self.current_week: Optional[int] = None

    # ---------------------------------------------------------------- cursors / seen
    def cursor(self, source: str, default: Any = None) -> Any:
        r = self.db.execute("SELECT value FROM cursors WHERE source=?", (source,)).fetchone()
        return json.loads(r[0]) if r else default

    def set_cursor(self, source: str, value: Any) -> None:
        self.db.execute("INSERT OR REPLACE INTO cursors VALUES (?, ?)", (source, json.dumps(value)))
        self.db.commit()

    def was_seen(self, fact_id: str) -> bool:
        return self.db.execute("SELECT 1 FROM seen WHERE fact_id=?", (fact_id,)).fetchone() is not None

    def mark_seen(self, fact_id: str, decision: str) -> None:
        self.db.execute("INSERT OR REPLACE INTO seen VALUES (?, ?, ?)", (fact_id, time.time(), decision))
        self.db.commit()

    def topic_spoken(self, topic: str) -> Optional[str]:
        r = self.db.execute("SELECT station FROM spoken WHERE topic=? AND outcome='played' LIMIT 1", (topic,)).fetchone()
        return r[0] if r else None

    def record_spoken(self, fact_id: str, topic: str, station: str, copy: str, outcome: str) -> None:
        self.db.execute("INSERT INTO spoken (at, fact_id, topic, station, copy, outcome) VALUES (?,?,?,?,?,?)",
                        (time.time(), fact_id, topic, station, copy, outcome))
        self.db.commit()

    # ---------------------------------------------------------------- discovery
    def discovery(self) -> Dict[str, Any]:
        d = {k: json.loads(v) for k, v in self.db.execute("SELECT key, value FROM discovery")}
        d.setdefault("loop_named", False)
        d.setdefault("chrome_attribution", False)
        return d

    def set_discovery(self, key: str, value: Any) -> None:
        self.db.execute("INSERT OR REPLACE INTO discovery VALUES (?, ?)", (key, json.dumps(value)))
        self.db.commit()

    # ---------------------------------------------------------------- learning from facts
    def learn(self, f: Fact) -> List[str]:
        """Fold a canonical fact into the Chronicle. Returns milestone keys newly reached (first podium, ...)."""
        new: List[str] = []
        if f.kind == "week_open":
            w = f.truth.get("week")
            self.current_week = w
            self.db.execute("INSERT OR IGNORE INTO weeks (week, opened_at, data) VALUES (?, ?, ?)", (w, f.at, "{}"))
        elif f.kind == "week_end":
            self.db.execute("UPDATE weeks SET closed_at=?, end_kind=? WHERE week=?",
                            (f.at, f.truth.get("end_kind"), f.truth.get("week")))
        elif f.kind in ("player_result", "player_dnf"):
            t = f.truth
            self._week_append("results", {"fact": f.id, "series": t.get("series"), "position": t.get("position"),
                                          "grid": t.get("grid"), "field": t.get("field_size"), "state": t.get("state"),
                                          "winner": t.get("winner")})
            for name, rel in ((t.get("finished_ahead"), "ahead"), (t.get("finished_behind"), "behind"), (t.get("winner"), "met")):
                if name:
                    self._meet(name, rel, f)
            pos = t.get("position")
            if f.kind == "player_dnf":
                new += self._milestone("first_dnf", f, "V's first did-not-finish on this Tape")
            else:
                new += self._milestone("first_finish", f, f"V's first classified finish: {ordinal(pos)} in the {t.get('series')}")
                if pos and pos <= 3:
                    new += self._milestone("first_podium", f, f"V's first podium: {ordinal(pos)} in the {t.get('series')}")
                if pos == 1:
                    new += self._milestone("first_win", f, f"V's first win, in the {t.get('series')}")
        elif f.kind == "player_position":
            for name in f.truth.get("passed") or []:
                self._meet(name, "passed", f)
            for name in f.truth.get("passed_by") or []:
                self._meet(name, "passed_by", f)
        elif f.kind in ("vehicle_destroyed", "chrome_attack", "upset", "season_title", "cup_title") or f.salience >= 70:
            self._week_append("incidents", {"fact": f.id, "kind": f.kind, "text": f.public or f.truth.get("person")})
        self.db.commit()
        return new

    def _week_append(self, key: str, item: Dict[str, Any]) -> None:
        if self.current_week is None:
            r = self.db.execute("SELECT MAX(week) FROM weeks").fetchone()
            self.current_week = r[0] if r and r[0] is not None else 0
            self.db.execute("INSERT OR IGNORE INTO weeks (week, data) VALUES (?, ?)", (self.current_week, "{}"))
        r = self.db.execute("SELECT data FROM weeks WHERE week=?", (self.current_week,)).fetchone()
        data = json.loads(r[0]) if r and r[0] else {}
        lst = data.setdefault(key, [])
        if not any(x.get("fact") == item.get("fact") for x in lst):
            lst.append(item)
        self.db.execute("UPDATE weeks SET data=? WHERE week=?", (json.dumps(data), self.current_week))

    def _meet(self, name: str, rel: str, f: Fact) -> None:
        """A meeting is one race shared with V; 'ahead'/'behind' count only classified finishes (passes are duels)."""
        race = f.truth.get("race") or f.id
        new_race = self.db.execute("INSERT OR IGNORE INTO met VALUES (?, ?)", (name, race)).rowcount
        ahead = 1 if rel == "ahead" else 0
        behind = 1 if rel == "behind" else 0
        r = self.db.execute("SELECT 1 FROM people WHERE name=?", (name,)).fetchone()
        if r:
            self.db.execute("UPDATE people SET meetings=meetings+?, ahead_of_v=ahead_of_v+?, behind_v=behind_v+?, "
                            "last_fact=?, last_at=? WHERE name=?", (new_race, ahead, behind, f.id, f.at, name))
        else:
            self.db.execute("INSERT INTO people VALUES (?, 1, ?, ?, ?, ?, ?)", (name, ahead, behind, f.id, f.id, f.at))

    def _milestone(self, key: str, f: Fact, text: str) -> List[str]:
        cur = self.db.execute("INSERT OR IGNORE INTO milestones VALUES (?, ?, ?, ?)", (key, f.id, f.at, text))
        return [key] if cur.rowcount else []

    # ---------------------------------------------------------------- recall
    def recall(self, f: Fact, limit: int = 3) -> List[Dict[str, str]]:
        """Context lines from this Tape's own earlier canonical facts, relevant to `f`."""
        out: List[Dict[str, str]] = []
        names = set()
        t = f.truth
        for k in ("finished_ahead", "finished_behind", "winner", "person", "target", "attacker"):
            if t.get(k):
                names.add(t[k])
        for k in ("passed", "passed_by"):
            names.update(t.get(k) or [])
        for n in names:
            r = self.db.execute("SELECT meetings, ahead_of_v, behind_v, first_fact FROM people WHERE name=?", (n,)).fetchone()
            if r and r[0] >= 2:
                out.append({"from": r[3], "text": f"{n} and V have raced each other {r[0]} times on this Tape; {n} finished ahead of V {r[1]} times, behind {r[2]}."})
        if f.kind in ("player_result", "player_dnf"):
            r = self.db.execute("SELECT COUNT(*) FROM spoken WHERE fact_id LIKE 'paddock_result:%' AND outcome='played'").fetchone()
            if r and r[0]:
                out.append({"from": "chronicle", "text": f"The Narrator has already told {r[0]} of V's race endings on this Tape."})
        return out[:limit]

    def milestone_text(self, key: str) -> Optional[Dict[str, str]]:
        r = self.db.execute("SELECT fact_id, text FROM milestones WHERE key=?", (key,)).fetchone()
        return {"from": r[0], "text": r[1]} if r else None

    def week_summary(self, week: int) -> Dict[str, Any]:
        r = self.db.execute("SELECT opened_at, closed_at, end_kind, data FROM weeks WHERE week=?", (week,)).fetchone()
        if not r:
            return {}
        data = json.loads(r[3] or "{}")
        return {"week": week, "end_kind": r[2], "results": data.get("results", []), "incidents": data.get("incidents", [])}

    def rivals(self, limit: int = 3) -> List[Dict[str, Any]]:
        rows = self.db.execute("SELECT name, meetings, ahead_of_v, behind_v, first_fact FROM people WHERE meetings >= 2 "
                               "ORDER BY meetings DESC, ahead_of_v DESC, last_at DESC LIMIT ?", (limit,)).fetchall()
        return [{"name": a, "meetings": b, "ahead": c, "behind": d, "from": e} for a, b, c, d, e in rows]
