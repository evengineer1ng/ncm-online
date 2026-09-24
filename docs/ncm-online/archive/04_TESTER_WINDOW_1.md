# Tester Window 1 — the inaugural NCX vertical slice

> **STATUS: SUPERSEDED** by 14_TEAM_ORGANIZATIONS.md - the granted-equipment model is abolished - kept for history. **Do not build from it.**
> Authority map: [INDEX.md](../INDEX.md) - classified 2026-09-24 (L125)

Date: 2026-09-20. Status: **superseded in scope on 2026-09-21 (L59–L63): the destination described here is now Tester Window 2, the first showcase event; Tester Window 1 is a controlled multiplayer QA + capture session with 3–5 testers, planned in [wp/BATCH-2.md](wp/BATCH-2.md).** The analysis below stands as the TW2 readiness map. Original status: scheduling analysis, approved direction (L43–L45, P23–P25). Companion to [02_ROADMAP.md](../02_ROADMAP.md); decisions in [DECISION_RECORD.md](../DECISION_RECORD.md). This document gives Tester Window 1 (TW1) a destination; it does not move current work.

**Readiness criterion (replaces "after M4"):** the chain
`CONNECT → OFFER → ACCEPT → PICKUP → ARRIVAL → GRID REVEAL → ASSIGNED CAR → STAGING/LIGHTS → RACE → RESULT`
runs end to end for a field of 1..20 human NCX drivers, reliably enough that the presentation carries an alpha.

---

## A. What already exists (M0–M3.3, live-tested)

| Chain step | Existing piece | State |
|---|---|---|
| CONNECT | OPEN//77 identity → NCM Driver ID minted/bound per server, survives reconnect/restart (M2.1) | done |
| ASSIGNED CAR (mechanics) | server-issued canonical vehicles at a kerb pose, `vehicle_assignment`, return on disconnect/restart (M2.2); server console issue/teleport tools | done |
| GRID | grid slots (two columns behind the line), presence check, absent = DNS (M3.2) | done |
| STAGING/LIGHTS | F1 light tree on our own HUD page, synced clock, jump-start penalty (M3.2) | done |
| RACE | server-validated gates (proximity-first), classification, finish window, disconnect grace + resume (M3.2/M3.3) | done, two-driver proof pending |
| RESULT | results board, persistence (`session`, `session_result`, `ledger`), `/ncm.results`, `/ncm.best`, route leaderboards (M3.3) | done |
| Messaging surface | server→player toasts (`open77_notifications`), chat, our WebUI page pipeline | done |
| World markers / objectives | `open77_worldui` rings + hold-E prompts, waypoints with route kick | done |
| Scheduling | posted events, entry windows, pings; dev `ncm.race.now` | done |

## B. Already planned in M1–M13

| Requirement | Milestone |
|---|---|
| RB15 + team liveries as required mods; unsecured-mod consent flow for tester windows (Q24); E13 part 2 | **M7** (E13 part 1 in M0 remains unrun) |
| 20 canonical RB15s with per-entry `appearance` on a grid, two clients observing (E3b) | **M7** |
| Teams, seats, entry rosters, occupancy (10 teams / 20 seats), fictional roster seeds | **M4** (seats) + **M7** (pack #2 data) |
| Organized events with advance registration; `registered → checked_in → provisioned → gridded` (P21) | **M4** |
| Race control with human override and audit (abort, DSQ) | **M4** (abort exists as of M3.3) |
| Spectators as non-entrants | **M4** (cuttable for TW1) |
| Standings/box scores persisted and shown | **M1-debt / M4** (not required for a single race) |
| Topology: `isolated`/`controlled_world` bucket for a venue (population/time/weather) | **M2** (topology service v1 not built yet) |
| Vehicle AI primitives measured (one car, fleet, handover) — E4/E5 | **M6** (the pickup uses the same primitives one car at a time) |
| Race HUD polish, results screen | **M6/M12** |
| Player guide, operator runbook | cross-cutting docs track |

## C. Genuinely missing from the roadmap

1. **NCM Messages (OPEN//77-native)** — targeted, authored, stateful messages with response options; the OFFER/ACCEPT step. Not in any milestone. SP has the content model to port (`contact_events.lua` archetypes with offers/expiry, `phone_bridge.lua` responses via Redscript facts) — port the *content and state model*, not the WovenKit/phone implementation.
2. **Team assignment ("sorting hat")** — variety-first programmatic assignment inside the game; no player choice. Small; sits on M4 seats.
3. **Pickup / transport** — team-appropriate vehicle dispatched, player boards as passenger, autonomous drive toward the venue. Not planned anywhere.
4. **Convergence + grid reveal** — drop-off near the venue, REPORT TO GRID objective, the assembled liveried field pre-staged in grid slots, YOUR CAR / ENTER VEHICLE on the assigned car. Assembly is new; every primitive exists.
5. **Dispersed spawn** — testers join spread around Night City rather than at one freeroam spawn. Small (teleport on ready to a curated place).
6. **Invitation-only event class** — an event whose entry is the accepted offer + assigned seat, not the venue prompt (L35 still holds for the car: you physically get in). Fits L16 "organized" and P21's `registered`; needs the ruleset/flag.
7. **Session-scale readiness** — 20 clients on a home-hosted server over a residential uplink, 20 human-driven cars replicating at speed. Never measured; not in any experiment (E2 is two clients, E5 is AI fleet).
8. **Ops for a live cohort** — Discord intake, consent text for unsecured mods, mod install guide (RB15 + liveries), a runbook, a way to re-run the slice.

## D. Classification of the missing pieces

| Piece | Required for TW1 | Polish, cuttable | Future NCX, must not block |
|---|---|---|---|
| NCM Messages v0: one authored offer per team, Accept/Decline, server state, message panel | **required** (one template + team name/one-liner) | per-team authored voices matrix, threaded conversations, branching trees | full port of SP contact-event system, contracts, career |
| Sorting hat: variety-first, deterministic seeded, re-runnable | **required** | reserve list / late joiners rebalancing | NCX qualification, standings-based seats |
| Pickup: transport arrives, passenger boards, autonomous drive | **required in fiction**, mechanism negotiable (see G/H) | team-specific transport vehicles; visible NPC driver | Delamain-grade routing across the whole city |
| Convergence: drop-off near venue, walk, REPORT TO GRID marker | **required** | authored drop-off points per venue | — |
| Grid reveal: pre-staged liveried field, YOUR CAR prompt, enter | **required** | ceremony (camera, music, nameplates on cars) | broadcast/remote cameras (M12) |
| Dispersed spawn | required (cheap) | authored "home" places per team | — |
| Invitation-only event class | **required** | — | organized-event tooling for organizers |
| Session-scale readiness measurement | **required** (a rehearsal at ≥6, ramp to intent) | — | — |
| Ops kit (intake, consent, install guide, runbook) | **required** | — | — |
| Spectators / overflow | — | cuttable | build when interest is known |
| Standings / box scores | — | cuttable for one race | M1-debt/M4 |
| AI backfill / physical AI fleet | — | — | M5/M6, explicitly not for TW1 (humans fill the grid) |
| Race Guide / interest model (M4.1) | — | not needed by the invitation flow | keep in M4 for the street world |

## E. Earliest credible point for the full chain

The chain needs, in dependency order: M3 complete (racing kernel, in hand) → **M7-lite** (RB15 + liveries delivered as required mods with consent, 20 canonical liveried RB15s spawnable in grid slots, team/seat data — this is E13 + E3b + pack #2 data, without the NCX weekend template or fictional seats) → **M4-lite** (organized/invitation events with `registered` entries and seats; race-control abort/DSQ; no spectators, no Race Guide dependency) → **TW1 slice package** (Messages v0, sorting hat, pickup, convergence/reveal, dispersed spawn, ops kit) → rehearsal → window.

M5 (living league) and M6 (physical AI at scale) are **not** on the critical path: the field is human and the transport is one AI car per passenger at low speed. M1-debt (standings) is not needed for a single race and can be sequenced beside M4-lite or after TW1.

## F. Recommended placement (roadmap amendment)

```
M0 ─► M1 ─► M2 ─► M3 ─► M4-lite ─► M7-lite ─► M7.5 TW1 slice ─► rehearsal ─► [TESTER WINDOW 1: inaugural NCX race]
                                                                       └─► M1-debt ─► M4 (rest: Race Guide, spectators, standings) ─► M5 ─► M6 ─► M7 (rest) ─► [TW2]
```

- **M4-lite** = the M4 items the invitational needs: events with sessions + advance registration, teams/seats/rosters, race-control abort/DSQ with audit. Race Guide (M4.1), spectators, standings HUD and HTTP routes stay in M4 proper, after TW1.
- **M7-lite** = E13 part 2 (required-mod pipeline with unsecured consent), RB15 base + livery archive delivery, 20 canonical RB15 appearances on a grid (E3b), team/seat data for the ten teams. NCX weekend template, fictional seats, shared-track qualifying and E9 stay in M7 proper.
- **M7.5 TW1 slice** (new, S/M): NCM Messages v0, sorting hat, pickup + convergence + reveal, dispersed spawn, invitation-only event class, ops kit; then an internal dress rehearsal with ≥6 trusted drivers on the exact slice.
- TW1 opens when the chain has run end to end in rehearsal without a console command from an organiser during the session.
- TW2 (NCX weekend with fictional seats, simulated backends) stays after M7 proper.

This moves TW1 **later than "after M4"** in content terms but **earlier than the "after M5" position** set on 2026-09-20 morning, because the invitational sidesteps the reason M5 was needed (empty street fields). L42's principle stands: no outsiders until the experience is coherent; this is the coherent experience.

## G. Expensive, fragile, or platform-dependent parts

1. **Autonomous pickup with a passenger.** The primitives exist and are documented: server-owned vehicle (`Open77.vehicles.create`), `ai.attachDriver` (driverless or NPC-driven), `driveTo`/`followRoute` (≤64 points, 0.5–55 m/s), passengers may board while the driver seat is reserved, `players.warpIntoVehicle` seats a player authoritatively. What makes it fragile: (a) **no headless physics** — the car moves only while a ready client is nearby; the passenger's own client qualifies, so it works in principle but a client that stalls in the appearance stage (KB-2) means a car that never moves; (b) native routing across Night City is unvalidated ("a nearby point may not have a valid road path"; `blocked`/`failed`/`no_progress` states are expected, not exceptional); (c) 20 simultaneous AI drives is exactly the fleet scale E5 exists to measure and hasn't; (d) elevation-correct pickup points per spawn place must be authored; (e) transport speed capped at 55 m/s is fine, but a 4 km drive at city speeds is 3–5 minutes of dead time per tester unless the route is short. Verdict: **build it as a single-car experiment first (E4-for-transport), and keep the fallback in H wired from day one.**
2. **Required mods on a secured server.** RB15 with its ERS runtime is executable content → refused unless verified; the window must run **unsecured with consent** (Q24 default) or RB15-without-ERS. E13 has never been run; it is the single biggest unknown on the critical path and should be the first thing M7-lite does.
3. **20 clients on a residential-hosted server.** Unmeasured. Upload bandwidth, tick budget with 20 human-driven cars at 250 km/h, and OPEN//77's own replication limits. A rehearsal ramp (6 → 10 → intent) is the only honest way to size it; a rented host is the contingency.
4. **Liveries per seat.** Appearance-per-canonical-vehicle is planned (E3b) but unproven on this build; if per-entry appearance fails, the reveal degrades to one livery per team pair or a single NCX livery.
5. **Message panel and grid ceremony are WebUI** — fine on primary clients, invisible on a second local instance (KB-4); irrelevant for remote testers.
6. **Spawn dispersal + convergence timing.** Testers arriving over 10–20 minutes need the offer/pickup to be per-player and idempotent, and the grid to wait for a formation deadline, not for everyone.

## H. The smaller implementation that keeps the experience

Keep every beat; simplify the mechanism:
- **Pickup fallback:** the team car pulls up and stops beside the player (spawn + one short `driveTo` of 30–60 m, or simply spawn at the kerb), the player boards as passenger, the screen fades ("transport is coming… en route"), the server dismounts and teleports player and car to the venue drop-off, fade in. Same fiction, zero cross-city routing, no fleet-scale AI. The full autonomous drive becomes an upgrade toggle per tester if E4-for-transport passes.
- **Convergence fallback:** drop-off is a fixed authored point 100–200 m from the grid; REPORT TO GRID is a worldui marker + waypoint (existing).
- **Reveal:** the field is pre-spawned at grid slots from `session.grid` with team appearances; YOUR CAR is the existing prompt with a team-coloured ring. If per-entry appearance is unavailable, one livery per team.
- **Messages v0:** a single authored template with team name, colour and a one-line voice hint; Accept/Decline; delivered as our WebUI panel with a toast. Threads, replies and the SP content port come later.
- **Event:** an `organized` event with `registered` entries created by Accept; the grid forms at a formation deadline with whoever has boarded; late accepters race next time.

## I. Deliberately NOT built before TW1

- NCX qualification, eligibility, contracts, careers, driver dimensions (M9/M10).
- The mature NCM Messages port (branching trees, conditions/consequences, SP content) — v0 only.
- Overflow/reserve/spectator systems (decide on real interest; M4 spectators can wait).
- AI backfill (M5) and physical AI fleets (M6); TW1 is human-only.
- The Race Guide as a TW1 dependency (M4.1 proceeds on its own track for the street world).
- Route-conflict detection, the NCX weekend template, shared-track qualifying, economy.
- Team voice matrix beyond a name + one line per team; ceremony cameras (M12).

## Rehearsal gate (TW1 opens when)

1. E13 passed: a fresh identity installs RB15 + liveries through the launcher consent flow and joins.
2. Chain runs end to end in an internal rehearsal with ≥6 drivers, no organiser console commands during the session.
3. Field renders all assigned liveries on every client (E3b).
4. Disconnect/reconnect in each phase handled (E3), results persisted and shown.
5. Server capacity measured at the rehearsal size with headroom; contingency host identified.
6. Ops kit: Discord intake, consent text, install guide, runbook, abort/re-run procedure.


---

# Addendum (2026-09-20): presentation & venue brief

Objective restated: for the duration of the event a participant should feel "I have somehow become a driver in an important Night City motorsport event and I want to win", not "I am testing someone's mod". We are authoring one polished temporary motorsport level inside Night City, using systems NCM keeps.

## What the platform actually offers (verified against the .78 docs; benchmarks still owed)

| Need | Platform capability | Verdict |
|---|---|---|
| Barriers / course furniture | `Open77.props.create` (server-owned, replicated, **streamed per player by `streamingRadius`**, "an RP server will hold thousands of props"); curated catalogue of 185 aliases incl. `barrier.*` (10: blockades, hesco, jersey, pedestrian barriers, swing gate, tire blocker), `fence.*`, `sign.*`, `street.*` (lamps, traffic lights, poles), `light.*` (spotlights), `race.checkpoint` (authored two-sided gate), `race.chevron`; `ttlMs`; `props.clear()` teardown; `setBucket`. Collision only on 116 of 184 hosts (hesco/shipping container may not block); non-unit scale on mesh hosts only; raw `.ent` templates disabled. Persistence off by default → a venue is always rebuilt from a definition. A `quota_exceeded` reason exists; the number is undocumented. | **Sufficient runtime substrate.** Benchmark the quota and client cost (E19). Barriers that must physically block need collision-bearing aliases (jersey/pedestrian), verified per alias. |
| Drafting/placement tool | `open77_props` ships admin console commands `prop.create / prop.here / prop.near / prop.move / prop.remove / prop.list` (ACL) and `Open77.props.all()` reads every prop; `Open77.io.writeJson` (server, `filesystem.write`) can export them. | **A drafting loop exists for free**: walk the course, `prop.here barrier.jersey`, nudge, then export `props.all()` into a VenueDefinition. An NCM-native editor is only a thin layer over this (see substrate). |
| CyberTrials | Nexus mod with in-game course authoring/sharing (SP). Not our code or assets; permissions respected. | **Reference only**: its authoring loop (place while driving, share as data) is the model; nothing to absorb. |
| Crowds | `Open77.npcs.create` from any `Character.*` record with `appearance`; passive/silent behaviour; task channels `hold`, `face`, `lookAt`, `playAnimation` (reviewed workspot clips); streamed per player by radius; **one nearby client simulates each NPC** (lease), others interpolate; "no ready client → tasks suspend". Plus `Open77.world.setPopulation(bucket, {crowd=0..1})` for vanilla ambient pedestrians (bucket-wide, unplaced). | **Feasible, unmeasured.** A static crowd (hold+face+idle clip) is cheap on the server and network; the cost is native NPC bodies on each client near the grid and the lease work of the simulating client. Benchmark density vs FPS/net (E20). Vanilla crowd density is a free ambient layer but cannot be shaped. |
| Crowd audio / PA / music | Package audio: `.mp3`/`.wav`/`.ogg` bundled in the resource (`files`), `Open77.audio.play3D` with **server-networked 3D emitters, range ≤ 1000 m, per-bucket audience**, loop/volume/seek; client-local `play2D` for personal music states; engine Wwise events via the effects catalogue. Assets must be declared in the manifest (licensing is ours to solve). | **Cheap and reliable** — the best value-per-effort item in the brief. Zoned crowd beds, grid atmosphere, PA bleed and a phase-driven music state machine are all a few emitters and a client crossfader. |
| Traffic / intersections in the shared world | Population (`crowd/traffic/police`) is **per routing bucket**, not per area; `Open77.world.clearArea(position, radius ≤ 2000, {vehicles, npcs, props, population})` sweeps a radius once; `setPreventionEnabled(bucket)` turns NCPD off; ambient traffic is per-client (E15 question). | **The hard trade-off.** In bucket 0 you cannot switch traffic off on the circuit only; you can sweep it and lower the whole bucket's traffic for the event (acceptable on an NCX night when everyone online is at the venue). The alternative is a controlled bucket for the race with spectators admitted (M4) — but then venue props/crowd must live in that bucket too. Decide with data (E22). |
| Spatial cost containment | Props and NPCs stream by radius + hysteresis per player; audio emitters have range. | Nonparticipants elsewhere in Night City pay nothing; a player driving past the venue streams it in. ✔ |
| Convergence / holding | `Open77.zones` (server `playersIn`), teleport with fade, worldui markers, notifications. | Trivial to build once the drop-off exists. |

## Classification (your intent, challenged where the platform says otherwise)

| Component | Class | Why / change from your draft |
|---|---|---|
| Race core: incidents → time penalties, corrected time, position readability, progress HUD, unmistakable gates, reliable GPS, missed-gate handling, start/grid/finish/classification, 20-car stability | **A blocker** | Agreed. Note incidents/damage penalties are new (M3 has jump start only); "prescribed course" needs authored gates (E1) — currently open-route. |
| Venue/course readability: start-finish + grid infrastructure, barriers at every place the route could be misread or exited, closed intersections | **A blocker** | *Elevated from "strong target"*: with authored gates still thin, barriers are how the prescribed course is communicated and enforced. Full-length barrier walls stay B. |
| Enough presentation for the reveal: pre-staged liveried field, competitors' entrance, controlled walk | **A blocker** | Agreed. |
| Crowd audio (zoned beds, grid atmosphere, start cheer, PA bleed) | **B strong target, cheap** | Package audio is the cheapest illusion in the brief; treat as near-blocker. |
| Substantial visual crowd (hundreds, authored density) | **B strong target, benchmark-gated** | Agreed; ceiling set by E20, not by us. Static hold+face+idle only. |
| Extensive barriers / full course construction | **B** | Agreed; the drafting loop makes volume cheap, the quota/FPS benchmark sets the cap. |
| Music states (arrival → approach → grid → pre-start → race → post) | **B** | Client-side state machine over 2D loops + 3D emitters; licensing is the real gate. |
| Polished arrival/grid environment (lights, signs, support vehicles) | **B** | `light.spotlight`, `sign.*`, parked canonical vehicles — all existing primitives. |
| Convergence/holding stage | **B (inaugural-only)** | Cheap; protects the reveal from Discord spoilers. Release at ≥X% arrived or a deadline. |
| PA / start announcer / commentary | **C quality-gated** | Agreed. A handful of pre-produced lines through 3D emitters; cut if it sounds robotic. |
| Sophisticated crowd AI, synchronized reactions | **D** | Agreed. |
| Dynamic broadcast commentary | **D** | Agreed. |
| Generalised chauffeur system | **D** | Agreed (P24 fallback stands). |
| Venue editor beyond the drafting loop + VenueDefinition | **D** | Agreed. |
| Shared-world discoverability of the race (nonparticipants watch) | **B** | Desired; hinges on E22. If traffic control forces a bucket, spectators are admitted through M4's bucket admission instead. |

## The smallest reusable substrate

1. **VenueDefinition** (data, versioned, part of a content pack): props `{alias, x, y, z, yaw, scale?}`; crowd zones `{shape, density, facing, appearance pool, clips}`; audio emitters `{asset, x,y,z, range, loop, volume, phase}`; places `{dropoff, competitors_entrance, grid_approach, spectator areas}`; gates/course reference; no-go zones; traffic policy. JSON-safe, loadable by `ncm_world`.
2. **Venue loader/teardown** (server): build = spawn props/NPCs/emitters with radii from the definition (idempotent, batched, budgeted); teardown = remove by ownership; rebuild on restart. This is a generic "event dressing" service NCM keeps.
3. **Drafting loop**: shipped `prop.*` admin commands (ACL) to place while walking/driving → `ncm.venue.export <name>` writes `props.all()` into the definition → hand-edit only density zones and emitters. Later, `ncm.venue.*` client commands with local preview replace the admin commands if it earns it.
4. **Audio state machine** (client): phase/zone → 2D music loop crossfade; 3D emitters are server-owned per definition.

That is one definition schema, one loader, one export command, one crossfader. Nothing else needs to exist to build one excellent venue, and all of it is what normal NCX venues use afterwards.

## Inaugural-specific vs permanent (kept explicit)

Inaugural-only: unexpected team offer, sorting hat, secrecy between participants, chauffeur/pickup, concealed approach, synchronized-ish reveal, holding stage.
Permanent NCX identity: temporary sanctioned venues (VenueDefinition + loader), barriers/course furniture, spectators + crowd audio, event music/presentation, PA where good, team/corporate dressing, sanctioned grid/start procedure, strong race UX, shared-world discoverability where E22 allows.

## Route selection = level design

The inaugural route is chosen by a scouting pass against both lists (racing: speed, corner variety, braking zones, overtaking, readability, gate structure, replication, 20-car start; presentation: grid/start-finish location, sightlines, private drop-off, pedestrian approach, spectator room and vertical viewing, barrier practicality, scenery, audio spots, dressing). A slightly worse road that is a dramatically better venue wins. Candidates come from the existing node/root set plus a purpose-authored circuit; the scouting pass is a work item of M7.5, done in-game with the drafting loop.

## Experiments added

| ID | Question |
|---|---|
| E19 | Prop/venue scale: server prop quota; N barriers along a 3–4 km course; client FPS and stream-in behaviour at speed; which `barrier.*` aliases actually block a car; `race.checkpoint` gate host usability. |
| E20 | Crowd scale: passive NPCs (hold+face+idle clip) at 50/150/300/500 in authored zones; client FPS near the grid, simulating-client lease cost, network snapshot cost, stream-in at approach speed; vanilla `setPopulation` crowd as an ambient layer. |
| E21 | Package audio: zoned 3D crowd beds + PA emitters + client music crossfade across phases; audibility on approach; volume balance against engine audio in the race. |
| E22 | Sanctioned venue in the shared world: `clearArea` sweeps + bucket-wide traffic reduction vs a controlled bucket with admitted spectators; per-client traffic divergence on the circuit (E15 data); NCPD prevention off. |

## Amendment to TW1 sequencing (P25 stays; M7.5 grows)

M7.5 TW1 slice now includes: venue substrate (VenueDefinition + loader + export), venue scouting pass and the inaugural venue build, crowd + audio per E19–E21 results, traffic policy per E22, incident/damage time penalties and corrected-time classification (race core), convergence/holding stage, PA only if it passes the quality bar. Rehearsal gate adds: venue builds and tears down cleanly on restart; FPS at the grid with the chosen crowd density acceptable on the weakest tester machine we know of.


---

# Addendum (2026-09-20): inaugural driver onboarding / secret team assignment

Opening chain: CONNECT → DRIVER PROFILE questionnaire (looks like onboarding) → PROFILE COMPLETE → ~60–90 s NCM orientation film (normal NCM only, no Formula) → back to the world, short beat → team message arrives (diegetic reveal; never "your team is X") → ACCEPT → pickup → arrival → REPORT TO GRID → reveal → race. Discord voice makes the sorting visible between testers; the UI never explains it.

## Fit against what exists / is being built

| Concept | State now | Decision |
|---|---|---|
| Driver | `ncm_driver` + `driver_profile` (M2.1) | keep |
| DriverProfile personality | none | **P29:** onboarding metadata on the profile (`onboarding_json`: questionnaire version, answers, affinity vector), no gameplay effects, never shown to the player. Added in migration 006 with M7-lite. |
| Team | core `competition.teams` + `team` table (M4-lite) | keep; `livery` key already present |
| VehicleDefinition | core `data.vehicle_pool` (SP records) | M7-lite adds the NCX RB15 definition (record, class Formula, appearance names) |
| TeamVehicle / livery per car | none | **M7-lite:** `team_car (server_id, team_id, car_index, vehicle_def, livery, number)` in migration 006; entry → car via the existing `vehicle_assignment` relation (L28) at provisioning |
| EventEntry | `entry` with `team_id`, `seat_index`, `registered_at` (M4-lite) | keep; add `car_number` when team cars exist |
| Message / Offer | in-memory `offers` + `seat.offered_at` (M4-lite placeholder) | **P30:** `message` table in migration 006 (to driver, from team/system, kind, subject, body, actions, state unread/read/accepted/declined/expired, ref, timestamps); the seat offer becomes a persisted message from then on; delivery stays toast+chat until the Messages panel (M7.5) |
| Sorting hat | `Teams.assignSeat` variety-first, seeded | **done now (P31):** affinity-weighted within the variety rule (`opts.affinity`); cohort-level matching (batch optimisation) only if greedy-in-arrival-order proves unfair in rehearsal |
| Questionnaire | none | core `onboarding.questionnaire` (pure: questions/answers data → affinity vector, versioned) — M7.5; content authored by the owner |
| Orientation film | none | E23 (below) — M7.5 |
| Targeted messages/UI | player bag, targeted net events, `open77_notifications` per player, our WebUI pages | sufficient; Messages panel = our page (M7.5) |
| Player-specific event state | `ncmEntry` bag, session view per player | sufficient |

The chain Race Control will reason over is therefore **Driver → Team → TeamVehicle (car/number/livery) → EventEntry (seat) → Grid slot → Session → Result**, with every link a table that exists or lands in 006 — no inaugural-only state.

## OPEN//77 capability answers

- **Video:** the client WebUI is CEF; the shipped `open77_media` package documents **VP9+Opus WebM plays natively**, **YouTube embeds work and are controllable**, H.264/AAC do not decode (the host can transcode links), no DRM. A bundled 90 s 720p WebM is ~15–25 MB of resource download per client (one-time, cached). Two viable routes: bundle the WebM in `ncm_world` `web_files` and play it in a `modal`-layer page with a Lua bridge for done/skip (deterministic, offline); or an unlisted YouTube embed (no download cost, needs internet, YouTube chrome). **E23** decides after a real test; bundled WebM is the default.
- **Player-targeted UI:** solved already — per-player notifications, chat, state bags, targeted net events, and our own WebUI pages (race HUD proves the pipeline).
- **Sequencing:** questionnaire and film are client pages gated by server state (profile complete → film → offer), all per player; nothing global.

## Natural implementation point

**M7.5 (TW1 slice), first packages, after M7-lite has delivered the cars and liveries** — the reveal is worthless without them, and the questionnaire's only consumer is the hat. Order inside M7.5: (1) migration-006 data already in place from M7-lite → Messages v0 panel + questionnaire + affinity hat wired to `ncm.invite`; (2) orientation film (E23); (3) pickup/arrival/reveal; (4) venue. Compact opening timing target: questionnaire ≤ 2 min, film 60–90 s, beat 10–20 s, offer.

## Parked (no implementation now)

Questionnaire content and the team personality matrix; per-team message voices; the film itself; the Messages panel; cohort-level matching; any RPG-ish use of profile traits (explicitly never).


---

# Addendum (2026-09-20): inaugural course concept — Pacifica Stadium + pre-race Route Plan

Direction: the inaugural venue candidate is the **Pacifica Stadium** area (grid/start most likely; scouting may make it the finish). The format's one strategic mechanic: some sectors have several legal routes; drivers **declare a route per Route Sector before lights out**; navigation guides each driver down their declared branch; branches reconverge at **Universal Gates** where the pack reforms. Not a triathlon; the race stays "who wins in the NCX Formula car". Geometry, timing and balance stay open until Pacifica is scouted.

## Fit against the current course / checkpoint / race-control architecture

Today a course is a flat ordered gate list (`course.gates.build`), progress is a gate index, and `session.race.report` accepts only `gateIndex == progress + 1`. Race control, the HUD strip, the results and the waypoint logic all read that index. The concept needs one generalisation, and it is small:

- **Course = ordered list of stages.** A stage is either one gate (start, universal, finish, plain checkpoint) or a **choice group** of alternative gates (branches, each with id, label, colour, an icon/shape hint and a **nominal length** to the next stage). Progress stays a stage index, so race control, results and the running order keep working unchanged.
- **Route Plan = per-entry map `stage → branchId`**, part of session state, published in the session view (race control sees every plan; aggregate counts can be shown after lock).
- **Report = (stageIndex, branchId?)**: accepted when the stage is next and (single gate) or (branch matches the plan under a *declared* ruleset) or (any branch under a *live-choice* ruleset). A **deviation policy** per ruleset decides what a non-planned branch crossing does: `accept` (street/live), `penalty` (NCX: time penalty "route deviation", progression continues), `reject`. No invisible walls; the world stays permissive, the ruleset defines valid progression.
- **Corrected position** across branches: progress fraction within a stage = (branch nominal length − distance to its gate) / nominal length, so P5 overall is knowable while you are first in your own group; the live running order already sorts by progress then distance and just needs the normalisation.
- **Navigation** = the existing per-client waypoint flow with the objective set to *my* branch gate, then to the universal gate; branch gates must sit on their branch's road so the engine's road route naturally takes that branch (placement is scouting work).

Nothing here conflicts with L31 (NCX not circuit-only), L47 (barriers as course readability — the choice sector triples that dressing), P26 (VenueDefinition carries the course stages), or race control. The only thing to **stop doing now**: no new code that assumes gates are a flat list (e.g. do not author intermediate gates as flat lists in M7-lite); author courses as stage lists from the first authored course.

## OPEN//77 capabilities needed (E24)

1. **Scripted re-route without a map open (KB-1).** A branch → universal objective change mid-race cannot open the map for 600 ms at 250 km/h. Test whether `setWaypoint` re-routes once a route already exists in the session (the kick may only be needed once); if not, this is a platform ask.
2. **Gate visual language**: `open77_worldui` gives ring/cylinder shapes, colour, label and description; `race.checkpoint` is an authored two-sided gate prop (E19). Universal = cylinder + gold/white + "◆ UNIVERSAL" label; branches = rings + colour + "RED ROUTE"; shape and text carry the distinction, not colour alone.
3. Per-player waypoints are client-local already; nothing new.
4. Merge safety is physical design + multiplayer replication at speed (E2/E5 territory), scouted and tested, not code.

## Smallest clean representation (for the CourseDefinition inside the VenueDefinition, P26)

```
course = { courseId, name, stages = {
  { kind = "start",     gate = {...} },
  { kind = "choice",    sector = "Stadium Exit", branches = {
        { id = "red",   label = "RED",   colour = "#FF5964", icon = "circle",  gate = {...}, nominalLengthM = 1420 },
        { id = "blue",  label = "BLUE",  colour = "#22D8E2", icon = "circle",  gate = {...}, nominalLengthM = 1610 },
        { id = "green", label = "GREEN", colour = "#4FE3A9", icon = "circle",  gate = {...}, nominalLengthM = 1380 } } },
  { kind = "universal", gate = {...}, nominalLengthM = 2200 },
  { kind = "checkpoint", gate = {...} },
  { kind = "finish",    gate = {...} } } }
ruleset.routeChoice = "declared" | "live";  ruleset.deviation = "accept" | "penalty" | "reject";  ruleset.deviationPenaltySec
entry.routePlan = { [stageIndex] = branchId }   -- locked before countdown; unlocked entries get a branch assigned by the ruleset's default policy (owner decision; proposal: least-declared branch)
```

## Pre-race flow (inaugural)

Grid forming → HUD page shows the short NCX ROUTE PLANNING briefing → SELECT ROUTE per Route Sector → LOCK ROUTE PLAN (net event `ncm:plan`, server validates against the course) → after lock the strip shows aggregate counts (RED 7 · BLUE 9 · GREEN 4; identities = owner decision) → lights. No branch capacities for the inaugural; what twenty humans choose is the data.

## Natural implementation milestone

**M7.5 (TW1 slice), in the course/venue packages** — the same package that authors the inaugural course and adds incident penalties (the race-core blocker). The core change (stages, plans, deviation policy, normalised progress) lands then; scouting Pacifica precedes it. Nothing is pulled forward: M7-lite (cars/liveries) and the migration-006 data are unaffected.

## Open until scouting

Start vs finish at the Stadium; number of choice sectors (one, at most two); the real character of red/blue/green; universal gate positions and merge geometry; barrier volumes (E19 budget); whether competitor identities are shown per branch after lock.

---

## TW1 tester brief (L59, L61) — send to each participant once they have confirmed

> **NCM Online — test session (about an hour).** We're building Night City Motorsports on OPEN//77: a racing league
> with a calendar, real race control, incidents and results. This is a **test**, not an event: we'll stop, restart,
> move cars and stage a few situations on purpose, and we're **recording** for a short video about the project (say
> so if you'd rather not be on camera — you can still race). Tell us everything you see, especially what confused you.
>
> **Install:** the game + the OPEN//77 launcher; join *NCM Staging*. For the last segment you'll need the RB15 mod
> files and the NCM liveries in your game folder (we'll send the zip and the launcher steps: *Mods & profiles → Your own
> game* → switch on the `rb15_f1_*`, `ncm_rb15_liveries*` groups and the ArchiveXL / TweakXL plugins).
>
> **Keys:** **F6** Race Guide · **F9** Messages · **F8** race graph on/off · **E** at a ring to get in your car.
> Chat twins if a page won't take input: `/ncm.guide`, `/ncm.interest <n>`, `/ncm.inbox`, `/ncm.accept`, `/ncm.debug`.
>
> **How it goes:** the host posts a run, your map routes you to the start; you'll get a car at the line when one is
> provided, otherwise use your own. Cross the start, follow the markers, finish at the last one. Contact costs
> seconds, not blame — both cars carry it. If the host says "restart", stay put; a new run forms in ~30 s.
>
> *(Once they are in, by voice — L61):* one segment uses a Formula car with team liveries; that's for a larger event
> we haven't announced. Please don't share the car or the liveries publicly before we do — a glimpse may appear in the
> video without explanation.

