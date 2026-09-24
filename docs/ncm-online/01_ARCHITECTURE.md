# NCM Online — architecture

Date: 2026-09-19. Status: **approved with amendments (L28–L33)**. Every structural choice traces to [DECISION_RECORD.md](DECISION_RECORD.md) (L = locked, P = provisional) or to platform evidence in [docs/research/open77/](../research/open77/README.md). Platform baseline: OPEN//77 2.31.13+op77.78.

Principle: **Configurable by architecture. Opinionated by default.**

## Commercial-source boundary

F6 is an aggregator over commercial sources known/available to a Driver, not a global inventory authority. Every
primary inventory/allocation query is scoped by stable `marketId`; Base Market is simply the universally known
first source. Market knowledge, access, product eligibility, affordability, Machine Index knowledge, authored
supply and ownership are separate domain facts. See [17_MARKET_NETWORK.md](17_MARKET_NETWORK.md).

---

## 0. The shape in one paragraph

NCM is one product with three parts. **ncm-core** is engine-free Lua holding the motorsport vocabulary, rules, timing, competition structures, simulation and content-pack schemas. **ncm-sp** is the existing CET host, which progressively consumes core (L26). **ncm-online** is a set of OPEN//77 resources that turn a dedicated server into a persistent Night City motorsport world (L10): a *world layer* (identity, presence, provisioning, activity, promotion), a *session kernel* (heat instances with topology policies, gates, timing, grid, race control, entrant lifecycle), a *league service* (events/weekends, seasons, teams/seats/entries, standings, settlement, records, box scores), a *simulation service* (roster population, ambient scheduler, statistical racing) and *entrant backends* (human, physical AI, simulated AI). Clients run a WebUI HUD and world presentation over the same `Open77.*` surface. Content packs (routes, rulesets, series, vehicles, liveries) are versioned data the framework loads; the reference world ships street racing first and NCX second (L27).

---

## 1. Layering and packages

```
repo
├─ ncm/core/                 ncm-core (pure Lua 5.4-compatible; no Game/TweakDB/MTE/os/io/require)
│   ├─ vocabulary/           ids, enums, provenance, context, effects
│   ├─ course/               nodes, routes, gates, sectors, grid geometry (from grid_solver), drag strip geometry
│   ├─ formats/              sprint, circuit, point_to_point, drag, endurance, knockout, exchange (+ session kinds)
│   ├─ rules/                rulesets, points tables, penalties, eligibility/homologation, SR math, hype/payout
│   ├─ timing/               clock abstraction, gap/interval math, classification, tie policy, finish resolver
│   ├─ competition/          driver, team, seat, entry, session, event(weekend), season, standings, box score, record
│   ├─ simulation/           roster population + traits (from roster), statistical race sim (from _computeAITime,
│   │                        Roster.simulate), ambient scheduler (from ambient_races), promotion relevance
│   ├─ packs/                pack schemas + validators (routes, rulesets, series, vehicles, liveries, ambient profiles)
│   └─ fixtures/             frozen SP fixtures + runner (fixture parity, L26)
├─ ncm/online/
│   ├─ resources/
│   │   ├─ ncm_world/        server+client: identity binding, driver profile, presence, provisioning, places, activity feed,
│   │   │                    promotion orchestration, world topology policies
│   │   ├─ ncm_session/      server+client: heat instances (session kernel), gates, timing, grid/starts, race control,
│   │   │                    entrant backends (human / physicalAI / simulatedAI), spectators
│   │   ├─ ncm_league/       server: calendar, events/weekends, registration, seasons, teams/seats, settlement,
│   │   │                    standings, records, box scores, decision log, HTTP results routes
│   │   ├─ ncm_sim/          server: roster population, ambient scheduler, off-screen resolution (may fold into league)
│   │   ├─ ncm_hud/          client: WebUI HUD, event/driver browser, race-control panel, spectator mode, notifications
│   │   ├─ ncm_pack_street/  content pack #1 (routes, rulesets, classes, ambient profile)
│   │   └─ ncm_pack_ncx/     content pack #2 (+ preload_mod liveries archive; RB15 via player-fetch)
│   ├─ profile/              server.jsonc fragment, tunables defaults, ACL roles, DB migrations
│   └─ build/                vendors ncm/core into each resource's shared/ (no cross-resource require on the server)
├─ ncm-localized/            ncm-sp (existing payload; gains a core loader shim and adopts slices in bounded passes)
└─ tools/                    SP-data → pack exporter, fixture generator, pack validator, migration runner, deploy
```

Why five resources (L29) rather than one: each OPEN//77 resource is an isolated VM with its own permissions, lifecycle and hot-reload; `ncm_session` needs `world.vehicles`, `world.npcs`, `players.*`, bucket control; `ncm_league` needs `database.access` and HTTP; `ncm_hud` needs UI permissions only. Cross-resource calls use generation-bound server exports (values copied; synchronous exports never yield). Keep the count small; a resource boundary is a contract, not a folder.

Why core is vendored: server Lua has no `require`; scripts load in manifest order into one VM per resource. The build step copies `ncm/core` into `shared/core/**` of each resource and emits an ordered `shared_script` list. CET loads the same files through a tiny `require` shim. Core files are written as chunks that return a table and receive dependencies through a `Core` registry argument, so neither host needs `package`.

---

## 2. ncm-core contract

### 2.1 Purity rules
- No engine, platform, registry (`MTE.`), OS, IO, clock or RNG access. Time and randomness are **injected** (`ctx.now()`, `ctx.rng`).
- Functions take plain tables and return **decisions + effect lists**; hosts apply effects (`credit`, `persist`, `notify`, `spawn`, `teleport`, `freeze`…). Rules never call `Game.AddToInventory` or save mid-rule (SP finalizer debt).
- Every state record is explicit and serialisable (JSON-safe), so it can be a SQL row, a state-bag value, a fixture, or an SP JSON file.

### 2.2 Vocabulary (from `event_definitions.lua`, extended)
```
Ids:       ncmDriverId (uuid, NCM-minted: P2), teamId, seriesId, seasonId (`YYYY-Sn`), eventId, sessionId, entryId,
           seatId, vehicleAssetId, routeId@rev, rulesetId@rev, packId@version, serverId, settlementKey
Provenance: physical | simulated | estimated | dnf | disconnected            (L6, per entrant per session)
Context:    { origin: sp|online, serverId?, sessionKind, sanctioned: bool, category? }   (L6, L11)
Topology:   open_world | controlled_world | isolated                                    (L15)
Backend:    human | physicalAI | simulatedAI                                            (P9)
EventClass: calendar | ambient | impromptu | organized                                   (L16, P12)
SessionKind: practice | qualifying(solo|shared) | race | sprint | feature | stint | leg   (L23)
EntryState: registered | checked_in | provisioned | gridded | racing | suspended | substituted | finished | dnf | dsq | withdrawn  (L20, P13, P21)
VehicleAssignment: entry × session × leg/phase → vehicle ref, time-scoped; an entry may change vehicles across legs (L28)
Effects:    credit | debit | persist | notify | award | penalty | log | spawn | despawn | teleport | freeze | release …
```

### 2.3 Modules and their SP ancestry

| Core module | Extracted from (SP) | Kept semantics | Changed |
|---|---|---|---|
| `course.nodes/routes/roots` | `data/nodes*`, `roots.lua`, `routes.lua`, `default_roots_pack` | IDs, coordinates, headings, road/urban flags, pack import/export, canonical direction | Endpoint-only roots are marked `incomplete`; a *course* adds authored gates, sectors, grid slots, AI path |
| `course.gates` | `checkpoint.lua`, Racing finish-line crossing, knockout progress | ordered progress, finish-plane sign change, capture radius as fallback | Gates are oriented boxes with Z band + grace; swept-segment crossing; direction test; monotonic progress score (fixes SP's non-monotonic score) |
| `course.grid` | `grid_solver.lua` (893 lines, zero engine refs) | row/lateral/setback geometry, side-by-side lanes, road-width/grade estimation | Validation of occupied slots done by host |
| `formats.drag` | Racing drag lane order, straightness/penalty, road width, lane count | all | Path deviation samples come from server motion |
| `formats.knockout` | `knockout.lua` elimination by checkpoint interval, danger zone, final sprint | all | Per-participant tracking generic over backends |
| `formats.endurance/exchange` | Racing sequence targets, laps; spec-field lineup | sequence progression, lap counting | Adds stints/legs, vehicle reassignment between legs, entry roster |
| `timing` | Racing countdown phases, gap text, live standings, finish resolver, DNF grace | five-light phases, gap/interval math, resolver ordering, near-finish grace | Clock is injected (server monotonic); explicit tie policy; provenance per entrant |
| `rules.rulesets/points` | `championships.lua` RULESETS/POINTS_TABLES/faction scoring | points tables, fastest-lap/pole bonus, factionScoringMode | Absence/substitution policy, provenance counting policy, topology policy, provisioning policy, consequences list (L24, L15, L13, L20) |
| `rules.sr` | `safety_rating.lua` | incident buckets, chain timeout, SR delta bounds, profiles per scope | Incident *source* is host-provided; fault attribution remains none |
| `rules.hype/payout` | `hype.lua`, PAYOUT_BY_POS, `betting.lua` formulas | multipliers, base payouts | All money flows through ledger effects (L21) |
| `rules.eligibility` | `parts.lua` fit logic, CLASS_TAGS, `vehicle_pool`, `vehicle_slot_profiles` | class detection, fit scoring | Homologation per ruleset; provisioning model per ruleset (L13) |
| `competition.*` | `careers.lua` (records of races), `championships.lua` seasons/standings/box scores, `records.lua`, `management.lua` slots | schedule generation (seeded LCG), standings sorting, box-score envelope, records keying | Driver≠Seat≠Entry≠Team (L18); events contain sessions (L23); records keyed by route@rev × class × context |
| `simulation.roster` | `roster.lua` | seeded generation, traits, momentum, lifecycle sweep, tier pressure, catch-up | Population is per *server world*, not per career; catch-up advances once per server interval (E11) |
| `simulation.race` | `Racing._computeAITime`, `Roster.simulate`, ambient `resolveEvent` | projected times, urgency/personality scales | Produces per-sector timelines so simulated entrants can appear on a live timing screen |
| `simulation.scheduler` | `ambient_races.lua` | district weights, windows, staging/active/completed lifecycle, promotion eligibility | Relevance/suitability/budget policy for online promotion (L17) |
| `narrative` (later) | `fan_engine`, `contact_events` | milestone reactions, archetypes | Private per-driver delivery via targeted events |

Not extracted (SP-only, mined for spec): `racing.lua` orchestration, `ai_vehicles.lua`, `telemetry.lua`, `tuning.lua`, `ink_hud.lua`, `mappins.lua`, `phone_bridge.lua`, `race_commands.lua`, all `ui_*`. The SP prestige ladder (`careers.lua` tiers/REP policy) is preserved for the SP redesign, not extracted as online policy (L22).

### 2.4 Fixture parity (L26)
`tools/fixtures` runs current SP modules under a CET-free harness (stubbing `MTE`, `Game`) to capture input→output pairs for each slice (standings from results, box-score envelopes, grid geometry, SR deltas, drag penalties, schedule generation for a seed). Core must reproduce them; deliberate rule changes are recorded as fixture revisions with a reason. A slice is *done* when the fixture suite passes and both hosts consume the slice.

---

## 3. ncm-online: server components

### 3.1 `ncm_world` — the persistent world layer (L10, L11, L13, L17)

| Service | Responsibility | Platform primitives |
|---|---|---|
| **Identity binding** | On `onPlayerConnected`: look up `userId → ncmDriverId`; first visit mints an NCM Driver ID (uuid) and profile; SP-minted IDs can be claimed later via a signed token (portability path, P2). Hold readiness (`Open77.ready.hold`) until profile + world state loaded. | `GetPlayerIdentifier`, `Open77.ready`, SQL |
| **Driver profile** | Multi-dimensional profile (Q19 default): display, numbers, per-discipline grade, SR, reputation, accomplishments; per-server ledger account (zero-balance, L21). Exposed to clients via a bounded read model (private fields via targeted callbacks, public via player state bag). | state bags, `Open77.net.register` |
| **Presence & places** | Where drivers are (bucket, district), named NCM places (venues, garages, meets) as content; activity feed (ambient events forming, results, records). Hooks for Q22 without committing to features. **Night City itself is the world (L30)**: places are things you can drive to, never nodes of a hub-to-hub model; driving through the city is first-class. | `Open77.players.position`, blips, worldui |
| **Provisioning** | Executes a ruleset's provisioning policy: `issued` (create canonical vehicle from series spec + appearance), `loaner`, `owned` (rehydrate `vehicleAsset.properties` via `setProperties`), `byo` (adopt the player's vanilla car or accept an owned canonical car); assigns seats (`warpPlayerIntoVehicle`/`taskPlayerEnter`), applies performance ceilings, returns vehicles at session end. | `Open77.vehicles.*`, `adopt`, `setPerformance` |
| **Topology & buckets** | Bucket allocator (reserved ranges per topology), per-bucket population/time/weather (`isolated`), `world.setPopulation`/`clearArea` around events (`controlled_world`), nothing for `open_world` (L15). Spectator admission = bucket move as non-entrant (L19). | `Open77.routingBuckets.*`, `Open77.world.*`, `Open77.environment.*`, `players.teleport{bucket}` |
| **Promotion orchestration** | Turns a simulated event into a physical session when relevant + suitable + within budget; demotes back to simulation preserving state (L17). Owns the AI vehicle budget. | session kernel, `ncm_sim` |

### 3.2 `ncm_session` — the session kernel (heat instances)

A **heat instance** = one session record + one entrant set + one vehicle set + one topology context (bucket or world region). Many run concurrently; each ticks on a fixed cadence (default 100 ms sampling, 250 ms state publication — the reference Race's defaults, to be measured in E2).

```
scheduled → open → provisioning → staging → formation/ready → countdown → green → running
         → finishing(grace) → classified → settled → closed
    ⤷ aborted / red_flag / suspended (race-control transitions, any phase after open)
```

| Concern | Design | Source |
|---|---|---|
| **Observations** | Per tick, for each entrant: canonical vehicle snapshot (`position`, `speed`, `physicsOwner`, `epoch`, `driverPlayerId`) and player position; stale/no-owner samples freeze accumulators, never reset them ("held for N ticks"). Client messages (gate claims, intents) are *hints* that trigger re-evaluation only. | gamemode-kernel contract; P11 |
| **Gates** | Core `course.gates` evaluates ordered progress with swept segments, direction, Z band, grace; server-side `Open77.zones` used for the geometric containment where cheaper. Wrong car/seat/bucket/epoch rejects. Tie policy: deterministic by accepted-sample time then grid order (core). | P8; Race geometry lessons |
| **Starts** | Standing (grid slots from core, `setFrozen`/control lock until green, jump-start = movement before green), rolling (pace band from SP `_computeRollingPaceBand`, violations), side-by-side/drag lanes; five-light countdown phases published to clients; server monotonic `startedAt`. | SP semantics |
| **Timing** | Server clock only; laps/sectors from gate acceptance; live classification from core `timing`; gaps/intervals; finish resolver with grace; per-entrant provenance. | core |
| **Entrant lifecycle** | States per P13/L20; `suspended` on disconnect with configurable grace (vehicle preserved, seat held); reconnect resumes; `substituted` swaps the driver on the entry (exchange/endurance rosters); DNF/DSQ/withdrawn are terminal. | L20 |
| **Entrant backends** | `human` (seat + observations), `physicalAI` (canonical vehicle + `Open77.vehicles.ai.followRoute` over the course's AI path, optional visible NPC driver with `appearance`; state machine over `waiting_for_simulator/running/blocked/failed`; falls back to `simulatedAI` on failure *with provenance change*), `simulatedAI` (core `simulation.race` timeline fed into the same timing engine → appears on the timing screen, optionally later as a ghost). A session declares allowed backends per seat. | P9, L12, vehicle-ai guide |
| **Race control** | Automated director drives the state machine; ACL-gated commands (`ncm.rc.delay/start/abort/redflag/penalty/correct/dsq`) write to an audited decision log consumed by the state machine; consequences resolved by ruleset (L19, L20, L24). | `RegisterCommand(restricted)`, ACL |
| **Spectators** | Non-entrants admitted to the instance (bucket), spectator HUD mode; later camera feeds when `remoteCamera` ships. | L19 |
| **Result envelope** | `{serverId, sessionId, eventId, seasonId?, routeId@rev, rulesetId@rev, topology, entrants[{entryId, driver(s), seat?, team?, backend, provenance, startPos, finishPos, times, sectors, penalties, status}], decisions[], finalizedAt, version}` → handed to `ncm_league.settle`. | yesterday's matrix |

### 3.3 `ncm_league` — competition and settlement

| Service | Responsibility |
|---|---|
| **Scheduler & calendar (the spine, L34)** | Series in content packs declare cadence (L37, P20); the scheduler materialises posted slots ahead of time with a wall-clock start and a start venue in the city. Events are first-class (L23): `event{class, eventId, seriesId?, round?, topology, ruleset, startsAt, venue, sessions[]}`; sessions share the entry list; one event may split into N grids by rating (L38). `impromptu` events are short-notice scheduled events at the creator's position (P17). Thin fields are backfilled from the roster per ruleset (L36). Pings at T−15/−5/−1 (P19). |
| **Registration, check-in & entries** | Advance registration reserves; the venue prompt ("Pay entry fee and enter?") produces `checked_in` (L35, P21) — presence alone never enters anyone. Entries bind seats (or independents) to sessions; entry rosters for exchange/endurance; reserves per seat (L18, P13). Entry fee / purse / payout run through settlement from day one at zero amounts (L21). |
| **Seasons & standings** | The global NCM season is a UTC calendar quarter with stable id `YYYY-Sn`; `seriesId` names the enduring championship and its edition in a season is a distinct historical object. A championship may occupy only part of the quarter. Core standings derive from authoritative settled results; rulesets decide provenance counting and absence/substitution (L24). Closed editions and their facts remain queryable; corrections use an audit trail. |
| **Settlement** | `settle(resultEnvelope)`: one SQL transaction keyed by `settlementKey = hash(serverId, sessionId, finalizationVersion)`; writes results, standings deltas, ledger entries (zero amounts in the first world, L21), records, SR updates, box score; publishes an outbox row; idempotent on replay; concurrent finalizers lose on the unique key (E7). |
| **Records** | Keyed by `routeId@rev × class × context(sanctioned, topology) × provenance`; SP records import only as `context.origin = sp`. |
| **Box scores / activity** | Paged public read model for settled events (human and simulated), served to HUD and via `Open77.http.listen` routes (public standings/results JSON) for a future website. |
| **Teams & seats** | Content-defined teams/seats for series; player-created teams; occupancy history; displaced fictional drivers' states (L18). |

#### Season boundary and closure contract

`competition.seasons` is the authoritative pure calendar resolver. Hosts supply Unix seconds; it never reads a
machine-local clock. S1/S2/S3/S4 begin January 1/April 1/July 1/October 1 at 00:00:00 UTC. Bounds are half-open,
so a fact exactly on a boundary belongs to the new season.

A season change creates new seasonal competitive aggregation; it does **not** reset ownership, vehicle
assets/provenance/history, money, organizations, progression, discoveries, all-time statistics, or other world
state. Closing a season is a durable authoritative transition, not a display-date change. The future finalizer
must claim each `(seriesId, seasonId, finalizationVersion)` once, persist final standings before publication, and
make replay/restart/concurrent execution return the already-finalized edition without duplicating settlement.
Startup must scan for unfinalized editions whose `endUtc` has passed; continuous uptime at midnight is never a
precondition. This foundation pass supplies identity and bounds onlyâ€”not the finalizer, edition table, rewards,
or rollover daemon.

Current state, authoritative historical facts, seasonal aggregates, and all-time aggregates are four different
readings. Domain records own their evidence; this is not a requirement for one universal history table.

### 3.4 `ncm_sim` — the living league (L17, P7)

Server-side roster population per world (seeded, persisted, catch-up advanced once per server interval), ambient scheduler producing `ambient` events by district/time window, statistical resolution of un-promoted events, box scores and activity-feed entries. Exposes `simulate(session)` for `simulatedAI` seats and `snapshot(eventId)` for promotion/demotion continuity. Budgeted and chunked to host limits (E11).

### 3.5 Platform adapter

All `Open77.*` calls go through one adapter module per resource (`platform/*.lua`) with narrow functions (`createVehicle(spec)`, `seatPlayer(...)`, `moveToBucket(...)`, `observeVehicle(id)`, `aiFollow(...)`) so preview churn is contained and the adapter can be stubbed in tests. Version-pinned: the adapter declares the minimum build per function (from cards' `since`).

---

## 4. Client (`ncm_hud` and client halves)

- **HUD (WebUI, transparent):** session phase, five-light countdown, position/gap/interval, lap/sector, next-gate cue, penalties, entrant list with backend/provenance badges, spectator mode, race-control panel (ACL-gated), notifications. Data arrives as bounded read models (targeted callbacks + state-bag deltas), never the whole session.
- **World presentation:** next gate via `open77_worldui` marker (matching the server's acceptance geometry), route blips/GPS via `Open77.map`, grid slot markers, event venues/places, ambient activity markers. Native HUD elements hidden selectively (`Open77.hud`).
- **Driver/event browser and heartbeat:** profile, calendar with posted start times, the persistent next-race element (countdown + distance to venue, P19), register, short-notice event creation ("race to X from here", P17), team/seat views, box scores/standings.
- **Practice overlay (P18):** route preview on the native map, waypoints/next-gate rings for a chosen course, local unofficial timer and practice bests; no server session.
- **Local observations (optional, diagnostic):** drivetrain/inputs from the client vehicle snapshot for telemetry/analytics uploads — never authoritative (P11, E8).
- **Input/assists:** stock inputs by default; MT/IWN never required (L25).

---

## 5. Data model (SQL, MariaDB via `Open77.database`)

```
ncm_driver(ncm_driver_id PK, created_at, origin)                          -- NCM-minted (P2)
ncm_driver_binding(server_id, user_id, ncm_driver_id, bound_at, UNIQUE(server_id,user_id))
driver_profile(ncm_driver_id, server_id, display, number, dimensions JSON, sr JSON, updated_at)
ledger_account(id, owner_kind{driver,team,server}, owner_id, balance)      -- zero-amount now (L21)
ledger_txn(id, settlement_key, account_id, amount, kind, ref, created_at, UNIQUE(settlement_key, ref))
team(team_id, kind{content,player}, name, colors, pack_id?)
team_membership(team_id, ncm_driver_id, role, from_at, to_at)
series(series_id, pack_id, ruleset_id, rev)  season(season_id, series_id, index, state)
seat(seat_id, series_id, team_id, number)   seat_occupancy(seat_id, occupant_kind{driver,fictional}, occupant_id, reserves JSON, from_at, to_at)
fictional_driver(fictional_id, server_id, seed, traits JSON, state{active,reserve,benched,unsigned,transferred}, history JSON)
event(event_id, class, series_id?, season_id?, round?, topology, ruleset_id, rev, scheduled_at, state, created_by)
session(session_id, event_id, kind, order, state, started_at, finalized_at, bucket?)
entry(entry_id, event_id, seat_id?, team_id?, independent_driver_id?, state)
entry_driver(entry_id, ncm_driver_id|fictional_id, role{primary,reserve,substitute}, stint_index?)
vehicle_assignment(entry_id, session_id, leg_index, vehicle_ref{asset_id|issued spec|canonical id}, from_at, to_at)   -- L28: vehicle is not the entry
result(result_id, session_id, entry_id, driver_ref, backend, provenance, context JSON, start_pos, finish_pos,
       time_ms, laps, sectors JSON, penalties JSON, status, settlement_key)
settlement(settlement_key PK, session_id, version, status, envelope JSON, settled_at)
standings(season_id, subject_kind{driver,team}, subject_id, points, tiebreak JSON, rev)
decision_log(id, session_id?, event_id?, actor, command, payload JSON, applied_at)      -- race control audit (P14)
record(route_id, route_rev, class_id, context JSON, provenance, holder_ref, time_ms, session_id, set_at)
box_score(event_id, session_id, public JSON, published_at)
vehicle_asset(asset_id, owner_kind, owner_id, record, properties JSON, state)          -- garages (L13)
sim_state(server_id, key, cursor, blob JSON)                                            -- roster/scheduler
content_pack(pack_id, version, hash, enabled)
outbox(id, settlement_key, kind, payload JSON, delivered_at)
```
Rules: every write that affects standings/ledger/records happens inside `settle` under one transaction; reads for HUD go through paged read models; no client-supplied identity or amounts (identity from `source`, amounts from core rules).

---

## 6. Content packs (L14, L25, L27)

A pack is a versioned, hashed data bundle loaded by the framework; packs never contain platform calls.

| Pack part | Contents | Notes |
|---|---|---|
| `routes/` | courses: nodes, ordered gates (box geometry + Z band), sectors, grid slots per start type, AI path (≤64 pts per task, chunked), topology defaults, road-width hints; `revision` | Exported from SP `nodes/roots/circuits` by `tools/export_pack`, then authored (E1) |
| `rulesets/` | format, session template(s), points, penalties, consequences, provisioning model, eligibility/homologation, topology policy, backends allowed, absence/substitution, provenance counting, ceremony level | Derived from `championships.lua` RULESETS + SP settings |
| `series/` | teams, seats, numbers, liveries (appearance names), fictional roster seeds, calendar template | NCX: 10 teams / 20 seats from the liveries manifest |
| `vehicles/` | classes, homologated records, appearance manifests, performance-ceiling profiles per class | From `vehicle_pool`, RB15 livery manifest |
| `ambient/` | district weights, windows, type weights (from `NCM_2_0_SYSTEMS` ambient profile) | |
| `mods` | `preload_mod` inert archives owned by the pack (e.g. `ncm_rb15_liveries.archive` + `.xl` + tweak yaml); external dependencies declared with hash + fetch policy (RB15 → player-fetch) | Requirements of the pack's *capability*, not of entering NCM Online (L25). Whether the platform can scope them below whole-server join is determined in M0/E13 |

Pack #1 **street**: Tip-to-Trench, the default roots, one circuit, street classes (Sport/Muscle/Tech/Nomad/Bike), `open_world`/`controlled_world` defaults, impromptu ruleset, a grassroots championship ruleset. Pack #2 **NCX**: RB15 spec class with 20 liveries, 10 teams / 20 seats, canonical weekend template (format chosen later, Q21), works-team absence policy, simulated seats allowed. Formula entries are not circuit-only (L31): NCX rulesets may admit circuits, point-to-point routes and other NCM event types.

---

## 7. Operator surface (L14, P10)

- `Open77.tunables`: AI budget, promotion radius, grace periods, sampling cadence, ceremony defaults, economy switch (off), enabled packs, bucket ranges. Round-boundary promotion for competitive values.
- Server profile: which packs, which event classes are player-creatable, ACL roles (`ncm.rc.*`, `ncm.admin.*`), required mods (auto-derived from enabled packs).
- Extension surfaces (later, once stable): pack schema, ruleset schema, backend interface, HTTP read routes.

---

## 8. Integrity path (P11)

Today: server-observed motion is the only input to classification; client messages are hints; identities from `source`; settlement idempotent; decision log for human actions. Later, without rebuilding: tighten sample-continuity thresholds, add anomaly flags to results (provenance sub-status), gate `sanctioned` records/standings on flags, ranked categories per ruleset, optional client attestation. Nothing in the first world assumes trusted clients; nothing in the first world spends effort on hostile ones.

---

## 9. Platform dependencies and requests

| Need | Status | Action |
|---|---|---|
| AI speed cap 55 m/s | platform limit | Owner raises in Discord (E16); backends abstraction means NCX physical seats switch on when it lands |
| Server-readable drivetrain fields | unknown | E8; request if absent |
| Content-scoped (below whole-server join) required mods | to be determined in M0/E13 | If the platform requires the complete mod world at launch, record the constraint and bring reference-server/profile options back for decision (L25); no pre-emptive second profile |
| Remote cameras / player models | unreleased (main) | Adopt when published; spectators in-bucket meanwhile |
| Event bus semantics | ambiguous | E0 probe; design assumes VM-local `TriggerEvent` |

---

## 10. How SP consumes core (L26)

`ncm-localized` gains `modules/core_loader.lua` (require shim) and, per slice, a thin adapter that maps SP state to core inputs and applies core effects through existing SP functions (e.g. `Championships.recordResult` → `core.competition.standings.apply` + SP persistence). Each adoption pass is bounded, fixture-verified, and gated by the SP playtest plan. SP keeps its orchestration, AI, telemetry, tuning and UI; the SP redesign (L2) is a separate track that can reuse core more deeply.

## 2026-09-23 as-built access boundary (L106)

The league continues to own asset/market/ledger mutations. ncm_world/server/vehicle_access.lua is a read-only
consumer of title and the owner of transient assetId→OPEN77 vehicleId mappings. Client geometry observations
can propose placement but cannot nominate a record, Driver identity, price or owner. The adapter rechecks SQL
title and world context, creates only the exact stored record, and never creates persistent assets. Discovery
registration carries both identities separately. UI intents and runtime lifecycle are outside the pure core.
Shared F6 navigation is SHELL_TABS/renderNav in panel.html; Machine Index reuses Collection and Help stays last.
See 16_MACHINE_INDEX.md, L106 and MASTER_TEST 2.17 for the bounded implementation and unrun live proofs.