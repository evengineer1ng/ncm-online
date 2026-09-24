# NCM Online — orientation and architecture brief

> **STATUS: SUPERSEDED** by INDEX.md + NOW.md - kept for history. **Do not build from it.**
> Authority map: [INDEX.md](../INDEX.md) - classified 2026-09-24 (L125)

Date: 2026-09-19. Status: **orientation, pre-interview**. No production change was made. Builds on the 2026-09-18 reconnaissance in [docs/research/open77/](../../research/open77/README.md); today's new evidence is in [evidence/2026-09-19/](../../research/open77/evidence/2026-09-19/README.md).

Baseline pinned today: OPEN//77 newest published build **2.31.13+op77.78** (unchanged since yesterday; docs index regenerated 2026-09-19, +15 cards/+1 guide at the same build); Freeroam/Race HEAD still **d3f2a7f** (2026-09-09), so yesterday's Race analysis stands unchanged. NCM payload: 7 Lua files changed since yesterday's hash inventory (Spec Field / liveries work, checkpoint-06), `modules/liveries.lua` is new.

---

## 1. Reconciling yesterday's research with today's platform

| Topic | Yesterday (2026-09-18) | Today (2026-09-19) | Verdict |
|---|---|---|---|
| Platform build / Race source | .78, d3f2a7f | .78, d3f2a7f | **Unchanged.** Recon, matrix and experiment plan remain valid. |
| Vanilla traffic / player street cars | "ordinary local traffic is not canonical"; setPerformance card: adoption "does not exist yet" | `Open77.vehicles.adopt` + `setAdoptPolicy` exist since **.67** (driver-shape 6 m / any 60 m, per bucket). The vehicles guide's *closest* section still says adoption does not exist. | **Stale guide paragraph; newer API.** A player's own vanilla car *can* become canonical at the point they stand at it. Fleet adoption of traffic still does not exist. |
| Vehicle appearance variants | Not covered | `create{appearance=}` / `setAppearance` (needs `world.vehicles.appearance`); variant is not server-validated, resolved on each client from the entity template | **Straightforward (C).** This is exactly the RB15 livery mechanism (`appearanceName`) — NCX liveries replicate natively **if** clients have the archive. |
| Garage persistence | Not covered | `getProperties/setProperties` round-trip is a documented contract (record, appearance, paint, damage, performance); position deliberately excluded | **Straightforward (C)** for persistent garages. |
| AI speed | "0.5–55 m/s" noted | Confirmed hard cap **55 m/s = 198 km/h**, in `setSpeed` and every drive task; behaviors normal/cautious/aggressive; 64 route points; "fleet-scale not guaranteed"; **no headless physics** | **Incorrect previous assumption in our vision:** platform-AI Formula cars cannot lap at Formula speed today — that is category **A** (platform change), not B. Street-class AI ≤198 km/h remains **B**. |
| Telemetry richness | "server motion is owner-reported and less rich than client drivetrain data" | RPM, max RPM, gear, throttle, brake, steering, slip, suspension forces ride on every owner motion sample; the **server validates their bounds**; observers read them in client snapshots. The server Lua snapshot field list does not include them. | **Partly superseded / unresolved:** data crosses the wire and the server sees it; whether server Lua can read it is an E8 question. |
| Checkpoint validation primitive | "platform supplies positions/authority, not a validator" | `Open77.zones.containsPlayer/playersIn` (server) with polygon / oriented box / sphere / entity-attached shapes and a Minkowski *grace*; gamemode contract: "re-derive every client-reported condition", "held for N seconds" | **Better than assumed for geometry (C)**; ordered progress, direction, timing and ties are still NCM work (D). |
| Required mods trust | "server-required mods can be installed and checked" | **Unverified packages may contain inert data only** (`.archive`, `.xl`, `.tweak/.yaml`, engine INI). CET Lua, `.reds`, `.dll` are refused unless that exact SHA-256 is verified. Redistribution is a separate axis → player-fetch. Indexed loaders (ArchiveXL, TweakXL, Codeware, CET) are free. | **Decisive new constraint** on *secured* servers (an *unsecured* server may require executable content after explicit player consent — correction 2026-09-19, see 03_PACKAGING_AND_COLLECTION.md). NCM Online cannot ship as "the CET mod + redscript HUD" through the world layer. It must be an OPEN//77 *resource*; only NCM's inert archives/tweaks ride as mods. Manual Transmission (CET Lua) cannot be required unless verified; RB15 archive is inert but its redistribution is the author's call (player-fetch likely). |
| Client Lua reach | "client dependency imports … explicit platform contracts" | Client resources see only the `Open77.*` surface (92 namespaces); engine RTTI / `Game.*` / TweakDB writes are reachable only from the privileged `open77_debug` resource | **Confirmed hard boundary.** `ai_vehicles.lua`, `telemetry.lua`, `tuning.lua`, `ink_hud.lua`, `mappins.lua`, all `ui_*.lua` cannot be ported — their *jobs* move to platform primitives. |
| Event bus semantics | "kernel guide says local; server API says host-wide queued" | gamemode-kernel guide (current) says "`TriggerEvent` remains local to a VM" | **Still unresolved**; E0 probe stands. Design assumes local-only. |
| Instancing scale | buckets exist | Deathmatch reserves 80+ buckets (lobby 4100, FFA 4200–4231, arena 4240–4287); `maximumPlayers` schema 1..1024; per-bucket time/weather (`Open77.environment … bucket`), per-bucket `crowd/traffic/police` density, `world.clearArea` | **C.** Concurrent events are a bucket-range choice. |
| Vanilla traffic across players | not analysed | Traffic is REDengine population **spawned per client**; "two players on one corner each describe their own" car; only server-owned vehicles are shared | **New finding, load-bearing:** traffic during a human race is *different for every driver*. Synchronized vanilla traffic is category **A**. Shared obstacles must be server-spawned. |
| Broadcast / spectator cameras | not analysed | `Open77.remoteCamera.*` and provider `open77_remote_camera` documented "from .82"; natives exist on `main` only; also `players.setModel` (server-owned NPC body for a player) and native map tabs on `main` | **B / not yet released.** The platform is building the broadcast direction; do not depend on it for early milestones. |
| Operator configuration | not analysed | `Open77.tunables.declare/set/promote` (round-boundary promotion), Warden admin panel, ACL `command.*`, `Open77.http.listen` inbound routes (since .73) | **C.** Server-operator policy and a results/stats endpoint have native homes. |
| Reference implementations | Freeroam/Race (PolyForm-NC) | + **open77-rp-examples** (MIT, 35 resources: SQL wallets, garage with `getProperties`, identity, live tunables, WebUI HUD) | Useful MIT reference for persistence/economy/garage patterns; not a racing reference. |
| Quick Race consequence discrepancy | found | unchanged | Still a SP contract bug to playtest; must not become the online contract. |

Net: yesterday's architecture hypothesis (shared domain core + SP adapter + OPEN//77-native online host) is **strengthened**, not weakened. What changed is *how strict* the boundary is (trust cap + no RTTI on clients) and *which ambitions are platform-limited* (AI speed, per-client traffic, unreleased cameras).

---

## 2. What NCM already has that should survive and be shared

Measured coupling of the current payload (engine refs = `Game.` / `TweakDB` / `DynamicEntity` / `ImGui`; registry refs = `MTE.`):

| Layer | Modules (lines) | Engine refs | Registry refs | Disposition |
|---|---|---|---|---|
| **Motorsport vocabulary & rules** | `event_definitions` (275), `grid_solver` (893), `hype` (310), `heat` (246), `checkpoint` (152), `records` (166), `knockout_circuits` (353), `routes` (539), `roots` (701) | 0 | 0–3 | **Extract as-is into `ncm-core`** with injected time/RNG/store. |
| **League / population / career** | `roster` (1769), `championships` (1631), `careers` (853), `management` (629), `ambient_races` (1406), `safety_rating` (416), `metrics` (395), `race_telemetry` (1441) | 0–3 | 3–31 | **Extract with identity/ownership rework**: replace `Careers.active()`/literal `"player"`/`"V"` with explicit competitor + ledger IDs; keep formulas, seeds, migrations. |
| **Narrative / economy** | `betting` (1227), `fan_engine` (881), `contact_events` (1092), `parts` (2053) | 0–6 | 13–17 | **Extract rules; rewrite effects.** `Game.AddToInventory` and JSON saves become server ledger writes. |
| **Data packs** | `nodes*`, `default_roots_pack`, `circuits`, `tracks`, `factions`, `vehicle_pool`, `parts`, `vehicle_slot_profiles`, `contact_event_archetypes`, liveries manifest | 0 | 0 | **Share verbatim** (versioned, hashed). |
| **Race orchestration** | `racing` (7801), `knockout` (1168), `race_commands` (3882) | 40 / 3 / 2 | high | **Do not port.** Mine for *semantics* (state machine, readiness gates, rolling-start envelope, drag lanes/straightness, sequence progression, finish resolver, DNF grace, spec-field lineup) and re-implement as server heat instances. |
| **Engine adapters** | `ai_vehicles` (6616), `telemetry` (531), `tuning` (708), `ink_hud` (524), `mappins` (223), `phone_bridge` (469), `persistence` (268), all `ui_*` (~7.9k), `.reds` HUD/journal | 13–651 | — | **Replaced by OPEN//77 primitives online; untouched in SP.** |

Roughly **15–17k lines** of NCM are engine-free domain logic and data — the shareable core is real, not aspirational. The other ~37k lines are either the SP host (keep) or SP engine adapters (replace online).

Specific mature behaviours worth preserving as *specification* even where code is rewritten: five-light countdown phases (`getCountdownPhase`), rolling-start pace band and violations, side-by-side/drag lane ordering and straightness penalty, standing-start readiness gates, deferred grid formation, quali → grid ordering, finish resolver with explicit `finishMode` provenance, near-finish DNF grace, knockout elimination by checkpoint interval, safety-rating incident chaining (`deltaV` buckets, chain timeout, SR delta bounds), championship rulesets per tier with faction scoring modes, box-score envelope, roster lifecycle/momentum/tier pressure, ambient schedule windows, hype multiplier, spec-field one-make lineups with per-entry livery.

---

## 3. What OPEN//77 provides that NCM must not reinvent

| Concern | Platform primitive (build .78 unless noted) | Category |
|---|---|---|
| Identity | Durable `userId` (Master-certified Ed25519), per-session `playerId`, verified display name; `onPlayerConnecting` deferrals, whitelists/bans | C |
| Join / readiness | Signed resource-set download before world load; `Open77.ready.hold/participate/release`; `onPlayerReady` | C |
| Networking | `RegisterNetEvent`/`TriggerClientEvent`, `Open77.net.register/callAwait` promise callbacks (48 KiB, 32 args), `source` is platform-derived | C |
| Replicated state | State bags: global / player (bucket-visible) / entity (viewer-set-visible); 64 keys, 16 KiB per bag; deltas per tick | C |
| Persistence | `Open77.database` (MariaDB, oxmysql-compatible, `transaction`, `ready`), `Open77.io` atomic JSON, `Open77.kvp` compare-and-set, `Open77.state.save` (64 KiB reload stash) | C |
| Canonical vehicles | `create/update/remove/setTransform`, `appearance`, paint, damage channels, `getProperties/setProperties` round-trip, seats ledger (`warpPlayerIntoVehicle`, `taskPlayerEnter`, exit lock), `setFrozen`, `setPerformance` ceilings, `adopt` | C |
| Authority | Physics lease with `physicsOwner/steward/aiDriven/epoch/leaseMs`; `requestAuthority` (request, never steal); server validates motion bounds, epoch, monotonic tick, travelled distance | C |
| Vehicle AI | `attachDriver` (driverless or NPC), `driveTo/followRoute/follow/chase/joinTraffic/setSpeed/setBehavior/stop`; events waypointReached/arrived/blocked/failed; simulated by one nearby ready client | B (racing use), A (>198 km/h, headless) |
| NPCs | `Open77.npcs.create{record, appearance, …}`, tasks, behavior, leased simulation; `players.setModel` on `main` | C / B |
| Instancing | Routing buckets: player/entity moves, lockdown modes, per-bucket population `crowd/traffic/police`, per-bucket time/weather, `clearArea` | C |
| World queries / zones | `Open77.zones` (polygon/box/sphere/entity-attached, grace, server `containsPlayer/playersIn`), raycast/ground height/district on client | C |
| Presentation | WebUI pages (`web_ui_page`, transparent overlays, `setConsumedKeys`), `open77_uikit`, `open77_notifications`, `open77_worldui` markers, `Open77.blips`, native-HUD hiding, `Open77.map` (client), package audio, screen transitions | C |
| Travel | `Open77.players.teleport` with bucket change + fade + settle promise | C |
| Operator surface | `Open77.tunables` (round-boundary promotion), Warden (mods, players, ACL), `RegisterCommand` + `command.*` ACL, `Open77.http.listen/request` | C |
| Content delivery | `requiredMods` / `preload_mod` (inert only unless verified), player-fetch for non-redistributable mods, indexed loaders | C (with trust cap) |
| Broadcast | `remoteCamera` (main / ".82"), scripted cameras, photo mode | B (unreleased) |

What OPEN//77 explicitly does **not** provide: a race/league framework (Race is a singleton Freeroam sub-mode, PolyForm-NC licensed — we do not derive from it), racing-grade AI, per-instance handling/tuning beyond speed/accel ceilings, synchronized vanilla traffic, headless physics.

---

## 4. Where the SP/Online abstraction boundary falls

```
┌──────────────────────────────────────────────────────────────────────┐
│  ncm-core  (pure Lua 5.4-compatible, no Game/TweakDB/MTE/os/io)       │
│  vocabulary: events, formats, rulesets, classification, timing math,  │
│  penalties/SR policy, roster & simulation, championships/standings,   │
│  box scores, records keys, eligibility/homologation, grid geometry,   │
│  drag/knockout/endurance rules, hype/payout, progression policy       │
│  data packs: nodes/roots/circuits/factions/vehicles/parts/liveries    │
│  contract: pure functions + explicit state records + effect lists     │
└───────────────┬──────────────────────────────────┬───────────────────┘
                │                                  │
   ┌────────────▼─────────────┐        ┌───────────▼──────────────────┐
   │ ncm-sp (CET, existing)   │        │ ncm-online (OPEN//77 resources)│
   │ racing.lua orchestrator, │        │ server: session/event         │
   │ ai_vehicles, telemetry,  │        │   orchestration (heat          │
   │ tuning, ink HUD, phone,  │        │   instances), authority,       │
   │ JSON saves, ImGui        │        │   ledgers (SQL), identity,     │
   │ — progressively consumes │        │   scheduler, race control      │
   │   core, never depends on │        │ client: WebUI HUD, world       │
   │   online                 │        │   markers, local observations  │
   └──────────────────────────┘        │ platform adapter: Open77.*     │
                                       └────────────────────────────────┘
```

Rules that make this hold:

1. **Core returns decisions and effects; hosts apply them.** No inventory credit, save, notify or spawn inside a rule.
2. **Identity is explicit.** `competitorId` (human: `userId`-backed; fictional: seed-backed), `entryId`, `eventId`, `sessionId`, `seasonId`, `routeId@revision`, `rulesetId@revision`, `serverId`. Literal `"player"`/`"V"` disappears from core.
3. **Provenance is a first-class field**: `physical | simulated | estimated | dnf | disconnected`, per entrant, per session.
4. **Online host owns concurrency.** A *heat instance* = one bucket + one event state machine + one entrant set + one vehicle set. Many can run. The scheduler and the live heat claim an event exactly once.
5. **Platform calls live in one adapter module** so preview churn has a small blast radius.
6. **SP stays shippable at every step.** Extraction is validated by frozen fixtures from current SP behaviour; SP consumes core one slice at a time under its existing playtest gates.

Loading: core files are plain Lua chunks that both CET (`require`) and the server manifest (ordered `shared_script`) can load without a `require` assumption — one small loader shim per host.

---

## 5. Extraction vs adaptation vs replacement

| NCM system | Online disposition | Notes |
|---|---|---|
| Race state machine / lifecycle | **Re-implement** (server heat instance) using NCM's phases as spec | CONFIG→PRERACE→QUALI→COUNTDOWN→RACING→RESULTS survives as vocabulary; per-entrant states added |
| Checkpoints / progress / finish | **Replace** SP radius checks with server zones (oriented-box gates, grace) + NCM ordered-progress/direction/tie policy | Reference Race's endpoint-inside bypass is a regression case to avoid |
| Timing / gaps / classification | **Extract** arithmetic; **rewrite** clock source (server monotonic) | NCM `getGapText`, live standings, `_buildResolvedResults` semantics reused |
| Qualifying / grid order / grid geometry | **Extract** `grid_solver` + `_sortFieldByQuali`; **adapt** spawn to canonical vehicles + forced seats + freeze | Rolling start envelope becomes a server rule with "held for N s" evaluation |
| Five-light start | **Extract** phase math; **replace** presentation with WebUI + package audio | Jump-start detection server-side via zone/motion |
| Drag (lanes, straightness, official time) | **Extract** rules; **adapt** path deviation from server motion samples | |
| Knockout / endurance / sequences | **Extract** rules; **re-implement** progression on server | Per-participant knockout is new work (SP tracks AI via checkpoints too) |
| Physical AI (`ai_vehicles`) | **Replace** with `Open77.vehicles.ai` for street classes ≤198 km/h; **keep** SP native branches in SP only | Racing-line quality, overtaking and fleet size are E4/E5 |
| Projected/statistical AI (`_computeAITime`, `Roster.simulate`) | **Extract** — becomes the server's off-screen and "AI seat" simulation backend | Never substitutes for a human's physical finish |
| Roster / named rivals | **Extract**; visuals via NPC `record+appearance` optional | |
| Championships / box scores / records | **Extract**; storage → SQL; keys gain route/ruleset revisions and provenance | |
| Careers / REP / prestige | **Extract** policy; identity → `userId`-scoped per server | |
| Safety rating / incidents | **Extract** SR math; **adapt** incident source (server-observed motion/contact, not client `deltaV` alone) | Fault attribution remains unsolved everywhere |
| Betting / payout / hype | **Extract** formulas; **rewrite** as idempotent ledger transactions | Gate behind trusted results |
| Parts / tuning | **Extract** inventory/eligibility; **replace** effect model: server `setPerformance` ceilings + class rules; uniform handling INI as a required mod | Per-instance handling upgrades: A today |
| Liveries / spec field | **Adapt**: per-entry `appearance` on canonical vehicles; livery archive as inert required mod | RB15 archive redistribution → player-fetch unless licensed |
| Telemetry / analytics | **Extract** schemas; **rewrite** acquisition (server motion + optional client traces) | |
| Phone / contacts / narrative | **Extract** content and reaction rules; **replace** transport (private targeted events, not quest facts) | |
| CET UI / ink HUD / mappins | **Replace** with WebUI + worldui + blips | |
| Settings | **Split** operator tunables (server) / player presentation prefs (client kvp) | |
| Persistence | **Replace** JSON stores with SQL ledgers; packs stay files | |

---

## 6. Important technical uncertainties

| # | Question | Category | Gate |
|---|---|---|---|
| U1 | Server-side ordered gate acceptance under real replicated motion: latency, tie policy, teleport/replay resistance | D (engineering) + B | E2 |
| U2 | Grid formation with 20 canonical vehicles + forced seats + freeze; cleanup under disconnect/restart | B | E3 |
| U3 | Platform AI on a real NCM course: path quality, elevation, stalls, handover, fleet size, observer FPS | B | E4/E5 |
| U4 | AI Formula cars at Formula pace | **A** (55 m/s cap) — request platform change; meanwhile AI seats in NCX are simulated | — |
| U5 | Mixed human + AI timing without provenance leaks | B | E6 |
| U6 | Durable idempotent settlement (replay, concurrent finalizers, DB outage) | D | E7 |
| U7 | Server Lua visibility of drivetrain fields (RPM/gear/inputs) and their trust; incident detection from server motion | B | E8 |
| U8 | Performance ceilings as class balance; client-local override precedence; uniform handling INI effect | B | E9 |
| U9 | WebUI HUD at 20 entrants, world markers on stacked roads, private narrative delivery | D | E10 |
| U10 | Off-screen league simulation at NCM roster scale within host budgets; catch-up semantics | D | E11 |
| U11 | Core extraction cost vs clean re-implementation per module | D | E12 |
| U12 | ~~`TriggerEvent` local vs host-wide~~ **resolved 2026-09-19: host-wide, queued (E0 part B)**; server export lifecycle across resource reloads still open | C / B | E0 |
| U13 | Which NCM Collection mods are verifiable/redistributable (RB15, MT, IWN braking patch, NCM archives) | D + external | E0 |
| U14 | Spectator/broadcast: remote cameras unreleased; in-bucket spectating as non-entrant works today | B | later |
| U15 | Per-client vanilla traffic makes "traffic on" street races non-deterministic across humans | **A** for sync; D for server-spawned shared obstacles | design decision |

---

## 7. What NCM Online appears capable of becoming

Grounded in C-category primitives plus NCM's domain code, without depending on B/A items:

- **One persistent Night City motorsport server**: free-roam paddock bucket(s) with player-owned/rented canonical vehicles; organized events spun off into isolated instances (own bucket, own time/weather, population policy per format); many concurrent events; results settled once into SQL; public standings, box scores and records served by the resource itself (WebUI + HTTP).
- **Every NCM discipline with human fields**: circuit, point-to-point street (Tip-to-Trench-style long routes included), Formula/NCX single-make grids with per-entry liveries, street cars and bikes by class, drag with lanes/straightness, endurance sequences, knockout eliminations, vehicle-exchange events (server reassigns canonical vehicles between stints), qualifying and race-weekend session structures, standing/rolling/side-by-side starts with five-light countdown.
- **Persistent sporting identities**: `userId`-backed drivers with per-server careers, REP/prestige, SR, records; teams/factions with membership snapshots per event; seasons, schedules, standings; fictional roster drivers coexisting with humans in the same standings via explicit provenance.
- **A living league between sessions**: NCM's ambient scheduler and roster simulation run server-side; fictional events settle statistically; humans can promote/enter scheduled events.
- **Race control and spectating**: an in-bucket race-control role (start/abort/penalties via ACL commands and a WebUI panel), spectators as non-entrants in the instance; broadcast cameras when the platform ships them.
- **AI where it works**: platform AI for street classes on validated routes and measured fleet sizes; statistical AI seats everywhere else — never silently mixed.
- **Operator configuration**: tunables for economy, formats, eligibility, event calendar; content packs (routes, rulesets, liveries) versioned and hashed; NCM Collection compatibility declared per server.

What it cannot become on .78 without platform change: physically raced AI Formula fields at pace, races on an empty server, synchronized vanilla traffic, per-car handling upgrades replicated per instance, in-game broadcast camera feeds.

---

## 8. Assumptions in the current vision the evidence does not support

1. **"Large fields of physical AI Formula cars" is category B.** It is **A** at Formula speeds (55 m/s AI cap) and **B** only for street classes. Plan NCX seats as human + simulated-AI; treat physical AI as a street-class feature to be measured.
2. **"OPEN//77 is substantially more than a player-sync layer."** True for identity, persistence, vehicles, instancing, UI. **Not true for motorsport**: there is no race framework to build on (Race is a small NC-licensed Freeroam sub-mode) and AI is destination-following, not a racing controller.
3. **"NCM Collection compatibility" as a required-mod set.** Only inert content can be required unverified. Every CET/redscript/DLL component (NCM's own HUD/journal, Manual Transmission, the IWN braking patch, RB15's CET helpers) needs hash verification or is excluded from the online client. Online NCM's own runtime must be an OPEN//77 resource.
4. **"World traffic as part of the sporting environment."** Vanilla traffic is per-client; it cannot be a fair shared obstacle. Shared traffic must be server-spawned AI (limited, needs simulating clients) or the design accepts per-driver chaos in unranked street formats.
5. **"Existing single-player implementation details" as the online race loop.** The 7.8k-line orchestrator and 6.6k-line AI module are unportable by construction (no RTTI on clients). They are a specification source, not code to lift.
6. **Broadcast/presentation "eventually"** is right — but the primitive is unreleased, so no early milestone should depend on it.
