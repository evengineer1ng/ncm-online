# NCM Radio (package `ncm-radio`)

Race Week Live: a station in Cyberpunk's own radio list that plays the authored Race Week talk show
(doc 59, [docs/ncm-online/59_NCM_RADIO.md](../../docs/ncm-online/59_NCM_RADIO.md)). On by default, never locked in.

| Piece | Where | Job |
|---|---|---|
| `ncm_radio.dll` | `red4ext/plugins/ncm_radio/` | plays the `ncm_radio` resource's programme (127.0.0.1:38720-38723); four natives |
| `pack/` | beside the DLL | the rendered voice clips (`clips/**.ogg`) and `VERSION` (manifest hash) |
| `NcmRadio.reds` | `r6/scripts/ncm_radio/` | the station row, selection, hotkey toggle, default-on, listening + volume heartbeat |
| `NcmRadioNatives.reds` | `r6/scripts/ncm_radio/` | the natives, **no `module` line** (KB-182) |
| `station.yaml` | `r6/tweaks/ncm_radio/` | `RadioStation.NcmRaceWeekLive`, index 7700 |
| `prefs.txt` | beside the DLL, written at runtime | `ncm` or `other`: whether the player ever chose another station |

It shares no code, state, port range or package with the Carrier, the Rig Bridge, Pace or any other NCM plugin.

## Who decides what

- **The server decides what airs** (`ncm_radio` resource): which authored beat, which names, when. The plugin never
  chooses content.
- **Redscript decides whether anyone is listening.** The plugin plays only then. The programme's clock runs regardless,
  so tuning in lands mid-broadcast.
- **No heartbeat for 750 ms = silence** (pause menu, loading).

## Build

1. Render (render venv, GPU): `python ncm/radio/voice/render.py design|lines|retry|stingers|lexicon --names <lexicon.json>`
2. Director data: `python ncm/radio/tools/build_corpus_lua.py` (after every render)
3. Package: `powershell -File tools\build-radio.ps1` (builds, runs the timeline tests, checks natives, compiles the
   redscript against vanilla + installed scripts, writes `dist/ncm-radio-<version>.zip` with the pack)

Licences: miniaudio (public domain / MIT-0), stb_vorbis (public domain / MIT). Voices are synthesised with OmniVoice
(k2-fsa); its weights are CC-BY-NC, so this pack is for non-commercial use only.
