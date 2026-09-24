# OPEN//77 reconnaissance

Checked **2026-09-18**. Static source/document inspection and read-only official MCP queries; no server, account, multiplayer client or gameplay experiment was run. This document distinguishes API availability from demonstrated race reliability.

## Evidence baseline and important corrections

- Official documentation: [OPEN//77 docs](https://open2077.net/docs). Developer Preview requires approved access; advertised client baseline is Windows, Cyberpunk 2077 2.31 and Phantom Liberty. Dedicated servers support Windows/Linux without a game installation. Access, downloads and these requirements must be rechecked before deployment.
- Actual hosted MCP queried at `https://mcp.open2077.net/mcp?build=2.31.13%2Bop77.78`. Its build response reports **2.31.13+op77.78**, newest publication 2026-09-17, documentation synchronization 2026-09-17 and index generation 2026-09-18. See [captured build response](evidence/mcp-build.txt). This pins a documentation index, not a locally installed/tested server.
- Public Race source is now a **Freeroam submode**, not necessarily the standalone resource described by older guides. Inspected [Freeroam commit d3f2a7f](https://github.com/Open2077/freeroam/tree/d3f2a7f96ea3b25a614c0f6892798429d8406b69), manifest version 0.7.0. Race entered Freeroam in 0.6.0; the legacy alias remains. Record both engine build and resource commit in any experiment.
- Do not use FiveM knowledge as an API specification. Similar function names conceal different execution, permission and physics models.

## Resource and execution model

Resources declare ordered client/server/shared scripts, dependencies, permissions and UI assets in `open77.lua`. Lua 5.4.8 runs in an isolated VM per resource. Shared scripts execute separately; they do not share mutable state across machines. Server Lua lacks ordinary `require`, `os`, `io`, `debug` and `package`; load domain files in manifest order and expose a resource namespace. Client dependency imports and cross-resource exports have explicit platform contracts. NCM's existing CET loader/global environment cannot simply be installed as a server script. See [resources](https://open2077.net/docs/server-resources), [server API](https://open2077.net/docs/server-api), and [Lua runtime](https://open2077.net/docs/resource-runtime).

Network handlers receive platform-derived `source`; do not accept player identity, final time, payout or inventory from payloads. Current server API describes bounded messages (48 KiB, 32 arguments), asynchronous tasks, host-wide queued `TriggerEvent` and local `TriggerLocalEvent`, and cross-resource exports with copied values/caller boundaries. Design narrow commands and bounded read models, not broadcasts of the whole roster/save. Server task/handler limits also argue for batched simulation rather than one permanent task per fictional driver. [Server API](https://open2077.net/docs/server-api).

State bags are transient replication, not a database. Server writes should own race state. A player-scoped bag is not automatically private: visibility can include other players in its bucket. Send bets, private messages and account data through targeted authorized responses. Global/entity scopes suit public heat status and interested observers. [State bags](https://open2077.net/docs/state-bags).

Current runtime guidance gives client budgets of 96 MiB, 1.5 million instructions per resume and 6 ms host time; earlier guidance used smaller limits. Measure the target build instead of treating these as a permanent performance budget. NCM roster catch-up, contact generation and full-table UI updates should be profiled and chunked. [Lua runtime](https://open2077.net/docs/resource-runtime).

## Players, vehicles, AI and trust

| Surface | Verified/documented contract | NCM implication |
|---|---|---|
| Players | Current server APIs include enumeration, readiness, canonical position, persistent identifier and teleport; session IDs are transient | Persist account identifiers, map connection IDs temporarily, require readiness before grid operations |
| Vehicles | Server creates canonical network vehicles; snapshots expose identity, transform, motion, occupants, damage/flags and authority | Replace CET/Codeware entity spawning online; do not attach network semantics to arbitrary native spawned cars |
| Synchronization | A client physics owner reports motion; server ownership of entity/rules is distinct from server physics | Position is stronger than a submitted finish time but not independently simulated proof; validate continuity and vehicle/bucket identity |
| Performance | `Open77.vehicles.setPerformance` server API since .67, permission `world.vehicles`, sets replicated ceilings | Top speed 0–1000 km/h (0 means none), acceleration scale >0 through 1, taper 3–200 km/h; cannot translate arbitrary horsepower, tire, suspension or gearbox upgrades |
| Control | Client `setControlLock` / `setFrozen` use `vehicles.performance` | Useful for staging; a cooperative client lock alone is not an anti-cheat boundary |
| Instances | Routing bucket APIs separate player/entity interest and race spaces | Model heat ownership/cleanup explicitly; changing a bucket does not create an autonomous physics server |

Sources: [identity](https://open2077.net/docs/identity), [vehicles](https://open2077.net/docs/vehicles), and routing/player entries in the [server API](https://open2077.net/docs/server-api); exact method availability additionally checked in official MCP cards. Server vehicle speed is in m/s, with speedKph where provided; never conflate units. Client telemetry cards expose more signals than the server vehicle snapshot. A missing physics owner can leave zero/stale motion; a zero must not automatically mean a stalled car. The client performance card explicitly says a local instance profile can override a replicated profile. Audit installed resources and test this precedence; server selection of a cap does not independently enforce honest physics.

**AI is documented, but distributed rather than headless.** Server AI tasks select a nearby ready client to simulate, with authority leases/epochs and bucket constraints. No eligible client means no physical progress. `Open77.vehicles.ai.followRoute` accepts 1–64 points, loop/speed/behavior/arrival radius/timeout and emits waypoint/arrival signals. Drivers may be attached; visible NPCs have resource/bucket/task restrictions and reserve a seat. Speed is limited to 0.5–55 m/s. Autonomous vehicles exclude AV/Basilisk cases. Normal/cautious/aggressive behavior is coarse, not a racing skill model. Published handover validation is narrower than a multi-car competitive field. [Vehicle AI](https://open2077.net/docs/vehicle-ai).

MCP places `followRoute` at .57, while the guide refers to the broader AI feature at .54. Use the newer requirement conservatively. API points are destinations, not a guaranteed road spline. NCM's race skill, setup and personality cannot be mapped one-to-one onto those controls. NPC existence, seat replication, overtaking, contact physics, elevated-road selection and large-grid pacing remain experiments. Off-screen NCM result simulation does not depend on this physical AI path.

NPC creation accepts Character records with server `world.npcs`; client inspection uses `npcs.read`. Creation returns an ID before the native body is ready. Records/assets must exist on observing clients; a dedicated server cannot validate their local TweakDB content. NPCs stream within bucket/radius and use leased simulation; task channels and behavior controls exist, but a chosen character record can bring unsuitable native combat behavior. NCM named rivals need a logical identity separated from an optional validated visual record. [NPCs](https://open2077.net/docs/npcs), [NPC behavior](https://open2077.net/docs/npc-behavior).

## Storage, hosting and lifecycle

Three different persistence options are available: resource KVP (typed values, compare-and-set/increment), scoped `Open77.io` (including atomic JSON writes), and asynchronous MySQL/MariaDB with parameterized calls and multi-statement transactions. Database access requires configuration plus `database.access`; ordinary Lua `io` being unavailable does not mean files are unsupported. Prefer files for immutable course packs, transactional storage for accounts/escrow/finalized results. KVP compare-and-set is not a multi-ledger transaction. Entity `persistent` flags must not be interpreted as disk persistence. [Database](https://open2077.net/docs/database), [server API](https://open2077.net/docs/server-api).

Deployment uses the published dedicated server, `server.jsonc`, resource dependencies and a server license key. Start scripts support Windows/Linux; public hosting needs reachable configured ports and resource HTTPS, protected signing keys, backups and logs. Resource bundles use signed/hash-verified distribution and keep server scripts off clients. Pin the server binary, resource revision, schema and mod pack together. Resource restart is an expected lifecycle: settle/refund interrupted heats, clean entities, release locks and resume durable schedules. [Host a server](https://open2077.net/docs/host-a-server), [server resources](https://open2077.net/docs/server-resources).

Server-required mods can be installed and checked before client startup. This provides packaging, not proof that NCM's native quest/phone hooks coexist with OPEN//77's world changes. Distinguish platform mods, server world mods and personal single-player mods. Test a minimal online package before adding NCM archives/redscript/handling dependencies. [Mods](https://open2077.net/docs/mods).

## UI, props and development

Platform surfaces include resource WebUI, native/world UI, anchors, markers/blips and replicated props. These permit a dedicated race panel and world course treatment without carrying all CET/ink UI code. Race demonstrates next-checkpoint native rings, GPS and a web HUD; it does not establish a finished physical barrier/arch system. Remote-WebUI guidance includes development validation that was not yet CDN availability at the time described: test what the pinned preview actually distributes. [UI kit](https://open2077.net/docs/ui-kit), [world UI](https://open2077.net/docs/worldui), [props](https://open2077.net/docs/props).

Use resource logs/status, a minimal reproducible resource, schema/manifest validation and two distinct clients. Restricted execution/admin tools have ACL boundaries; never expose them through normal player events. Agent testing guidance describes a privileged local harness, not permission to run remote commands on an arbitrary server. [Debug runtime](https://open2077.net/docs/debug-runtime), [agent testing](https://open2077.net/docs/agent-testing).

## Official devkit/MCP for the next agent

[Official agent guide](https://open2077.net/docs/agents) and [open77-devkit](https://github.com/Open2077/open77-devkit) provide API search/cards, guides, permissions/events/schema data, change/build inspection and local resource tooling. The devkit is MIT licensed. Hosted MCP was actually contacted using JSON-RPC `initialize`, `tools/list`, `tools/call`; key calls were `open77_build`, `open77_search`, `open77_api` and `open77_guide`. No package, global agent configuration or privileged administration integration was installed. Node 24.20 was available in this environment.

Use the pinned endpoint above and query `open77_api` with `{ "name": "Open77.vehicles.ai.followRoute", "runtime": "server" }`, then inspect the actual return before coding. For a new deployment also query the unpinned build, compare changes and deliberately select a tested version. [query_open77.ps1](query_open77.ps1) is the read-only query helper; local PowerShell policy blocked direct script execution during research, so equivalent inline requests were used. Do not change global execution policy for it. The agent-config initializer can edit multiple clients' settings; it was not needed for this assessment.

Evidence includes selected [API metadata](evidence/api-availability.json) from the official devkit index and the pinned build response. The index was fetched from repository main and is **not** an independently versioned server source checkout; requery full pinned cards before implementation. Temporary downloaded guide/card bundles are not required to continue from this report.

## Documentation conflicts to carry forward

| Conflict | Working interpretation / required check |
|---|---|
| Older writing-a-gamemode material lacks server exports/player enumeration and recommends kill/respawn travel | Current .78 cards expose these APIs and teleport; do not reproduce old workaround without testing |
| Kernel guide calls TriggerEvent local; current server API says host-wide queued | Prefer current runtime-specific card and probe event delivery/order with two resources |
| Teleport description names a permission while metadata reports none checked | Do not assert permission enforcement either way; exercise denied/allowed manifests and report upstream |
| AI guide feature date versus followRoute card date differs | Pin .78; method-level minimum .57 until clarified |
| Preview/UI documentation can describe validation before distribution | Confirm installed feature through a small resource, not page presence |
| Generic Race documentation describes standalone deployment | Inspect Freeroam's pinned manifest and Race modules; do not build against obsolete paths |

## OPEN//77 Race: implementation, not feature inference

Source links below are pinned to the inspected commit. Shared Freeroam permissions/dependencies are not evidence that Race uses every available API. The repository is **PolyForm Noncommercial 1.0.0**, unlike the MIT devkit; review [its license](https://github.com/Open2077/freeroam/blob/d3f2a7f96ea3b25a614c0f6892798429d8406b69/LICENSE) before deriving/distributing code. Independently implementing ideas is distinct from copying source/assets.

| Concern | Actual behavior found |
|---|---|
| Session/lobby | Freeroam terminal/panel and queue feed one active `heat`; not a concurrent multi-league scheduler |
| Course data | Schema v2 JSON under resource `data/race/courses`; editor/import courses rather than bundled samples; sprint/circuit, ordered checkpoints, explicit grid slots, one selected vehicle model |
| Course constraints | Up to 96 checkpoints, 32 grid slots; lap count 1–99, sprint one lap; radius 2–30m; eight-model allowlist. Grid positions need spacing checks. Defaults are configuration, not engine capacity guarantees |
| Editor | ACL-gated session, expiry and server-side save validation; captures server-known vehicle/player position, accepts heading input, uses atomic JSON writes |
| Grid | Seat/spawn/readiness polling, minimum loading interval, timeout DNFs, then countdown. All entrants use the course's chosen model |
| Timing | Server monotonic timer; race start and accepted finish timestamps, current/best lap; sampling quantizes finish order/time |
| Ranking | Finished entrants first by finish order; active standings use completed checkpoints then next-checkpoint distance and grid tie-break; unresolved/disconnected categories follow |
| Results | Heat result panel then cleanup/return to prior position/bucket; in-memory heat statistics |
| Persistence | Courses/settings persist. No durable race-result/account progression/season store found in inspected Race paths |
| AI | No NPC/vehicle-AI grid path found in Race; platform AI availability is a separate capability |
| Leagues/economy | No championship, career, roster, betting or ambient racing system found in inspected Race files |
| Balancing | Same selected car for a heat. No Race call to per-vehicle setPerformance found; manifest permissions do not imply a tuning model |

Sources: [Race README](https://github.com/Open2077/freeroam/blob/d3f2a7f96ea3b25a614c0f6892798429d8406b69/race/README.md), [course validation/storage](https://github.com/Open2077/freeroam/blob/d3f2a7f96ea3b25a614c0f6892798429d8406b69/race/server/courses.lua), [configuration](https://github.com/Open2077/freeroam/blob/d3f2a7f96ea3b25a614c0f6892798429d8406b69/race/shared/config.lua).

Execution trace in [server/main.lua](https://github.com/Open2077/freeroam/blob/d3f2a7f96ea3b25a614c0f6892798429d8406b69/race/server/main.lua): join queue -> `beginGrid` (882) -> `pollGridVehicles` (817) -> `startCountdown` (993) -> `beginRace` (1023) -> `evaluateCheckpoint` (1201) / `acceptCheckpoint` (1156) -> `finishPlayer` (1126) -> `resolveHeat` (1063) -> `closeHeat` (1089). Net checkpoint intent is only a request to re-evaluate canonical position; it cannot directly submit completion. Timed server polling also evaluates progress. Disconnect handlers remove vehicles and mark unfinished membership. Readiness checks include assigned seat and completed forced entry. Finalization and return are session effects, not a durable result transaction.

Default position polling is 100ms, state delivery 250ms; 3-second countdown, 20-second minimum grid loading, 60-second readiness limit, 20-minute race limit and 30-second post-winner window. These choices produce a usable reference flow, but no sub-frame timing guarantee. Multiple same-tick finishers require an explicit tie policy for competitive NCM.

[Checkpoint geometry](https://github.com/Open2077/freeroam/blob/d3f2a7f96ea3b25a614c0f6892798429d8406b69/race/shared/checkpoints.lua) tests a horizontal radius and vertical band, including segment/cylinder intersection to avoid missing a gate between samples. **The current-position-inside branch returns before the maximum-segment-length test.** Thus the 80m swept-segment bound is not comprehensive teleport rejection. It checks ordered progress and bucket but not a directional crossing plane. Test huge jumps into a gate, vehicle switches, stale authority, clock delays and replayed intents before competitive scoring. Existing [geometry tests](https://github.com/Open2077/freeroam/blob/d3f2a7f96ea3b25a614c0f6892798429d8406b69/race/tests/checkpoints_test.lua) were inspected, not executed; no Lua executable was found in the local PATH.

[Client checkpoint presentation](https://github.com/Open2077/freeroam/blob/d3f2a7f96ea3b25a614c0f6892798429d8406b69/race/client/checkpoints.lua) uses native anchors for only the next authoritative checkpoint, matching radius and differentiating finish color. It avoids predicting removal before server acceptance. [Client main](https://github.com/Open2077/freeroam/blob/d3f2a7f96ea3b25a614c0f6892798429d8406b69/race/client/main.lua) and [race WebUI](https://github.com/Open2077/freeroam/blob/d3f2a7f96ea3b25a614c0f6892798429d8406b69/web/race/app.js) combine direction/GPS cues, countdown, status and results. Useful NCM lessons: visible acceptance volume, unambiguous next target, authoritative HUD reconciliation, and a clear staging state. Native rings are not physical props. Config comments explicitly refer to NCM spawn/countdown behavior; this is an observed reference, not a broader claim about shared implementation.

## Adjacent projects

This is a bounded public-feature review, not code/compatibility testing. Current page headers and changelog versions sometimes disagree. See [LANDSCAPE.md](LANDSCAPE.md) for dated capabilities and concrete lessons.

## Status and limits

Completed: current primary API/resource/hosting survey, official MCP query, pinned Race execution/geometry/editor/presentation inspection, adjacent public-page review. Unknown: runtime AI scale and handover, cheating resistance, telemetry freshness, native-mod compatibility, precise permission enforcement and actual access/deployment. Next: review [architecture options](OPEN77_ARCHITECTURE_OPTIONS.md), then run [ordered experiments](OPEN77_EXPERIMENT_PLAN.md). No port architecture is validated by documentation alone.
