# Deterministic Race Week Radio — Simulation Truth and Commentary Surface Audit

> **STATUS: SPEC** - authority for: *the deterministic commentary fact surface (sources, provenance, knowledge boundaries)* - affirmed 2026-10-08 (L346-L347); audit only — owner-directed source audit for the writer and future deterministic commentary work. It authorizes no runtime implementation, prose corpus, voice recording, package, or change to the current Chronicles pipeline.
>
> Scope owner: 2026-10-08. Decision authority: [DECISION_RECORD.md](DECISION_RECORD.md), L346. This document inventories evidence in the present source tree; it is not a promise that every field is public or that every event should be spoken.

## Purpose and result

The show is to be authored by people and driven by deterministic simulation facts. It must not require a listener to install or download an LLM. The eventual voice packs are intended to ship through NCM Online, but their format, rights, and delivery path remain un-decided. The two main hosts are **equal co-hosts**. Their equal standing is a writing constraint, not a claim that they share knowledge or opinions.

The source audit finds substantial deterministic material already available for expansive race commentary: scheduled events, entry and grid state, segment splits, passes, mistakes, contacts, retirements, results, standings, career arcs, and causal references. There is also a Race Week model and public rule announcements. These sources do not combine into one universal public feed. Some are private simulation state, some are reconstructed or observed, and some are deliberately selected public stories. A writer can build recurring segments from these surfaces, but every line must retain its source, time, provenance, and knowledge boundary.

This is a **static source/schema audit**. It did not query a live database, observe a live Online session, validate client visibility, inspect voice-pack redistribution rights, or run Chronicles. A field present in a schema is not by itself proof of a current row, public access, or an in-world character knowing it.

## Reading the evidence

Use these labels in a writer’s source ledger:

| Label | Meaning |
|---|---|
| **Canonical** | Server-owned state or a deterministic result. It may still be private or provisional. |
| **Simulated** | A result from NCM’s deterministic model. It is a real NCM outcome with simulated provenance, not proof that a physical street event happened. |
| **Physical** | A result corroborated from the live race path and stored as physical provenance. |
| **Reported** | A report or claim; it must not silently become a verified result. |
| **Published** | Explicitly exposed through a public-facing event, projection, broadcast, or announcement. Confirm the actual recipient and time. |
| **Private / internal** | Useful to the sim or game, but not established as public knowledge. |
| **Derived** | Computed from stored facts. Preserve the derivation and avoid treating interpretation as observed fact. |
| **Proxy** | A model signal standing in for a more complicated phenomenon. Do not narrate it as a literal city measurement. |

“Could support a segment” means there is a source to investigate, not that a segment must fire every time. This audit does not invent an interestingness score, cadence, or dialogue rule.

## Main surfaces

### 1. Race Week and city policy

`ncm_world/server/week.lua` maintains the Race Week clock and private curve state; `ncm/core/week/curve.lua` tracks carrier, deviation, safety/enforcement/momentum reservoirs, and a policy step. The server persists hourly samples and boundary verdicts in `racing_week_*` tables. Samples include internal tolerance and reservoir values. The verdict table includes internal probability terms. Those are simulation machinery, not broadcast facts.

The replicated `GlobalState.ncmWeek` is a distinct public summary: run/day/chapter/hours, step, speed limit, race/police caps, countdown, money multiplier, and active Moody names. `ncmWeekFx` exposes tier purse/calendar/lure modifiers to the Paddock. These are rule/policy surfaces. A modifier proves a rule was published to consumers; it does not prove that a team entered, a purse was paid, a crowd responded, or a specific enforcement action occurred.

The hourly week code also produces “RACING RADIO” lines from `week.vibe.lua`. That classifier derives mood/cause/surprise from the curve and policy inputs. Some wording implies literal crowds, bars, or district reaction that are not backed by a crowd or sentiment measurement. Treat those lines as **authored proxy copy**, not ground truth for the new show. Do not quote them as eyewitness evidence.

### 2. Calendar, cards, and entry

`ncm/core/paddock/season.lua`, `ncm/core/competition/calendar.lua`, and Paddock event schemas define a deterministic schedule: race/series identity, tier, route, start and entry windows, venue/finish, distance, discipline/format/class, laps, seats, and economy. Paddock’s schedule is dense across tiers; its core supports recurring cards and season/cup structure. `paddock_race` holds the materialized race, seed commitment, conditions, state, provenance, backend, and details. `paddock_entry` and `paddock_quali` hold entry/withdrawal and qualifying state.

These sources support a factual “what is on the card / what is open / who entered / who qualified” segment when the exact event projection and time are known. A secret race seed is never commentary material; the commitment is not the outcome. A scheduled event is not proof it ran, and an entry is not proof the entrant started.

### 3. Live race and timing

`ncm/core/paddock/sim.lua` runs a seeded deterministic segment model. It can retain segment index, ordered positions, cumulative splits, overtakes (attacker and defender), mistakes with time loss, contacts, crash-outs, and mechanical retirements. The race record stores results and detail JSON; `ncm_paddock/server/races.lua` can reload result details. This is the richest currently identified deterministic race-action surface.

The live path is different. `ncm_paddock/server/live.lua` stages physical vehicles when a player/host can simulate them, samples positions and gate timing, can recover/reset stuck cars, and classifies the physical result only when corroborated; otherwise the sealed simulation result remains. `paddock_live_crossing` stores gate crossings and source (`server` or `pace`) with elapsed milliseconds. `paddock_live.detail_json` stores finishers, retirements, and recovery/reset counts. The source audit found no durable, general live telemetry/event stream equivalent to the simulator’s segment-by-segment `events` list.

Owner ruling (L347): hosts may use settled race results even when nobody physically witnessed that event. Keep `simulated` provenance internally for selection, audit, and diagnosis, but never identify the result to the player as a simulation/replay. This ruling covers the settled result; it does not yet authorize narrating unobserved, moment-by-moment sim events as if witnessed. Physical race narration still needs live authorized observations and must preserve physical/fallback/mixed provenance. A gate order change can support “changed places at this gate” if derived carefully; it cannot by itself establish a sustained wheel-to-wheel duel, cause, blocking, or intent. Recovery/reset counts are system intervention, not necessarily driver error.

`ncm_paddock/server/broadcast.lua` and NCM Broadcast send a local timing tower/nameplate view to nearby players and race entrants. This is a visual data feed, not a talk-radio or voice feed.

### 4. Results, standings, and history

`paddock_result` records finishing position/grid/state, finish and gap times, points, purse, DNF reason, and timestamp. `paddock_standing` and season summaries retain standings and career totals. Result provenance is `simulated` or `physical` at the race level; the source distinguishes physical fallback and corroboration. `ncm/core/paddock/tape.lua` supplies stable event IDs, causal/effect references, provenance, salience, retention, and facts. Its documented invariant is valuable for writing: **the facts object is the only input to a news template**.

The public story layer selects story kinds and facts. Results, upset, streak, first win, crash-out, rivalry/feud, transfers/releases/retirement, titles, sponsor changes, rookie debut, vehicle destruction, and chrome attack are among the kinds in the tape vocabulary. WIRE/news is a selected event surface; it is not a complete play-by-play transcript. Absence from WIRE does not prove that no sim event occurred, and an event’s presence does not automatically imply every character heard it.

### 5. Drivers, teams, and relationships

Persistent Paddock people/orgs include identity, role, organization, seat, region, public presentation, contracts, lifecycle, and race history. Hidden attributes/personality/evidence are used by simulation and are intentionally omitted from normal client projections. Performance attributes such as pace, consistency, mistakes, aggression, or pressure handling are not biographies, public reputation, or a character’s self-knowledge.

Career results, repeated head-to-head outcomes, public callouts, and explicit arcs can support history if sourced. Existing `paddock_arc` callout/rivalry/feud records are chiefly the player-facing arc system; do not assume a complete named relationship graph among all NPCs. Repeated contact or a derived head-to-head edge is evidence of the recorded events, not proof of personal hatred, friendship, or intention.

### 6. Machines, engineering, and discovery

Vehicle/component designs, installed configuration, transfers, component condition/fuel, machine passports, R&D competency, and releases exist in schemas and runtime systems. Some specifications are authoritative physical data; others are only known to a particular driver through ownership, market publication, authored display, scanner, or measured encounter. The player-scoped machine knowledge model distinguishes observation, publication, ownership verification, and evidence basis. This is not a universal public knowledge model for hosts, NPCs, institutions, or the audience.

A machine’s hidden configuration or measured performance can explain a sim result internally. It does not let a host claim a team secretly changed a part, discovered a weakness, or has a development plan unless a permitted event or knowledge record makes that claim knowable. Public R&D release events, market listings, and visible machine identity are stronger surfaces, each with its own timestamp and scope.

### 7. Incidents, quickhacks, and city response

League incident records can include session, driver/other driver, kind, speed/delta-v, timing, coordinates, attribution, and evidence. They are not by themselves a public report. Paddock tape has public story events for vehicle destruction and chrome attack, and sim race events record contact/crash-out. Preserve attribution state and do not convert an un-attributed incident into blame.

Race Week accumulates incident facts into policy reservoirs; those aggregate inputs are not a real-time police dispatch log, injury report, traffic count, or public sentiment. The audit did not find a comprehensive persisted city response feed (e.g. verified closures, emergency-service arrival, public witness statements) linked to every racing incident. Use explicit recorded consequences only.

### 8. Economy, sponsors, and organizations

Org cash, contracts, wages, purse, sponsorship, player market listings/bids/settlements, and exchanges are represented across economy and Paddock tables. Their existence as private accounting does not make them public. Tape events such as sponsor signed/left, transfer, manager changes, fold, and founding provide explicit story candidates. A purse modifier, cash change, market offer, completed sale, and public sponsorship announcement are different facts; don’t collapse them into “the team is broke” or “sponsors are piling in.”

### 9. Flight, Deep, and discovery

`machine_journey` persists a driver/machine journey with origin/destination/outcome/timing and summary/trace. These support canonical historical journey facts for authorized records. Driver-specific knowledge evidence exists for vehicle discovery, but the audit did not find a complete public/NPC/institutional epistemic layer for every Deep, flight, or aerospace fact. A canonical journey row does not establish public awareness. Keep private player discovery, observed evidence, published reports, and world truth separate. No Deep spoiler should be narrated as public absent an explicit publish/observation record.

### 10. Voice, audio, and distribution

The existing Chronicles work is a separate local narration pipeline described in [57_NIGHT_CITY_CHRONICLES.md](57_NIGHT_CITY_CHRONICLES.md). It includes generated realization and Piper playback; it is not the deterministic authored show specified here. Existing NCM Broadcast is a UI/timing presentation surface. The audit did not find a shipped authored talk corpus, voice pack manifest, or verified Online delivery path for voice assets.

Owner direction is that voice packs ultimately be hosted through NCM Online as part of the mod. Implementation and packaging are open. Audio source, performer/synthesis rights, redistribution, updates, client opt-in, storage size, and offline behavior need their own decisions. No rights conclusion is made here.

## Commentary inventory matrix

| Domain | Deterministic source / useful facts | Availability and persistence | Provenance / knowledge boundary | Writer-safe use; unsupported leap |
|---|---|---|---|---|
| Week clock / policy | day, chapter, step, caps, modifiers, Moody names | private hourly samples; selected state replicated | policy is published; curve/verdict are private | State the published rule; don’t claim public mood or outcome from it. |
| Calendar | series, route, start, entry window, class, laps, venue | schedule and materialized event rows | canonical; public projection must be checked | Preview the card; don’t say it ran or who started. |
| Entry / qualifying | entrants, withdrawal, qualifying best | persistent entry/quali rows | identity/presentation surface; timing may be private until shown | Attribute only after confirming the relevant view/time. |
| Grid / live timing | grid, positions, splits, gate crossings, elapsed time | transient live state; crossing rows persist | simulated, physical, or mixed; physical validation applies | Report an observed change at the source/time; do not assert cause or duel from a single crossing. |
| Segment action | pass, mistake/loss, contact, retirement/crash-out | deterministic sim events and race detail; live detail less granular | simulation vs corroborated physical | Sim can support a detailed recap; physical coverage needs captured evidence. |
| Results | position, state, margin, DNF reason, points, purse | persistent result rows/details | race provenance retained internally; result may replace sealed sim after validation | Use ordinary result language; never expose the internal simulation/replay label to the player. |
| Standings/history | points, wins, podiums, starts, DNFs, titles | persistent standings, tape, season summaries | derived aggregates; source window matters | Explain exact trend/window; avoid turning stats into personality. |
| Driver/team | identity, seat/org, contract/lifecycle, explicit arcs | persistent; projections filter private fields | hidden simulation traits are not public knowledge | Use published event or observable career history; no motive/inner-state claims from attrs. |
| Machine/R&D | design, fit, transfers, component state, releases | persistent machinery/R&D/market data | knowledge is driver-scoped; some facts private | Use public release/listing/observation; no secret setup or strategy claims. |
| Incidents/hacks | contacts, crashes, attributed attacks, speed/session evidence | incident and event rows; selected tape stories | evidence/attribution and provenance required | Say recorded/attributed facts; no injury, blame, police response without source. |
| City response | week fact tallies, district climate/events | aggregate/proxy and some daily state | not a real-time city sensor/public mood | Describe recorded policy or explicit event; no crowds/bars/closures from proxy. |
| Economy/sponsors | balances, wages, purse, transfers, public events | accounting rows; selected tape events | private accounting vs published announcement | Say announced deal or completed recorded transaction; no inferred solvency/strategy. |
| Flight/Deep | journey, route, outcome, trace, discovery evidence | journey persists; knowledge scoped incompletely | canonical private vs observed/published | Avoid spoilers unless a publication/observation establishes audience knowledge. |
| Audio / delivery | local TTS/playback and visual broadcast exist | not a hosted deterministic voice pack | rights and Online delivery unverified | Treat pack distribution as a future decision, not present capability. |

## Traceable source map

- Race Week public/private split: `ncm/online/resources/ncm_world/server/week.lua`; `ncm/core/week/curve.lua`, `moody.lua`, `vibe.lua`; migrations `060_racing_week.lua` through `064_racing_week_moody.lua`.
- Calendar and generic sessions: `ncm/core/paddock/season.lua`, `ncm/core/competition/calendar.lua`; `ncm/online/resources/ncm_league/server/schema/003_events.lua`, `004_sessions.lua`, `008_competition.lua`.
- Paddock race and story storage: `ncm/online/resources/ncm_league/server/schema/047_paddock_racing.lua`, `048_paddock_story.lua`, `057_paddock_entries.lua`; `ncm/core/paddock/tape.lua`, `sim.lua`, `story.lua`; `ncm/online/resources/ncm_paddock/server/races.lua`.
- Live race and presentation: `ncm/online/resources/ncm_league/server/schema/051_paddock_live.lua`; `ncm/online/resources/ncm_paddock/server/live.lua`, `broadcast.lua`, `racestate`/views modules.
- People, orgs, and incidents: schema `045_paddock_world.lua`, `046_team_affiliation.lua`, `059_speed_incident.lua`; `ncm/core/paddock/projection.lua` and `principal.lua`.
- Machine knowledge and R&D: schema `016_machine_knowledge.lua`, `028_observation_provenance.lua`, `029_evidence_trust.lua`, `031_component_assets.lua`, `032_component_supply_rnd.lua`, `067_machine_journey.lua`, `070_machine_passport.lua`–`072_physical_rnd_competency.lua`; `ncm/core/competition/machine_knowledge.lua`.
- Prior narration and UI boundary: [57_NIGHT_CITY_CHRONICLES.md](57_NIGHT_CITY_CHRONICLES.md), `ncm/chronicles/`, `ncm/online/resources/ncm_broadcast/`.

## Open questions for the writer/owner

1. **Knowledge boundary for the hosts:** settled race results may be used whether observed or not; simulated provenance is internal and must not be surfaced as a “simulation replay” label. Still open: may hosts narrate detailed, unobserved segment action (passes, mistakes, contacts) as play-by-play, or is that material limited to facts from a real observation?
3. Which real-world history window should recurring “form” segments use: current Race Week, season, career, or a host-selected comparison with the window spoken aloud?
4. Is a downloadable/streamed voice pack mandatory for launch, or should the authored text show work first with voice packs delivered later through the same Online mod channel?

These are questions, not decisions. The remaining knowledge-boundary question should be answered before drafting detailed unseen play-by-play.
