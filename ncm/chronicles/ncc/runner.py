"""Night City Chronicles: the pipeline, end to end.

    NCM canonical rows -> Normalizer (facts) -> Editor (epistemic view, score, cooldown, dedup, segment)
        -> Realizer (LLM, validated) -> perform (TTS script) -> Piper -> scene (+ stinger) -> Player (queue, staleness)

Usage (from ncm/chronicles):
    .venv/Scripts/python -m ncc --fixture fixtures/race_week_demo.jsonl --speed 20
    .venv/Scripts/python -m ncc --config chronicles.json            # dev MariaDB or Online over ssh
Options: --no-llm (templates only), --no-audio (render WAVs, do not play), --ident, --ribbon (captions to RibbonOS).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from typing import Dict, List

import numpy as np

from . import scene, stingers
from .editorial import Candidate, Editor, MAX_AGE, DEFAULT_MAX_AGE, coalesce_positions
from .facts import Fact
from .memory import Chronicle
from .normalize import Normalizer, load_week_steps, ordinal
from .perform import perform
from .playback import Player
from .pulse import Pulse
from .realize import Realizer
from .stations import STREET_VOICES, stations_for_preset
from .trace import Trace
from .tts import PiperEngine, write_wav

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(os.path.dirname(HERE), "core")


class Chronicles:
    def __init__(self, cfg: Dict):
        self.cfg = cfg
        self.preset = cfg.get("radio_preset", "talk_radio")
        if self.preset not in ("talk_radio", "lean"):
            raise ValueError("radio_preset must be 'talk_radio' or 'lean'")
        self.stations = stations_for_preset(self.preset)
        self.tape = cfg["tape"]
        self.out = os.path.join(HERE, cfg.get("out_dir", "out"), time.strftime("%Y%m%d-%H%M%S"))
        os.makedirs(self.out, exist_ok=True)
        self.trace = Trace(self.out, echo=True, verbose=cfg.get("verbose", False))
        self.chron = Chronicle(os.path.join(HERE, cfg.get("data_dir", "data")), self.tape + cfg.get("tape_suffix", ""))
        for k, v in (cfg.get("discovery") or {}).items():
            self.chron.set_discovery(k, v)
        prefix = "fixture:" if cfg.get("fixture") else ""
        self.norm = Normalizer(self.tape, cfg.get("player_driver_ids", []), cfg.get("player_name", "V"),
                               load_week_steps(CORE), source_prefix=prefix)
        # on a real world, only what happens from (shortly before) now is spoken; the rest is memory
        grace = float(cfg.get("speak_grace_s", 300))
        self.editor = Editor(self.chron, speak_after=0.0 if cfg.get("fixture") else time.time() - grace,
                             stations=self.stations)
        self.realizer = Realizer(cfg.get("model", "qwen3.5:latest"), cfg.get("ollama", "http://127.0.0.1:11434"),
                                 enabled=not cfg.get("no_llm", False))
        self.tts = PiperEngine(os.path.join(HERE, cfg.get("voice_dir", "voices")))
        self.assets = os.path.join(HERE, "assets")
        ribbon = tuple(cfg["ribbon"]) if cfg.get("ribbon") else None
        self.player = Player(self.trace.play, play=not cfg.get("no_audio", False), ribbon=ribbon)
        self.speed = float(cfg.get("speed", 1.0))
        self.coalesce_s = float(cfg.get("coalesce_s", 20.0))
        self.pending_pos: Dict[str, List[Fact]] = {}
        self.seq = 0
        self.week_start: Dict[int, int] = {}
        self.current_week = None
        self.produced: List[Dict] = []
        default_quiet, default_every = (60, 120) if self.preset == "lean" else (24, 60)
        self.pulse = Pulse(CORE, quiet_s=float(cfg.get("pulse_quiet_s", default_quiet)),
                           every_s=float(cfg.get("pulse_every_s", default_every)))
        self.last_spoken = 0.0
        self.volume_db = float(cfg.get("volume_db", -4.0))

    # ------------------------------------------------------------------ situation: the compact Week context
    def situation(self, now: float) -> Dict:
        s: Dict = {}
        if self.current_week is not None:
            s["racing_week"] = self.current_week
            start = self.week_start.get(self.current_week)
            if start:
                s["day"] = int((now - start) // 86400) + 1
        return s

    # ------------------------------------------------------------------ facts in
    def ingest(self, batches, now: float) -> None:
        for table, rows in batches:
            for f in self.norm.ingest(table, rows):
                if f.kind == "week_open":
                    self.current_week = f.truth.get("week")
                    self.week_start[self.current_week] = f.at
                self.trace.fact(f)
                self.pulse.see(f)
                if f.kind == "player_position":
                    self.pending_pos.setdefault(f.truth["race"], []).append(f)
                    continue
                if f.kind in ("player_result", "player_dnf") and f.truth.get("race") in self.pending_pos:
                    self.flush_race(f.truth["race"], now)      # the race's story before its result
                self.process(f, now)
        self.flush_positions(now)
        if self.pulse.due(now, self.last_spoken) and self.player.idle():
            beat = self.pulse.compose(now, self.tape)
            if beat:
                self.trace.fact(beat)
                self.process(beat, now)

    def flush_positions(self, now: float, force: bool = False) -> None:
        for race, lst in list(self.pending_pos.items()):
            if force or now - max(f.at for f in lst) >= self.coalesce_s:
                self.flush_race(race, now)

    def flush_race(self, race: str, now: float) -> None:
        lst = self.pending_pos.pop(race, [])
        if not lst:
            return
        merged = coalesce_positions(lst)
        if len(lst) > 1:
            self.trace.note(f"coalesced {len(lst)} position changes in {race} into one beat", ids=[f.id for f in lst])
        self.process(merged, now)

    def process(self, f: Fact, now: float) -> None:
        cands = self.editor.judge(f, now)
        for c in cands:
            self.trace.candidate(c)
        for c in sorted([c for c in cands if c.selected], key=lambda c: -c.station.priority):
            try:
                self.produce(c, now)
            except Exception as e:  # a production failure is traced; the next fact still runs
                self.trace.note(f"production failed for {c.fact.id} on {c.station.id}: {e!r}")

    # ------------------------------------------------------------------ one segment
    def packet(self, c: Candidate, now: float) -> Dict:
        facts = [{"id": f"{c.fact.id}#{i}", "statement": s} for i, s in enumerate(c.view.statements)]
        if c.fact.kind == "week_end" and c.station.id == "narrator":
            facts += self.obituary(c.fact.truth.get("week"))
        ctx = [{"id": r["from"], "statement": r["text"]} for r in c.recall + c.milestones]
        return {"segment": c.station.label, "situation": self.situation(now), "facts": facts, "context": ctx,
                "forbidden": c.view.forbidden}

    def obituary(self, week) -> List[Dict]:
        """The Week's closing narration: only what this Tape's Chronicle recorded from canonical facts."""
        w = self.chron.week_summary(week) if week is not None else {}
        out = []
        res = w.get("results", [])
        for i, r in enumerate(res[-4:], 1):
            nth = f"V's {ordinal(i) if len(res) > 1 else ''} race of the Week".replace("  ", " ")
            if r.get("state") == "dnf":
                out.append({"id": r["fact"], "statement": f"In {nth}, the {r.get('series')}, V did not finish."})
            elif r.get("position"):
                out.append({"id": r["fact"], "statement": f"In {nth}, the {r.get('series')}, V finished {ordinal(r['position'])} of {r.get('field')}."})
        for key in ("first_win", "first_podium"):
            m = self.chron.milestone_text(key)
            if m and any(m["from"] == r["fact"] for r in res):
                out.append({"id": m["from"], "statement": m["text"] + "."})
                break
        if not res:
            out.append({"id": "chronicle", "statement": "V took no classified result this Week."})
        inc = w.get("incidents", [])
        if inc:
            out.append({"id": inc[-1]["fact"], "statement": f"The Week's incidents included this: {inc[-1].get('text')}"})
        for rv in self.chron.rivals(1):
            out.append({"id": rv["from"], "statement": f"{rv['name']} has raced V {rv['meetings']} times on this Tape."})
        return out

    def produce(self, c: Candidate, now: float) -> None:
        st = c.station
        pk = self.packet(c, now)
        real = self.realizer.realize(pk, st.persona, st.style, st.max_words, bool(self.chron.discovery().get("loop_named")),
                                     use_llm=st.llm, preset=self.preset)
        perf = perform(real.copy, st.style, st.tts)
        voice = st.voice
        if st.id == "street":
            voice = STREET_VOICES[int(hashlib.sha1(c.fact.id.encode()).hexdigest(), 16) % len(STREET_VOICES)]
        tts = dict(perf.tts)
        gap = tts.pop("sentence_gap_s", 0.0)
        x, sr = self.tts.synth(voice, perf.script, sentence_gap_s=gap, **tts)
        seed = int(hashlib.sha1(c.fact.id.encode()).hexdigest()[:8], 16)
        audio = scene.render(x, sr, st.scene, seed=seed, assets=self.assets)
        if st.stinger:
            sting = stingers.get(st.stinger, sr, self.assets)
            audio = np.concatenate([sting, np.zeros((int(sr * 0.12), 2), np.float32), audio])
        audio = audio * scene.db(self.volume_db)
        fin = min(len(audio), int(sr * 0.15))           # a soft entrance: no line should startle
        audio[:fin] *= np.linspace(0.0, 1.0, fin, dtype=np.float32)[:, None]
        self.last_spoken = now
        self.seq += 1
        wav = os.path.join(self.out, f"{self.seq:03d}_{st.id}.wav")
        write_wav(wav, audio, sr)
        dur = len(audio) / sr
        self.trace.produced(c, pk, real, perf, voice, st.scene, st.stinger, wav, dur)
        self.chron.record_spoken(c.fact.id, c.view.topic, st.id, perf.transcript, "queued")
        age = now - c.fact.at
        ttl = max(5.0, (MAX_AGE.get(c.fact.kind, DEFAULT_MAX_AGE) - age) / self.speed)
        self.player.submit(wav, st.id, st.priority, perf.transcript, ttl, c.fact.id, dur)
        self.produced.append({"fact": c.fact.id, "station": st.id, "copy": real.copy, "path": real.path, "wav": wav})

    def mark_played(self, item, outcome):
        self.trace.play(item, outcome)
        if outcome.startswith("played") or outcome.startswith("rendered"):
            self.chron.db.execute("UPDATE spoken SET outcome='played' WHERE id=(SELECT MAX(id) FROM spoken WHERE fact_id=? AND station=?)",
                                  (item.trace_id, item.station))
            self.chron.db.commit()

    # ------------------------------------------------------------------ loop
    def run(self, source, clock=None, until_done=None) -> None:
        self.player.on_result = self.mark_played
        if self.cfg.get("ident"):
            sr = 22050
            write_wav(os.path.join(self.out, "000_ident.wav"), stingers.get("ident", sr, self.assets), sr)
            self.player.submit(os.path.join(self.out, "000_ident.wav"), "ident", 9, "Night City Chronicles", 30, "ident", 2.6)
        self.trace.note(f"Night City Chronicles on tape {self.tape} -> {self.out}", source=type(source).__name__)
        clock = clock or time.time
        try:
            while True:
                now = clock()
                try:
                    self.ingest(source.poll(now), now)
                except Exception as e:
                    self.trace.note(f"source poll failed: {e!r}")
                if until_done and until_done():
                    self.flush_positions(clock() + 3600, force=True)
                    break
                time.sleep(getattr(source, "poll_interval", 2.0))
        except KeyboardInterrupt:
            self.trace.note("stopped by user")
        self.player.drain()
        self.trace.note(f"done: {len(self.produced)} segments produced", segments=self.produced)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="ncc", description="Night City Chronicles -- Race Week narrator")
    ap.add_argument("--config", help="JSON config (tape, player_driver_ids, source)")
    ap.add_argument("--fixture", help="replay a JSONL fixture instead of a database")
    ap.add_argument("--speed", type=float, default=1.0, help="fixture replay speed")
    ap.add_argument("--no-llm", action="store_true")
    ap.add_argument("--no-audio", action="store_true")
    ap.add_argument("--ident", action="store_true")
    ap.add_argument("--ribbon", action="store_true", help="captions to RibbonOS on 127.0.0.1:47921")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--preset", choices=("talk_radio", "lean"), help="show format; defaults to talk_radio")
    ap.add_argument("--fresh", action="store_true", help="fixture: start a fresh Chronicle (new tape suffix)")
    a = ap.parse_args(argv)
    cfg: Dict = {}
    if a.config:
        with open(a.config, encoding="utf-8") as f:
            cfg = json.load(f)
    if a.preset:
        cfg["radio_preset"] = a.preset
    cfg.update({k: v for k, v in (("no_llm", a.no_llm), ("no_audio", a.no_audio), ("ident", a.ident),
                                   ("verbose", a.verbose), ("speed", a.speed)) if v})
    if a.ribbon:
        cfg["ribbon"] = ["127.0.0.1", 47921]
    if a.fixture:
        cfg.setdefault("tape", "fixture-demo")
        cfg.setdefault("player_driver_ids", ["drv-v"])
        cfg["fixture"] = a.fixture
        if a.fresh:
            cfg["tape_suffix"] = "-" + time.strftime("%Y%m%d%H%M%S")
    if "tape" not in cfg:
        ap.error("--config with a tape (server_id), or --fixture")
    app = Chronicles(cfg)
    if a.fixture:
        from .sources import FixtureSource
        src = FixtureSource(a.fixture, speed=a.speed)
        app.run(src, clock=src.clock, until_done=src.done)
    else:
        from .sources import MySqlSource, SshSource
        s = cfg["source"]
        common = dict(tape=cfg["tape"], player_driver_ids=cfg.get("player_driver_ids", []), chronicle=app.chron,
                      lookback_s=int(cfg.get("lookback_s", 6 * 3600)))
        if s["kind"] == "mysql":
            src = MySqlSource(s["dsn"], **common)
        elif s["kind"] == "ssh":
            src = SshSource(s["ssh"], s.get("database", "ncm"), **common)
        else:
            ap.error(f"unknown source kind {s['kind']}")
        app.run(src)
    return 0


if __name__ == "__main__":
    sys.exit(main())
