# Night City Chronicles (package `ncm-chronicles`)

NCM simulates Race Week; Night City Chronicles narrates it. A local process that reads NCM's canonical tables
(read-only), decides what is worth saying and who may know it, has a local LLM say only those facts, performs them
through Piper, and puts each voice in its own acoustic world. Mostly the Narrator; News, Race Control, Street Voices
and Garage interrupt when the simulation gives them material. Design, audit and rulings:
[docs/ncm-online/57_NIGHT_CITY_CHRONICLES.md](../../docs/ncm-online/57_NIGHT_CITY_CHRONICLES.md).

It shares no code, state or package with Carrier, Rig Bridge, Broadcast or Pace, and it changes nothing on any NCM server.

## Setup (Windows, once)

```powershell
cd ncm/chronicles
python -m venv .venv
.venv/Scripts/python -m pip install numpy piper-tts pymysql
.venv/Scripts/python -m piper.download_voices --download-dir voices en_US-ryan-high en_GB-alba-medium en_GB-alan-medium en_US-danny-low en_GB-southern_english_female-low en_GB-northern_english_male-medium en_US-lessac-medium
ollama pull qwen3.5      # already on this PC
```

## Run

```powershell
# the demo Week (fixture rows in NCM's table shapes), spoken through the speakers
.venv/Scripts/python -m ncc --fixture fixtures/race_week_demo.jsonl --speed 2 --fresh --ident

# a real world: copy chronicles.example.json -> chronicles.json, fill tape / driver id / source
.venv/Scripts/python -m ncc --config chronicles.json

# opt back into the original short, restrained bulletin style
.venv/Scripts/python -m ncc --config chronicles.json --preset lean
```

The default `talk_radio` preset uses recurring character voices, longer conversational turns and a 24 s quiet / 60 s
beat cadence. Set `radio_preset` in JSON or use `--preset lean` for the former short format and its 60 s / 120 s
cadence. Flags: `--no-llm` (canonical statements verbatim), `--no-audio` (render WAVs only), `--ribbon` (captions to RibbonOS on
UDP 47921), `--verbose` (every suppressed candidate). Each run writes `out/<stamp>/`: numbered WAVs, `trace.log`
(readable: FACT / SELECTED-suppressed + why / SEGMENT / FACTS / COPY / REJECTED / PERF / PLAY) and `trace.jsonl`.
The Tape's memory is `data/tape-<server_id>.sqlite`.

## Layout

| file | stage |
|---|---|
| `ncc/sources.py` | canonical rows: MariaDB (dev), `ssh ... mariadb` (Online), JSONL fixture |
| `ncc/normalize.py` | rows -> facts (truth, public text, knowers, secrets, provenance) |
| `ncc/epistemics.py` | canonical truth -> what each station may say |
| `ncc/editorial.py` | score, staleness, dedup, cooldown, segment; reversal coalescing |
| `ncc/memory.py` | the Chronicle: per-Tape memory (rivals, milestones, Weeks, discovery) |
| `ncc/realize.py` | LLM realization + the grounding validator + template fallback |
| `ncc/perform.py` | TTS performance script (measured controls only) |
| `ncc/tts.py`, `ncc/scene.py`, `ncc/stingers.py` | Piper; acoustic scenes; the stinger vocabulary |
| `ncc/playback.py`, `ncc/trace.py`, `ncc/runner.py` | queue + staleness; the debug trail; the pipeline |
| `tools/tts_probe.py`, `tools/scene_report.py` | evidence: `docs/TTS_PROBE_RESULTS.md`, `docs/SCENE_REPORT.md` |

Tests: `.venv/Scripts/python -m unittest discover -s tests`.
