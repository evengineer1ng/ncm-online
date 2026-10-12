"""The debug trail: every candidate, every decision, every stage -- so a silence can be explained.

Distinguishes the five failure points: the simulation produced no fact (no FACT line), the editor ignored it
(SUPPRESSED + reason), the language model failed (REALIZE path=template + rejections), TTS mangled it (PERF script
next to the copy; the WAV is kept), playback failed (PLAY line). Written as readable text and as JSONL.
"""
from __future__ import annotations

import json
import os
import sys
import threading
import time
from typing import Any, Dict


class Trace:
    def __init__(self, out_dir: str, echo: bool = True, verbose: bool = False):
        os.makedirs(out_dir, exist_ok=True)
        self.txt = open(os.path.join(out_dir, "trace.log"), "a", encoding="utf-8", newline="")
        self.jsonl = open(os.path.join(out_dir, "trace.jsonl"), "a", encoding="utf-8", newline="")
        self.echo = echo
        self.verbose = verbose
        self.lock = threading.Lock()

    def _w(self, line: str, rec: Dict[str, Any], quiet: bool = False) -> None:
        with self.lock:
            stamp = time.strftime("%H:%M:%S")
            self.txt.write(f"{stamp} {line}\n")
            self.txt.flush()
            rec["ts"] = time.time()
            self.jsonl.write(json.dumps(rec, ensure_ascii=False, default=str) + "\n")
            self.jsonl.flush()
            if self.echo and (not quiet or self.verbose):
                try:
                    print(f"{stamp} {line}", flush=True)
                except UnicodeEncodeError:
                    sys.stdout.buffer.write((f"{stamp} {line}\n").encode("utf-8", "replace"))
                except OSError:
                    self.echo = False           # console gone (closed pipe): the files keep the trace

    def fact(self, f) -> None:
        self._w(f"FACT     {f.short()} knowers={'/'.join(sorted(f.knowers))}"
                + (" PLAYER" if f.involves_player else ""),
                {"stage": "fact", "id": f.id, "kind": f.kind, "salience": f.salience, "source": f.source,
                 "provenance": f.provenance, "knowers": sorted(f.knowers), "truth": f.speakable_truth(),
                 "secret_keys": sorted(f.secret)}, quiet=not f.involves_player and f.salience < 50)

    def candidate(self, c) -> None:
        sel = "SELECTED  " if c.selected else "suppressed"
        quiet = not c.selected and (c.view is None or "below threshold" in c.reason) and "DEDUP" not in c.reason
        self._w(f"  {sel} {c.station.id:<12} score={c.score:<3} view={c.view.domain if c.view else '-':<9} {c.reason}",
                {"stage": "editorial", "fact": c.fact.id, "station": c.station.id, "selected": c.selected,
                 "score": c.score, "reason": c.reason,
                 "statements": c.view.statements if c.view else None}, quiet=quiet)

    def produced(self, c, packet, real, perf, voice, preset, sting, wav, dur) -> None:
        self._w(f"  SEGMENT  {c.station.id} voice={voice} scene={preset} sting={sting or '-'} -> {os.path.basename(wav)} ({dur:.1f}s)\n"
                f"           FACTS    {' | '.join(s['statement'] for s in packet['facts'])}\n"
                + (f"           CONTEXT  {' | '.join(s['statement'] for s in packet.get('context', []))}\n" if packet.get('context') else "")
                + f"           COPY     [{real.path}] {real.copy}\n"
                + (f"           REJECTED {' || '.join(real.rejected)}\n" if real.rejected else "")
                + f"           PERF     {perf.script}  {perf.tts}",
                {"stage": "produced", "fact": c.fact.id, "station": c.station.id, "packet": packet,
                 "copy": real.copy, "path": real.path, "rejected": real.rejected, "used": real.used,
                 "performance": perf.script, "transcript": perf.transcript, "tts": perf.tts, "voice": voice,
                 "scene": preset, "stinger": sting, "wav": wav, "duration": dur})

    def play(self, item, outcome: str) -> None:
        self._w(f"  PLAY     {item.station} {os.path.basename(item.wav)}: {outcome}",
                {"stage": "play", "trace_id": item.trace_id, "station": item.station, "wav": item.wav, "outcome": outcome})

    def note(self, msg: str, **kw) -> None:
        self._w(f"NOTE     {msg}", {"stage": "note", "msg": msg, **kw})
