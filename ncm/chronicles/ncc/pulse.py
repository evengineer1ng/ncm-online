"""The Week's pulse: Racing Week is alive between the big moments.

Events alone leave long silences (a busy Online hour still yields only a few story-worthy facts), and a narrator who
speaks once in twenty minutes startles more than it tells. The pulse keeps a rolling digest of EVERY canonical fact
(backfilled ones included) and, when the air has been quiet for a while, composes one short status beat from it.

Beats rotate so the Week is heard from several sides, each built only from public / canonical facts with their ids:
    week      Week N, day and chapter, the real hour in Night City, and the city's mood (NCM's own public vibe proxy:
              `week.vibe` -> racing_week_event radio samples; never the hidden tolerance)
    roundup   the last hour's racing: how many races resolved, the latest winners, upsets, streaks, first wins
    trouble   the last hour's wrecks: crash-outs, destroyed cars (no causes the public does not have)
    rules     what is posted: the current Racing Week step and Moody's active faces
    you       V's own recent racing, when V has raced recently
A beat is a synthetic fact (`week_pulse`) whose statements each carry the canonical fact id they came from, so the
trace still answers "which facts produced this sentence". Items are mentioned once; counts are real counts.
"""
from __future__ import annotations

import os
import re
import time
from collections import deque
from typing import Deque, Dict, List, Optional, Tuple

from .facts import Fact
from .normalize import ordinal

MOOD_WORDS = {"euphoric": "euphoric, the whole city out on the curb", "buoyant": "buoyant, still on side",
              "uneasy": "uneasy, the welcome wearing thin", "tense": "tense, losing patience with the racing",
              "hostile": "hostile, done with Racing Week"}
CAUSE_WORDS = {"safety_bad": "too many wrecks", "safety_good": "clean racing", "enforcement": "the police everywhere",
               "momentum_up": "a packed calendar", "momentum_down": "a thinning schedule", "money": "the money"}
RACE_KINDS = {"race_result", "upset", "streak", "first_win"}
TROUBLE_KINDS = {"crash_out", "vehicle_destroyed", "chrome_attack", "feud"}
ROTATION = ["week", "roundup", "trouble", "rules", "roundup", "you"]
STATION_FOR = {"week": "narrator", "trouble": "narrator", "rules": "race_control", "you": "narrator"}


def load_chapters(core_root: str) -> List[str]:
    try:
        src = open(os.path.join(core_root, "week", "curve.lua"), encoding="utf-8").read()
        m = re.search(r"M\.CHAPTERS\s*=\s*\{([^}]*)\}", src)
        return re.findall(r'"([^"]+)"', m.group(1)) if m else []
    except OSError:
        return []


def time_of_night(t: float) -> str:
    h = time.localtime(t).tm_hour
    if h < 4:
        return "the small hours"
    if h < 7:
        return "just before dawn"
    if h < 12:
        return "morning"
    if h < 17:
        return "afternoon"
    if h < 21:
        return "evening"
    return "late night"


class Pulse:
    def __init__(self, core_root: str, quiet_s: float = 60.0, every_s: float = 120.0, window_s: float = 3600.0):
        self.chapters = load_chapters(core_root)
        self.quiet_s, self.every_s, self.window_s = quiet_s, every_s, window_s
        self.recent: Deque[Fact] = deque(maxlen=2000)
        self.vibe: Optional[Fact] = None
        self.step: Optional[Fact] = None
        self.moody: List[Fact] = []
        self.week_start: Dict[int, int] = {}
        self.week: Optional[int] = None
        self.player: Deque[Fact] = deque(maxlen=20)
        self.mentioned: set = set()
        self.turn = 0
        self.last_pulse = 0.0
        self.n = 0
        self.news_turn = False

    # ------------------------------------------------------------------ digest
    def see(self, f: Fact) -> None:
        if f.kind == "week_open":
            self.week = f.truth.get("week")
            self.week_start[self.week] = f.at
        elif f.kind == "week_vibe":
            if not self.vibe or f.at >= self.vibe.at:
                self.vibe = f
        elif f.kind == "week_step":
            if not self.step or f.at >= self.step.at:
                self.step = f
        elif f.kind == "week_moody":
            self.moody.append(f)
            self.moody = self.moody[-8:]
        elif f.kind in ("player_result", "player_dnf", "player_entered"):
            self.player.append(f)
        if f.kind in RACE_KINDS or f.kind in TROUBLE_KINDS:
            self.recent.append(f)

    def _window(self, now: float, kinds) -> List[Fact]:
        return [f for f in self.recent if f.kind in kinds and now - f.at <= self.window_s]

    # ------------------------------------------------------------------ beats
    def _week(self, now: float) -> List[Tuple[str, str]]:
        out = []
        if self.week is not None and self.week in self.week_start:
            hours = (now - self.week_start[self.week]) / 3600.0
            day = int(hours // 24) + 1
            chap = self.chapters[min(day, len(self.chapters)) - 1] if self.chapters else ""
            out.append((f"racing_week_run:{self.week}:open",
                        f"It is Day {day} of Racing Week {self.week}" + (f", {chap.title()}" if chap else "")
                        + f"; {time_of_night(now)} in Night City."))
        if self.vibe:
            t = self.vibe.truth
            mood = MOOD_WORDS.get(t.get("mood"), t.get("mood"))
            line = f"The city's mood is {mood}"
            if t.get("cause") in CAUSE_WORDS:
                line += f", and what moves it is {CAUSE_WORDS[t['cause']]}"
            out.append((self.vibe.id, line + "."))
            if t.get("surprise") == "better":
                out.append((self.vibe.id, "It is going better than anyone expected."))
            elif t.get("surprise") == "worse":
                out.append((self.vibe.id, "It is going worse than anyone feared."))
            if t.get("off_map"):
                out.append((self.vibe.id, "No Racing Week has run this long before."))
        return out if len(out) >= 1 else []

    def _roundup(self, now: float) -> List[Tuple[str, str]]:
        races = self._window(now, {"race_result"})
        fresh = [f for f in self._window(now, RACE_KINDS) if f.id not in self.mentioned]
        if not fresh:
            return []
        out = []
        if len(races) >= 2:
            out.append((races[-1].id, f"{len(races)} races have been run in the last hour."))
        picked = sorted(fresh, key=lambda f: (-f.salience, -f.at))[:3]
        for f in picked:
            t = f.truth
            if f.kind == "upset":
                s = f"{t.get('winner')} won the {t.get('series')} from {ordinal(t['fromGrid'])} on the grid" if t.get("fromGrid") \
                    else f"{t.get('winner')} won the {t.get('series')} against the odds"
            elif f.kind == "streak":
                s = f"{t.get('driver')} has now won {t.get('count')} in a row in the {t.get('series')}"
            elif f.kind == "first_win":
                s = f"{t.get('driver')} took a first win, in the {t.get('series')}, after {t.get('starts')} starts"
            else:
                s = f"{t.get('winner')} won the {t.get('series')}" + (f" on {t.get('route')}" if t.get("route") else "")
            out.append((f.id, s + "."))
        return out

    def _trouble(self, now: float) -> List[Tuple[str, str]]:
        tr = self._window(now, TROUBLE_KINDS)
        fresh = [f for f in tr if f.id not in self.mentioned]
        if not fresh:
            return []
        out = []
        crashes = [f for f in tr if f.kind == "crash_out"]
        wrecked = [f for f in tr if f.kind == "vehicle_destroyed"]
        if len(crashes) + len(wrecked) >= 2:
            out.append((tr[-1].id, f"In the last hour: {len(crashes)} drivers crashed out of sanctioned races and "
                                   f"{len(wrecked)} race cars were destroyed."))
        for f in sorted(fresh, key=lambda f: -f.at)[:2]:
            t = f.truth
            if f.kind == "vehicle_destroyed":
                s = f.public or f"{t.get('person')}'s car was destroyed during a race."
            elif f.kind == "crash_out":
                s = f"{t.get('driver')} crashed out of the {t.get('series')}" + (f", {t.get('cause')}" if t.get("cause") else "")
            elif f.kind == "chrome_attack":
                s = f.public or "Officials attributed a quickhack."
            else:
                s = f.public or ""
            if s:
                out.append((f.id, s.rstrip(".") + "."))
        return out

    def _rules(self, now: float) -> List[Tuple[str, str]]:
        out = []
        if self.step and self.step.public and self.step.id not in self.mentioned:
            out.append((self.step.id, "In force: " + self.step.public))
        faces = [m for m in self.moody if m.id not in self.mentioned]
        if faces:
            m = faces[-1]
            out.append((m.id, f"Moody's latest roll: {m.truth.get('face')}." + (f" {m.truth.get('line')}" if m.truth.get("line") else "")))
        return out

    def _you(self, now: float) -> List[Tuple[str, str]]:
        mine = [f for f in self.player if now - f.at <= 2 * 3600 and f.kind in ("player_result", "player_dnf")]
        if not mine:
            return []
        out = []
        last = mine[-1]
        t = last.truth
        if last.kind == "player_dnf":
            out.append((last.id, f"V's last race, the {t.get('series')}, ended without a finish."))
        else:
            out.append((last.id, f"V's last race ended in {ordinal(t['position'])} of {t.get('field_size')}, in the {t.get('series')}."))
        if len(mine) >= 2:
            out.append((mine[0].id, f"V has raced {len(mine)} times in the last two hours."))
        return out

    # ------------------------------------------------------------------ the beat
    def due(self, now: float, last_spoken: float) -> bool:
        return now - last_spoken >= self.quiet_s and now - self.last_pulse >= min(self.every_s, self.quiet_s * 2)

    def compose(self, now: float, tape: str) -> Optional[Fact]:
        for _ in range(len(ROTATION)):
            kind = ROTATION[self.turn % len(ROTATION)]
            self.turn += 1
            items = getattr(self, "_" + kind)(now)
            if not items:
                continue
            station = STATION_FOR.get(kind)
            if kind == "roundup":
                self.news_turn = not self.news_turn
                station = "news" if self.news_turn else "narrator"
            if kind == "trouble" and any(f.kind == "vehicle_destroyed" for f in self.recent if f.id in {i for i, _ in items}):
                station = "street" if self.n % 2 else "narrator"
            for i, _ in items:
                self.mentioned.add(i)
            self.last_pulse = now
            self.n += 1
            return Fact(id=f"pulse:{int(now)}:{self.n}:{kind}", kind="week_pulse", at=int(now), tape=tape,
                        source="pulse(digest of canonical facts)",
                        truth={"beat": kind, "station": station, "items": items},
                        knowers={"canonical", "public", "local", "officials"}, salience=60, provenance="digest",
                        causes=[i for i, _ in items])
        self.last_pulse = now
        return None
