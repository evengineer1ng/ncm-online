"""CANONICAL TRUTH -> NARRATOR KNOWLEDGE -> PLAYER KNOWLEDGE / DISCOVERY -> PERMITTED NARRATION.

`view(fact, station, discovery)` returns what that station may SAY about a fact -- a list of plain statements, each
traceable to the fact -- or None with the reason it may not. Statements are written here, deterministically, from
canonical fields; the language layer only rephrases them. This is the only place a fact's truth becomes words.

Rules (each one is a test in tests/test_epistemics.py):
  * a station hears a fact only through a domain both share (stations.Station.domains vs Fact.knowers);
  * keys in Fact.secret (tolerance, verdict probabilities, meter samples) are never spoken by anyone;
  * the quickhack truth ledger (chrome_event) reaches the Narrator only when V was involved, and names the attacker
    only when V was the attacker or the player has discovered attribution; News never sees it (not public);
  * a destroyed car with no public attribution carries its uncertainty as a statement ("no cause announced");
  * the Narrator knows the Week repeats; until `loop_named` is discovered it may not SAY so (forbidden list + the
    realizer's validator).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from .facts import Fact
from .normalize import ordinal
from .stations import Station

LOOP_WORDS = ["loop", "reset", "repeat", "again and again", "time loop", "groundhog", "rewind", "relive", "start over"]

HACK_LABEL = {"total_failure": "Total Failure", "short_circuit": "Short Circuit", "overheat": "Overheat",
              "cripple": "Cripple Movement", "detonate": "Detonate Grenade", "distract": "Distract", "reboot": "Reboot Optics"}


PENALTY = {"dsq": "disqualification", "time": "a time penalty", "warning": "a warning"}

RACE_CONTROL_KINDS = {"week_pulse", "week_end", "week_step", "week_moody", "chrome_attack", "player_entered",
                      "player_result", "player_dnf"}


@dataclass
class View:
    fact_id: str
    station: str
    statements: List[str]
    forbidden: List[str] = field(default_factory=list)
    domain: str = ""
    topic: str = ""                     # dedup key across stations (an event and its WIRE story share one)


def _shared(fact: Fact, st: Station) -> Optional[str]:
    for d in ("canonical", "officials", "player", "technical", "local", "public"):
        if d in st.domains and d in fact.knowers:
            return d
    return None


def topic_of(fact: Fact) -> str:
    if fact.kind.startswith("wire_") and fact.causes:
        return fact.causes[0]
    return fact.id


def _race_label(t: Dict) -> str:
    bits = [t.get("series"), t.get("route")]
    return " on ".join(b for b in bits if b) or "a race"


def _player_result(t: Dict, audience: str) -> List[str]:
    s = []
    if t.get("state") == "dnf":
        reason = {"mechanical": "a mechanical failure", "contact": "contact"}.get(t.get("dnf_reason") or "", None)
        s.append(f"V did not finish the {t.get('series') or 'race'}" + (f", out with {reason}" if reason else "") + ".")
        if t.get("grid"):
            s.append(f"V had started {ordinal(t['grid'])} on the grid.")
        if t.get("winner"):
            s.append(f"{t['winner']} won it.")
        return s
    pos, grid = t.get("position"), t.get("grid")
    if audience == "officials":
        s.append(f"Classification, {t.get('series') or 'race'}: V, position {pos} of {t.get('field_size')}, from grid {grid}.")
        return s
    s.append(f"V finished {ordinal(pos)} of {t.get('field_size')} in the {t.get('series') or 'race'}, having started {ordinal(grid)}.")
    g = t.get("positions_gained")
    if g and g >= 3:
        s.append(f"That is {g} places gained from the grid.")
    elif g and g <= -3:
        s.append(f"That is {-g} places lost from the grid.")
    if pos == 1:
        s.append("V won.")
    elif t.get("winner"):
        s.append(f"{t['winner']} won the race.")
    if t.get("finished_ahead") and pos and pos > 1:
        s.append(f"{t['finished_ahead']} finished one place ahead of V.")
    return s


def _statements(fact: Fact, st: Station, domain: str, discovery: Dict) -> Tuple[Optional[List[str]], str]:
    t = fact.speakable_truth()
    k = fact.kind

    # ---------------------------------------------------------------- the truth ledger
    if k == "chrome_truth":
        if st.id != "narrator":
            return None, "truth ledger: only the Narrator may hold it"
        if not fact.involves_player:
            return None, "truth ledger: V had no line of sight on this hack"
        hack = HACK_LABEL.get(t.get("hack"), t.get("hack"))
        if t.get("player_was_attacker"):
            s = [f"V uploaded {hack} into {t.get('target')}'s car."]
            if t.get("catastrophic"):
                s.append("It was catastrophic.")
            return s, ""
        who = t.get("attacker") if discovery.get("chrome_attribution") else None
        s = [f"Someone uploaded {hack} into V's car" + (f": it was {who}" if who else "") + "."]
        if t.get("outcome"):
            s.append(f"The upload {'landed' if t['outcome'] in ('landed', 'applied', 'success') else 'ended: ' + str(t['outcome'])}.")
        return s, ""

    # ---------------------------------------------------------------- the Week
    if k == "week_pulse":
        if st.id != t.get("station"):
            return None, f"this {t.get('beat')} beat was composed for {t.get('station')}"
        return [text for _, text in t.get("items") or []], ""
    if k == "week_vibe":
        if st.id == "street":
            return [t.get("line")] if t.get("line") else None, ""
        if st.id == "news":
            return [f"On the racing radio: {t.get('line')}"] if t.get("line") else None, ""
        return None, "the Narrator hears the vibe through the pulse"
    if k == "week_open":
        n = t.get("week")
        s = [f"Racing Week {n} opens in Night City."]
        if st.id == "narrator" and (t.get("previous_weeks") or 0) > 0:
            s.append(f"It is the {ordinal(n)} Racing Week of this Tape; V has lived {t['previous_weeks']} before it.")
        return s, ""
    if k == "week_end":
        if st.id not in ("narrator", "news", "race_control"):
            return None, "week end belongs to the narrator and the institutions"
        s = [f"Racing Week {t.get('week')} is over."]
        ek = t.get("end_kind")
        if ek and st.id in ("narrator", "race_control"):
            s.append({"collapse": "The city ran out of patience before the festival's last day.",
                      "complete": "It ran its full seven days.",
                      "scheduled": "It ended on schedule."}.get(ek, f"It ended: {ek}."))
        return s, ""
    if k == "week_verdict":
        if st.id != "narrator":
            return None, "verdicts are never published"
        if t.get("verdict") in ("continue", "survive", "continued"):
            return [f"Day {t.get('day') - 1} ended without a verdict against it, and the Week went on into Day {t.get('day')}."], ""
        return None, "a non-continuing verdict is narrated by the week end"
    if k == "week_step":
        ann = fact.public
        if not ann:
            return None, f"step {t.get('step')} has no public announcement text"
        if st.id == "street":
            return [f"The city put out a notice today: \"{ann}\""], ""
        s = [f"Night City announced: \"{ann}\""] if st.id == "narrator" else [ann]
        if st.id == "narrator" and t.get("early"):
            s.append("It came earlier than the city had planned.")
        return s, ""
    if k == "week_moody":
        face, line = t.get("face"), t.get("line")
        return [f"Racing Week's dice, Moody, rolled {face}." + (f" {line}" if line else "")], ""

    # ---------------------------------------------------------------- the player's racing
    if k in ("player_result", "player_dnf"):
        aud = "officials" if st.id == "race_control" else "story"
        if st.id == "news":
            return None, "a single racer's result is not news unless the WIRE makes it so"
        return _player_result(t, aud), ""
    if k == "player_position":
        if st.id != "narrator":
            return None, "in-race position changes are V's own experience"
        a, b = t.get("from_position"), t.get("to_position")
        best = t.get("best_position")
        if t.get("reversal") and best:
            up = ", ".join(t.get("passed") or [])
            down = ", ".join(t.get("passed_by") or [])
            return [f"V climbed from {ordinal(a)} to {ordinal(best)}" + (f", passing {up}" if up else "") + ".",
                    f"Then V fell back to {ordinal(b)}" + (f"; {down} got by" if down else "") + "."], ""
        if b < a:
            who = ", ".join(t.get("passed") or [])
            s = [f"V moved from {ordinal(a)} to {ordinal(b)}" + (f", passing {who}" if who else "") + "."]
        else:
            who = ", ".join(t.get("passed_by") or [])
            s = [f"V dropped from {ordinal(a)} to {ordinal(b)}" + (f"; {who} got by" if who else "") + "."]
        return s, ""
    if k == "player_entered":
        if st.id == "race_control":
            return [f"Entry confirmed: V, {t.get('series')}."], ""
        return [f"V entered a {t.get('series')} race."], ""

    # ---------------------------------------------------------------- the Paddock's tape and WIRE
    if k.startswith("wire_"):
        if st.id == "narrator" and not fact.involves_player:
            return None, "WIRE is News' material; the Narrator takes the underlying event"
        body = t.get("body") or ""
        head = t.get("headline") or ""
        return [x for x in (head.rstrip(".") + "." if head else "", body) if x], ""
    if k == "vehicle_destroyed":
        who = t.get("person")
        if st.id == "street":
            return [f"A race car was wrecked out here during a race; it was {who}'s."], ""
        s = [fact.public or f"{who}'s car is destroyed during the race."]
        if st.id in ("news", "street"):
            s.append("No cause has been announced.")
        return s, ""
    if k == "chrome_attack":
        return [fact.public or "Officials attribute a quickhack."] + (
            [f"Penalty: {PENALTY.get(t['penalty'], t['penalty'])}."] if t.get("penalty") and st.id == "race_control" else []), ""
    if k == "rnd_release":
        return [fact.public] if fact.public else None, "" if fact.public else "no public release text"
    if fact.public:
        return [fact.public], ""
    # generic tape kinds without a public summary: their WIRE story is the public text
    if k == "race_result" and st.id == "narrator":
        w = t.get("winner")
        return ([f"{w} won the {_race_label(t)}."] if w else None), ""
    return None, f"no statement form for {k} on {st.id}"


def view(fact: Fact, st: Station, discovery: Dict) -> Tuple[Optional[View], str]:
    domain = _shared(fact, st)
    if domain is None:
        return None, f"{st.id} cannot know this ({'/'.join(sorted(fact.knowers))} vs {'/'.join(sorted(st.domains))})"
    if not st.available(discovery):
        return None, f"{st.id} not available yet"
    if st.id == "race_control" and fact.kind not in RACE_CONTROL_KINDS:
        return None, f"race control does not speak {fact.kind} (not an institutional matter)"
    stmts, why = _statements(fact, st, domain, discovery)
    if not stmts:
        return None, why or "nothing permitted to say"
    forbidden = []
    if not discovery.get("loop_named"):
        forbidden.append("saying or implying that the Week repeats, resets, loops or that time rewinds")
    forbidden.append("any number, name, place, cause, motive, injury, quote or reaction not in the statements")
    return View(fact.id, st.id, stmts, forbidden, domain, topic_of(fact)), ""
