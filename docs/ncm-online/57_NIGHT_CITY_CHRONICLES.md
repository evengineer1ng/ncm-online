# 57 - Night City Chronicles: the Race Week narrator

> **STATUS: CURRENT** - authority for: *Night City Chronicles: spoken narration of the canonical world (sources, epistemic boundary, editorial, voices, scenes)* - affirmed 2026-10-08 (L344)
> Decision: [DECISION_RECORD.md](DECISION_RECORD.md) L344. Authority map: [INDEX.md](INDEX.md). Code: `ncm/chronicles/` ([README](../../ncm/chronicles/README.md)).

**In one paragraph.** NCM now runs more of Night City than anyone can watch. Night City Chronicles makes it audible: a
local process reads NCM's canonical tables (read-only), turns rows into facts that know who could know them, lets an
editor decide what is worth saying and by whom, has a local LLM say *only those facts* (checked, with a template
fallback), performs the copy through Piper with controls we measured, and puts each voice in its own acoustic world.
Mostly an omniscient Narrator whose lifetime is the Tape; News, Race Control, Street Voices and Garage interrupt with
their own stingers when the simulation gives them material. **The simulation produces facts; Chronicles never does.**
Built and run end to end on 2026-10-08 against a fixture Week in NCM's real table shapes; **no run yet against dev's or
Online's database** (that needs a read-only DSN or the owner's go-ahead for Online reads; §7).

## 1. The audit (2026-10-08)

**The old bridge** (`ncm-localized/.../MT_Ecosystem/modules/radioos_bridge.lua`, NCM 2.0 single player): a CET sidecar
writing `ncm_race_state.json` every 50 ms with live standings, telemetry and up to 24 queued `MTE.Events`
(RaceStart, LeadChange, CrashSpike, ...); Radio OS's `plugins/ncm_race_feed.py` polled it. Reusable: the *idea* of a
sequenced event sidecar beside a state snapshot, and its event vocabulary as a checklist. Not reusable: every source
(MTE globals, CET, single-player saves) -- none exists in OPEN//77, and it had no epistemics (everything it saw, it said).

| question | Radio OS (`D:/dev/Radio-OS`) | Ribbon OS (`D:/dev/ribbon-os-(4.5)`) |
|---|---|---|
| 1. structured facts in cleanly? | yes: feed plugins (`ncm_race_feed`, `nc_story_feed`), but its stations assume a single-player "player bible" | only its 5-event UDP contract (heat, subtitle, transition, transport, station) from Radio OS |
| 2. LLM/TTS pipeline? | yes: `model_provider.py` (Ollama/OpenAI/Claude/Gemini), `voice_provider.py` (Piper, Kokoro, ElevenLabs, Google, Azure) | no |
| 3. queue/interleave segments? | yes: producer/audio queues in `bookmark.py` (9.8k lines) | no |
| 4. stingers? | per-plugin (`ok_audio_engine.play_stinger`), not a shared vocabulary | no |
| 5. per-segment acoustic processing? | **no**: voices differ, rooms do not | no |
| 6. persistent station identity? | yes: `stations/<id>/manifest.yaml`, a NightCityChronicles station already exists (2.0-era) | renders a station's identity visually |
| 7. defer around game audio? | external-app ducking helpers (`duck_external_audio`) | n/a |
| 8. later in-game radio? | through a native carrier only (it is a desktop process) | its Godot shell is a desktop surface |
| 9. reusable old-bridge code | `ncm_race_feed.py` (file poller), the station manifest's voice roster | `ribbon_bridge.py` captions |
| 10. fastest true spoken fact? | the voice assets and the Ollama models are here; the runtime is heavy and single-player-shaped | not an audio path |

**State on this reinstalled PC:** Radio OS's venv was dead and its seven Piper `.onnx` voices were 0-byte stubs; Ollama
0.35.1 is installed with `qwen3.5` (6.6 GB) and `qwen3.6:27b`. Ribbon OS is a Godot device shell (HID, process manager,
the ribbon) that renders what Radio OS emits.

**Decision (L344): a thin new NCM-owned engine, hybrid with both.** The NCM-specific brain (facts, epistemics, editorial,
memory, validation, performance, scenes) lives in `ncm/chronicles/` -- it must understand NCM's tables and rulings and
change with them. It reuses Radio OS's choices (Piper voices, Ollama, the Night City Chronicles station identity) and
emits Ribbon OS's existing `subtitle` event for captions. Radio OS's `bookmark.py` runtime is not used: wrapping NCM's
editorial inside a 9.8k-line single-player-shaped producer would have been slower and would have hidden the trace. The
engine exposes finished, traced audio items; a Radio OS feed plugin can wrap it later without changing it.

## 2. Where the facts come from (Online)

Every narratable fact today originates **server-side** and is already persisted, so a reader needs no new server code:

| table | becomes | knowers |
|---|---|---|
| `paddock_event` (tape ledger, `public_summary`, salience, provenance) | race results, upsets, streaks, first wins, crash-outs, `vehicle_destroyed`, `chrome_attack`, `rnd_release`, ... | canonical + public (+ officials for `chrome_attack`, + local for physical incidents, + technical for `rnd_release`) |
| `paddock_news` (WIRE) | News copy in NCM's own words | public |
| `paddock_entry` + `paddock_result` | the player's entries, classification, DNF, who finished beside V | player, officials |
| `paddock_live_crossing` | V's passes and losses gate by gate (server/Pace crossings) | player |
| `chrome_event` | **the truth ledger**: who really uploaded what | canonical only (+ player when V is attacker or target) |
| `racing_week_run` / `_event` (steps) / `_moody` / `_verdict` | the Week opening, PA steps, Moody's rolls, the noon verdicts, the end | public PA and rolls; tolerance, samples and verdict probabilities are **secret** (doc 47 §1.6) |
| `paddock_person`, `paddock_series` | names | - |

**Client-side** facts (speed, G, wheel input, what is on V's screen) stay on the client; nothing reads them yet. The
first pass narrates the player's race from server crossings, which arrive at the gate cadence. Finer moments
(a near miss, a spin) would need a local feed from Pace or Carrier into this process -- a separate mod by the owner's
rule, not an addition to either.

**Continuity:** the Tape is `server_id` (L338), the Chronicle is `data/tape-<server_id>.sqlite`, and cursors and `seen`
live in it, so a restart or a disconnect resumes without re-narrating. While the game is closed nothing plays; on return
the editor sees the missed facts, learns them all (memory, rivals, milestones) and lets staleness keep them silent.
Narration is **local and private** to whoever runs the process; a shared broadcast would be a server-side resource
later. Observed 2026-10-08: the only `server_id` in Online's `paddock_event` is `ncm-dev`, so that is Online's Tape key.

## 3. The epistemic boundary

`CANONICAL TRUTH -> NARRATOR KNOWLEDGE -> PLAYER KNOWLEDGE / DISCOVERY -> PERMITTED NARRATION`, as code
(`epistemics.py`, tested):

* A station hears a fact only through a domain both share: Narrator `canonical`; News `public`; Race Control
  `officials`+`public` but only institutional kinds; Street `local`+`public`; Garage `technical`.
* `Fact.secret` keys (tolerance, deviation, p/z/u, meter samples) are never spoken by anyone.
* The quickhack truth ledger reaches only the Narrator, only when V was involved, and names the attacker only when V
  was the attacker or the player has discovered attribution. A destroyed car with no public attribution carries its
  uncertainty as a statement ("No cause has been announced"); when officials attribute it later, Race Control says so
  as a follow-up (the editor links stories by race).
* The Narrator knows the Week repeats; until `loop_named` is discovered it may say "the 3rd Racing Week of this Tape;
  V has lived 2 before it" and may not say loop/reset/rewind (forbidden list + validator).
* Every statement handed to the LLM is written deterministically from canonical fields and carries its fact id.

## 4. Editorial, memory, language

* **Score** = NCM salience + editorial weight (V involved +30, else -25 for the Narrator; milestones; recurring rivals;
  story follow-ups +25). Per-station threshold, cooldown and priority; stale facts (90 s for an in-race pass, 30 min for
  a result, hours for the Week) are silent; a topic is told by at most two stations; dedup survives restarts.
* **Coalescing:** a race's position changes are held 20 s and merged, so "5th -> 3rd, then Kat Morrow takes 3rd back"
  is one beat (a *reversal*, +20), flushed before that race's result.
* **The Chronicle** keeps people met per race (finished ahead/behind), milestones (first finish/podium/win/DNF), each
  Week's results and incidents, discovery flags, cursors. `recall` returns a few relevant lines for the packet; the Week
  obituary is built only from what it recorded.
* **Realization:** Ollama `qwen3.5`, thinking off, JSON out, a bounded packet. The validator rejects copy with a name or
  number not in the packet, a number in a different role than in the facts (`2nd of 5` spoken as "fifth"; an invented
  "turn three"), gendered pronouns (nobody's are known), loop words before discovery, or too many words. One retry with
  the violation stated, then the canonical statements verbatim. Race Control never goes through the LLM.

## 5. Voices and rooms (measured)

* Piper controls that work: commas, sentence breaks, our own inter-sentence gap, `length_scale`. Ellipses, dashes,
  CAPS, `!!!` and paragraph breaks do nothing; `noise_w` > 1 breaks the high voice
  ([TTS_PROBE.md](../../ncm/chronicles/docs/TTS_PROBE.md)).
* Scenes (numpy DSP, procedural beds; [SCENE_REPORT.md](../../ncm/chronicles/docs/SCENE_REPORT.md)), one line through each:
  Narrator floor -122 dBFS and a dry 300 ms tail (-77 dB): the impossible clean room; Studio the brightest; Race Control
  band-limited to ~2.5 kHz with a PA slap (-27 dB tail) and squelch; Street a traffic/crowd bed with pass-bys (floor
  -43 dBFS); Garage a hard metallic room with tools and a distant engine (-16 dB tail).
* Stingers (procedural, owned by the project, free to ship): News, Race Control, Street, Garage, and the Chronicles
  ident; the Narrator has none. Any one is replaced by dropping `assets/stingers/<id>.wav`; beds by `assets/beds/<scene>.wav`.

## 6. What the first run proved (2026-10-08, fixture Week, speakers)

16 segments played from 61 fixture rows: the Week opening (Narrator + News), the opening PA (Race Control), V's entry,
the in-race reversal as one beat, V's 4th, Sol Brandt's destroyed car on News ("No cause has been announced") and from
a street voice, the WIRE upset, the officials' attribution as a Race Control follow-up, an R&D release in the Garage,
V's first podium behind the same rival, two duplicate rows suppressed as DEDUP, the noon verdict, and the Week's
obituary. The validator caught: a swapped classification, an invented "turn three", "him" for V, and an obituary that
inverted attacker and victim (caught by the number check, not by understanding: §8).

## 7. To run it on a real world

**Online is authorised (owner, 2026-10-08) and configured** in `ncm/chronicles/chronicles.json` (gitignored): tape `ncm-dev`, driver `baremetaleven` (`72519ab3-010d-4a3e-b5d9-ed5e653d2be6`, the only human in Online's `paddock_entry`). The ssh source keeps ONE `sudo mariadb -B` session open with `SET SESSION TRANSACTION READ ONLY` (verified: even DDL is refused, ERROR 1792) and reopens it on failure; a poll is ~0.2 s. On start, everything older than 5 minutes is learned into the Tape's memory silently (`backfill`); first pass: 660 facts, 532 backfilled, two fresh WIRE streak stories spoken.


Dev: a read-only MariaDB user on dev's database in `chronicles.json` (`source.kind = mysql`). Online: the `ssh` source
runs the same SELECTs as `sudo mariadb` over the deploy key; reading Online's rows needs the owner's go-ahead (the
session's permission layer blocks production reads by default). The config needs `tape` (`ncm-dev` on Online) and the
owner's `ncm_driver_id`.

## 8. Expression losses and open edges

* The validator checks names, numbers and roles, not meaning: a sentence can still invert who did what with the right
  words. The Week obituary is the most exposed (many facts); its fallback is the verbatim statements.
* In-race narration rides server crossings only (gate cadence); no client telemetry yet.
* Street and Garage beds are procedural placeholders; no licensed field recordings yet.
* Playback is a WAV through `winsound` at full volume: no automatic ducking of game audio yet.
* The fixture's people are invented; the first canonical run is owed (MASTER_TEST §NC).
* `ncm_world/server/week.lua`'s header says "noon of Day 3 (hour 72)", but `week.curve.chapter` (and therefore every
  published `day`) makes hour 72 the start of Day 4. Chronicles follows `chapter`.
