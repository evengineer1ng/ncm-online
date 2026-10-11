"""Semantic copy -> TTS performance script (+ the clean transcript).

Built only on controls measured to work with Piper (docs/TTS_PROBE.md):
  * commas and sentence breaks: real pauses (~0.3 s each) and a pitch reset per sentence -> our main phrasing tool;
  * the inter-sentence gap: Piper emits one chunk per sentence with almost no silence; we insert our own;
  * length_scale: linear tempo, per station;
  * NOT used, because measured to do nothing: ellipses, dashes, CAPS, repeated '!!!', paragraph breaks.
    Ellipses and dashes in copy are rewritten into commas or sentence breaks so the pause the writer meant happens.
The transcript is the semantic copy, never the performance script.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Dict

UNITS = [(r"(\d)\s*kN\b", r"\1 kilonewtons"), (r"(\d)\s*N m\b", r"\1 newton metres"), (r"(\d)\s*kg\b", r"\1 kilograms"),
         (r"(\d)\s*s specific impulse", r"\1 seconds specific impulse"), (r"€\$\s*(\d[\d,]*)", r"\1 eddies"),
         (r"\bkm/h\b", "kilometres an hour"), (r"\bNCPD\b", "N C P D"), (r"\bP(\d+)\b", r"P \1")]


@dataclass
class Performance:
    script: str
    transcript: str
    tts: Dict[str, float]


def _clean(text: str) -> str:
    t = text.replace("—", " -- ").replace("–", " -- ").replace("…", "...")
    t = re.sub(r"\s+", " ", t).strip()
    return t


def transcript_of(copy: str) -> str:
    t = _clean(copy)
    t = re.sub(r"!{2,}", "!", t)
    return t


def perform(copy: str, style: str, tts: Dict[str, float]) -> Performance:
    t = _clean(copy)
    for pat, rep in UNITS:
        t = re.sub(pat, rep, t)
    # ellipsis / dash: Piper ignores both. A pause the writer meant becomes a sentence break before a turn word
    # ("... and lost it") and a comma elsewhere.
    t = re.sub(r"\s*(\.\.\.|--)\s*(?=(and|but|then|until|so)\b)", ". ", t, flags=re.I)
    t = re.sub(r"\s*(\.\.\.|--)\s*", ", ", t)
    t = re.sub(r"!{2,}", "!", t)
    t = re.sub(r"\b([A-Z]{4,})\b(?![-\d])", lambda m: m.group(1) if m.group(1) == "NCPD" else m.group(1).capitalize(), t)
    if style == "narrator":
        # the turn of a story gets its own sentence: a measured pause and a fresh pitch contour
        t = re.sub(r",\s+(then|and then|but|until)\s+", lambda m: ". " + m.group(1).capitalize() + " ", t)
        t = re.sub(r";\s*", ". ", t)
    elif style == "control":
        t = re.sub(r";\s*", ". ", t)
        t = re.sub(r",\s+(and)\s+", ". ", t)
    elif style == "street":
        t = re.sub(r";\s*", ", ", t)
    # capitalise sentence starts after our rewrites
    t = re.sub(r"([.!?]\s+)([a-z])", lambda m: m.group(1) + m.group(2).upper(), t)
    if t and t[-1] not in ".!?":
        t += "."
    return Performance(script=t, transcript=transcript_of(copy), tts=dict(tts))
