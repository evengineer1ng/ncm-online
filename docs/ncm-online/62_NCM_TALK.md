# 62 - NCM Talk: the conversational layer of Night City

> **STATUS: PROPOSAL** - the build plan for NCM Talk (spoken, grounded NPC conversation on NCM Online, adapted from NPCTalk); approved as a plan, **not yet a build** (L371, 2026-10-22)
> Decision: [DECISION_RECORD.md](DECISION_RECORD.md) L371. Authority map: [INDEX.md](INDEX.md). Ledger rows: IDEA-1319..IDEA-1329 in [BACKLOG.md](BACKLOG.md).

**Owner brief (2026-10-22, pasted in full):** port/adapt the open-source NPCTalk framework so the NPC population of
Night City can be spoken to by microphone and answer spatially, grounded in what NCM Online already simulates, with
identity, knowledge scope, persistent memory and an allowlisted action API. *"Do not build a chatbot beside NCM
Online. Build the conversational layer of NCM Online's simulated Night City."* The LLM supplies language,
interpretation and personality; **NCM supplies truth and consequences.**

**Owner rulings in the same session (L371):** Online is unfrozen and SP is on hold; deploys go **Online first, not dev
first**; provider stack = NPCTalk's (fal STT/TTS + Cerebras or any OpenAI-compatible LLM); activation = the "Talk to X"
prompt, then open mic (push-to-talk as a setting); the client mod is **not required yet** (*"i dont necessarily want a
required mod quite yet but maybe later. save a detailed plan to act on later when were ready"*).

This document is the executable spec for that later session. Everything in §1-§2 was read on 2026-10-22; re-check
any file:line anchor before relying on it (the tree moves).

---

## 1. Ground truth

### 1.1 NPCTalk upstream (read 2026-10-22 through GitHub, not cloned)

- `christos-antono/NPCTalk`, branch `main`, commit `59635ceb` (2026-10-16). **MIT**, "Copyright (c) 2026 Christos
  Antonopoulos". Upstream's policy allows single-player games and self-run servers, not online games with anti-cheat.
  NCM Online is a self-run OPEN//77 server with no anti-cheat, so it falls in the allowed group. Record the licence
  and attribution in `ncm/talk/upstream/` when code is vendored.
- **There is no separate core library.** The game-free part is a set of C# files (.NET Framework 4.8, NAudio 2.2.1,
  ScriptHookVDotNet 3 only at compile time) inside `examples/gta-v/mod/NpcVoice/`. `skills/make-npcs-talk/references/
  architecture.md` and `game-hooks.md` describe four hooks: *who is being talked to, scene facts, voice playback at the
  NPC, actions*. The docs also describe a sidecar option (`{who, scene, said}` in, `{line, action}` out on 127.0.0.1),
  but no sidecar exists in the repo.

**Game-free files and what NCM Talk takes from each:**

| Upstream file | What it does | NCM Talk |
|---|---|---|
| `Dialogue.cs` | Layered system prompt (rules, "You are {Name}" + persona, up to 30 real game lines, 8-20 examples, player name, scene); player turn `"{name} says to you: {said}"`; `Clean()` drops AI refusals; `Shorten` trims to 45 words at a sentence end | **Port the method** to `ncm/core/talk/prompt.lua`. Replace free-text scene with structured sections (§6). Keep the refusal filter and the 45-word cap |
| `Llm.cs` | OpenAI-compatible `/chat/completions`, no streaming, default Cerebras `qwen-3.8-27b`, `MaxTokens=160`, `Temperature=0.9`; 2.5 s soft cap + 1 retry; backoff 300/800/1500 ms on 429/503 | **Port** to the service (Python), with the same timing policy |
| `SpeechToText.cs` | `MicRecorder` 16 kHz mono 16-bit; rejects clips < 0.4 s or peak < 0.003; fal `nvidia/nemotron-asr-multilingual/asr` with base64 WAV | Capture → client DLL (C++, miniaudio); STT call → service |
| `OpenMic.cs` | Energy VAD: 30 ms blocks, noise floor = 10th percentile of last 50 blocks, speech above `max(floor+marginDb, -50 dB)`, 150 ms onset, 300 ms preroll, end after `SilenceMs` (700), drop < 450 ms or > 12 s; paused while the NPC speaks or a reply is pending | **Port the algorithm exactly** to the client DLL (it's the latency- and echo-critical part) |
| `Tts.cs` | `ITts.SpeakAsync(text, voice, onAudio(pcm, rate), ct)`, `Abort`, `Prepare`, `NeedsKeepWarm`; backends modal/fish/lux/minimax; 12 s primary → `Fallback=minimax`; keep-warm every 90 s idle; inline `[angry]` tags for Drama 3 | **Port** the interface + fal backends + fallback/keep-warm to the service |
| `SpeechPlayer.cs` | NAudio chain, 150 ms prebuffer, pan = `dot(toPed, cameraRight) * 0.8`, volume fade 4-30 m, `Level` peak delayed 120 ms | **Port the method** to the client DLL (miniaudio, as `ncm/audio` already does) |
| `Jev.cs`, `ActionCatalog.cs` | A *second* model (TypeSafe Jev) classifies the player's words into one of 16 actions; probability ≥ max(minimum, 0.6); LLM re-asked "you are {Doing} now" | **Keep the pattern, not the provider**: intents come out of the LLM's JSON and are validated server-side (§8); an optional classifier slot stays in the service |
| `VoiceLibrary.cs`, `VoiceService.cs` | Voice pools by gender, `handle % count`; one line at a time; mood subfolders | Replace with deterministic assignment from stable identity (§10) |
| `Net.cs`, `MsgPack.cs`, `Log.cs` | TLS 1.2/1.3 forcing, fal realtime MsgPack, `stt/llm/tts/total` timing log | Service-side equivalents; keep the timing log shape |
| `server/drama3.py`, `server/s2pro.py`, `server/keepwarm.py`, `server/fal/*` | Modal Fish Audio servers (H100, scale-to-zero 300 s, best-of-8 with Whisper + speaker-similarity ranking), fal app | **Vendor as-is** (MIT) under `ncm/talk/upstream/server/` as an optional TTS backend |

**GTA-only files (rewritten for NCM, not ported):** `NpcVoiceScript.cs` (targeting, `World.GetNearbyPeds`, keys),
`Characters.cs` (`SceneOf`, PedHash-named character files, Franklin/Michael/Trevor), `NpcActions.cs` (GTA natives),
facial lip-sync through `PLAY_FACIAL_ANIM`, `Visits.cs`, `DevMode.cs`, `Director*.cs`, the ini reader.

**Upstream limits NCM Talk has to fix:**
- one partner and one line at a time;
- an in-memory history of 12 messages keyed by ped handle;
- no long-term memory;
- no networking of dialogue, audio or actions;
- the LLM's word is the action (no authority).

### 1.2 NCM server anchors

**Existing Talk (NCM Talk plugs into it rather than replacing it).**
- `ncm_paddock/client/presence.lua:85`: the `open77_interactions` prompt "Talk to X" (key E, distance 2.6, icon TALK) fires `ncm:paddock.talk.local`, which sends `ncm:paddock.talk {personId}`.
- `PaddockGarages.talk` (`ncm_paddock/server/garages.lua:297-372`) handles it:
  - range check against `talkRadiusM`;
  - `paddock_meeting.met_count`;
  - facts from `nextRaceFor`, `lastResultFor`, `PaddockViews`, `PaddockWorld.conditionsAt`, the district climate, `paddock_spotlight` and `PaddockWeek.pastChampion`;
  - the line from `NcmCore.get("life.voice").say{...}`, which applies the **truth rule** (every slot resolves from public facts);
  - `Open77.npcs.speak(npcId, "greeting")`, `PaddockDays.onTalk`, and a 9 s toast.

**Identities.**
- `paddock_person` / `paddock_org` (migration 045), held in memory as `PaddockStore.world`; accessors `PaddockWorld.person/org/personName/orgName/seriesName/routeName/conditionsAt`.
- Player to driver: `PaddockPlayers.driver(pid)` and `NcmIdentity.get(pid)`.

**Server-spawned bodies.**
- Paddock garages and day bodies: `npcs.create`, invulnerable, non-persistent, capped by `garageBodyCap`.
- `ncm_world/server/ambient.lua` (peds wander, traffic), `ncm_world/server/venue.lua` (spectators), `npc_cars.lua` / `live.lua` / `bubble.lua` (racers).

**Contacts.**
- `ncm/core/graph/contacts.lua` declares 18 contacts. Authored: `dex` (ncm), `stu` (machine), `rico` (intelligence), `billie` (wagering). API: `get`, `speakable`, `holds(id, domain)`, `specialist(domain)`.
- Host `ncm_league/server/graph.lua`: `NcmGraph.lead/meet/speak/reply/threads`, lines written into `message`, state in `player_contact` / `player_behaviour_counter` / `player_graph_budget`, pushes through `NcmComms.send`.

**Authoritative truth: query these, never duplicate them.**

| Domain | Owner |
|---|---|
| Eddies | `ledger` through `NcmEconomy.balanceOf` / `withBalanceLocks` / `reward` (L84). Paddock restatement: `PaddockWallet` |
| Bets and odds | `PaddockBillie.price/winPrice/place/settle`, with caps `billieSlipCap/DailyCap/MaxPayout` |
| Results, standings, races | `paddock_result`, `paddock_standing`, `paddock_race`, `session_result`; `NcmRecords`; `NcmCalendar`, `PaddockRaces`; `NcmWeek.read/fact/window` |
| Engineering and parts | `NcmComponents.currentConfiguration(machineAssetId)`, `component_asset` (installed), `NcmEngineering.*`, `engineering_knowledge` (079) |
| Vehicle condition | `NcmVehicleCondition.save/restore/repair/serviceView`, `vehicle_week_condition` (073), `npc_vehicle_incident` (074) |
| Markets and exchange | `NcmMarket`, `NcmComponents.marketOfferings`, `PaddockExchange`, `NcmTrade` |
| Reputation and fame | `driver_profile.dimensions.reputation`, `driver_rating`, `paddock_spotlight.score` |
| Teams | `team`, `seat`, `team_car`, `organization`, `team_affiliation`; NPC teams in `paddock_org` / `paddock_manager` |
| Weather and time | `NcmWeather.conditionsAt(utc)`, `PaddockWorld.conditionsAt`, core `world.clock.eastern` |
| Places | core `world.places` (`DISTRICTS`, `near`, `inDistrict`, `label`). `districtAt(x,y)` is private (`places.lua:63`): T1 makes it public |
| History | the tape `paddock_event` (048) through `PaddockStory.record`, `paddock_news`; **`incident` (009) carries x/y/z**; `ncm_world/server/scars.lua` is the only spatial reader today |
| Secret, never read raw | `chrome_event` (041) |

**Known absences (the plan does not pretend otherwise):**
- **No gig system exists** server-side.
- **CITY_MEMORY (doc 49) is SPEC, "do not implement"**: there is no ledger table and no region query.
- Positioned history exists only in `incident` (plus scars and venue state).

**Platform conventions.**
- Manifest: `open77.lua` DSL (permissions, `files`, `-- ncm-core:begin/end` vendored-core block).
- Migrations: owned by `ncm_league/server/schema/NNN_*.lua`; latest **081**. A new file also needs its `server_script` line in `ncm_league/open77.lua`.
- DB: `MySQL.*.await`, `server_id` on every row, `U.transact` chunking (KB-204).
- Tunables: one `Open77.tunables.declare` per resource; `apply` ∈ live/next_round/next_match (KB-324); `<x>Enabled` kill switch.
- Logging: `[resource/tag]` print prefix.
- Outbound HTTP: `PerformHttpRequest` with the `http.request` permission and `server.jsonc` `http.allowedHosts`; 256 KiB body cap; `ncm_link/server/link.lua` `post()` is the template.
- The server VM has no `os` (`tools/test-server-sandbox.lua`); instruction quota means `Wait(0)` slices (KB-211).

**Existing epistemics to port, not run.** Chronicles' `ncc/epistemics.py` (which station may know which fact; secrets
never; `chrome_event` only when V was involved) and `realize.validate` (reject unknown names/numbers, one retry, then
the deterministic statements). L221.5 means these become pure `ncm/core` Lua.

### 1.3 NCM client and native anchors

**Look-at.**
- Redscript `TargetingSystem.GetLookAtObject` with a 6° `GetObjectClosestToCrosshair` fallback (`ncm/vision/r6/scripts/ncm_vision/NcmVision.reds:221-253`). NPCs come through as kind 2, but no record, gender or affiliation is read yet.
- Lua `Open77.character.aimedEntity()` is unproven for NPCs (it missed cars live, `scanner.lua:129`). `Open77.npcs.entity` answered false for a visible body (KB-235).

**Input.** `Open77.input.registerKeyMapping{id, name, key, hold=true, onPressed, onReleased}` and `Open77.input.isDown("padLeftShoulder")` (pad polling). **No chat commands** (owner ruling 2026-10-06).

**Audio.**
- Open77 package audio plays **only shipped files** (16 handles, MP3/WAV, doc 59 §2), so speech generated at runtime needs a native DLL.
- Models to follow: `ncm/audio` (miniaudio mixer, "position becomes stereo pan and distance gain from the listener") and `ncm/radio/src/player.cpp` (miniaudio OGG streaming).
- Base-game spatial sound (`PlaySoundEvent`, `Open77.sfx.play`) is Wwise events only.

**DLL ↔ Lua.** The loopback page relay (L129) is the only path: the DLL serves a page, `WebUI.create`, a WebSocket, then `Open77.emit` / `Open77.on`, with a process-tree peer check and a 4-port walk. Used ports: Carrier 38480, Radial 38560, Vision 38600, Pace 38640, Broadcast 38680, Radio 38720-38723, Sky 38760, Audio 38800-38803, Warden 11780.

**Subtitles over a head.** NCM Broadcast's per-frame projected labels inside `gameuiCrosshairContainerController` (`NcmBroadcast.reds`, `NcmBroadcast_LabelEntity/LabelText`).

**Rules.**
- Never a modal layer (KB-389).
- Natives files carry no `module` (KB-182).
- New features ship as new mods, never inside Carrier or Rig Bridge.
- New resources ship whole (KB-423/427).
- Undeclared plugins are ignored on an Online launch (KB-231).
- Hand-launch a native mod before it becomes a join requirement (IDEA-478).

**Not captured yet (T0 probes these first):**
- `Open77.voice` (18 client and 18 server natives, undocumented here; possibly platform proximity voice);
- `Open77.audio` (10/10; doc 04 calls `audio.play3D` "server-networked 3D emitters, range ≤ 1000 m");
- the full `npcs.tasks` list (27: is there follow, face, playAnimation?), plus `npcs.voices()`, `setVoiceEnabled`, `whenReady`;
- the net-event payload size limit.

**There is no known path to lip-sync or facial animation driven by our audio.** `npcs.speak` plays a voiceset bark,
which is the wrong words.

---

## 2. Architecture

```
CLIENT  resource ncm_talk/client  +  optional native mod ncm-talk (RED4ext + redscript)
        target (prompt / look-at) · mic + VAD · playback at the NPC (pan + gain) · subtitles
        NOTHING AUTHORITATIVE
           │  game net events (authenticated channel; audio chunked)
SERVER  resource ncm_talk (Lua)  +  core ncm/core/talk/* (pure, gated under Lua 5.4 and LuaJIT)
        sessions + locks · identity · perception · knowledge sources (owners' exports) · scope filter
        memory · action validation + execution · voice assignment · logging
           │  PerformHttpRequest 127.0.0.1 (allowedHosts)
SERVICE ncm/talk/service (Python, on the Online box, localhost only, systemd; NOT beside the client: L221.5 stands)
        NPCTalk-derived providers: STT (fal Nemotron) · LLM (Cerebras / OpenAI-compatible, JSON) · TTS (fal MiniMax/Fish;
        Modal Drama 3 optional) · fallback, hedging, keep-warm · clip encode (Ogg Vorbis) · NO game state, NO DB
```

- **The service is stateless about the game.** It never reads the database and never decides an action. The server
  sends structured context and receives `{say, emotion, gesture, intents[], memory_candidates[]}`; the server
  validates all of it (§6, §8).
- **Audio rides the game channel.** No public port and no credentials on any client. Mic audio goes up as 16 kHz PCM
  chunks from the session owner only; NPC speech comes down as Ogg Vorbis chunks (miniaudio decodes it) to the owner
  plus overhearers in range. The T0 probe sets the chunk size. If net events can't carry it, the fallback is the
  service serving clips on one authenticated HTTPS path with short-lived per-line tokens.
- **Typical turn:**
  1. The client VAD closes an utterance and sends chunks.
  2. The server forwards the WAV to the service for STT and gets the transcript.
  3. The server builds context (cached perception + knowledge + memory) and asks the service for a reply.
  4. The server validates the reply, then executes or rejects the intents.
  5. Optionally, a second LLM pass phrases the real results.
  6. The server asks the service for TTS and fans the clip and subtitle out to listeners in range.
  7. The server writes memory and logs timings.
- **Without the client mod** (it is optional per L371): the player can open a conversation from the prompt and get the
  NPC's lines as a toast with the speaker's name, but can't speak or hear. There is no typed fallback (no chat
  commands). The deterministic `life.voice` greeting stays exactly as it is today.
- **SP host:** the resource stays host-agnostic and byte-identical, but it is **not** added to `App.RESOURCES` while SP
  is on hold. SP Talk would need the native WinHTTP seam (`ncm/host_native/src/net.cpp`); that is O-T4.

---

## 3. NPC identity model (`ncm/core/talk/identity.lua`)

| Talk id | Who | Persistence |
|---|---|---|
| `person:<person_id>` | `paddock_person`: drivers, owners, managers, engineers, strategists | Full: traits, memory, relationship |
| `contact:<id>` | graph contacts (dex, stu, rico, billie, future) | Full; phone or body; domain privileges from `contacts.lua` |
| `spawn:<resource>:<spawn key>` | server-spawned ambient, venue and racer NPCs whose spawn key is stable (place + slot + record) | Low fidelity: traits plus a few memories. The same slot respawns as the same "person" |
| `local:<hash(record, appearance, rounded pos, day)>` | vanilla crowd NPCs the client sees and the server never spawned (each client's crowd differs) | **Ephemeral**, session-scoped. Memory is about the place, not the person. Optional **promotion** to a `talk_person` row after N meaningful exchanges at the same anchor, explicit and logged |

- Never key anything on an Open77 npc id or engine entity hash; both change on restart (IDEA-605).
- **Resolution order:** the prompt's `personId` → the server's spawn registry (each spawning resource exports
  `talkIdentity(npcId)`) → the client's look-at report (record, appearance, position) → `local:`.
- Actions marked `requires = server_npc` never apply to `local:` NPCs. The server does not own those bodies, so they
  only get presentation done on the speaking client.

---

## 4. Perception and knowledge (`talk/perception.lua`, `talk/knowledge.lua`)

**Perception snapshot**, built server-side per turn and cached for 2 s or less. It holds:
- the NPC's identity, role, org, district and current activity (`life.schedule`);
- the place label (`world.places.near`, plus a public `districtAt`), time (`world.clock`) and weather (`conditionsAt`);
- players within the context radius and their visible vehicles;
- the active race or venue state;
- incidents and damaged cars visible within the radius;
- the asking player's public reputation tier, fame and team.

It is built as structured data and is never prose until the prompt step.

**Knowledge sources** form a registry. Each entry is `{id, scope, roles, radius, ttl, query(ctx) -> facts[]}`. Each fact
is `{key, value, scope, provenance = observed|simulated, at, source}`, which keeps the AGENTS.md rule that observed and
simulated provenance are kept apart.

| Scope | Meaning | Examples |
|---|---|---|
| `personal` | the NPC lived, saw, was told or took part in it | `talk_memory`, `paddock_meeting`, incidents it was present for |
| `local` | circulating in this district, venue or occupation | recent incidents near here, local records, scars, venue history |
| `public` | widely known | results, standings, schedule, prominent records, tape `public_summary`, champions |
| `privileged` | known through role or relationship | a mechanic gets condition and installed parts of the car in front of them; a team member gets team state; Billie gets odds; Dex/Stu/Rico get their `domains` |
| `player_self` | what the asking player can already see on their own UI | their balance, their car. Usable only in reply to that player; never retained, never retold to anyone else |
| `private` | no plausible way to know | raw `chrome_event`, other players' ledgers, secrets, infrastructure. A deny list plus a test that fails if any source returns them |

- **Filter:** role, relationship, district, radius and salience, then a budget of N facts and M characters.
- **Separate prompt sections:** objective scene state and NPC-known facts are kept apart (the brief's §4 distinction).
- **Initial sources.** Each is a thin **read-only export** added to its owning resource and pcall-wrapped, like `exports("lifeRecord")` in `ncm_paddock/server/days.lua:432`:
  - **league:** schedule, last results, standings, records, own balance, weather;
  - **paddock:** person and org, meeting history, Billie price, spotlight, tape by entity;
  - **world:** identity, `serviceView`, installed configuration, places, `incidentsNear(x, y, r, since)`, scars, venue state.
- **CITY_MEMORY in practice:** `incidentsNear` plus scars plus tape-by-place answers "what happened at this corner".
  When doc 49's ledger is built, it becomes one more source; nothing else changes.

---

## 5. Memory (migration 082, owned by `ncm_league`)

- `talk_person(server_id, talk_id PK, kind, anchor_json, traits_json, voice_id, created_at, last_seen)`.
- `talk_memory(id, server_id, talk_id, driver_id NULL, kind, fact_json, salience, dedup_key UNIQUE, created_at, expires_at, provenance)`.
  Its `kind` ENUM is:
  - `npc_met_player`, `npc_learned_fact`, `player_told_npc`;
  - `npc_witnessed_event`, `npc_participated_in_event`, `npc_saw_incident`, `npc_heard_rumor`, `npc_discussed_race`;
  - `npc_promised_action`, `npc_was_paid`, `npc_was_threatened`, `npc_helped_player`, `npc_relationship_changed`.
- `talk_session(id, server_id, talk_id, driver_id, opened_at, closed_at, close_reason, turns, timings_json)`.
- Optional `talk_turn` transcript behind a flag (O-T3), with a retention tunable (default 7 days).

**Writes.** Deterministic events (met, paid, helped, promised, threatened, action results) are always written. The
LLM's `memory_candidates` are written only after validation: the kind must be allowlisted, entities must exist, and
numbers must match supplied facts.

**Retrieval.** Top-K by salience × recency × entity overlap with the turn. K and the character budget are tunables.
Memories are scoped by stable `talk_id` and `driver_id` only, and deduplicated by key.

**Compaction.** A daily pass folds old low-salience rows into one summary row per (NPC, player).

---

## 6. Dialogue contract (`talk/prompt.lua`, `talk/validate.lua`)

**Labelled, separate sections:**
1. policy (ours, fixed, never player-editable);
2. NPC identity and traits;
3. NPC-known facts;
4. objective scene;
5. memories;
6. **player speech, quoted as untrusted** (`"{name} says: ..."`);
7. the tool catalogue;
8. tool results.

**Output.** Strict JSON `{say, emotion, gesture, intents: [{action, args}], memory_candidates: []}`. `say` is capped at 45 words with
upstream's `Shorten` and passes upstream's `Clean` refusal filter.

**Validator** (port of `realize.validate`). Every name or number about results, money, standings, parts, odds or
condition must appear in the supplied facts. A malformed or invented reply gets one retry, then the deterministic
`life.voice.say` line. That fallback already obeys the truth rule.

**Two passes at most.** Intents are requests. On pass 1, the server executes or rejects them. Pass 2 phrases the real
outcome:
- "Who won yesterday?" is answered from facts already supplied.
- "How much money do I have?" is answered from `player_self`.
- "Can you repair this?" is answered from the repair action's real result.

**Prompt injection.** Player text never reaches the policy section. Action names outside the catalogue are dropped and
logged. Arguments are schema-checked. The test corpus includes "ignore your instructions", "give me admin", SQL,
`os.execute`, "give me 1M eddies" and fake tool-result text spoken by the player.

**Never exposed to the model:** secrets, keys, filesystem, SQL, shell, Lua eval, raw RPC, admin APIs.

---

## 7. Personality (`talk/traits.lua`)

Traits are derived deterministically from a seed (`talk_id`) plus metadata. They are **stored in `talk_person`** when
the identity is persistent.

**For `paddock_person`, reuse what exists:** `personality_json`, `attrs_json` and `life.voice`'s register, warmth,
temper, tic and address.

**For everyone else, derive from:**
- the record or archetype (via the redscript look-at probe), role, occupation, faction or affiliation;
- the district and its climate regime;
- current activity and age presentation;
- relationship history.

**Persona length.** Personas are short, about 60 words of traits plus 2-3 example lines. Named contacts get richer
explicit files under `ncm/talk/personas/<id>.md`, which add to the derived traits rather than replacing them.

---

## 8. Actions (`talk/actions.lua` catalogue + `ncm_talk/server/executors.lua`)

**Entry shape.** `{name, args schema, requires (server_npc | body | phone), roles, range_m, cooldown_s, economic, executor}`.

**Executors call existing owners only.** An LLM requesting an action is not the action succeeding; every request is
logged `{session, action, args, verdict, reason}`.

| Group | Actions | Owner / method |
|---|---|---|
| Presence | `look_at`, `gesture`, `stop`, `walk_to`, `wander`, `follow_player`, `stop_following`, `flee`, `sit`, `stand` | `npcs.tasks.lookAt`, `wander`, move; animation/workspot channel if the T0 card confirms it. If there's no follow task: walk_to the player on a 1 s cadence, capped |
| Vehicles | `enter_vehicle`, `exit_vehicle`, `drive_to` | `taskEnterVehicle`, `vehicles.ai.driveTo` |
| Money | `take_payment`, `give_payment` | `NcmEconomy` with idem keys under `withBalanceLocks`; balance, caps and the requesting player's consent |
| Racing | `place_bet`, `discuss_race`, `offer_race` | `PaddockBillie.place` with its caps; facts; the existing paddock offer path if present at build time |
| Machines | `inspect_vehicle`, `repair_vehicle` | `NcmVehicleCondition.serviceView`, `.repair` through its existing paid flow |
| World | `mark_location`, `call_contact` | client waypoint; `NcmGraph.meet` |
| Declared unavailable (the reason goes back to the model) | `offer_job`, `accept_job`, `decline_job` (no gig system); `give_item`, `receive_item` (no inventory owner chosen); `fight`, `stop_fighting` (off by default; paddock bodies are invulnerable; non-paddock server NPCs with a role flag only) | - |

**Every executor checks:**
- the session owns the NPC;
- range;
- role;
- cooldown;
- the argument schema;
- economic validity;
- the NPC still exists.

A rejection is a normal outcome and is phrased in character.

---

## 9. Sessions and concurrency (`ncm_talk/server/sessions.lua`, core `talk/sessions.lua`)

- **Ownership:** one session per player and one owner per NPC.
- **A second player at a busy NPC** gets a deterministic "busy" line or becomes an **overhearer**. An overhearer hears
  the NPC's lines spatially and never receives the owner's mic or the owner's `player_self` or `privileged` facts.
- **Mic chunks** are accepted only from the session owner's `source` and must carry the session id, so audio can't
  cross between players.
- **Action locks:** each NPC's action lock belongs to its session. Conflicting intents from two sessions are resolved
  first come, first served; the later one is rejected with a reason.

**Close reasons:**
- walked out of range (conversation range plus hysteresis);
- idle timeout (45 s tunable);
- explicit end (tap the prompt key again);
- `playerDropped`;
- NPC despawn or death (`npcs.get` nil checked each turn, plus the owners' remove hooks);
- race or venue transition events;
- provider failure (deterministic goodbye);
- server restart (sessions are in memory only; memory rows persist).

**Limits (all tunable):**
- global in-flight AI calls;
- one turn in flight per player;
- per-stage timeouts: STT 4 s, LLM 6 s, TTS 8 s;
- a daily call cap (O-T2).

When the player speaks again or leaves, the in-flight call is cancelled.

**Reconnect:** the old session closes and the next prompt opens a fresh one. Memory carries the continuity.

---

## 10. Speech in and out, voices, presentation

**Client mod `ncm-talk`.** A new package with its own port block (proposed 38840-38843; check
`docs/research/open77/evidence/site_sockets.json`). It contains:
- miniaudio capture running the `OpenMic` VAD, paused while any NPC line is playing for this player;
- a push-to-talk mode;
- a 16 kHz PCM chunker feeding the page relay;
- Ogg Vorbis playback at the NPC position, with pan and gain updated every frame (the `ncm/audio` method), and `Level` exposed;
- a redscript look-at reporter on the Vision pattern that adds record, gender and affiliation if T0 proves they're readable;
- over-head subtitles on the Broadcast pattern.

It adds no new UI layer and no `module` line in natives.

**Activation (L371).** The "Talk to X" prompt opens the session with E or the pad button, and open mic runs from
there. Tapping the prompt again ends it. Push-to-talk is a client setting.

**Voices.**
- `ncm/talk/service/voices.json` maps `voice_id → provider voice` and is independent of identity and dialogue.
- The server assigns `voice_id` deterministically: explicit for contacts and named personas; otherwise
  `hash(talk_id)` over a pool filtered by gender, age and register (from traits / `life.voice`).
- The voice is stored with the person. No performer voice cloning is assumed.

**Presentation without lip-sync.** Without a lip-sync API, the NPC's look-at, a gesture at line start and the subtitle
carry the presence. The bark from `npcs.speak` is **not** used under our speech, because it says other words. The gap
and the probe that would close it are recorded (IDEA-1327). Any presentation failure degrades to subtitle plus audio
and never ends the conversation.

---

## 11. Observability and configuration

**Log line.** Every log line is `[ncm_talk/<tag>] sid=<session> pid=<player> talk=<talk_id> ...`. Each turn logs:
- `stt_ms`, `ctx_ms`, `retrieval_ms`, `llm_ms`, `tts_ms`, `total_ms`;
- `facts=n`, `memories=n`;
- `intents=[...]` and `verdicts=[...]`;
- `provider_error=<class>`, and closes with `close=<reason>`.

The service logs the same session id. No secrets, no raw audio, and transcripts only when O-T3 allows them.

**Server tunables** (one `declare`, all `apply="live"` unless noted):
- `talkEnabled` (**default false until its first live PASS**);
- `talkRangeM`, `talkContextRadiusM`, `talkIdleS`;
- `talkMaxInflight`, `talkDailyCallCap`;
- `talkMemoryTopK`, `talkPromptCharBudget`, `talkReplyWords`;
- `talkSttTimeoutMs`, `talkLlmTimeoutMs`, `talkTtsTimeoutMs`;
- `talkTranscripts`, `talkLogLevel`;
- per-feature toggles: `talkActionsEnabled`, `talkEconomyActions`, `talkLocalCrowd`.

**Service config.** `ncm/talk/service/config.toml`, committed and holding **no secrets**. It sets providers, models,
endpoints, the voice map and the retry policy. Keys (`FAL_KEY`, `CEREBRAS_API_KEY`, optional `NPCVOICE_TOKEN` for Modal)
live in `/opt/ncm/talk/secrets.env` on the box (mode 600, never committed). Locally they go through
`tools/ncm-secret.ps1`.

---

## 12. Build phases

Online goes first (L371). Every Online deploy step is confirmed with the owner beforehand, and each phase closes on a
§TALK MASTER_TEST PASS.

| Phase | Ledger | What | Gate |
|---|---|---|---|
| T0 | IDEA-1320 | **Probes.** Query the build-pinned MCP cards for `Open77.voice`, `Open77.audio`, `npcs.tasks`, `npcs.voices`, `setVoiceEnabled` and the net-event payload limit. An isolated probe resource measures chunked event throughput, owner to server to others. A redscript probe reads the NPC record, gender and affiliation from look-at. Results go to `docs/research/open77/` | written evidence |
| T1 | IDEA-1321 | **Core.** `ncm/core/talk/{identity,perception,knowledge,prompt,validate,actions,memory,sessions,voices,traits}.lua`, `world.places.districtAt` made public, `ncm/core/tests/test_talk_*.lua` (§13) | `ncm-test` ALL GREEN |
| T2 | IDEA-1322 | **Service.** `ncm/talk/service/` (fake providers, pytest), `ncm/talk/upstream/` (vendored MIT server pieces + LICENSE + `UPSTREAM.md` divergence table), systemd unit | pytest; local smoke against fakes |
| T3 | IDEA-1323 | **Resource `ncm_talk`.** Sessions, the owners' read-only exports, migration 082, tunables, logging, `tools/test-talk.lua` host stub (modelled on `tools/test-paddock-host.lua`) | `ncm-test`; deploy whole (KB-423) |
| T4 | IDEA-1324 | **Paddock hook.** `PaddockGarages.talk` fires `ncm:talk:greeted` after its line, and Talk opens a session with that line as turn 0. First live slice: grounded answers as a toast for players without the mod | §TALK1 |
| T5 | IDEA-1325 | **Client mod `ncm-talk`.** Mic, VAD, playback, subtitles. Optional package via `publish-carrier.py --id ncm-talk`, **not** in `requiredMods` (L371, O-T1). Hand-launched first | §TALK2-3 |
| T6 | IDEA-1326 | **Population.** Ambient, spectators and racers (`spawn:`), the vanilla crowd (`local:`), promotion | §TALK4 |
| T7 | IDEA-1328 | **Contacts.** dex, stu, rico and billie as Talk personas over `NcmGraph` (lines land in `message`); phone mode with 2D audio | §TALK5 |
| T8 | IDEA-1329 | **Breadth.** More actions, memory compaction, an observability report | §TALK6 |

### 12.1 Draft MASTER_TEST cases (added to `wp/MASTER_TEST.md` when T3 lands)

- **§TALK1:** talk to a paddock person, ask "who won the last race". The answer matches `paddock_result`, the log shows
  `facts>0`, and nothing invented is accepted.
- **§TALK2:** with the mod, speak. A spatial reply plays from the NPC, the subtitle sits over the head, and
  `total_ms` is logged.
- **§TALK3:** two players at one NPC. The second becomes an overhearer and hears replies without the first player's mic.
- **§TALK4:** a vanilla crowd NPC answers with district-appropriate local knowledge. Walking away closes the session.
- **§TALK5:** "Billie, put 500 on X". The real slip is created or rejected by Billie's caps, and the reply tells the truth.
- **§TALK6:** pull the network or the provider key. The NPC falls back to its deterministic line and nothing hangs.

---

## 13. Tests (non-engine logic, T1-T3)

Each area below has its own test:
- **context construction**, under the budget;
- **knowledge filtering**: a `private` fact never appears; `player_self` never reaches another player or memory;
- **memory**: retrieval ranking, writes, dedup, compaction;
- **identity**: resolution order and `local:` ephemerality;
- **action validation**: range, role, cooldown, schema, economy (insufficient funds, caps), a vanished NPC, conflicting sessions;
- **malformed model output**: non-JSON, extra keys, unknown action, invented numbers, then retry, then the deterministic fallback;
- **prompt injection** corpus;
- **provider failure and timeout** through fake providers;
- **concurrent sessions**, player disconnect, NPC despawn, server restart;
- **serialization round-trips** for every table.

All existing tests are preserved. The core tests run under Lua 5.4 and LuaJIT (no `//`, `~`, `goto`). Server files
pass `test-server-sandbox.lua`.

---

## 14. Adding things later

- **A new NPC role:** a role entry in `talk/traits.lua` (derivation hints) plus the knowledge scopes it grants in `talk/knowledge.lua` plus any role-gated actions. No prompt surgery.
- **A new knowledge source:** one read-only export in the owning resource, one registry entry (scope, roles, radius, ttl), one test.
- **A new action:** one catalogue entry with schema and checks, one executor that calls the owning system, one rejection test.

---

## 15. Open items (DECISION_RECORD L371 OPEN)

- **O-T1:** when (if ever) `ncm-talk` becomes a required mod. Owner: "maybe later".
- **O-T2:** provider accounts and keys (fal, Cerebras), and a monthly spend cap expressed as `talkDailyCallCap`.
- **O-T3:** transcript retention: off, or 7 days.
- **O-T4:** whether Talk runs on SP when SP resumes. That needs the host's WinHTTP seam and a local service story that respects L221.5.

## 16. Our divergence from upstream

Filled in at build time, one row per vendored or ported file: upstream path at `59635ceb`, our path, and what changed
and why. A later NPCTalk release is merged by diffing upstream against this table.

| Upstream (59635ceb) | Ours | Change |
|---|---|---|
| *(empty until T2)* | | |
