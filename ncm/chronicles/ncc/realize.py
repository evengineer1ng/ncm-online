"""Language realization: "say these true things, from this voice".

The model receives a bounded packet (statements derived from canonical facts, a little Tape context, the forbidden
list) and returns copy. The validator then checks the copy against the packet: every proper name and every number
in the copy must appear in the packet, loop words are refused until discovered, and the length is bounded. A
rejected copy is retried once with the violation stated; a second failure falls back to a deterministic template
built from the statements themselves. The trace records which path produced every spoken line.
"""
from __future__ import annotations

import json
import re
import urllib.request
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

from .epistemics import LOOP_WORDS

NUM_WORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
             "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
             "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "first": 1, "second": 2, "third": 3,
             "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
             "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15, "sixteenth": 16,
             "twentieth": 20}
# "one" and "second" are ordinary words too often to police ("one more", "a second chance")
SOFT_NUMS = {"one", "second", "first"}

ALWAYS_OK = {"v", "night", "city", "racing", "race", "week", "ncpd", "tape", "moody", "wire", "paddock", "day",
             "premier", "pro", "regional", "street", "i", "officials", "control", "news"}

COMMON = set("""a about after again against all almost alone along already also although always among an and another
any anyone anything are around as at back be because been before behind being below beside best better between
both but by came can could day did do does down during each even ever every everyone everything few for from
had has have he her here him his how however if in inside into is it its just last later least less let like
little long made make many may maybe meanwhile might more most much must my near never new next no nobody none
nor not nothing now of off often on once one only onto or other others our out outside over perhaps quite
rather right same says see she should since so some somebody someone something somewhere soon still such than
that the their them then there these they this those though through thus to today tomorrow tonight too toward
under until up upon us very was we well were what whatever when where whether which while who whoever whole whom
whose why will with within without would yesterday yet you your yours another no not yes well oh so and but
across ahead around beneath beyond despite except plus per via whereas whilst somehow nobody elsewhere
attention notice reminder update warning classification entry penalty provisional confirmed listen look
good bad fine sure okay right wrong true false first second it's that's there's here's what's
saw seen heard hear watched watch got get took take went go came come said say told tell guess honestly man
listen crazy whole place people folks everybody nobody somebody thing things damn hell yeah yep nah oh wow
was were wasn't weren't didn't don't doesn't can't couldn't won't wouldn't isn't aren't i'm i've i'd you're
they they're they've we're we've there their then now later earlier tonight morning evening night afternoon
started finished climbed fell dropped passed moved gained lost won took held kept made ended opened closed
by on in at to from with without for into onto off over under after before during while until since across
behind ahead between beyond around through near far here there where when how why what who which whose
officials organisers organizers racing racers racer drivers driver crowd fans streets roads limits notice
classification penalty penalties provisional entry entries confirmed result results update status attention
welcome please respect keep clear standard reduced raised limits enforce enforcement traffic law city-wide
base market price torque thrust capacity pulse specific impulse delivers sits rated weighs costs priced
in the end at last at least eventually finally meanwhile elsewhere across town downtown uptown tonight""".split())


@dataclass
class Realization:
    copy: str
    path: str                 # llm | llm_retry | template
    rejected: List[str]
    used: List[str]
    raw: str = ""


def _packet_text(packet: Dict) -> str:
    bits = [s["statement"] for s in packet["facts"]] + [c["statement"] for c in packet.get("context", [])]
    sit = packet.get("situation") or {}
    if sit.get("racing_week") is not None:
        bits.append(f"Racing Week {sit['racing_week']}" + (f", day {sit['day']}." if sit.get("day") else "."))
    return " ".join(bits)


ANCHOR_STOP = set("the a an of to and from in on at by for with as is was were be been out its it this that their "
                  "then just only also had has have after before into over up out among place places".split())
ORD_RE = re.compile(r"^(\d+)(st|nd|rd|th)$")


def _tokens(text: str) -> List[str]:
    """Lower-case word tokens with every number (digits, ordinals, number words) reduced to its digits."""
    out = []
    for w in re.findall(r"[A-Za-z0-9]+", text.lower()):
        m = ORD_RE.match(w)
        if m:
            out.append(m.group(1))
        elif w in NUM_WORDS:
            out.append(str(NUM_WORDS[w]) + ("~" if w in SOFT_NUMS else ""))   # ~ : anchors only, never policed
        else:
            out.append(w)
    return out


def _anchors(tokens: List[str], i: int) -> set:
    """The word a number leans on: the content word right before it (its role: 'finished 4th', 'grid 4')."""
    before, after = [], []
    j = i - 1
    while j >= 0 and len(before) < 1:
        if tokens[j] not in ANCHOR_STOP:
            before.append(tokens[j])
        j -= 1
    j = i + 1
    while j < len(tokens) and len(after) < 0:
        if tokens[j] not in ANCHOR_STOP:
            after.append(tokens[j])
        j += 1
    return set(before + after)


def number_roles(copy: str, src: str) -> List[str]:
    """Every number in the copy must lean on at least one of the same words as some occurrence of that number in
    the facts: '2nd of 5' spoken as 'fifth' is caught ('classification' is not what 5 leans on), as is an invented
    'turn three' borrowing the 3 of '3rd'."""
    problems = []
    st, ct = _tokens(src), _tokens(copy)
    src_anchor: Dict[str, List[set]] = {}
    for i, t in enumerate(st):
        if t.isdigit():
            src_anchor.setdefault(t, []).append(_anchors(st, i))
    st = [t.rstrip("~") for t in st]
    for i, t in enumerate(ct):
        if not t.isdigit():
            continue
        mine = {a.rstrip("~") for a in _anchors(ct, i)}
        theirs = src_anchor.get(t)
        if theirs is None:
            continue                       # reported by the plain number check
        if not any(mine & a for a in theirs):
            problems.append(f"number {t} is used next to {sorted(mine)}, but the facts put it next to "
                            f"{sorted(set().union(*theirs))}")
    return problems


def _numbers(text: str) -> set:
    out = set(int(x) for x in re.findall(r"\d+", text))
    for w in re.findall(r"[a-z]+", text.lower()):
        if w in NUM_WORDS:
            out.add(NUM_WORDS[w])
    return out


def validate(copy: str, packet: Dict, loop_named: bool, max_words: int) -> List[str]:
    problems = []
    src = _packet_text(packet)
    src_low = src.lower()
    allowed_nums = _numbers(src)
    for tok in re.findall(r"\d+", copy):
        if int(tok) not in allowed_nums:
            problems.append(f"number {tok} is not in the facts")
    for w in re.findall(r"[A-Za-z]+", copy):
        lw = w.lower()
        if lw in NUM_WORDS and lw not in SOFT_NUMS and NUM_WORDS[lw] not in allowed_nums:
            problems.append(f"number word '{w}' is not in the facts")
    problems += number_roles(copy, src)
    # V's (and everyone's) pronouns are not known: never guess
    for m in re.finditer(r"\b(he|him|his|himself|she|her|hers|herself)\b", copy, re.I):
        problems.append(f"gendered pronoun '{m.group(1)}' (pronouns are unknown: use the name or they)")
    # proper names: capitalized tokens that are not common words must come from the packet
    for m in re.finditer(r"\b([A-Z][a-zA-Z'\-]+)", copy):
        w = m.group(1)
        lw = re.sub(r"'s$", "", w.lower())
        if lw in ALWAYS_OK or lw in COMMON or w.lower() in COMMON:
            continue
        if lw in NUM_WORDS:
            continue
        if w.lower() in src_low or lw in src_low:
            continue
        problems.append(f"name '{w}' is not in the facts")
    if not loop_named:
        for lw in LOOP_WORDS:
            if re.search(r"\b" + re.escape(lw), copy.lower()) and lw not in src_low:
                problems.append(f"loop word '{lw}' before the player discovered the loop")
    n = len(copy.split())
    if n > int(max_words * 1.35):
        problems.append(f"{n} words > {max_words}")
    if n == 0:
        problems.append("empty")
    return sorted(set(problems))


def template(packet: Dict, style: str, preset: str = "lean") -> str:
    stm = [s["statement"] for s in packet["facts"]]
    if style == "control":
        return "Race Control. " + " ".join(stm)
    if preset == "talk_radio" and stm:
        return ("Here's what we can say with confidence: " + " ".join(stm)
                + " That's the part I keep turning over. What does it mean for the rest of Racing Week? "
                  "I can't settle that from the facts I've been given.")
    if style == "news":
        return " ".join(stm)
    if style == "street":
        return "Yeah. " + " ".join(stm)
    return " ".join(stm)


LEAN_SYSTEM = """You write one short spoken segment for a radio drama set in Night City's Racing Week.
You are {persona}

Rules, all mandatory:
- Express ONLY the supplied facts. You may leave facts out; you may not add any.
- Do not invent names, numbers, places, causes, motives, injuries, deaths, relationships, quotes, history or public reaction.
- Use names and numbers exactly as given, in the same role (a finishing position stays a finishing position).
  Context lines are background: allude to them only if natural.
- Nobody's pronouns are known, V's included: use names, or 'they'. Never he/she/him/her/his.
- Do not mention turns, corners, laps, sectors, gates or weather unless a fact names them.
- Forbidden: {forbidden}.
- At most {max_words} words. Spoken language: no lists, no headings, no stage directions, no sound effects.
- Silence is better than filler: no greetings, no sign-offs, no "stay tuned".
Reply as JSON: {{"copy": "<the words to be spoken>", "used": ["<fact ids you expressed>"]}}"""


TALK_RADIO_SYSTEM = """You are live on Night City's Racing Week talk radio.
You are {persona}

This is a conversation with the city, not a bulletin or a recap. Do not introduce yourself by name; listeners know
the voice. Stay with the supplied subject long enough to make
it interesting: connect the fact to relevant context, explain what is at stake from your character's perspective,
and probe what it might mean. Aim for a substantial 90-145 word spoken turn when the material supports it. Use
natural speech with varied sentence lengths. Ask one or two real questions that open the subject up; a question may
remain unanswered. Do not pad, summarize in report format, or force a tidy conclusion. The character may have a
viewpoint, but must not pretend to have witnessed events or know private thoughts.

Truth rules:
- Every factual assertion must be directly supported by a supplied fact or context line.
- You may voice the character's assigned opinions and preferences as opinions; distinguish these from claims about
  what happened in Night City.
- You may offer a clearly marked interpretation of those facts, or wonder aloud about an unanswered question. Do not
  smuggle a new fact, cause, motive, reaction, consequence, history, relationship or prediction into an interpretation.
- Keep uncertainty audible: say what is known, what is only a possibility, and what nobody here can answer yet.
- Do not invent names, numbers, places, injuries, deaths, quotes or public reaction. Context is usable, but do not
  imply it happened at the same time as this fact unless the packet says so.
- Use names and numbers exactly as given, in the same role. Nobody's pronouns are known: use names or 'they'.
- Do not mention turns, corners, laps, sectors, gates or weather unless a fact names them.
- Forbidden: {forbidden}.
- At most {max_words} words. Spoken language only: no headings, lists, stage directions or sound effects.
Reply as JSON: {{"copy": "<the words to be spoken>", "used": ["<fact ids you expressed>"]}}"""


class Realizer:
    def __init__(self, model: str = "qwen3.5:latest", host: str = "http://127.0.0.1:11434", enabled: bool = True,
                 timeout: float = 120.0):
        self.model, self.host, self.enabled, self.timeout = model, host, enabled, timeout

    def _chat(self, system: str, user: str) -> str:
        body = {"model": self.model, "stream": False, "think": False, "format": "json",
                "options": {"temperature": 0.78, "num_predict": 700},
                "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}
        req = urllib.request.Request(self.host + "/api/chat", data=json.dumps(body).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=self.timeout) as r:
            return json.loads(r.read())["message"]["content"]

    def realize(self, packet: Dict, persona: str, style: str, max_words: int, loop_named: bool,
                use_llm: bool = True, preset: str = "talk_radio") -> Realization:
        rejected: List[str] = []
        if not self.enabled or not use_llm:
            why = "llm disabled" if not self.enabled else "station speaks institutional templates"
            return Realization(template(packet, style, preset), "template", [why], [s["id"] for s in packet["facts"]])
        prompt = LEAN_SYSTEM if preset == "lean" else TALK_RADIO_SYSTEM
        system = prompt.format(persona=persona, forbidden="; ".join(packet.get("forbidden", [])), max_words=max_words)
        user = json.dumps({k: packet[k] for k in ("segment", "situation", "facts", "context") if k in packet},
                          ensure_ascii=False)
        raw = ""
        for attempt in range(2):
            try:
                raw = self._chat(system, user if attempt == 0 else user + "\n\nYour previous copy was rejected: "
                                 + "; ".join(rejected[-1:]) + ". Use only the supplied facts.")
                data = json.loads(raw)
                copy = str(data.get("copy", "")).strip()
                used = [str(x) for x in (data.get("used") or [])]
            except Exception as e:  # network, JSON, model missing
                rejected.append(f"llm error: {e}")
                break
            problems = validate(copy, packet, loop_named, max_words)
            if not problems:
                return Realization(copy, "llm" if attempt == 0 else "llm_retry", rejected, used, raw)
            rejected.append(f"'{copy}' -> " + ", ".join(problems))
        return Realization(template(packet, style, preset), "template", rejected, [s["id"] for s in packet["facts"]], raw)
