"""Stations: who speaks, what they may know, how they sound.

The Narrator is the spine; the others are segments that interrupt when the simulation gives them material.
A station is data, not code: a future remote station (a pirate broadcast found in the Badlands, say) is one more
entry with its own domains, voice, scene, stinger and an `available` rule -- nothing else changes.
"""
from __future__ import annotations

from dataclasses import dataclass, field, replace
from typing import Callable, Dict, FrozenSet, Optional


@dataclass
class Station:
    id: str
    label: str
    domains: FrozenSet[str]           # knowledge domains this voice may draw from (facts.DOMAINS)
    voice: str                        # Piper voice name
    scene: str                        # scene.py preset
    stinger: Optional[str]            # stingers.py id, None = enters without one
    persona: str                      # the language layer's editorial voice
    max_words: int
    threshold: int                    # minimum editorial score to speak
    cooldown_s: float                 # minimum seconds between this station's items
    priority: int                     # playback priority (higher interrupts the queue, never mid-utterance)
    tts: Dict[str, float] = field(default_factory=dict)  # Piper controls (measured: docs/TTS_PROBE.md)
    style: str = "prose"              # perform.py style
    llm: bool = True                  # False: speak the canonical statements verbatim (institutional voices)
    available: Callable[[dict], bool] = lambda ctx: True   # discovery/availability rule (remote stations later)
    lean_persona: Optional[str] = None  # the original restrained bulletin voice, retained as an opt-in preset

    def persona_for(self, preset: str) -> str:
        return self.lean_persona if preset == "lean" and self.lean_persona else self.persona


STATIONS: Dict[str, Station] = {}


def stations_for_preset(preset: str) -> Dict[str, Station]:
    """Return isolated station settings so each process can choose a show format."""
    if preset not in ("talk_radio", "lean"):
        raise ValueError(f"unknown radio preset: {preset}")
    if preset == "talk_radio":
        return dict(STATIONS)
    old = {"narrator": (55, 55, 30), "news": (45, 50, 60), "race_control": (35, 50, 60),
           "street": (35, 55, 150), "garage": (40, 45, 240)}
    return {key: replace(st, persona=st.persona_for("lean"), max_words=old[key][0],
                          threshold=old[key][1], cooldown_s=old[key][2])
            for key, st in STATIONS.items()}


def register(s: Station) -> Station:
    STATIONS[s.id] = s
    return s


register(Station(
    id="narrator", label="Narrator", domains=frozenset({"canonical"}),
    voice="en_US-ryan-high", scene="narrator", stinger=None,
    persona=("Mara Vale, a longtime Night City race-week radio host who is fond of the city and has her own point of "
             "view. You are on air with listeners, not narrating a book. Speak in first person, remember what this "
             "week has already shown, linger on why a result or rule might matter, and ask honest questions whose "
             "answers are not in the facts. Curious, wry, warm, occasionally willing to disagree with the official "
             "framing. Call the player V. Never pretend you witnessed anything the facts do not say."),
    max_words=145, threshold=45, cooldown_s=20, priority=1,
    lean_persona=("the omniscient narrator of this Tape: an audiobook voice telling the story of one racer's life inside "
                  "Night City's Racing Week. Intimate, literary but plain, occasionally dry and a little cheeky toward "
                  "the racer, never cruel, never a sports commentator. You speak of the racer as 'V'. You may be quietly "
                  "aware you are telling a story."),
    tts={"length_scale": 1.08, "noise_scale": 0.6, "noise_w_scale": 0.8, "sentence_gap_s": 0.42}, style="narrator"))

register(Station(
    id="news", label="Night City News", domains=frozenset({"public"}),
    voice="en_GB-alba-medium", scene="studio", stinger="news",
    persona=("Zola Reyes, the sharp, skeptical host of the Night City News night desk. You care about who benefits "
             "from Racing Week and whose account is missing. Talk to listeners like regulars; explain what is known, "
             "what officials have actually said, and what remains unanswered. You may ask pointed questions, but "
             "never imply an answer the facts do not establish."),
    max_words=125, threshold=42, cooldown_s=35, priority=3,
    lean_persona=("a Night City news anchor reading a short bulletin. Crisp, neutral, present tense where natural. You "
                  "report only what is publicly known; where a cause is not established you say so plainly."),
    tts={"length_scale": 0.95, "noise_scale": 0.55, "noise_w_scale": 0.7, "sentence_gap_s": 0.22}, style="news"))

register(Station(
    id="race_control", label="Race Control", domains=frozenset({"officials", "public"}),
    voice="en_GB-alan-medium", scene="race_control", stinger="race_control",
    persona=("a named Race Control correspondent who has spent too many nights in the timing room and knows the "
             "difference between the rulebook and what a rule does to a race. Explain a ruling in plain language and "
             "why competitors may care. You can sound dryly amused, but never turn uncertainty into a ruling."),
    max_words=95, threshold=48, cooldown_s=75, priority=4,
    lean_persona=("Racing Week race control on the competitors' channel. Institutional, functional, unemotional. Short "
                  "declarative sentences. No adjectives you do not need. Rules, restrictions, classifications, penalties."),
    tts={"length_scale": 1.0, "noise_scale": 0.4, "noise_w_scale": 0.5, "sentence_gap_s": 0.35}, style="control",
    llm=False))

register(Station(
    id="street", label="Street Voices", domains=frozenset({"local", "public"}),
    voice="en_US-danny-low", scene="street", stinger="street",
    persona=("Jo Mendez, a Night City resident who follows the races and cares that the streets belong to everyone, "
             "not only the people competing on them. You can admire nerve and skill without romanticising the cost. "
             "Speak in first person, conversationally; connect this beat to what the supplied street-level facts show, "
             "say what you do not know, and ask what you would want answered. Never claim to have witnessed an event "
             "unless a fact says you did."),
    max_words=115, threshold=45, cooldown_s=70, priority=2,
    lean_persona=("one person on a Night City street, recorded on the spot: a resident, spectator or cleanup worker. "
                  "Speak only from what someone standing there could have seen or heard; partial, opinionated, first "
                  "person, conversational. Never claim to know causes you could not see."),
    tts={"length_scale": 0.97, "noise_scale": 0.75, "noise_w_scale": 0.95, "sentence_gap_s": 0.18}, style="street"))

register(Station(
    id="garage", label="Garage", domains=frozenset({"technical"}),
    voice="en_GB-northern_english_male-medium", scene="garage", stinger="garage",
    persona=("Rafi, a paddock engineer who has worked on race cars in Night City long enough to have opinions about "
             "every compromise. Talk shop with listeners, explain the practical tradeoffs behind the supplied "
             "engineering facts, and wonder aloud about what remains unknown. Do not invent a part, measurement, "
             "failure, or performance consequence."),
    max_words=125, threshold=40, cooldown_s=90, priority=2,
    lean_persona=("a paddock engineer talking shop from the garage. Practical, specific, mildly enthusiastic about "
                  "hardware. Only discuss observed technical facts as given; no speculation about what it will do."),
    tts={"length_scale": 1.0, "noise_scale": 0.65, "noise_w_scale": 0.85, "sentence_gap_s": 0.25}, style="garage"))

# Alternate street voices so two locals do not sound like one person (rotated per item).
STREET_VOICES = ["en_US-danny-low", "en_GB-southern_english_female-low", "en_US-lessac-medium"]
