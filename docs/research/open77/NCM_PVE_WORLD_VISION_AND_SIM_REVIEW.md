# NCM Online PvE world: a simulation stack over Night City

> **STATUS: PROPOSAL** — long-term design handoff, 2026-09-29, restructured the same day under `L220`, rulings added under `L221` and `L222`. Owner answers and corrections in L218–L222 are direction; the architecture, capability tiers and examples below are recommendations awaiting review. No NCM runtime change or live PASS is claimed.
> Read with [the authority map](../../ncm-online/INDEX.md), [the current work index](../../ncm-online/NOW.md), [quest graph Pass 1](../../ncm-online/41_QUEST_GRAPH_PASS1.md), [the Oracle assessment](ORACLE_KINGDOM_PVE_ASSESSMENT.md), [the Oracle Racing prototype](../../../prototypes/oracle_racing/README.md), and the owner's attached **THE PADDOCK** plan at `C:/Users/eveng/.codex/attachments/5eddbe7c-1378-42f4-a779-fc98733fa5bd/Pasted text.txt`. At this revision `44_THE_PADDOCK.md`, `ncm/core/paddock/` and `ncm_paddock/` still do not exist in this checkout.

## Contents

1. [One sentence to build toward](#one-sentence-to-build-toward)
2. [The stance: simulation-led, Night City-performed](#the-stance-simulation-led-night-city-performed)
3. [The five layers](#the-five-layers)
4. [Layer 1: what CDPR gave us, and how we reach it](#layer-1-what-cdpr-gave-us-and-how-we-reach-it)
5. [Layer 2: the sim stack — one job per engine](#layer-2-the-sim-stack--one-job-per-engine)
6. [Layer 3: facts, tapes and projections](#layer-3-facts-tapes-and-projections)
7. [Layer 4: expression — bodies, dialogue, Messages, media](#layer-4-expression--bodies-dialogue-messages-media)
8. [How it plays](#how-it-plays)
9. [Content grammar: depth without an opaque sim](#content-grammar-depth-without-an-opaque-sim)
10. [Next coder: research and architecture handoff](#next-coder-research-and-architecture-handoff)
11. [Open questions](#open-questions)
12. [Appendix: source review of the five Python engines](#appendix-source-review-of-the-five-python-engines)

See also, inside Layer 1: [Night City runs on real time](#night-city-runs-on-real-time) and [Per-system control](#per-system-control-decided-one-system-at-a-time).

## One sentence to build toward

**The model to abstract is a life sim** (L222): think *inZOI* or *The Sims 4*, if those games were set in Night City and flavoured by motorsport, without being so rigid that it is only racing. The owner's Python engines are the seed of a proper life-sim engine. CDPR and OPEN//77 have already provided the hard part: Night City itself, and REDengine hostable as a multiplayer server. There is **no "first arc"**: the world is an ongoing snow globe that players live in.

NCM Online should let each player live **their own motorsport adventure in Night City**, as a driver, a manager, or both over time. Underneath, a **stack of simulations** (derived from the owner's earlier Python engines) keeps the Paddock and the city moving for everyone. **CDPR's Night City and the engine beneath it give that simulation a body**: real districts, crowds, traffic, NPCs, police, weather and native UI. The player's races, driving jobs, local challenges, choices and relationships make their adventure distinct. Some acts alter the shared world's people, access and alliances, and other players meet those public changes through their own stories.

The owner's answers so far (L218–L222) set the direction:

- Blend a racing career with city ties.
- Repeat a mix of jobs, turf and racing.
- Recurring NPCs appear through Messages **and** place-based encounters, with a **named physical NPC** as the intended form.
- Conversations use authored consequential choices with reactive dialogue.
- The underlying world is shared and evolving. Change shows chiefly through people, access and opportunities, and longer-term shared change is shifting access and alliances.
- Mix the existing contact web with new NPCs. The 18 quest-graph contacts become physical people too (L222). Keep recognizable Night City places; invent most groups, and **canon gangs and groups may be used** (L222). Canon crowds already stand outside places like Arasaka HQ because vanilla pedestrians populate the server.
- The player chooses driver, NPC-team manager, or both. Neither role gates the other.
- **Each player has their own PvE adventure over a shared sim** (L219). The Paddock is the foundation, not a global questline.
- Physical meetings target a **Fallout 4-like text dialogue**, without voice acting or mocap.
- **Night City runs on real time** (L221, L222): `America/New_York` with daylight saving; 11:00 PM Eastern is 11:00 PM in game, on a 24-hour day. Nighttime players and daytime players are both legitimate. Races run at the real hour.
- **How far the sim directs vanilla systems is decided per system** (L221), and each system is now ruled (L222; [table](#per-system-control-decided-one-system-at-a-time)).
- **Order of work: the Paddock first, then the social sim** (L222). All PvE and sim work happens on the **development server**; Online is frozen as **Baseline 1** (L223).
- **Native dialogue is approved as the first probe; the native phone is deferred** (L221). Online Messages stays the phone for now.
- **The approach is simulation-led** (L220). It is built from the owner's multiple Python sim engines, and it uses CDPR's Night City and its engine for bodies, places and behaviour. That capability is **not limited to the OPEN//77 API**: NCM already ships its own required redscript and RED4ext mods and can author more.

## The stance: simulation-led, Night City-performed

Four rules follow from the owner's direction. Every later section depends on them.

1. **The sims decide; Night City performs, and physical reality can answer back.** Who races, who wins a simulated round, who is angry with whom, where a named mechanic is tonight and which garage supplies which team are all **sim state on the server**. By default an engine NPC, an AI car, a pedestrian bark and a phone message are **projections** of that state, and a projection that goes wrong (a despawned body, an AI car that stalls, a streaming hole) never rewrites the sim. **L222 amends the Paddock plan's blanket "physical outcomes never write back"**, because a read-only puppet would squander the whole Night City advantage. When an activity runs in an explicit **physical-authoritative mode** and NCM can corroborate the outcome, the physical fact writes back: an AI race that was actually instantiated and observed, a named NPC who was actually stopped by NCPD, a delivery a simulated courier actually made. Gate crossings are not the only things allowed through reality's membrane.
2. **Provenance keeps it honest: `physical`, `simulated`, `reported`, and never one pretending to be another.** The path from engine to sim is a **physical fact the server can corroborate**: gate crossings, server position checks, the Scanner's dwell-and-identify, a completed delivery at a verified location, a police state the server set or read, a corroborated event involving a named NPC's body. A result the sim computed is `simulated`. Client-side natives may detect things, but a client claim alone is `reported`, never `physical`.
3. **Persistent identity lives in the sim, not the entity.** A named NPC is a stable person ID with a role, a schedule, an agenda, memories and a **physical experience**. The engine body is **materialised** when a player is near and the schedule puts that person there, then dematerialised. Engine entities are cheap and disposable; people are not, and what corroborably happens to their body becomes part of their life.
4. **Narrative has no direct authority over physical systems.** Only established physical and mechanical systems change physical state. Rico being angry doesn't cost you 8% grip; Rico sabotaging your tyres through an actually implemented mechanic someday would, because that is a physical state change with provenance.

These rules also explain why a solo player can feel at home. The city's heartbeat comes from simulations that run whether or not anyone else is online. Night City already supplies the texture (crowds, traffic, rain, neon, police, vendors) that a from-scratch world would take years to build. The sim gives that texture **reasons**.

## The five layers

```text
 L4  EXPRESSION     physical NPC + native/text dialogue · Messages/phone · WIRE/news · map pins · Scanner · F6
         ▲  renders projections only; never grants money, results or memory
 L3  FACTS          shared world fact tape  ·  per-player adventure tape  ·  per-player NPC belief projection
         ▲  idempotent, versioned events with provenance (observed | simulated | reported)
 L2  SIM STACK      clock/ledger (ForkUniverse) · Paddock motorsport (FTB1) · minds (Oracle) ·
                    trajectory & access (Neikos) · places & scenes (FTB2)          — pure ncm/core, deterministic
         ▲  corroborated observations only                     ▼  commands to materialise / act
 L1  NIGHT CITY     CDPR world + engine, reached through three tiers:
                    (a) OPEN//77 server API  (b) NCM's own redscript / RED4ext required mods  (c) vanilla systems they touch
 L0  PLATFORM       OPEN//77 server authority, buckets, requiredMods delivery, the NCM gate and MASTER_TEST
```

The sims (L2) are pure `ncm/core` modules: deterministic, with no clock, RNG or I/O, and tested under Lua 5.4 and LuaJIT, like every other core module. Server resources own scheduling, persistence and the calls down into L1. Anything a client sees is a projection built by an allow-listed payload builder that carries no hidden numbers (the Paddock plan's `assertNoHidden`).

## Layer 1: what CDPR gave us, and how we reach it

Night City is not a backdrop that NCM paints over. It is an engine full of systems the PvE layer can **direct**: a navigable city of named districts, crowds with their own routines, traffic, NPCs with appearances, voicesets and workspots, vehicle AI, police response, weather and time of day, vendors, and native phone, journal, dialogue-choice and map UI.

### Three capability tiers

| Tier | What it is | Authority | Examples already in the tree |
|---|---|---|---|
| **(a) OPEN//77 server API** | Networked natives the server calls | Server-owned, visible to every client in the bucket | `npcs.create`/`tasks`/`ai`/`damage`; `vehicles.create`/`ai.attachDriver`/`driveTo`/`joinTraffic`/`stop`; `environment.setWeather`/`getState`; notifications, chat, map pins (`NcmMapPins`) |
| **(b) NCM's own required mods** | Redscript and RED4ext packages delivered through `requiredMods` and the launcher | Client-local execution; server-commanded where it matters | **Carrier** (RED4ext: vehicle hook, physics probe, tweak effects, loopback bridge); **Rig Bridge** (RED4ext: DirectInput, FFB); **ncm-vision / Scanner** (redscript: vanilla scanner render, reticle, natives); **NCM Radial** (redscript: native HUD quick menu); the Paddock plan's **Pace DLL** spike (native `AIVehicleDriveToPointAutonomousCommand`) |
| **(c) Vanilla systems reachable from (b)** | Anything in the game's RTTI that a redscript wrap or a RED4ext hook can drive | Client-local unless a tier-(a) channel carries it | Single-player NCM already wrapped `MessengerDialogViewController`/`MessangerItemRenderer` (native phone SMS), journal and quest nav (`MTEJournalHandler`, `MTEQuestNav`, `MTEQuestSpike`), six mappin controllers, and a native HUD |

**The design must not assume OPEN//77 is the ceiling.** Where the API stops, NCM can write a native mod, as it already did for input, FFB, the Scanner render and the radial. The constraints are about **authority**, not reach:

- A client-side native acts on **that client's** world. Shared PvE state must be **decided by the server** (rule 1), **performed** per client by the mod, and **corroborated** back (rule 2). AGENTS.md's warning still stands: CET spawning, mutable single-player globals, TweakDB tuning and JSON saves are not network-safe by default.
- **New features ship as new mods** and never as additions to Carrier or Rig Bridge. Use the lightest carrier first (redscript-only before RED4ext). They deploy through `requiredMods` and the launcher projection, not checkpoint scripts.
- **Compiling is not loading.** A redscript `native func` inside a `module` compiles but blocks game start under RED4ext (`KB-182`). Every native package needs a hand launch before it is ever a join requirement (`IDEA-478`).
- Patch days are the failure mode that matters. A native PvE package must degrade to a tier-(a) or WebUI fallback rather than take the game down (Carrier's rule).

### What Night City can give each PvE need

| PvE need | CDPR system | Reach today | Status (L69: nothing is done without a live PASS) |
|---|---|---|---|
| Places with meaning | Districts, streets, landmarks, vendors, Autofixers, fuel pumps | Coordinates in core; F6 and map projections | Autofixers (L206) and fuel (L204) built; `§CF9` probe sprites PASS; fuel/landmark pins await `§CF7`/`§AD7` |
| A living street | Vanilla crowd and traffic | Per-client and a binary switch in 2.31; NCM server-owned ambient layer (L177, `ambient.lua`) | `§BL` **NOT RUN** |
| Named bodies | NPC records, appearances, equipment, workspots, idle animations | (a) `npcs.create`, `tasks`, `ai`; `setAppearance`/`setEquipment`/`speak` documented (IDEA-605) | `create` used; appearance, voiceset barks and workspots unproven |
| Bodies that drive | Vehicle AI, traffic lanes, drive-to-point | (a) `vehicles.ai.*` (chauffeur `pickup.lua`, ambient); (b) Pace DLL native command | Chauffeur built; racing-grade AI parked (L165) except as Paddock **projection** |
| Consequence and heat | NCPD response, wanted levels | (a) server wanted policy (`ncm.wanted` probe, `§BV`); Hellfire direction in L203 | `§BV` deployed, **awaiting PASS** |
| Weather and hour | Environment weather, time of day | (a) `environment.*`; L208/L209 handling | Built, live-gated |
| Perception | Scanner, `aimedEntity` | (b) ncm-vision; L197 discovery | Built, live-gated |
| Conversation in place | Vanilla interaction/dialogue-choice hub | **Candidate:** (b) a redscript/RED4ext dialogue package driving the native choice UI; fallback a WebUI surface (CEF budget-bound, IDEA-605) | **UNKNOWN**: the first physical-NPC probe |
| The phone | Vanilla messenger, SMS, holocall UI | Online Messages is WebUI today (L190); SP proved native messenger wraps | **DEFERRED (L221).** SP's phone was costly to build through WolvenKit, caused whole-game lag during development, and its richest thread (Foreman) still lags in the final build (`KB-212`). Needs a deeper audit before any Online attempt |
| Journal and objectives | Vanilla journal, quest nav, custom waypoint | SP `MTEJournalHandler`/`MTEQuestNav`; `NCM_QUEST_SPIKE.md` | SP-only; Online unexplored |

Two rows change the design's feasibility. Native dialogue is the approved first probe; the native phone is deferred (L221):

- **Native dialogue choices.** If a required redscript/RED4ext package can drive CDPR's own interaction/choice UI from server-supplied choices, the Fallout 4-like conversation (L219) uses the game's own look. It also stops competing for the CEF page budget that blocks IDEA-605.
- **Native phone (deferred).** Surfacing Online threads in the vanilla messenger, as SP's MT_Ecosystem did, would make contacts feel like Night City's own phone. The owner's experience is that the SP phone was brutal to build and prone to whole-game lag, with Foreman's thread still lagging every time (`KB-212`). The audit should first find why a rich thread lags (thread length, per-message controller cost, journal size) before Online considers it. Online Messages is adequate for now.

### Night City runs on real time

**Owner direction (L221):** the in-game clock follows real time in US Eastern. 11:00 PM Eastern is 11:00 PM in Night City, and a day lasts 24 hours.

**It is reachable with the platform as shipped.** `open77_weather` is the server-authoritative clock. It exposes `environment.setTime(h, m, s[, bucket])`, `setTimeFrozen` and `setTimeRate(rate[, bucket])`, with a range of 0–120 game seconds per real second. Its shipped default is **8×** (a 3-hour day) starting at **noon on every restart**, and the clock does not survive the resource going down. Real time is **rate 1.0 plus `setTime` from the real Eastern clock**. A small NCM clock service would do this at boot and re-anchor on a slow reconcile, beside `NcmWeather`'s existing 10-second loop, so a restart, drift or an admin `/weather.time.set` falls back to real time. No NCM code was found that assumes the 8× day. `ncm_world` declares the `world.environment` permission but uses it read-only today, so writing the clock is a new, deliberate use.

**What it gives the sim.** NPC schedules key to the same clock every player sees: day and night shifts at garages, the night street scene, late-night couriers, dawn test sessions. "Meet me at 2 AM" means 2 AM for the player too.

**Ruled (L222).** Daylight saving follows `America/New_York`. A player who always plays at 9 PM Eastern will only ever see night, and a player abroad lives at a fixed offset: that is the cost of doing business, and it is too good for roleplay to pass up. **Events do not pin their own time**; a midnight race at noon makes no sense, so every race runs at the real hour. L209's time-of-day handling is now exercised in real-time slices rather than a full cycle every three hours.

### Per-system control, decided one system at a time

**Owner direction (L221):** there is no blanket answer to "how far may the sim direct Night City"; each system gets its own ruling. **L222 rules every row.** The owner judged several proposals too conservative for what is now a life simulation inside Night City.

| # | Vanilla system | Ruling (L222) | What it means |
|---|---|---|---|
| 1 | Clock | **Real time, `America/New_York`** (L221, L222) | Rate 1.0, anchored to Eastern with DST; races run at the real hour |
| 2 | Weather | **ACCEPT, with expansion** | Weather is world state, not a storytelling knob. `NcmWeather`'s plan stays authoritative; PvE, the Paddock, NPCs and scenes **react** to it and never manufacture it. Billie does not make it rain because a race needs drama: the forecast says rain, so everybody deals with rain. Later, NPC behaviour reacts too: meetings move indoors, some street scenes thin out, drivers prepare differently, activities gain or lose appeal |
| 3 | NCPD / wanted | **CHANGE: broadened** | The sim may cause legitimate NCPD interactions for **players and simulated actors** when their physical or simulated actions warrant it, where technically feasible. If Rico gets into trouble independently of you, that can happen; if you are standing beside him, Tuesday got interesting. **Never manufacture a wanted level merely for drama** |
| 4 | Ambient crowds and traffic | **ACCEPT** | Add the people a scene needs; don't sterilise Night City every time Rico wants a conversation. Race corridors stay a separate safety and performance concern (L177) |
| 5 | Vanilla per-client traffic | **CHANGE: kept available as a tool** | Normally untouched, and never switched by a social mood. An authoritative activity or scene may control it where technically necessary, with **explicit scope and restoration**. Traffic itself is gameplay: it affects driving, AI racing, police and the lived world |
| 6 | Named NPC bodies | **ACCEPT AND EXPAND** | Named NPCs are persistent simulated people, physically materialised when appropriate: presence, appearance, equipment, idle, bark, location, schedule, activity **and physical experience**. Corroborated physical events involving them may become simulation facts |
| 7 | AI vehicles | **CHANGE substantially** | AI vehicles may represent persistent actors and activities; simulated people can drive places. When an activity runs explicitly in **physical-authoritative mode** and NCM can corroborate the outcome, physical facts write back. Otherwise they are projections and cannot manufacture truth |
| 8 | Map pins | **ACCEPT** | Private knowledge makes a private pin; a public place or event makes a shared pin. The **absence** of a pin matters too: discovery stays meaningful |
| 9 | Autofixer and Market supply | **ACCEPT, deepen later** | Supply changes need a **named cause**: team demand, supply problems, deliveries, Engineering production, regional circumstances, a fulfilled contract, a resolved shortage. Markets become economic participants. **Simulated NPCs buy parts** and move supply and demand through the R&D system and supply chain NCM has already modelled |
| 10 | Vehicle handling | **ACCEPT the boundary, reject the wording** | PvE narrative and social state get **zero** direct handling authority. Only established physical and mechanical systems (parts, tyre state, weather and surface, fuel load) modify handling. A future sabotage mechanic would qualify only as an implemented physical state change with provenance |
| 11 | Chrome hacks and cyberware | **CHANGE: genuine sim verbs** | PvE may use supported hacks and cyberware as simulation verbs where target, capability and consequence are authoritative: a player hacks an NPC or vehicle, an NPC hacks something, a job enables an unusual hack, a relationship unlocks access, the Scanner reveals hackability, consequences propagate. **No arbitrary scripted effects masquerading as hacks** |
| 12 | Time scale / slow motion | **ACCEPT** | Presentation only, no sim authority. Nothing gained is worth turning time authority into soup in multiplayer |
| 13 | In-world screens, radio and billboards | **ACCEPT AND EXPAND** | Simulation-to-world projection surfaces, not decoration: Paddock results, race coverage, market events, public incidents, team news, advertisements, public reputation events, eventually live race feeds on TVs. Everything is **sourced**; the media may frame, interpret, or be deliberately modelled as unreliable, but a source always sits underneath the claim |
| 14 | Native dialogue UI | **Approved as probe** (L221) | Renders server-chosen choices only |

## Layer 2: the sim stack — one job per engine

The owner's earlier engines are **complementary**, and the stack works only if each owns one job and they talk **only through the fact tape** (Layer 3). No engine reads another's internals.

**Reuse rule (owner, L221): borrow what is proven, test it first, and make it work in Cyberpunk, not in Python.** There are tens of thousands of lines and many working systems to borrow from, so nothing is designed from a blank page. Every mechanism is **reimplemented as a pure `ncm/core` Lua module**, so it runs under the server's Lua/LuaJIT runtime, the NCM gate and OPEN//77's instruction quota (`KB-211` is a reminder that the quota is real). The Python original then earns its keep as a **test oracle**: feed the same seed and inputs to both and compare the Lua port's outputs before the port is trusted. No Python process runs beside the game. Whether any source text may be copied verbatim is a separate rights question (GPL-3.0 Radio-OS; AGPL-3.0/Apache-2.0 oracle-radio); reimplementation lets work start without that answer. Detailed per-engine strengths and weaknesses are in the [appendix](#appendix-source-review-of-the-five-python-engines).

| Engine (source) | Job in NCM | It owns | It must not |
|---|---|---|---|
| **ForkUniverse** — the clock and the ledger | Time, determinism and replay for the whole stack | Event-keyed seeded RNG, tick/epoch stepping on one code path, obligations with due dates, open threads, truth deltas, compact catch-up | Generate social motion because a player was offline; settle an unresolved thread by dice and call it an outcome |
| **FTB1 (From the Backmarker)** via THE PADDOCK — the heartbeat | The NPC motorsport world | Orgs, people, hidden attributes, contracts, finance, seasons, lap-by-lap sim, calibration from human medians, Billie's pricing | Share a grid, standing or result with humans (parallel circuit); leak hidden numbers |
| **Oracle Kingdom/Court** — the minds | What each NPC believes about each player, and what factions remember | Bounded private memory with half-lives, trust/resentment/admiration, agendas, faction memory, cause-linked offers | Grant decree-like player power; let a memory exist without a source event and an information path |
| **Neikos** — trajectory and gates | Who the driver is becoming, and which doors that opens | Compact evidence-derived driver trajectory; small shared scene-pressure model; explicit gate rules from state to access | Expose a secret archetype meter; diagnose personality from one drive; echo a memory with no retained fact |
| **FTB2** — places and scenes | Where people are and what can happen there | Place/presence projection, participant checks, authored scene seeds, overhear (no state change) versus focused interaction (may change state) | Stand a role stand-in in for a real person ID; score conversation as won/lost combat |

### How one tick flows

```text
clock (ForkUniverse)      advance to now; due obligations; event-keyed RNG streams
   → Paddock (FTB1)       scheduled rounds simulate; contracts, finance, silly season
   → corroborated L1 facts  human results, deliveries, scans, police outcomes, arrivals
   → fact tape            append, idempotent by source key, with provenance and scope
   → pressure (Neikos)    scene pressure and gate recompute from new facts
   → minds (Oracle)       only NPCs with a knowledge path update beliefs about a player
   → scenes (FTB2)        select eligible authored situations; plan presences for the next window
   → expression (L4)      materialise bodies near players; queue Messages under the §20 budget
```

The order matters. Minds update **after** facts, so nobody reacts to something that did not happen. Scenes select **after** minds, so a situation is chosen because someone has a reason. Expression is last and read-only.

### Existing evidence for the stack

- `prototypes/oracle_racing/` (L216) already recasts Oracle into racing language. It shows replay, idempotency, provenance, shared-cast/private-history divergence and event → offer → choice → outcome paths in a 100-seed sweep. Those metrics show **variance, not yet good pacing or writing**.
- The Paddock plan specifies the FTB1 heartbeat end to end (core modules, migrations 043–050, `ncm_paddock`, F6 PADDOCK, sightings and the Pace spike). It is not yet reconciled into the decision record (its L210–L214 are reserved by L215).
- ForkUniverse, Neikos and FTB2 are reviewed statically (L217, L218). None of their suites was rerun here.

## Layer 3: facts, tapes and projections

The shared tape answers **what happened in the city** and **how it was known**. A player's adventure tape answers **what happened to this player**. A private social projection answers **what this NPC believes about this player**. A public scene projection answers **what changed for everyone**. An adventure event becomes a shared-world effect only through an explicit validated transaction. A contact can be wrong, withholding or biased; those are authored belief states, never silent edits to either tape.

```text
Shared Paddock sim + public human results + public place/organization changes
                              |
                    shared world fact tape
                              |
                   public presence / access / news
                              |
         +--------------------+--------------------+
         |                                         |
player A adventure tape                    player B adventure tape
jobs, choices, private outcomes            different jobs and choices
         |                                         |
NPC memory, leads, obligations             different NPC memory and leads
         |                                         |
bodies + dialogue + Messages               bodies + dialogue + Messages
         \_____________ explicit public effects ___________/
                    (validated shared transactions)
```

| State | Key | Owner and update source | What players may see |
|---|---|---|---|
| Paddock season and NPC race | server + season + race/person/org ID | Future Paddock host; scheduled authoritative simulation | Calendar, standings, result, provenance, headlines, sightings with honest labels |
| Public place and alliance | server + place/group/person ID | Shared scene reducer; Paddock fact or validated public transaction | Who is present, who holds access, what publicly changed and when |
| Person presence | server + person ID + window | Scene planner from schedule, agenda and events | Where a named NPC can be met; their body when materialised |
| Player adventure | server + player ID + event ID | Job/route/choice adapters; accepted player actions and observed results | Their own history, obligations, leads, chosen paths and outcomes |
| NPC's view of player | server + player ID + person ID | Social reducer; only facts the NPC witnessed or learned through a stored source | Dialogue tone, authored options and earned descriptions, never raw hidden scores |
| Conversation instance | player + person + scene ID | Conversation service; Messages or physical meeting reads one state | Lines, four primary intents, deeper branches, selected choice and follow-up |
| Public effect of a private act | unique transaction/source ID | Relevant world owner validates preconditions and writes one public event | News/access/scene change with cause, without leaking private dialogue |

An NPC's knowledge update needs a path: direct witness, participant, public result, named intermediary, or publication. For example, a mechanic at the finish can react at once; Rico learns later from that mechanic or a public wire; a private promise stays unknown to a rival unless exposed. A player-facing "why is this option here?" can use a plain clue such as "you brought the scan from Kabuki", while rules and raw scores stay server-side.

Suggested event envelope for the design, *not* a committed schema:

```text
id, schema_version, server_id, occurred_at, kind, actor_id, subject_ids,
location_id, source_system, source_ref, provenance(physical|simulated|reported),
scope(shared|player), visibility(public|participants|private), facts,
cause_refs, ruleset_version
```

Require idempotent ingest by `(server_id, source_system, source_ref, kind)` or another stable source key. Persist the ruleset version that interpreted each fact. If a social rule changes, decide explicitly whether old events replay under their original rules or a migration applies. Keep physical observation, authoritative simulation, player report and NPC rumor distinct. A headline may be about a report, but it must say so.

### Shared substrate, individual adventures

The Paddock supplies the continuously shared substrate: NPC organizations, people, calendars, results, contracts, rivalries and public news. The city layer adds public places, presences, access rules and alliances. Each player's adventure selects incidents from that substrate and accumulates its own leads, jobs, choices, obligations, memories and conclusions. Two players can meet the same team owner at different stages of their own story. One gets a sponsor introduction while the other is refused because of a broken promise, and neither private arc waits for the other.

Use shared world transactions for **publicly legible, bounded changes**: a route record changes hands, a venue opens, a garage offers a special supply window, an NPC org hires or fires, a district contact withdraws support. Store the causing event, scope, expiry/rollover rule and replacement rule. Shared outcomes need limits so a single player cannot permanently exhaust another player's PvE: prefer contestable records, rotating windows, multiple routes into an opportunity, and visible re-entry after a loss. Alliances and access carry a named holder, cause, start and review/expiry condition.

When two players meet the same named NPC, they address the **same public person**: identity, role, organization, location and public situation agree. Each gets choices projected from their own evidence, relationship and obligations. A choice that would settle shared state re-checks it at commit time; if another player settled it first, the NPC acknowledges the change and offers a continuation, with no duplicate payout. A private scene cannot teleport or erase the person for everyone else.

Scale the cast by relevance. A small recurring cast has deep memory and authored scenes. Named peripheral people have stable IDs, agendas and summaries. **Vanilla crowds supply atmosphere without pretending every passerby has a biography**: this is where CDPR's crowd system does work no sim should duplicate. Preserve durable promises, betrayals, titles and turning points; compact lower-salience detail with source links.

## Layer 4: expression — bodies, dialogue, Messages, media

### Surfaces and pacing

- NPC Paddock races follow their own schedule; player adventures react to relevant shared facts and their own choices. On login, catch-up compacts missed **shared facts** into a digest tailored to what that player knows. It does not simulate a stream of private emotions.
- Deadlines are authored obligations with a clock type (UTC, session, race count) and an explicit consequence. Ordinary silence or logging off carries no hidden penalty.
- Messages carry an actionable invitation, a direct consequence or requested context. Place encounters carry presence, overheard texture and deeper exchanges. Paddock WIRE and other media publish public events. Scanner and map reveal evidence or access.
- Respect `graph.conversation`'s §20 budget, the solicited-introduction exception, one-time pushes and re-entry routes. Dex is neutral guidance; specialists own their domains (L176). Contacts stay unspeakable until authored (L183). A scene needs a trigger, actor, location, visibility, choice, consequence and re-entry, not merely a large prompt.
- Reactive text may use deterministic templates or a bounded performer. **The server selects and validates the choice and state delta before text is rendered.** Generated text never grants money, invents a race result, opens a Market or changes an NPC's canonical memory.

### Bodies

A named NPC's body is materialised from sim state when the presence plan puts that person at a place and a player is near enough to meet them:

- **Server tier (a):** `npcs.create` at the planned location in the right bucket, with appearance and equipment from the person's record, a workspot or idle task, damage policy and AI appropriate to a non-combat meeting, and a voiceset bark when greeted (`npcs.speak`, if proven).
- **Client tier (b)**, when the server tier cannot do something: a required redscript package can add the native interaction prompt, look-at and dialogue choice hub. The server still owns who is there and what the choices are.
- **Honest fallback:** if streaming or platform capability prevents a real meeting, use a venue/contact fallback and defer the physical beat. Never record a meeting that did not occur.

Paddock sightings are the same pattern for cars. Pack positions come from the sim's splits, materialised upstream of a player through `vehicles.ai.followRoute` or the Pace DLL. A sighting in projection mode never writes back. An activity explicitly running in physical-authoritative mode, whose outcome NCM corroborates, does (L222), with provenance `physical`.

### Physical dialogue: long-term interaction contract

A named NPC exists in the shared world at a known place, with a stable person ID, a public role and a current reason to be there. Approaching them opens a text conversation: an NPC line, **four primary intents**, a reply, and deeper choices when the subject warrants it. The interface may frame the two characters and use ordinary idle or gesture animation. **Voice acting and mocap are not part of the design**; writing and choice structure carry the scene. The player must understand a choice's intent and material stakes before selecting it. The preferred rendering is CDPR's own choice UI through an NCM native package (Layer 1 probe), with a WebUI fallback.

The conversation is a projection from one story state, whether the player arrives through Messages or in person. A physical-only choice also requires actual co-presence. Messages can continue a relationship, arrange a meeting or follow up on it, and neither surface owns a separate version of the NPC's memory. At each turn the server checks current facts, the player's leads and evidence, the NPC's knowledge and their relationship. It then offers authored choices, records the selected choice and its consequence, and renders the reply.

Treat the four primary intents as a readable doorway into topics (for example ask, offer help, challenge, leave), not four canned tone buttons. Each contact and situation authors the actual wording and deeper branches. Evidence and relationship history should **often unlock distinct choices**, with a grounded reason visible: a scan they made, a delivery they completed, a promise this NPC remembers, an organization they manage. A locked line may name the missing *fictional condition*; it must not expose thresholds or a progress meter.

Illustrative physical conversation, tied to one shared Paddock fact:

| What exists | Driver A | Manager B |
|---|---|---|
| Shared fact | An NPC team lost its parts supplier before a wet round; its mechanic is at a Kabuki workshop | Sees the same team and workshop |
| Four primary intents | Ask what happened / Offer a run / Press for the supplier's name / Leave | Ask what happened / Propose a supply deal / Ask about the next Cup / Leave |
| Deeper earned option | "Show the scan of the damaged component" appears because A actually scanned it; the mechanic explains the failure and offers a courier route | "Put our org's spare batch on the table" appears because B manages an org with a qualifying inventory; the mechanic proposes terms |
| Private aftermath | Mechanic remembers A kept or broke the delivery promise; Rico may hear a sourced report | Mechanic remembers B's negotiating stance; the org's treasury and contract reflect accepted terms |
| Possible shared aftermath | A verified delivery can settle the supplier shortage for the team's next round | B's valid contract can also settle it; the shortage resolves once, with the accepted cause recorded |

## How it plays

The unit of PvE is an **incident with an aftermath**, not a quest step or a random message. A player sees a reason to go somewhere, then drives and acts. The server records what actually happened, relevant people interpret it, and one or more doors open or close **for that player**. Occasionally the incident is public enough to change the shared world. The player can come back later and ask why. Meanwhile the world keeps moving through the Paddock's NPC circuit, other players' public results, scheduled events and authored world changes.

Example, illustrative rather than promised content:

1. At a Kabuki garage, a mechanic (a materialised named NPC) mentions that a courier has missed two deliveries. This is a **Lead** with a source, not a mission marker. Rico can mention the same person through Messages because the lead exists.
2. The player meets the courier at a real location and chooses whether to take a timed, fuel-limited run with a concrete stake and deadline. The choice records an obligation, and the route, vehicle and target are fixed before starting.
3. A clean finish is an observed fact and so is a missed deadline. Either can affect payment, a garage's willingness to sell a specialty part, and one contact's trust. A witness may report the run, with the source stored, so a distant NPC does not simply know everything. If the run drew NCPD, the police outcome the server saw is a fact too.
4. A local Kabuki route crew answers a new time on a nearby route. The **record is a time-trial target or a labelled simulation**, not an invented physical race against unseen AI.
5. News mentions a contested route only if a public event exists to cite. Another player may see the headline and find their *own* way into the garage's story, without inheriting the first player's friendship, outcome or private choices.

### Three connected loops

| Loop | Player act | Durable consequence | Visible return |
|---|---|---|---|
| **Drive** | Race, practice, deliver, escape, claim a local time | Verified result or outcome with provenance, conditions and source event | Money/Parts where authored, a record, a new job, rival response, press |
| **Relate** | Ask, accept, decline, help, betray, negotiate at a place or in Messages | Private NPC memory, obligation, promise, lead and choice event | Changed line, referral, refusal, opportunity or visit |
| **World** | Witness or influence an NPC circuit, local scene, venue or organization | Shared public event or bounded scene state when the action crosses a public threshold | Different people present, access, headlines, scheduled activity |

The loops must cross. A job should create race-relevant access; a race should give someone a reason to call; a Paddock result should affect a real person the player can meet. A social stat increment with no later playable consequence does not fulfil this vision.

### The world acts when the player does nothing

The Paddock gives the shared world a mechanical heartbeat. The social layer adds **NPC-to-NPC consequences**: an owner loses patience with a principal, a driver considers another org, a garage changes whom it supplies, a sponsor attaches conditions, a reporter follows a sourced dispute. These are shared facts with causes and limits, and they create new situations for players. The player can intervene, ignore them, arrive after the change, or hear different versions from interested people. Night City's crowds, traffic and weather keep the street alive in between, which is how a solo session feels populated without filling the inbox with artificial chatter.

The social sim selects from **authored situation families** when real inputs align: a result streak plus contract pressure; a shortage plus an upcoming Cup; a broken promise plus a witness; a district record plus a rival crew's claim. NPC agendas and relationships choose who acts and when. Stable seeded variation chooses among plausible options, but the source facts, constraints and resulting public event must stay recoverable. The world needs room for surprise; it does not need random drama on every tick.

### Two player roles in the same world

A driver earns standing through observed drives, records, jobs and relationships. A manager founds or accepts an NPC-circuit organization under the Paddock plan and shapes roster, development, contracts and sponsors while NPC results remain simulated. Both see the same public Paddock and city changes and can form personal ties. The Paddock plan's One-Team Rule, separate NPC circuit and no per-race orders are the starting constraints for management; its mechanics still need reconciliation into the living authority documents. The story architecture must not assume the player joined a team or personally drove every race.

## Content grammar: depth without an opaque sim

Start from **conflicting motivations**, not more numerical axes. A garage owner wants reliable deliveries; a street crew wants its route to stay theirs; a Paddock team needs parts; Rico values information; a fan wants spectacle; a cautious mechanic dislikes risky wins. One observed action can satisfy one desire and injure another, which gives variance the player can understand. Seed personality sets how strongly each person values evidence; exposure decides *whether they know it*. Save the cause chain so the game can answer why someone changed their mind.

Give the city durable tensions that touch racing from different angles: underground prestige versus organized sanction, speed versus reliability, spectacle versus discretion, loyalty versus opportunity, scarce parts versus open competition. Put them in **specific Night City places**, with mostly original crews, shops and institutions. Let the place do work: a Kabuki alley at 3 a.m. in rain, a Badlands fuel stop, a Japantown garage under a holo sign. Do not use a famous gang or corporation merely as a label on an otherwise generic time trial.

| Family | Shared sim source | Personal adventure | Social crossing | Night City performs |
|---|---|---|---|---|
| **Team politics** | Paddock season, results, contracts, owner/driver agendas | Help a person, negotiate as manager, or compete for attention as a driver | A hiring or supplier change becomes public; trust stays personal | Named NPCs at team garages; Paddock sightings on the street |
| **Local routes** | Route records, weather, venue access, crew claims | Chase a time, broker access, or decide whom to credit | A new public target and changed standing open approaches for others | Crew members loitering at the route; weather and hour from the environment |
| **Jobs and supply** | Markets, Parts, fuel, calendar demand, named couriers | Deliver, recover, repair, source or refuse, with stated stakes | Supply and alliances shift; payment and blame follow the actor | Real destinations, fuel burn, NCPD heat, Autofixer terminals |
| **Evidence and mystery** | Scanner observations, ghost/practice data, sourced rumors | Follow an unresolved lead through contacts and places | A revelation changes who is present or willing to deal | The Scanner render, witnesses in the crowd (IDEA-639) |
| **Media and fandom** | Verified results, Paddock events, public statements | Correct a rumor, invite attention, withdraw, cultivate a fan | Headlines reflect sourced events; disclosures stay scoped | WIRE, phone, the Fan turning up in person |

For each situation, author at least **two perspectives and one later callback**. The existing 18-contact graph supplies roles and re-entry grammar; FTB2 supplies staging; Oracle supplies memory; Neikos supplies trajectory; ForkUniverse supplies replay and obligations; the Paddock supplies a reason for anyone to care. This is a grammar, not a mandatory sequence. The Zero mystery in quest graph Pass 1 is a candidate authored thread, not something implemented online.

## Next coder: research and architecture handoff

1. **Read authority first.** `docs/ncm-online/INDEX.md`, `NOW.md`, `DECISION_RECORD.md` L165/L171/L175/L176/L183/L215–L223, `41_QUEST_GRAPH_PASS1.md` §§0/20/Appendix A, the Paddock attachment, this document, and `prototypes/oracle_racing/README.md`. Check whether `44_THE_PADDOCK.md` or `ncm/core/paddock/` has appeared.
2. **Inventory Night City capability across all three tiers.** For each Layer 1 row, record the OPEN//77 card, any existing NCM native (Carrier, Rig Bridge, ncm-vision, Radial, SP `MT_Ecosystem` scripts) and the vanilla class a new native package would drive. Mark each proven, documented or unknown. Query the current build-pinned API cards; preview docs conflict.
0. **Work on the development server only** (L223). Online is frozen at Baseline 1 and receives nothing until the sim expansion is ready.
3. **Run the native dialogue probe** (IDEA-727, approved under L221) as its own isolated required mod, redscript-only if possible: a named NPC materialised by the server, greeted with a bark, and conversed with through the **native** choice UI fed by server choices, with a WebUI fallback. It gets `MASTER_TEST` cases and runs on the Windows dev server before Lightsail. The native phone (IDEA-728) is **deferred** until an audit explains the single-player phone's lag (`KB-212`).
4. **Build the real-time clock service** (IDEA-729): rate 1.0, anchored to Eastern, re-anchored on reconcile, with a live check that the in-game hour matches the wall clock across a restart.
5. **Define the domain map and the tape.** Public Paddock facts; shared people, presences, places, access and alliances; each player's adventure; per-player NPC belief; conversation and scene state; presentation. Name the authority and persistence owner of every object, and how a private act promotes one validated public consequence. Reconcile the Paddock plan into the decision record rather than a competing plan.
6. **Specify the tick contract** from [How one tick flows](#how-one-tick-flows): the order, what each engine reads and writes on the tape, event-keyed RNG scopes and the catch-up rule.
7. **Land the Paddock first, then the social sim** (L222). **Write contrasting lifetime paths:** a driver with jobs, records and contacts; a manager with roster, sponsor and personal ties; two players meeting the same NPC after different histories. Include refusal, loss, inactivity, return, season rollover and a public access shift.
8. **Extend `prototypes/oracle_racing` into a stack prototype.** Add a ForkUniverse-style clock/ledger, a stub Paddock feed, Neikos-style gates and FTB2-style presence plans behind the tape. Where a Python original exists, use it as the test oracle for the matching behaviour. Run long varied histories and inspect story quality, replay, idempotency, provenance, bounded memory and hidden-data projection.
9. **Design the NCM adapters and proof plan:** `ncm_league` results, `ncm_world` Machine/fuel/market/ambient/police, the future `ncm_paddock`, native presentation packages and Messages/graph. Live completion requires a `wp/MASTER_TEST.md` PASS (L69).

## Open questions

### Rulings so far

L218–L222 settle the direction. The world is a life sim in Night City, flavoured by motorsport, over a shared Paddock/city simulation, with personal adventures inside it and no "first arc". Players can be drivers, managers or both. Named physical NPCs use native text dialogue with four primary intents. The clock is real-time Eastern. Every vanilla system has its own ruling, and physical facts can write back when corroborated. Proven code is reused by reimplementing it in Lua against the Python originals. **L223 freezes Online as Baseline 1**; all sim work happens on the development server.

### Answers to the L221 questions (L222)

| # | Question | Owner answer |
|---|---|---|
| 1 | Daylight saving | Follow `America/New_York` |
| 2 | Same hour, same part of the day | Cost of doing business, too good for roleplay to pass up; night players and day players are both fine |
| 3 | Events pinning their own time | No: a midnight race at noon makes no sense |
| 4 | Per-system rows 2–13 | [Ruled individually](#per-system-control-decided-one-system-at-a-time) |
| 5 | Which engine first | **The Paddock first, then the social sim** |
| 6 | Run the Python originals as test oracles | Yes: run whatever tests are needed |
| 7 | Contacts as physical people | Yes |
| 8 | Cast size for the first arc | Question struck: there is no first arc, the world is an ongoing snow globe |
| 9 | Canon gangs and groups | May be used |
| 10 | How NPCs address the player | Could be both driver name and earned handle |
| 11 | Solo incident frequency | Not locked; test and iterate over time |
| 12 | Who writes dialogue | A mix; Night City's own dialogue will be studied for voice |

### Still open

1. How managing an NPC organization overlaps with personally doing street jobs and turf.
2. The maximum shared impact of one player's action, and what persists across a Paddock season.
3. The dev server's database for sim work: start from a fresh schema, or seed it with a copy of Online's data?
4. Rights for verbatim reuse of GPL/AGPL source, if reimplementation ever proves insufficient.

Record answers in `DECISION_RECORD.md`. Keep this file a proposal rather than silently promoting it to authority.

## Appendix: source review of the five Python engines

This is a **static source review** of ForkUniverse, Neikos and FTB2, combined with the Oracle headless findings in the companion assessment and the Paddock plan's use of FTB1. No test suite was rerun, and no handoff-doc claim is treated as fresh verification.

### Oracle Kingdom and Court — people remember and reinterpret

**Source:** `D:/dev/Radio-OS/plugins/oracle_kingdom.py` (`SeededRNG`, `CausalLedger`, interpretation and ripple systems) and `oracle_court.py` (`MemoryEntry`, `CourtAgent`, `FactionMemory`, `PresenceRequest`, `CourtEngine`). In-repo copy and racing recast: `prototypes/oracle_racing/` (L216).

**Good at:** persistent personal memory with different half-lives; trust, resentment, admiration and perceived consistency; faction memory that outlives an individual; agents whose agendas interpret the same decree differently; a causal ledger behind interpretation. It is the closest source for an NPC remembering *who the driver was to them*. Presence requests suggest contextual offers.

**Weak for NCM:** the Oracle player has decree-like power, while an NCM player is one driver among many. Kingdom health, faith and legitimacy are not racing language. Court memories decay but never prune. The earlier seed sweep produced a narrow kingdom-health band and one dominant archetype. Request counts do not prove story quality. Its threading, UI and persistence should not be copied.

**Carry forward:** a small private NPC memory and agenda reducer with source event IDs, bounded retention, explicit knowledge/exposure and authored offer conditions. Carry faction memory only after deciding whether faction state is public truth or an opinion of one player.

### ForkUniverse — the world can answer "why" and recover after absence

**Source:** `D:/dev/Radio-OS/forkuniverse/engine/world_core.py` (`SeededRNG.stream`, `UniverseState.advance_tick`, `simulate_epoch`, `compute_absence`, obligations, threads, predictions, `TruthDelta`), `compiler/models.py`, `runtime/query.py`, and `docs/FORKUNIVERSE_RUNTIME_MODEL.md` (a query-driven world calculator).

**Good at:** separating authoritative state and factual ledger from the layer that summarises it; RNG namespaced by seed and tick; single-step and epoch computation on one path; obligations with due dates; first-class unresolved threads; memory tiers; predictions that are settled and scored. A world can reconstruct what happened while a player was away without a heavy process per player.

**Weak for NCM:** ambient pressure spawns abstract threads with generic titles. `compute_absence` converts wall-clock time to owed ticks, which would generate social motion just because a player was offline. `resolve_predictions` can score an unresolved thread with an RNG draw, which NCM must never present as observed. Prediction feedback moves legitimacy mechanically without authored meaning.

**Carry forward:** event-scoped randomness, versioned input envelopes, factual ledger and downstream projections, compact catch-up, explicit obligations and answerable cause chains. NPC predictions are fallible beliefs settled against verified facts, and a prediction roll never creates the result it predicts.

### Neikos — actions shape a trajectory and alter access

**Source:** `D:/dev/Radio-OS/plugins/neikos.py`, especially `IslandLedger`, `compute_gate_thresholds`, `PlayerTrajectory`, `BehavioralProfileSignature`, `generate_echo_events` and `NKController`.

**Good at:** a seeded geography with factions and gates; a macro ledger whose axes interact; a separate player trajectory built from repeated actions; command-driven progression without wall-clock drift; echoes based on prior history. Its gate calculation is a clear causal route from scene condition to access.

**Weak for NCM:** much of the domain is creature collection. Many hidden axes, thresholds and bands make classification opaque. Faction diffusion and passive ticks can produce weak or seed-invariant change. Echo templates can claim memories without a matching fact, which would be false in a shared world. The controller is a monolith.

**Carry forward:** a **compact driver trajectory** from meaningful evidence (routes claimed, jobs kept, machine choices, sporting conduct, risk) and a small shared scene-pressure model that changes access through explicit rules. An echo points to a real event ID or retained summary.

### FTB1 (From the Backmarker) — the motorsport heartbeat

**Source:** Radio-OS FTB1, as used by the Paddock plan: `_simulate_race_lap_by_lap`, `apply_tendency_weights`, `apply_personality_inflection`, `ftb_names.py`, `ftb_sponsors.py`, and the SP `championships.lua` points table.

**Good at:** a deep management sim of orgs, drivers, principals, contracts, finance and development, with a race model that produces plausible results from hidden attributes and conditions.

**Weak for NCM (per the Paddock plan's findings):** a per-tick growth bug (fixed there as once per day); name lists that include real drivers (denylist required); nationality not weighted to Night City; attributes that must never reach a client.

**Carry forward:** exactly what the Paddock plan specifies. It is the heartbeat the other engines read from, and the reason a solo player's city has a season in it.

### FTB2 — a motorsport world you inhabit through places

**Source:** `D:/dev/oracle-radio/docs/FTB2_CONTRACT.md`, `FTB2_UNIFICATION_HANDOFF.md`, and `ftb2/`: `ftb1_bridge.py`, `world_view.py`, `world_projection.py`, `lens_surfaces.py`, `nako/conversation.py`, `nako/canisters.py`, `nako/canister_llm.py`, `house_runtime.py`.

**Good at:** the *experiential grammar* the other sims lack. A person has a reason to be at a place. Background conversation can be overheard and optionally entered, and overhearing does not secretly change trust. Engineering, paddock, media and events feel different because they expose different facts and people. Role-specific scene seed libraries beat one universal NPC template. The active-save `WorldView` keeps one motorsport authority behind many surfaces. Its group-scene adapter is a deterministic performer over authored seed material despite the `LLM` name.

**Limits visible in code:** `tick_engine.py` still makes a two-driver placeholder race every tick, a generic rumor, office gain and a random sponsor conflict. `event_tape.py` appends without duplicate rejection. `oracle/social_graph.py` is four hard-coded edges. Some lenses expose raw pace, pressure and morale, which NCM's hidden-attribute rules forbid. A walk-up may display a real roster member while routing through a fixed role character, so identity and memory would diverge if ported literally. The contract and lens map disagree on the fifth node. `nako/conversation.py` scores exchanges as won/lost/stalemate with universal moves, which flattens a character's dilemma.

**Carry forward:** a Night City place/presence/scene projection, authored overhear-to-interaction scenes, distinct domains and speakers, and a performer downstream of fixed choices and state, using stable NCM person IDs and only earned tags. FTB2's RibbonOS shell, ESP32 knots, 100-city atlas, audio mixer and clip simulator are not NCM dependencies. **Night City replaces FTB2's invented spatial shell**: the places are real, and the engine provides the bodies.

### Port map and boundaries

| Source mechanism | NCM destination | Treatment |
|---|---|---|
| ForkUniverse tick-keyed RNG, obligations and deltas | Stack clock, fact tape and catch-up | **Adapt pure patterns**; event-driven scheduling and factual settlement |
| ForkUniverse generic pressure threads | Authored situation selector | **Inspiration only**; no generic "public reckoning" pushes |
| FTB1 race and management sim | Paddock heartbeat | **Adapt per the Paddock plan**; parallel circuit, hidden attributes |
| Oracle court memory and agenda | Player × NPC belief projection | **Adapt rules** with bounded memories and source IDs; author meaning per contact |
| Oracle causal edges | Event lineage | **Adapt shape**; source, effect, scope and provenance |
| Neikos trajectory and gates | Evidence-backed driver tendencies and access | **Adapt** with few axes and visible causal explanation |
| Neikos cross-run echoes | Returning-player callbacks | **Adapt** only with retained source history |
| FTB2 WorldView, presence and scene canisters | Presence planner + encounter selector over real Night City places | **Adapt design** with NCM stable IDs and locations |
| FTB2 conversation moves | Authored choices and reactive lines | **Adapt selectively**; no universal win/loss meter |
| FTB2 race demo, raw-number lenses, role stand-ins, spatial shell | NCM authority, UI and Night City itself | **Do not port** |

**Source rights:** `D:/dev/oracle-radio/LICENSING.md` scopes its format/spec as Apache-2.0 and the rest, including `ftb2/`, as AGPL-3.0. `D:/dev/Radio-OS/LICENSE` declares GPL-3.0. The repositories name the same author, but a source copy into published NCM still needs an explicit rights and attribution decision and a compatible distribution plan. This review proposes mechanisms and original NCM implementations; it authorises no verbatim port.
