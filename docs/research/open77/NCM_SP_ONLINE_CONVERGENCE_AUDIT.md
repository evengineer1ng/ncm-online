# NCM Single Player <-> Online convergence audit

> **STATUS: CURRENT RESEARCH** - architectural reconnaissance as of 2026-09-24. This document is advisory. It does not change the authority of `docs/ncm-online/INDEX.md` or `DECISION_RECORD.md`, and it authorizes no runtime, schema, save, API, deployment, or gameplay change.

Date: **2026-09-24**. Scope: the released Single Player payload in `ncm-localized/`, the checked-in Online implementation in `ncm/core/` and `ncm/online/`, schema through migration 027, prior live evidence recorded in the repository, and current official OPEN//77 documentation. This was static analysis plus prior recorded observations. No game/server experiment was run.

## Executive conclusion

**"One Night City Motorsports, multiple execution contexts" is technically and conceptually defensible, but only if "one" means a common vocabulary, content lineage, and evidence format - not one save, one economy, one authority, one physics implementation, or one mod list.**

The strongest evidence is already in the code. Online's `data.roots` says it is derived from SP's `default_roots_pack.lua v1.2.0`; both carry the same ten root IDs and names. Online's vehicle pool is descended from the same TweakDB-record vocabulary, while `vehicle_catalogue.lua` has already made the crucial improvement of separating a stable conceptual `vehicleKey` from runtime records and persistent `assetId`s. Online's pure `ncm-core` also already defines SP/Online result origin and physical/simulated/estimated entrant provenance. Convergence is therefore not a hypothetical merger of unrelated products. It is an existing, incomplete lineage with manual copies and unfilled contracts.

The correct long-term shape is broader than a single shared library:

1. **NCM vocabulary and authored content** - manufacturers, conceptual machine/model IDs, route/course definitions and revisions, sporting terms, event templates, presentation metadata, and asset requirements.
2. **NCM evidence envelopes** - results, observations, configuration descriptions, and proxy references with explicit execution context, authority, source world, revision, and trust.
3. **Execution adapters** - SP/CET for local spawning, physical AI and local persistence; OPEN//77 client/server resources for multiplayer authority, replication, canonical vehicles, SQL settlement, markets, and organizations.
4. **Sovereign world ledgers** - ownership, money, markets, custody, odometer, wear, components, knowledge earned in-world, championship consequences, and corrections. These remain owned by the world that can enforce them.

This decomposition preserves the best reason SP exists: locally simulated AI racing, offline practice and experimentation. It preserves the best reason Online exists: a durable shared world with authoritative settlement and serialized assets. It also permits honest bridges: an Online machine can be represented by a read-only SP proxy; one personal sporting history can show both SP and Online performances; and a common route can be used in both contexts without claiming the resulting times have equal authority or physics.

The immediate risk is not the absence of synchronization. It is allowing historical facts to be written without enough identity and provenance to interpret them later. Route identity, direction, revision, result context, machine attribution, configuration reference, world namespace, content/physics profile and observation source are cheap at creation and expensive or impossible to reconstruct. Endpoint design, global authentication, synchronization, a launcher, and cross-world economics are safe to defer.

This audit does **not** supersede locked decision L50 (two products, one brand/driver identity/lore, not one mod list). The technical finding is compatible with its strongest constraint - separate delivery and runtime authority - while showing that the shared layer can honestly be much richer than branding alone. Any change to that product framing remains an owner decision in the living decision record.

## Evidence and terminology

Confidence labels used below:

- **Code verified**: present in an inspected execution path; not necessarily proven in gameplay.
- **Live recorded**: supported by a repository live-test/bug record.
- **Platform documented**: stated in current official OPEN//77 documentation.
- **Plausible**: compatible with current primitives but not implemented or tested.
- **Roadmap-dependent**: requires a capability described as planned/documented but not available to this build, or a platform change for which NCM has no evidence of delivery.
- **Speculative**: technically imaginable, not promised.
- **Invariant conflict**: would destroy authority, trust, property, or gameplay meaning even if technically possible.

Three identities must not be collapsed:

- **Execution context**: where the activity ran (`sp`, a particular Online world, or a future context).
- **Authority world**: which sovereign ledger owns a referenced asset/fact.
- **Presentation runtime**: the temporary CP2077/Open77 entity that depicts it now.

`Makigai MaiMai #0000001` is a display serial, not a durable cross-world key. A portable reference must at least be `{ authorityWorldId, assetId }`; the ordinal may be shown beside it but cannot substitute for it.

## 1. Current architecture as implemented

### 1.1 NCM Single Player

The working SP payload boots from `ncm-localized/bin/x64/plugins/cyber_engine_tweaks/mods/MT_Ecosystem/init.lua`. It is a large mutable CET application, not a small race plug-in. `init.lua` loads racing, AI vehicles, careers, roster, championships, ambient races, parts, tuning, records, route telemetry, betting, heat, contacts, phone commands, multiple UIs and native presentation bridges into the global `MTE` registry. Lifecycle comes from CET `onInit`, `onUpdate`, `onShutdown`, `onDraw` and overlay events.

The payload contains:

- CET Lua for almost all behavior and JSON persistence under the mod's `save/` directory;
- redscript for HUD, journal, mappins, race runtime/beacons and quest/navigation bridges;
- ArchiveXL archives/XL files and TweakXL YAML, including named-rival content;
- dependencies on CET, RED4ext, redscript, ArchiveXL, TweakXL, Codeware/DynamicEntitySystem, Native Settings, Input Loader and Custom Map Markers.

SP uses the player's current mounted vehicle. `Racing._getVehicleId()` reads its TweakDB record; `Tuning.onVehicleEnter()` resolves the record's drive model and temporarily changes TweakDB flats. NCM itself does **not** currently unlock or register player-owned vehicles in the vanilla garage, and it has no persistent serialized-car identity for the player's vehicle. Its career garage is a parts inventory and per-**record-key** loadout, not title to physical vehicle examples.

Persistence is local, editable JSON. A career gets a time/random-derived `career_*` ID, statistics, last-20 race history, seasons, standings, rivals, garage/parts and narrative state. Separate files hold top-five route records, route/session telemetry, tuning profiles and other systems. This is useful personal state but cannot be made server-authoritative: the player controls CET, files, time, TweakDB, saves and process memory.

SP has three overlapping result products:

- `records.json`: top five times per career and alphabetically canonicalized node pair, containing time, driver name, TweakDB vehicle record and date;
- `career.raceHistory`: the last 20 summaries and their local economy/rep consequences;
- rich per-session telemetry documents with route snapshot, participants, lap/sector timing, incidents, traces, results and per-AI `provenance`/`finishMode` such as live/physical, estimated, projected, simulated or untracked.

The rich telemetry is the best convergence candidate. The legacy record board is not: it intentionally makes A->B and B->A the same board, omits route revision, ruleset, configuration, execution context and trust, and records only the runtime vehicle record.

SP's event model includes quick races, career schedules, deterministic season schedules, championship rounds, knockout/circuit modes, and ambient off-screen races. `event_definitions.lua` already distinguishes event definition fields from runtime state reasonably well, but IDs embed local season/round/endpoints and are not cross-context canonical event-template IDs. Ambient races are statistical simulations; a scheduled ambient event may be promoted into a live player race. Results can therefore legitimately mix physical and simulated entrants if provenance remains visible.

### 1.2 NCM Online

Online is an OPEN//77 resource set, not the CET mod in multiplayer:

- `ncm_league`: server authority for migrations, calendar, entries, sessions, results, standings, telemetry, ownership, markets, production, Machine Knowledge, progression and organization systems;
- `ncm_world`: server/client world integration, identity, vehicle materialization/access, odometer, venues, navigation, WebUI and telemetry capture;
- `ncm/core`: engine-independent Lua modules copied into both resources by the build, covering identifiers, provenance, catalogues, routes/gates, event/race kernels, competition, markets, knowledge and other pure rules.

Online identity separates platform `userId`, durable NCM Driver UUID and per-world profile. The binding is keyed by `server_id`; current code treats that opaque value as world identity and separately publishes `environment`. The same setting is still declared in two resource VMs, and KB-94 proved that disagreement can split identities and assets across nominal worlds. This is a present convergence risk, not an abstract one.

Online machine identity is materially stronger than SP's:

- `vehicleKey`: stable conceptual model;
- `record`: exact TweakDB runtime configuration;
- `vehicleId`: ephemeral live OPEN//77 entity;
- `assetId`: durable serialized physical machine;
- world-scoped immutable production ordinals and lifecycle/odometer history.

Assets can be unowned market stock or owned by a driver/organization principal, transferred, painted, materialized and attributed to entries/results. Entry migration 026 binds a race entry to one `asset_id`; result migration 024 stores `asset_id`, recorded/derived/unknown attribution and a reserved `configuration_ref`. That reservation is exactly the sort of cheap substrate this audit recommends, although nothing writes a configuration snapshot yet.

Online races are server-clocked state machines. Events have real-time entry windows and event instances; sessions progress through forming, grid, countdown, running, finishing and complete/cancelled; gate reports are checked against server-readable position. Results, incidents, ledger effects and telemetry chunks are written to MariaDB. Client telemetry samples at 5 Hz and is batched; the server maintains bounded rings, cross-checks position and falls back to a 1 Hz server read. This is stronger than SP local evidence, but OPEN//77 physics is still client-simulated; "server-authoritative" here means authoritative orchestration, validation and settlement, not headless server physics.

Online UI is OPEN//77 WebUI, state bags, notifications, map/world UI and commands. It does not load SP's redscript/CET UI. Its present external/network surfaces are documented separately in `EXTERNAL_TOOLING_API_AUDIT.md`: NCM registers no HTTP routes; in-game net events, state bags, local events, SQL, logs and console commands are internal or gameplay surfaces, not a public API.

### 1.3 Same names, different semantics

| Name | SP meaning | Online meaning | Convergence implication |
|---|---|---|---|
| Vehicle/machine | Mounted TweakDB record; parts keyed to that record | Conceptual `vehicleKey`, runtime record, persistent `assetId`, ephemeral entity all separate | Share model vocabulary; adapter maps to runtime. Never import SP record ownership as asset title. |
| Route | Root endpoints plus local generated path signature/fallback polyline and optional circuit checkpoints | Root ID currently used as route ID; endpoints plus optional authored intermediate gates | Shared root name is not yet proof of the same competitive course. Require revision/geometry identity. |
| Record/PB | Local top-five board, direction-collapsed by node pair | Per-world best derived from settled session results grouped by route | Aggregate only as provenance-partitioned personal history. |
| Career/Driver | Editable local career ID and saves | NCM Driver UUID bound to a platform identity, with per-world profile | Future association is possible; current identities are not the same and must not be inferred. |
| Garage | Parts inventory/loadout keyed by vehicle record | Title/custody of persistent machine assets plus materialized runtime vehicles | Shared configuration vocabulary possible; economic/property state remains sovereign. |
| AI result | Physical, projected, simulated and recovery-assisted local classification | Human results today; core already has `physicalAI`/`simulatedAI` provenance vocabulary | Share entrant/result vocabulary, not the control implementation. |
| Money | Vanilla inventory money plus local betting/payout logic | NCM ledger, intentionally separate from Freeroam money | Never synchronize or convert implicitly. |
| Discovery | No equivalent epistemic subsystem | Per-driver/per-world discovery plus evidence-bearing Machine Knowledge foundation | Taxonomy/docs may be shared; earned knowledge remains world/context-scoped. |

## 2. What can become a shared NCM definition

### Directly shareable authored vocabulary

These concepts have no inherent world authority and should have one canonical identity even if each runtime receives a generated/adapted representation:

- manufacturer key and display metadata;
- conceptual machine/model `vehicleKey`, aliases and runtime-record mappings;
- route/root ID, direction, course geometry revision/fingerprint, node/gate identifiers and presentation name;
- race/session kinds, entrant backend, finish status and provenance vocabularies;
- event **templates**, disciplines, classes, eligibility language and ruleset IDs/revisions;
- result and observation envelope semantics;
- livery identity and presentation metadata, separate from the runtime record suffix used to realize it;
- documentation-bearing model facts and Machine Knowledge taxonomy;
- content requirements: package/mod identity, version/hash, license/distribution status and per-context adapter support.

The canonical source need not be executable in both runtimes. A small authored data source with deterministic generated Lua projections is safer than forcing CET LuaJIT and OPEN//77 Lua 5.4 to execute one monolith. `ncm/core` deliberately avoids incompatible bit operators and is already tested across interpreters, but it also contains Online economy/world assumptions and cannot simply be relabeled "the shared core" wholesale.

### Shareable source with environment adapters

- Course definitions: common geometry and revision; SP converts to local checkpoints/AI targets, Online to gates and navigation/validation.
- Machine definitions: common `vehicleKey`; SP maps to a locally installed TweakDB record, Online maps to allowed server records and assets.
- Performance/configuration descriptors: portable semantic description plus SP and Online realization reports. Exact equivalence is not assumed.
- Sporting rules: common vocabulary and versioned intent; environment adapters implement timing/gates/penalties and declare deviations.
- AI competitor profiles and statistical simulation: common driver traits, pace/racecraft and result provenance; physical control stays adapter-specific.
- Results/telemetry summaries: common envelope; sampling and authority evidence differ by context.
- Presentation assets/liveries: common identity and metadata; package projection/loading differs and licensing controls distribution.

### Must remain instance- or world-local

A definition may be shared while its instance is sovereign. A championship template can be canonical; one world's season, entries, money, standings and consequences cannot. A model definition can be canonical; title to `assetId X`, its custody, wear and odometer cannot. A market type can be shared; inventory, price, access and supply cannot. The invariant is not "SP and Online are separate"; it is **only the authority able to validate and settle a state may mutate that state**.

## 3. Hard and soft boundaries

### Hard boundaries

- **Online title/custody and serialized-machine biography.** SP can reference or mirror a snapshot, never award, transfer, damage, retire or advance it.
- **Money, ledger, market inventory, production, supply, organization treasury and contracts.** Local play cannot create shared-world scarcity or liabilities.
- **Online odometer, wear, components and engineering progression.** Local motion and local files are not trusted world evidence. A later explicit import process would still be a sovereign Online decision, not synchronization by default.
- **Official Online results, ratings, licence/SR, championship settlement and prizes.** SP results remain local evidence even when the route and represented machine are canonical.
- **World-earned discovery/knowledge.** Reading a global model manual can be shared; discovering an Online market, seeing a serialized Online car, earning ownership knowledge or conducting an Online observation is world evidence.
- **Live runtime entities and state.** CET entity IDs and OPEN//77 vehicle IDs are ephemeral implementation objects.
- **Execution freedoms.** Pause, time manipulation, arbitrary spawn, file editing and local mods are SP capabilities, not defects Online should emulate.

### Soft boundaries

- Route, machine and livery definitions are separate today primarily because of repository history and runtime packaging.
- SP and Online event/rules vocabulary differs, but both already represent races, sessions, fields, grids, timing, results and championships.
- AI physical control is separate because the platforms expose different commands and authority; driver profiles, course intent, simulation and result provenance need not be.
- Player identity is separate because no binding/claim flow exists, not because a person cannot have one NCM identity with multiple context-local careers.
- Mod availability is separate because launcher profiles intentionally isolate World and Solo projections; the same content hash can still be known to both channels.
- UI is necessarily adapter-specific, but presentation vocabulary and data contracts can be common.

## 4. AI racing findings

### How SP physical AI works

`modules/ai_vehicles.lua` creates a physical vehicle and driver NPC separately through Codeware's `DynamicEntitySystem`. It resolves a TweakDB vehicle record or entity template, requests always-spawned/in-view entities, waits for materialization, then mounts the NPC in `seat_front_left`. Mounting has three fallbacks: the mounting facility, `AIMountCommand`, and `MountAIEvent`.

Grid formation is a defensive state machine rather than one spawn call. It solves slots, checks ground/traffic/other vehicles, clears traffic, staggers creation, waits for materialization and mounting, assembles cars, positions them, and only then declares the field ready. Comments and guards show why: spawning into an unstreamed or dense sector can crash the game; high-speed teleport is treated as dangerous.

Driving is issued with native AI commands, primarily `AIVehicleDriveToPointAutonomousCommand`; chase/follow commands support other personalities, while active races force autonomous drive-to-point behavior. Commands are dispatched through vehicle events, AI components or the NPC controller. Profiles derive min/max speed, launch behavior, follow/chase distance and recommanding cadence from tier, personality, racecraft, aggression and hardware. Routes can be split into waypoints and commands refreshed. Stalls are detected and re-commanded.

The race system tracks visible cars by position/speed and line crossing. When streaming loses a car it attempts recovery; classification may fall back to cached progress, projected time or simulation. `Racing._buildResolvedResults()` explicitly stamps `finishMode` as `physical`, `projected`, `simulated` or `untracked`. This is not a flaw to hide: it is the seed of an honest multi-backend result model.

### The high-speed limitation

There are two different ceilings and they must not be conflated:

- **SP:** the local native command accepts authored values above 55 m/s. Current Formula quick-race tuning asks for base 82 m/s and a 95 m/s cap; Hold Your Breath's saved profile asks for base 80 and cap 120. Code comments say the prior base 55 field topped out around 200 km/h and predict ~330 km/h from the new settings. That proves the absence of a syntactic 55 m/s cap in this path, **not** successful 300+ km/h racing. No live PASS was found for a field sustaining those speeds. Native road following, braking/path choice, streaming, collision recovery and the vehicle's own drive model remain likely constraints; the exact limiting mechanism is not isolated.
- **OPEN//77 today:** official `Open77.vehicles.ai` validates speed at 0.5-55 m/s (198 km/h). It requires a nearby ready client to simulate, accepts 1-64 route points and coarse cautious/normal/aggressive behavior, and does not guarantee fleet-scale handover. This is an explicit current API limit.

Thus the owner's practical ~200 km/h observation is consistent with both systems but has different causes. Online NCX-speed physical AI is blocked today by a documented platform cap. SP NCX-speed AI is an unproven local-engine behavior problem despite higher requested values. Neither justifies abandoning SP AI.

### What can cross the boundary

Shareable: competitor identity/profile, course/waypoint intent, grid slot, expected pace model, statistical simulation, finish/DNF vocabulary and per-entrant backend/provenance. Adapter-specific: spawning, mounting, command dispatch, streaming recovery, authority leases and observation.

OPEN//77 physical AI is architecturally plausible for slower or experimental fields today, because the platform supplies server-created vehicles, optional visible drivers and follow-route tasks. It is not suitable evidence yet for NCM's primary Online world: it has a hard speed cap, no headless progress, coarse behavior, unproven fleet scale and no demonstrated racing/overtaking quality. Those are platform maturity constraints rather than proof of fundamental impossibility. Product policy is separate: the reference persistent world may remain human-first even if a third-party NCM server enables AI-heavy races.

The reusable abstraction is an **entrant backend**, not "the SP race system": `human`, `physical_ai_local`, `physical_ai_open77`, `simulated_ai`. A backend reports capabilities and provenance; race policy decides whether it is allowed. Do not force every backend to pretend it supplies the same evidence.

## 5. Online-machine proxies in SP

An SP proxy is useful and conceptually safe if it is modeled as a representation, never a second asset:

```text
executionContext = sp
representationKind = authoritative_asset_proxy
authorityWorldId = <online-world>
assetId = <durable Online UUID>
snapshotRevision/asOf = <what was known when imported>
vehicleKey = makigai_maimai
runtimeRecord/contentRequirement = <local adapter>
configurationDescriptor = <portable facts, with fidelity report>
```

Current SP does not provide this. It reads a mounted vehicle's TweakDB record, keys tuning/parts to that record, and spawns AI via DynamicEntitySystem. It neither unlocks player garage vehicles nor attaches durable external identity to player cars. A future proxy adapter would need a local binding between the imported proxy descriptor and the spawned/mounted local entity; the engine entity ID is temporary and cannot be the proxy identity.

What a proxy can legitimately preserve:

- authority-world and `assetId` reference, serials and immutable production provenance;
- conceptual `vehicleKey`, exact runtime record requirement and content hash/version;
- last synchronized display snapshot: owner-visible name, factory/current appearance, odometer/wear/configuration as **read-only annotations**;
- livery identity when the same assets/record are available locally;
- a portable configuration descriptor and an explicit fidelity report (`exact`, `mapped`, `approximate`, `unsupported`);
- local practice/results that state they used a proxy of that asset.

It must not change Online odometer, wear, components, ownership, money, engineering, markets, championships or race history. Even an offline drive that is later uploaded remains an SP observation/result about a proxy, not a missing segment of the authoritative machine biography.

Exactness is uneven:

- Same `vehicleKey`, exact record and same content hash: exact conceptual/runtime selection.
- Derived RB15 livery record/appearance with the same ArchiveXL/TweakXL content: plausibly exact presentation.
- Online RGB factory paint: not exactly reproducible by current SP NCM, which has no corresponding per-asset paint application path.
- Online class ceiling (`topSpeedKph`, acceleration scale, taper) versus SP TweakDB drive-flat multipliers: at best mapped/approximate; they are different control models.
- Future Online components, wear, condition and engineering effects: portable as description before they are portable as physics.

If required content is absent, the correct state is **proxy unavailable locally**, with its identity/snapshot still readable. Substituting a MaiMai-like car and calling it the asset would corrupt identity. A deliberately labeled visual fallback may be allowed later, but it remains a fallback representation and cannot generate comparable machine-specific results.

## 6. Modded vehicles and switching contexts

Current OPEN//77 launcher behavior is deliberately profile-isolated. Online boots Stack + World; Solo projects the player's own mods and removes OPEN//77's projected files. World mods are applied before boot and **never appear in Solo**. REDengine archives, redscript and TweakXL/ArchiveXL registrations are boot-time concerns; resource hot reload does not add depot assets. Switching context therefore means a launcher profile change and a fresh game boot when the projection/digest differs, not an in-session "Play Alone / Play Online" toggle.

Consequences:

- A modded Online vehicle currently must be present in the Online World projection (hosted/player-fetched) or installed manually in the permitted profile. OPEN//77 does not make it magically available to SP afterward.
- The same vehicle can be spawned by CET in SP only if its archive/tweak/XL content is separately installed in the Solo profile and compatible with the SP loader stack.
- Cached World blobs may avoid a re-download, but cache presence is not Solo availability.
- Current NCM evidence says the RB15 exact record renders and drives in multiplayer when the client already has the files. Hosted required-mod delivery remains blocked/unresolved in KB-8; TW testing uses manual installation. Missing-asset behavior from another client's viewpoint remains unverified (KB-40).
- The RB15 livery add-on depends on the third-party RB15 archive. NCM can distribute its own patch only under its rights; base vehicle redistribution/player-fetch is a separate licensing decision. Technical loadability never grants redistribution permission.

Official current platform docs support required World mods, content-addressed packages and player-fetch, with executable content subject to verification/unsecured-world policy. That makes a future shared **content catalog** plausible: one logical package identity/hash/license record, projected through the SP collection channel and Online required-mod channel. It does not imply one installation profile or that Online-downloaded content may legally be reused outside Online.

## 7. Sporting records, comparability and trust

The legitimate aggregation is a **provenance-bearing personal sporting history**, not one undifferentiated leaderboard:

```text
Snake in the Grass
  Online PB  3:12.104  verified by world ncm-online / settled
  SP PB      3:08.422  local / proxy of ncm-online:<assetId>
```

Both are NCM performances. They answer different questions. The Online row is competitive evidence under that world's rules and settlement. The SP row is valid personal history and useful practice evidence, but the player can edit it.

A result envelope needs enough data to decide whether comparison is meaningful:

- immutable result/session ID and schema version;
- execution context and trust/authority class;
- authority world for settlement and, separately, authority world of any referenced proxy asset;
- player/NCM Driver reference or local career identity plus binding status;
- route/course ID, direction, revision and geometry/path hash;
- event/session kind, ruleset ID/revision, sanctioning and timing method/precision;
- game, NCM adapter and physics/performance-profile versions; relevant content hashes;
- machine `vehicleKey`, exact runtime record, persistent `assetId` reference when any, proxy flag/snapshot revision;
- configuration reference/portable descriptor and realization fidelity;
- livery/appearance where materially relevant;
- environment/conditions and assists or a declared comparability profile;
- field size and each entrant's human/physical-AI/simulated-AI backend and finish provenance;
- raw time, corrected time, penalties, DNF/DSQ, incidents and record validity.

Not every field belongs in UI, but fields omitted at creation may be unrecoverable. A route and physics **comparability contract** can later define which differences matter. Until one exists, same-name route times should be displayed side-by-side, not ranked together.

Useful trust levels are few:

- **world-authoritative Online**: server-orchestrated and settled in a named world;
- **local SP**: self-recorded, player-controlled;
- optionally **local SP with evidence attached**: trace/build metadata available, useful for diagnosis or leagues, but still not tamper-proof.

Local signatures, hashes or a bundled CET recorder can make accidental edits detectable; they cannot make a player-controlled process trustworthy against its owner. Calling such a tier "verified" would be security theater. Human league attestation or video review may form a separate social rule later, not an automatic NCM authority promotion.

SP evidence can safely flow Online as a **claim**, route-QA artifact, AI benchmark or personal-history import. The receiving world may store/display it with origin intact. It must never silently settle Online money, title, ratings, records or championships.

## 8. Machine Knowledge across contexts

Online already has a strong epistemic seam: `vehicle_discovery` summarizes identity discovery, while `vehicle_knowledge_evidence` records driver, world, `vehicleKey`, optional `assetId`, evidence key, knowledge/source/epistemic kinds, time and JSON evidence. Current core distinguishes identity reveal, observed speed floor, observed configuration and authoritative specification; sources distinguish world encounter, markets, ownership, authored displays and manufacturer publication.

SP has no equivalent Machine Knowledge system. It knows its catalogue/roster and records telemetry, but it does not distinguish what the player has discovered, documented, observed, researched or learned through ownership.

Under a broader NCM umbrella:

- Canonical taxonomy and documentation-bearing **model facts** can be shared when they are globally meaningful and legally distributable.
- SP observations can be local evidence with SP execution provenance and optional Online-proxy asset reference.
- Online observations remain world evidence governed by Online visibility, privacy and retention.
- A personal Index could display both partitions, never silently union them. "Observed in SP" must not unlock an Online discovery or exploration reward unless that world deliberately adopts a one-way policy.
- An SP proxy may generate local observations about its local representation. Those observations describe that representation/configuration and cannot update the authoritative asset or model documentation.
- Selling/losing an Online asset does not erase knowledge already earned there; similarly, local knowledge remains local history.

There is a promising one-way relationship: globally published manufacturer/model documentation can seed both contexts, while context-earned observations and discovery remain partitioned. A future player-controlled "import my Online Index into my private SP viewer" is less dangerous than the reverse because it creates no Online reward, but it still needs authentication, consent and a snapshot provenance label.

Coordinates are context evidence. Even when both contexts use Night City's map, a coordinate plus game/content revision and source is safer than assuming that an authored place name or route revision is identical everywhere.

## 9. World sovereignty and allowed relationships

Use these verbs precisely:

- **Share**: one canonical definition feeds both adapters.
- **Reference**: one context stores a typed pointer to another world's fact.
- **Mirror**: read-only snapshot, labeled with source/revision/time.
- **Proxy**: local runtime representation of an externally authoritative thing.
- **Aggregate**: display/index facts together without merging authority.
- **Transfer**: authoritative state moves under an explicit protocol and both ledgers record it.
- **Synchronize**: ongoing bidirectional mutation; almost nothing here currently justifies it.

Potentially safe one-way flows are definitions to both contexts, Online asset snapshots to SP proxies, and SP evidence to an Online/private archive as non-authoritative claims. Controlled two-way exchange may someday be meaningful for portable identity bindings, authored community routes, or league submissions, but only through explicit admission/review. Money, title, supply, odometer, wear, components, championship consequences and world-earned knowledge should never drift across automatically.

## 10. Shared-core architecture assessment

The proposed Core/SP Adapter/Online Adapter split is directionally right but underspecified. A better decomposition is:

```text
NCM Vocabulary + Content
  stable IDs, revisions, definitions, assets, documentation
             |
NCM Evidence + Sporting Semantics
  provenance, result/observation/config envelopes, pure rules/simulation
         /                         \
SP adapter + local ledgers       Online adapters + sovereign SQL ledgers
CET/redscript/DES/JSON           OPEN//77 server/client/WebUI
```

Why two shared layers? Authored content and evidence evolve differently. A route definition should not depend on a result schema; a result must be able to cite an old route revision forever. Splitting them prevents "updating the track" from reinterpreting history.

Current `ncm/core` is an excellent seed for Evidence/Sporting Semantics: it is engine-free, copied deterministically, and already owns IDs, provenance, catalogues, gates, race kernels and simulation-oriented rules. It is not yet a neutral full NCM core because it contains Online-specific economy, production, provisioning and profile assumptions, and SP does not consume it. The cheap move now is to protect neutral module boundaries and canonical IDs, not to refactor SP onto it.

High-leverage framework seams for third-party NCM servers:

- authored content packs with stable IDs/revisions and declared required assets;
- entrant-backend capability/provenance interface;
- world adapter interface for spawn/control/observe/settle rather than direct platform calls in pure rules;
- machine model -> environment record mapping with availability/fidelity reporting;
- result/observation envelopes independent of storage and UI;
- operator policy in versioned packs/tunables, with world ledgers always sovereign.

This permits an AI-heavy private server without imposing AI grids on the reference world, and permits a league server without an economy while sharing the same sporting vocabulary.

## 11. OPEN//77 current capability and future optionality

| Possibility | Classification | Evidence/reason |
|---|---|---|
| Human authoritative Online races, schedules, assets, markets, telemetry | Currently supported and implemented | Current resource/server code and live records. |
| Small custom HTTP health/read adapters | Currently supported by platform; unused by NCM | Official `Open77.http`; see external API audit. Not needed for convergence now. |
| Modded vehicle records in Online | Works when clients have content | RB15 recorded live; current delivery remains manual/KB-8. |
| Same modded vehicle in SP | Works if independently installed in Solo | CET/TweakDB can see boot-loaded Solo content; World projection does not carry over. |
| SP proxy of an Online asset | Plausible with current local primitives, not implemented | Descriptor + local spawn/binding; fidelity varies. No Online mutation required. |
| Online physical AI below 55 m/s | Platform-supported, NCM-unimplemented and unproven at race scale | Client-simulated AI API, 64-point tasks, coarse behavior. |
| Online 300+ km/h physical AI | Blocked today | Explicit 55 m/s API cap. A lifted cap alone would not prove racecraft/fleet quality. |
| Empty-server physical AI | Fundamentally unavailable in current distributed model | OPEN//77 server has no CP2077 physics; a ready client must simulate. A future headless simulator would be a different architecture. |
| Server-delivered vehicle assets remaining usable in SP | Not current behavior; technically plausible only through a separate Solo install/catalog action | World files never project into Solo. Licensing remains independent. |
| Cross-world NCM Driver/history | Architecturally plausible, authentication/federation-dependent | Current schema anticipates origin/bindings; no global claim service exists. |
| Shared official leaderboard across SP/Online | Invariant conflict by default | Local SP is player-controlled and physics/configuration differ. Side-by-side provenance is valid. |

Current official sources: [Launcher/profile layering](https://open2077.net/docs/launcher), [server resources](https://open2077.net/docs/server-resources), [required/server mods](https://open2077.net/docs/server-mods), [resource runtime](https://open2077.net/docs/resource-runtime), [vehicles](https://open2077.net/docs/vehicles), [vehicle AI](https://open2077.net/docs/vehicle-ai), and [API overview](https://open2077.net/docs/api). These are alpha contracts and must be rechecked against the deployed build before implementation.

## 12. Retrofit traps ranked

### Preserve now - cheap now, expensive or impossible later

1. **Route identity must include direction and immutable geometry revision/fingerprint.** Today the same root ID can mean an SP generated route ID/path signature and an Online endpoint/gate course; Online often measures crow-flight distance. Never declare times equivalent from root/name alone.
2. **Results must retain execution context, authority/trust and cited definition revisions.** `ncm-core` has an origin/context validator, but current SP and Online persistence do not carry the complete envelope. History cannot be reliably backfilled.
3. **Use composite external asset references `{worldId, assetId}`.** UUID collision is unlikely; authority ambiguity is certain without the world. Never use `#0000001` as the key.
4. **Separate result settlement world from referenced asset world.** An SP result using an Online proxy has two legitimate worlds. One overloaded `world_id` cannot express it.
5. **Keep `vehicleKey`, runtime record, live entity and `assetId` distinct.** Online does; SP currently only knows the record. Add mappings later, never reinterpret old record strings as physical assets.
6. **Preserve machine/configuration at event entry and result time.** Online's entry `asset_id` and reserved `configuration_ref` are correct. SP records need an eventual proxy/local configuration reference; current ownership is not historical evidence.
7. **Make world identity fail loud across Online resources.** KB-94 proved two `serverId` declarations can split one deployment. This is independently urgent for every future bridge.
8. **Choose one authored source for root/model metadata and generate adapters.** Current explicit copy lineage is valuable but manual. Hash/version generated outputs so drift is detectable.
9. **Do not conflate definition, template, occurrence and settlement.** A canonical event template can be shared; an Online scheduled occurrence or SP season round is a world instance.
10. **Carry content/physics realization identity.** A model ID alone cannot establish that SP and Online used the same archive, record, handling or cap. Store a reference/hash/profile, not an exhaustive mod list.
11. **Keep livery identity separate from implementation record.** `Vehicle..._kimiko` is an adapter technique, not the canonical meaning of the livery.
12. **Preserve observation source, subject, coordinates, time and epistemic class at creation.** These are irrecoverable and prevent SP proxy observations from contaminating Online/model truth.

Specific existing history caveats to quarantine, not silently fix: SP `records.json` merges forward/reverse node pairs; Online leaderboards group by current `route_id` without route revision; early Online results before migration 024 have permanently unknown machines; `configuration_ref` is currently unwritten.

### Important, but safe to investigate later

- portable configuration descriptor and per-adapter fidelity vocabulary;
- optional NCM Driver claim/link between a local career and an Online identity;
- canonical course authoring/export and road-path capture shared by both adapters;
- slower OPEN//77 AI proof: one car, then handover, then a small field, with provenance/fallback;
- common statistical AI kernel and reproducibility fixtures;
- personal cross-context history viewer/import with explicit consent;
- content catalog generation across Solo collection and Online World packages;
- correction/supersession and durable publication cursor before a real external consumer.

### Safe to defer deliberately

- endpoint paths, REST/RPC/WebSocket choices and JSON wire design;
- public authentication/OAuth, global account system and cross-server federation;
- automatic sync, launcher/mode selector and seamless in-session switching;
- two-way economy, title, component, wear, odometer or knowledge transfer;
- exact physics parity and one mixed-context leaderboard;
- large Online AI grids or reference-world AI policy;
- public telemetry export and long-term retention.

## 13. Creative possibilities discovered

These are possibilities, not recommendations to build now.

1. **SP as a machine-configuration wind tunnel.** A portable descriptor can be realized locally with a fidelity report, letting a player practice or compare setups without lending the authoritative asset. The useful artifact is the experiment/result, not imported wear or progression.
2. **Course conformance fixtures.** One canonical course revision could ship sample positions/crossings and expected sector/gate outcomes. Both adapters run the fixture offline, catching geometric drift without sharing runtime code.
3. **Asset biographies with multiple evidence lanes.** One Online machine page could someday show authoritative Online race/odometer history beside explicitly local "represented in SP" performances. The local lane enriches cultural history without mutating the asset.
4. **AI as a portable capability pack.** SP's physical AI, Online physical AI and statistical simulation become backends behind a capability declaration. Third-party operators choose policy per event; the reference world can disallow a backend without removing it from NCM as a framework.
5. **Definition publishing, not save synchronization.** Online or a neutral authoring repository can publish signed/versioned course/model/event definitions that SP consumes. This captures most convergence value while avoiding every sovereign-ledger problem.
6. **Non-authoritative community evidence.** SP traces can propose braking points, course defects or observed envelopes. A curator may turn accepted evidence into a new authored route revision or documentation fact through review; raw evidence never promotes itself.
7. **Graceful absence as a first-class state.** A proxy, livery or course asset may be known but unavailable in this context. Representing `known / unavailable / unsupported / approximated` is more powerful and safer than forcing every context to materialize everything.
8. **Third-party world interoperability without federation.** Independent NCM servers can use the same model/route/result vocabulary while keeping separate world IDs, identities and ledgers. Aggregators can compare published evidence later without any server trusting another's economy.

## 14. Concept matrix

`Yes/adapted` means one canonical definition with environment realization. "Aggregate" always means preserve provenance, never merge authority.

| Concept | Shared NCM definition? | SP-local state | Online-authoritative state | Proxy/reference? | Aggregate? | Current blocker | Future possibility |
|---|---|---|---|---|---|---|---|
| Manufacturer | Yes | Display/catalogue copy | Catalogue/production key | Yes | Yes | Manual lineage | One canonical maker key/metadata |
| Machine model | Yes/adapted | TweakDB record + pool metadata | `vehicleKey` + allowed records | Yes | Yes | SP lacks `vehicleKey` | Generated record mappings |
| Runtime vehicle entity | No | CET/DES entity | OPEN//77 `vehicleId` | No, ephemeral | No | Different runtimes | Always adapter-local |
| Serialized machine | Identity format only | None today | `assetId`, ordinals, lifecycle/title | Read-only SP proxy | Biography lanes only | No proxy/binding | `{worldId,assetId}` reference |
| Machine configuration | Vocabulary/descriptor | Parts/loadout + TweakDB tuning profile | Paint now; components planned; reserved result ref | Yes, fidelity-labeled | With descriptor/revision | Different effect models; Online components absent | Portable description, adapter realization |
| Livery/appearance | Yes/adapted | appearance/derived record manifest | record/appearance + asset paint | Yes | Yes | Content availability/licensing | Stable livery ID + content requirement |
| Route/root | Yes/adapted | root + generated path signature | root currently used as route + gates | Yes | Only same revision | No shared geometry revision | Canonical directed course revisions |
| Checkpoint/gate | Shared semantics, adapters | 50 m proximity/circuit points; finish line | ordered plane/capture gates with server check | Yes | If same course contract | Different crossing rules | Versioned gate semantics or declared adapter deviation |
| Event template | Yes | career/quick/ambient builders | series/pack/ruleset definitions | Yes | Yes | IDs and fields differ | Common template vocabulary |
| Scheduled event occurrence | No | local season/game clock | server real-time event row | Reference only | Timeline display | Different clocks/authority | Context-partitioned calendars |
| Race/session lifecycle | Semantics yes | CET state machine | server session kernel | View/reference | Results only | Runtime-specific transitions | Common event names/envelopes |
| Timing rules | Yes/adapted | local frame/telemetry and finish resolver | server clock + validated/interpolated gates | Reference | Only declared comparable | Different sensors/precision | Ruleset + timing-method IDs |
| AI competitor | Profile/backend vocabulary | physical local + projected/simulated | none in product today; platform AI available | Yes | Yes with backend | 55 m/s Online cap; unproven scale | Pluggable entrant backend |
| Player identity | NCM Driver concept | local career ID only | NCM Driver UUID + world binding | Optional future link | Personal history | No claim/auth flow | Explicit user-approved binding |
| Result | Yes, envelope | local editable records/telemetry/history | settled SQL result/incidents | Yes | Yes, partitioned | Missing common context/revisions | Cross-context personal history |
| PB/record | Definition of claim | local top five, direction-collapsed | per-world route board | Reference | Side-by-side; not one board | Comparability absent | PB by comparability class |
| Championship template | Yes/adapted | tier rules/schedule generator | competition/series packs | Yes | Documentation | Semantics differ | Shared sporting template vocabulary |
| Championship instance/consequences | No | local season/rep/payout | world standings/ledger/licence | Read-only mirror | Historical display | Sovereign consequences | Never automatic two-way sync |
| Money | Currency vocabulary at most | vanilla/local editable | NCM ledger | Display snapshot only | No balance merge | Trust/economy invariant | Do not merge |
| Market definition | Possibly | local shop/offers | markets/offerings/production | Read-only catalogue | Public facts only | Different economy/knowledge | Shared market archetype, local inventory |
| Market inventory/supply | No | generated local offers | authoritative assets/production | Mirror only if entitled | No | Scarcity/knowledge | Do not synchronize |
| Component/part definition | Potentially adapted | implemented local parts | specification, not runtime system | Descriptor | Documentation | Ontologies/effects not reconciled | Canonical component identity later |
| Component ownership/custody | No | local editable inventory | future world ledger | Read-only snapshot | No | Property invariant | Do not merge |
| Wear/condition | Vocabulary possible | little/no serialized-machine truth | planned authoritative component state | Read-only snapshot | Evidence lanes | No common model | Never increment Online from SP |
| Odometer | Unit/format only | no authoritative per-asset odometer | server-filtered asset mileage | Read-only snapshot | Display with source | Local trust | Do not merge totals |
| Machine Knowledge taxonomy | Yes | absent today | core vocabulary/evidence | Yes | Partitioned Index | SP system absent | Shared taxonomy, local evidence stores |
| Discovery | Source vocabulary | none today | driver/world earned | Mirror to SP only with consent | Partitioned | Exploration invariant | One-way viewer, not unlock sync |
| Observation | Yes, evidence envelope | local telemetry/evidence | world evidence | Proxy may be subject | Yes with provenance | Retention/privacy/vocabulary | Personal evidence graph |
| Documentation | Yes where globally meaningful | packaged/read-only | documentation-bearing sources/knowledge | Yes | Yes | Rights/source authority | Canonical published model docs |
| Engineering knowledge | Taxonomy maybe | local parts/tuning skill not epistemic | planned driver/world progression | Read-only reference | No automatic level merge | Gameplay progression | Context-local progression, shared ontology |
| Team/organization definition | Some templates | factions/local management | persistent organization/principal | Read-only mirror | History | Different agency/economy | Shared presentation; sovereign membership/title |
| Telemetry schema | Summary vocabulary yes | rich local sessions/traces | 5 Hz client + 1 Hz fallback/chunks | Export/reference | Downsampled with trust | Different fields/trust; no retention policy | Common field dictionary, context sources |
| Schedule/calendar | Template vocabulary | game-time/local generated | real-time server calendar | Read-only reference | Combined viewer, partitioned | Different clocks/consequences | Multiple context calendars |
| Ruleset/eligibility | Yes/adapted | local class/prestige/settings | versioned class/ruleset/asset entry | Yes | Cite versions | Different performance enforcement | Common intent + adapter capability declaration |
| World identity | Common namespace rules | no world ID today | opaque `server_id`; duplicated setting risk | Required for every external ref | Yes | No SP context ID; KB-94 | Separate execution, authority and runtime IDs |
| UI/presentation | Shared vocabulary/assets only | CET ImGui + redscript/native phone/HUD | WebUI/state bags/map/notifications | N/A | N/A | Different UI stacks | Common view models, native adapters |
| Authentication | No shared implementation yet | local player controls files | platform identity -> world binding | Required for any private import | No implicit federation | No SP claim/global service | Defer until real consumer/threat model |

## 15. Recommendations

### Preserve now

These are substrate decisions, not implementation authorization:

1. Treat model/root/livery IDs as canonical NCM vocabulary and document their meanings independently of runtime records.
2. Define route identity as directed ID + immutable revision/geometry fingerprint before either branch creates more historical records.
3. For every new durable result/observation, preserve execution context, authority/trust, world namespace, referenced definition revisions, occurred time and source provenance. Do not redesign old storage in this audit.
4. Keep Online's `vehicleKey` / record / `assetId` / live entity distinctions and use `{worldId,assetId}` in any future cross-context reference.
5. Preserve entry/result machine attribution and `configuration_ref`; do not let the reserved field become a reason to invent a premature component schema.
6. Separate settlement world from referenced-asset world in terminology and future envelopes.
7. Make generated/copy lineage detectable with source version/hash. The first goal is to detect drift, not to force one runtime library.
8. Treat unavailable/approximate adapter realization as valid explicit states. Never substitute content silently.
9. Keep per-entrant backend/finish provenance through results. Do not flatten physical, projected, simulated and untracked AI.
10. Resolve the existing Online cross-resource `serverId` agreement risk on its own scheduled authority path; every convergence idea depends on world identity being singular.

### Investigate later

- one canonical directed course/revision format and adapter conformance fixtures;
- stable vehicle/livery/content catalogue generation for both delivery channels;
- portable configuration descriptors and fidelity comparison;
- a non-mutating Online-asset snapshot format suitable for an SP proxy;
- explicit local-career <-> NCM Driver claim UX and threat model;
- shared statistical AI/profile core and a bounded OPEN//77 physical-AI experiment;
- personal provenance-partitioned history/Index;
- reviewed ingestion of SP evidence as non-authoritative claims;
- common telemetry field dictionary, retention and privacy policy.

### Defer deliberately

- synchronization protocols, automatic import/export and conflict resolution;
- API endpoints, public website, webhooks and external authentication;
- seamless launcher/mode selector or in-session switching;
- global/federated leaderboards or cross-world market;
- full economy recreation in SP;
- large AI multiplayer fields and reference-world AI policy;
- exact cross-context physics equivalence.

### Do not merge

- Online ownership/title/custody, money/ledger, market inventory/supply and organization treasury;
- Online odometer, wear, component state and engineering progression;
- Online discovery/knowledge earned through world participation;
- official Online settlement, ratings, licences, championships and prizes;
- live runtime entity identity;
- SP-local results into Online-authoritative leaderboards without an explicit independent admission process;
- World-profile mod files into Solo by assumption or in violation of licenses.

## Final finding

NCM is not two unrelated games, and it should not become one synchronized save. The code already points to a more durable model: **one motorsport vocabulary and content lineage, multiple execution contexts, multiple sovereign ledgers, and evidence that says exactly where it came from**.

SP's strategic identity can be lean and still important: the AI racing laboratory, offline/practice context, route and machine sandbox, and local sporting history. Online is the persistent authoritative world. Neither needs to impersonate the other. The valuable convergence is that a MaiMai, a route revision, a livery, a ruleset and a performance can retain the same NCM meaning while their ownership, trust and consequences remain honestly separate.

The most urgent work is therefore semantic preservation, not synchronization: IDs, revisions, provenance and namespace distinctions. If those survive, richer bridges remain optional. If they are omitted now, later convergence will require guessing historical truth - and several existing SP/Online records already demonstrate that the guess cannot be made reliably.
