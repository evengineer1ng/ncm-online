# 59 - NCM Radio: Race Week Live, the deterministic talk-radio station

> **STATUS: CURRENT** - authority for: *Race Week Live as an in-game radio station: corpus compilation, trigger map, director, voice render, the `ncm-radio` required mod and the `ncm_radio` resource* - affirmed 2026-10-08 (L348)
> Decision: [DECISION_RECORD.md](DECISION_RECORD.md) L348. Authority map: [INDEX.md](INDEX.md). Lines: [radio/RACE_WEEK_RADIO_BIBLE.md](radio/RACE_WEEK_RADIO_BIBLE.md). Facts audit: [58_DETERMINISTIC_RACE_WEEK_RADIO_AUDIT.md](58_DETERMINISTIC_RACE_WEEK_RADIO_AUDIT.md). Code: `ncm/radio/`, `ncm/online/resources/ncm_radio/`, `tools/build-radio.ps1`, `tools/test-radio.lua`.

**In one paragraph.** Race Week Live is a station in Cyberpunk's own radio list (car radio and pocket radio), on by
default and never locked in. Every word on air is a line from the owner's authoring bible, performed by a cast of
pre-rendered voices. The simulation decides which authored beat airs and which names fill its slots; nothing is
generated at runtime and no player needs an LLM. It replaces the LLM narration of Night City Chronicles (doc 57) as the
target for Race Week commentary (owner, 2026-10-08: "llms hallucinate and its too unwieldy").

## 1. The pieces

| Piece | Where | Job |
|---|---|---|
| Authoring bible | `docs/ncm-online/radio/RACE_WEEK_RADIO_BIBLE.md` | Owner's text, imported verbatim (only a STATUS banner added). 249 sections and 5,689 speaker lines after expansion passes I-II, imported 2026-10-08. Speaker lines come in two formats, bold `**MARA:**` and plain `MARA:` (§210+); the compiler reads both. |
| Corpus compiler | `ncm/radio/tools/compile_corpus.py` -> `ncm/radio/corpus/corpus.json` | Every heading holding dialogue becomes a beat (1,088); every speaker paragraph a line, verbatim. **Refuses to write if one bible line is missing.** Stable ids: `<beat>#<nn>`. |
| Trigger map | `ncm/radio/corpus/families.py` | Which simulation moment selects each beat, plus the gates the bible states (day, Week condition, first-ever, whose result). A beat no rule claims fails the compile. |
| Slot classes | `ncm/radio/corpus/slots.json` | How each `{SLOT}` is spoken: name / org / series / route / number / ordinal / day / margin / clock / odds / phrase. Anything else is abstract (§4). |
| Voice render | `ncm/radio/voice/render.py`, `cast.json`, `spoken.py` | OmniVoice (§5): one designed voice per cast member, cloned for every line, placed in its room with Chronicles' scene DSP, OGG Vorbis. Output outside the repo (`D:/ncm-radio/pack`). |
| Director data | `ncm/radio/tools/build_corpus_lua.py` -> `ncm_radio/server/corpus_data.lua` | Every beat and line as clip keys + slots, with rendered lengths; Moody faces and Week PA steps read from `ncm/core/week`. |
| Director | `ncm_radio/server/director.lua` | Picks the next beat for one listener (§3). Pure Lua (LuaJIT ∩ 5.4). |
| Facts | `ncm_radio/server/facts.lua` | SELECT-only reads of the tape, the Week, human results, standings, the calendar. |
| Transmitter | `ncm_radio/server/main.lua` | One programme clock per listener; tells a client how far into the current beat the broadcast is. |
| Relay | `ncm_radio/client/radio.lua` | Hidden loopback WebUI to the plugin (L129 pattern), ports 38720-38723 (its own block; 38680 is NCM Broadcast's, KB-420). |
| Plugin | `ncm/radio/src` -> `ncm_radio.dll` | Plays the programme (miniaudio + stb_vorbis, public domain) only while listening; seeks to the broadcast's position on tune-in. |
| Station | `ncm/radio/r6/scripts/ncm_radio/*.reds`, `r6/tweaks/ncm_radio/station.yaml` | `RadioStation.NcmRaceWeekLive` (index 7700) as the first row of the vanilla radio popup; selection, hotkey toggle, default-on. |

## 2. Why our own plugin (not RadioExt, not Audioware)

RadioExt proves the vanilla radio classes can be extended, but its licence forbids re-upload and code reuse without its
author's permission, so it cannot travel in `requiredMods`. Audioware carries no licence file and only plays sounds
declared in a manifest at load. The station's redscript is our own code against vanilla classes
(`VehiclesManagerDataHelper.GetRadioStations`, `VehicleRadioPopupGameController.Activate/SetupData`,
`VehicleComponent.OnRadioToggleEvent`), decompiled from the installed game for exact signatures.

OPEN//77 has package audio (`Open77.audio.play2D`, op77.63+: MP3/WAV a resource ships, seek, volume). It was not used
for playback: 16 handles per resource, MP3/WAV only, absent from the NCM 3.0 CET host, and the plugin is needed anyway
for the redscript-to-resource channel. It remains an option for **delivering** the pack as resource files instead of a
required-mod zip.

## 3. The director (bible §51, §150, §174)

Order of choice for each listener, every time the previous item (beat + its pause) ends:

1. **Pending facts** for this listener, most salient first (NCM's own salience; +30 when it is the listener's own
   result). Each fact kind has a shelf life (`D.TTL`): a result is news for 25 minutes, a destroyed car for an hour, a
   Moody roll for 90 minutes. A fact with no eligible authored beat is dropped, not paraphrased.
2. **The station's clock:** the fixed opening once per Week (the bible's "Groundhog Day anchor"), a day opening in the
   first four hours of Day 2+, a day closing after hour 21 of a day, one time-of-day beat per clock slot (dawn, morning,
   midday, afternoon, sunset, night, midnight, in Night City time), standings every three hours once three races ran.
3. **The studio's reservoir:** long-form conversations whose gates the Week satisfies.
4. **Silence** (bible §66), with the station ident between rooms.

A beat is eligible only if every gate in the trigger map can be **checked** against real state. A gate this code
cannot verify yet (`needs_memory`, `joined_late`, `player_absent`, ...) makes the beat ineligible. It is never assumed.
Every slot must bind to a fact **and** to a voiced clip, or the beat is skipped. A line that is nothing but an abstract
slot is optional and dropped. Re-air cooldown: 20 h for event coverage, 10 h for studio and clock material. Ties break
on a stable hash, so a restart re-airs nothing differently. Pause after a beat: 12 s by day, 25 s at night, +15 s in a
bad Week.

**Habitation budget (bible §210, §246):** the studio's own conversations are budgeted, not filler. After 2 factual
items in a healthy Week (3 when slightly troubled, 5 when subpar; never in a bad or cataclysmic one), a studio
conversation airs before the next routine fact. A fact with salience 55+ still goes first. The 35 quiet-period long
forms of §211-§245 carry no slots at all. Their eligibility notes become gates: late night only, rare (once in 48 h),
not within two hours of a destroyed car, and only after a quiet stretch. The scorer also cools down the shape of the
conversation (§206): never the same section twice running, and it prefers a change of room.

Live today: 626 of 1,088 beats have a trigger NCM emits. The other 462 (flight, Deep, space, fuel, records, penalties,
qualifying for NPC fields, interviews, city scar tissue, ...) are compiled, rendered and shipped `dormant`. Each one
goes live the day NCM emits its fact, by editing one rule in `families.py`.

## 4. Slots and the knowledge boundary

Facts come only from public surfaces (doc 58): the tape's `facts` (what the WIRE may print), published Week steps,
Moody's public lines, settled results (L347: aired without any simulation label), standings. Never read: the
quickhack truth ledger, the Week's tolerance, samples or verdict probabilities.

Finite domains are voiced ahead of time and keyed `lex/<SPEAKER>/<slug>`: numbers 0-99, ordinals to 40th, days,
margins (tenths under 2 s, halves under 10 s, whole seconds to a minute), the clock to the quarter hour, odds, NCM's
own Moody and PA sentences, DNF causes. Names (drivers, teams, series, routes, players) come from `lexicon.json`,
which the resource writes to its data directory at boot and every ten minutes. `render.py lexicon --names` voices
them. The director and the render must speak a value identically. `spoken.lua` mirrors `spoken.py`, and
`tools/test-radio.lua` checks 51 cases.

Abstract slots (`{SUPPORTED_PERFORMANCE_FACT}`, `{SUPPORTED_CONTEXT}`, ... 500+ distinct names) need authored fills.
Until a fill exists, a line that is only that slot is dropped, and a beat that uses one mid-sentence does not air.
192 live beats wait on fills this way; §7 tracks it.

## 5. Voices

**OmniVoice** (k2-fsa, the engine under the VoiceStudio app). Code is Apache-2.0; **weights are CC-BY-NC** (training
data). NCM is free and non-commercial, so it qualifies. Attribution: "Voices synthesised with OmniVoice (k2-fsa)". Any
monetisation of NCM would require re-voicing. The VoiceStudio app itself (AGPL) is not used.

Each speaker is designed once from a reference line (`cast.json`: gender, age, pitch, accent). Three candidates per
speaker are under `D:/ncm-radio/pack/voices/<SPEAKER>/cand*.wav`, and `candidate` picks one. Every line is then cloned
from that reference, so a voice never drifts. Rooms (bible §10): studio for Mara, Jules and Celeste; a clean booth for
Imani; band-limited trackside for Tommy; the garage for Nia; the street for Darnell.

Measured 2026-10-08 (RTX 5060 Ti): about 0.8 clips/s. Average clip is 2.2 s, so the expanded bible is **about 3.5
hours of speech**, and a simulated 72 h Week airs about 619 beats, roughly 7-8 h of it (§7). OmniVoice returns nothing for some one-word lines
("What?", "Yeah."). `render.py retry` re-renders them one at a time with an explicit duration.

**Owner's cast picks (2026-10-08):** Tommy cand2, Celeste cand2, Darnell cand0, Imani cand0, Jules cand1, Nia
cand0, second remote feed cand2, and all three driver takes as three different drivers. Each driver line is rendered in
all three voices (`key@1`, `key@2`), and the director keeps one voice per beat. **Mara:** all three first designs were
noise (KB-403; Whisper heard "Bye-bye. Bye-bye..."). The cause was the long reference line with "honestly?" in it.
`audition.py` re-designs with a plainer reference line and keeps only takes Whisper transcribes word for word: 9 of
12 survived, and the owner picks one.

Re-casting: change `pick` in `cast.json` and re-run `render.py lines`. Clips record the voice that made them, so exactly
the recast speaker's clips re-render. `build_corpus_lua.py` counts only clips voiced with the current pick, so a
rejected voice can never air, and `render.py prune` deletes them before packaging. `render.py qc [--fix]` runs Whisper
over every line clip and removes any clip that does not say its words, so `retry` re-renders it. A clip whose speaker,
voice and words already exist under another key is copied, not regenerated, so a re-imported bible with renumbered
sections costs nothing. Human voice actors drop in by writing recordings to the same keys.

## 6. On the client

The plugin starts its audio device and loopback bridge when the game reaches Running. The resource's hidden page
connects. The plugin reports its version and pack hash, and the server warns when the hash differs from the
`corpus_data.lua` it airs. Every 100 ms redscript reports whether the player is listening (tuned and on) and the
game's own radio volume (`CarRadioVolume` in a car, `RadioportVolume` on foot, times `MasterVolume`). If no heartbeat
arrives for 750 ms (pause, loading), the station falls silent while its clock keeps running.

**Default on, never locked:** the first car of a session tunes in unless the player has ever picked another station
(`prefs.txt` beside the DLL). Picking another station, or turning the radio off, is respected and remembered. The
radio hotkey toggles Race Week Live while it is the station. No new UI layer (KB-389): the station is a row in the
vanilla popup.

## 7. Open edges

* **Airtime:** about 3.5 h of unique speech for a 72 h Week, of which about 7-8 h airs with repeats. The owner is
  writing more (expansion pass II added 2,219 lines). The bible's own target is tens of hours of habitation (§248).
* **Tags are a reading, not the writer's:** the shapes and delivery in `hand_tags.txt` were assigned by the coder
  reading every airable beat on 2026-10-08. The owner corrects them in that file; `tags.json` overrides both.
* **Abstract slot fills:** 192 live beats wait on authored fills for `{SUPPORTED_*}` slots.
* **Names:** a name joins the lexicon only after `lexicon.json` is rendered. Until then, beats that need that name do
  not air.
* **Previews** know series and time but not field, route or pole, so most pre-race beats wait.
* **Unseen play-by-play:** still the NOW.md open question (L347 covers settled results only). Every in-race
  middle-phase beat stays dormant.
* **Live:** nothing has been heard in game yet (MASTER_TEST §RW).

## 8. Show history, conversational shape, delivery (bible §206-§208, §247)

Every airable beat (623) was read and tagged by hand in `ncm/radio/corpus/hand_tags.txt` (`BEAT: CODES | direction`).
Dormant beats get tags inferred by `tag_corpus.py`, and `tags.json` overrides both. The compile refuses an unknown
code, and refuses a motif that has no origin beat.

* **Motifs (§247):** 11 running jokes, each with an origin and its callbacks: the 10 mm socket (§224, recalled in §243),
  the sad pharmacy (§214, §243), the old car's migrating vibration (§235, §240), the garage chair (§213, §243-§244),
  fluorescent coffee (§211, §245), cup holders (§211), the glove compartment (§218, §224, §238), warning lights as mail
  (§231, §240, §243), the trunk rattle (§238, §241), the terrible merch (§243), and "driver question earlier" (§195,
  §196). A callback is eligible only after its origin aired for that listener. Show history (what aired, which
  motifs a listener has heard) is saved per driver in the resource's `history/` directory and survives a restart.
* **Shapes (§206):** 16 codes (ask-translate, epistemic check, machine tease, one-word answers, prediction, support
  refuses, callback, standings, machine/driver/location lens, no analysis, long philosophical, joke utility,
  reflective, banter). A shape heard one beat ago costs 12 points, two to four beats ago 4. The same section running
  twice costs 15. Two joke-utility beats never run back to back. Banter is exempt as the show's tonal centre (§4).
* **Delivery (§208):** bright 1.05, neutral, late 0.96, tired 0.95, grave 0.93, rendered as pace because OmniVoice has
  no emotion control. A clip records the direction it was rendered with, so a re-tag re-renders exactly those clips.
* **Week condition:** habitation is capped per hour (healthy 4, slight 3, subpar 2, bad 1, cataclysmic 0) and never
  more than two in a row. In a bad or cataclysmic Week, generic studio, clock and utility beats and ungated bright
  beats do not air: "seriousness reduces ornament" (§9.10). Only material written for that Week airs, plus silence.
* **Determinism:** the queue has a total order, and the tie-break hash stays below 2^37, so Lua 5.4 (the Online
  server) and LuaJIT (the single-player host) air the identical Week (`test-radio.lua`, 30 checks, both runtimes).
