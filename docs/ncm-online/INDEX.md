# INDEX - what governs NCM now

> **STATUS: LEDGER** - the authority map. Kept accurate every session; everything else points here.
> Classified 2026-09-24 (L125).

**Read this first.** It answers one question: *what is the current authority on X?* It does not summarise NCM.

Authority is **per topic**, not per document. Two CURRENT documents covering different topics is normal.
Two claiming the same topic is a conflict, and is listed below rather than silently resolved.

**Document number and date confer nothing.** There are two 16_ and two 17_ documents, and the
next-free-ID line in NOW.md has been stale three times. Trust this map, not filenames.

---

## Status legend

| Status | Meaning | What you do |
|---|---|---|
| **CURRENT** | the present statement of intent for its topic | **build from it** |
| **SPEC** | owner intent, captured, NOT authorised | **do not implement; do not contradict** |
| **PROPOSAL** | a coder recommendation awaiting a ruling | **do not rely on it** |
| **SUPERSEDED** | was current; something replaced it | read for history only |
| **HISTORICAL** | a record of a moment - experiment, run sheet, completed work package | evidence, never architecture |
| **LEDGER** | living, append-only, current by construction | read for state; never rewrite prior entries |

**Headers carry authority. Build state lives in the ledgers** (BACKLOG.md, KNOWN_BUGS.md, wp/MASTER_TEST.md).
That split is deliberate: build state rots, authority does not. It is why 05_DATA_MODEL.md could sit in the
corpus claiming migrations 001-007 while the schema was at 023.

---

## Authority by topic

| Topic | Authority | Affirmed |
|---|---|---|
| **NCM 3.0 single player**: the NCM Host (the dev resources in-process over SQLite), Race Week tapes, offline canonical time, the deck, the seam report toward Nexus | [55_NCM3_SINGLE_PLAYER.md](55_NCM3_SINGLE_PLAYER.md) | L338 |
| **Race Week Live (NCM Radio)**: the in-game station, corpus compiler, trigger map, director, OmniVoice voice render, `ncm-radio` required mod and `ncm_radio` resource | [59_NCM_RADIO.md](59_NCM_RADIO.md) | L348 |
| **Race Week Live cast and every on-air line**: the owner's authoring bible, imported verbatim | [radio/RACE_WEEK_RADIO_BIBLE.md](radio/RACE_WEEK_RADIO_BIBLE.md) | L348 |
| **Deterministic Race Week radio**: simulation-truth/commentary-surface audit for writer-authored show; equal primary co-hosts; hosted voice packs intended; settled unobserved results may air with provenance undisclosed | [58_DETERMINISTIC_RACE_WEEK_RADIO_AUDIT.md](58_DETERMINISTIC_RACE_WEEK_RADIO_AUDIT.md) | L346-L347 |
| **Night City Chronicles prior narration work**: LLM realization and local audio pipeline, retained as historical/session context; Race Week commentary now airs from doc 59 (L348) | [57_NIGHT_CITY_CHRONICLES.md](57_NIGHT_CITY_CHRONICLES.md) | L344-L346; superseded as the target for new Race Week radio |
| Organisations, team ownership, governance, grid slots | [14_TEAM_ORGANIZATIONS.md](14_TEAM_ORGANIZATIONS.md) | L92, L93; reaffirmed L123 |
| Foundational primitives, contradictions, build sequencing | [24_FOUNDATION_RECONCILIATION.md](24_FOUNDATION_RECONCILIATION.md) | L123 |
| NPC motorsport world: organizations, calendar, sim, WIRE, Billie's board, manager mode, garages, live races | [44_THE_PADDOCK.md](44_THE_PADDOCK.md); [DECISION_RECORD.md](DECISION_RECORD.md) L248 for the oval spline candidate and its live gate | L222, L224-L227, L248 |
| Environments, promotion discipline (Online vs Development) | [16_ENVIRONMENTS.md](16_ENVIRONMENTS.md) | L112, L121, L223 (Online frozen at Baseline 1) |
| **Database schema** | CODE: `ncm/online/resources/ncm_league/server/schema/` | - |
| **Online temporal-loop carryover, one anchor, Week vehicle damage and repair, physical trunk cargo; NPC damage and engineering** | [DECISION_RECORD.md](DECISION_RECORD.md) L349-L350, [45_RACING_WEEK.md](45_RACING_WEEK.md) §Q-§R; code in `week.collapse`, migrations 073-076, `ncm_world/server/vehicle_condition.lua` and Paddock race/car hosts | L349-L350; repair correction, scalar display and workshop route deployed Online; MASTER_TEST §WL16 server correction PASS, client PASS owed; team loaners and native item custody open |
| Lap ghost replay | [39_GHOST_REPLAY.md](39_GHOST_REPLAY.md) | L166 |
| Overall system shape | [01_ARCHITECTURE.md](01_ARCHITECTURE.md) | L28-L33 - see conflict C-1 |
| Milestone vocabulary (M0-M12) only | [02_ROADMAP.md](02_ROADMAP.md) | L39-L42, L59-L63 |
| Nodes, routes, ordered chains | [07_NODE_NETWORK.md](07_NODE_NETWORK.md) | - |
| Economy v1 build contract | [40_ECONOMY_V1.md](40_ECONOMY_V1.md), supported by the ledger/refund audit in [08_ECONOMY.md](08_ECONOMY.md) | L84, L85, L165, L167-L169 |
| Player Exchange: synchronous heterogeneous barter | [DECISION_RECORD.md](DECISION_RECORD.md#l194---locked--executed-in-code--live-gated---player-exchange-is-a-first-class-f6-system-not-a-backend-slice), [40_ECONOMY_V1.md](40_ECONOMY_V1.md) §12, plus CODE: `ncm/core/economy/trade.lua`, `ncm_league/server/trade.lua`, migration 040 | L123, L194; full F6 system built locally, MASTER_TEST §BW live PASS owed; persistent listings/escrow remain later |
| Markets and market discovery | [17_MARKET_NETWORK.md](17_MARKET_NETWORK.md) | L106, L117 |
| Player-scoped machine knowledge | [16_MACHINE_INDEX.md](16_MACHINE_INDEX.md) | - |
| Discovery and collection | [13_VEHICLE_COLLECTION.md](13_VEHICLE_COLLECTION.md) | - |
| Weather as world state | [11_WEATHER.md](11_WEATHER.md) | - |
| Vehicle artwork | [15_GENERATION_1_VEHICLE_ARTWORK_MANIFEST.md](15_GENERATION_1_VEHICLE_ARTWORK_MANIFEST.md) | - |
| Day-to-day operation of NCM Online | [OPS_STAGING.md](OPS_STAGING.md) | - |
| Carrier follow-up and in-place Production package upgrade | [CARRIER_NEXT_STEPS_AND_UPGRADE.md](CARRIER_NEXT_STEPS_AND_UPGRADE.md) | L146-L147; KB-132-KB-136 |
| Rig integration ownership and separation from Carrier | [43_RIG_BRIDGE_ASSESSMENT.md](43_RIG_BRIDGE_ASSESSMENT.md), [DECISION_RECORD.md](DECISION_RECORD.md#l191---executed-in-code-live-gated---rig-bridge-is-a-full-dedicated-mod-not-a-probe-and-not-carrier), plus CODE: `ncm/rig_bridge/` | L185, L186, L188, L191; dedicated multi-vendor product built, Carrier unchanged, `MASTER_TEST §BU` live PASS owed |
| QA instrumentation mapping | [wp/QA_INSTRUMENTATION.md](wp/QA_INSTRUMENTATION.md) | - |
| Driver Card and Fingerprint direction | [DECISION_RECORD.md](DECISION_RECORD.md#l130--locked--driver-card-expression-and-fingerprint-authority-stay-separate) | L130 |
| Foundry scope and invariants | [DECISION_RECORD.md](DECISION_RECORD.md#l153---locked-owner-direction---foundry-is-vehicle-rd-over-existing-geometry) | L153; representation awaits ruling in Proposal 38 |
| Engineering II (physical machines, the four ways to push, lineage and reverse engineering), the seed tree, Snowglobe motorsport (Sprint, Fireball, Relay, Triathlon), NPC drivers across domains, the cross-runtime physics contract | [54_ENGINEERING_II.md](54_ENGINEERING_II.md) | L321, L322, L323 |
| NCM Los Santos dev build: FiveM server, GTA adapter, space above Los Santos | [53_LOS_SANTOS_SPACE.md](53_LOS_SANTOS_SPACE.md) | L319 |
| Cross-world (Los Santos / FiveM as a second NCM server, Snowglobe as the shared protocol, cross-world identity and transfer) and the interface boundaries to preserve | [52_CROSS_WORLD.md](52_CROSS_WORLD.md) | L318 (direction only; not authorised) |
| The flight ladder, the altitude/space hand-off (NCM Snowglobe), the wormhole as a seed transition, and the dev-only experiments that walk them | [51_THE_CAUSAL_TUNNEL.md](51_THE_CAUSAL_TUNNEL.md) | L315, L316 + addendum (dev only; not production) |
| Engineering architecture: the physical body grammar (car and city), sites and envelopes, the fitting rule, drivetrain composition, cause / actuator / state / coarse model | [50_ENGINEERING_ARCHITECTURE.md](50_ENGINEERING_ARCHITECTURE.md) §11-§12 | L314 (R1-R5); SPEC above it: doc 48, doc 49 §7-§8 |
| Parts economy and fitting v1 | [DECISION_RECORD.md](DECISION_RECORD.md#l162---executed-in-code--live-gated---parts-becomes-a-conserved-economy-of-physical-assets) | L162-L163; deployed/enabled on private Online surface; MASTER_TEST §BF live evidence pending |
| Component Wear & Tear lifecycle | [DECISION_RECORD.md](DECISION_RECORD.md#l178--executed-in-code--live-gated--component-wear--tear-is-active-tyre-compounds-remain-deferred) plus CODE: `ncm/core/parts/wear.lua`, migration 038 | L120, L178; distance-only first generation built locally; Hard/Medium/Soft compounds deferred; MASTER_TEST §BM pending |
| Observation vocabulary and observation provenance | [DECISION_RECORD.md](DECISION_RECORD.md#l164---executed-owner-ruling---the-first-observation-vocabulary-is-accepted-the-estimator-is-not) plus [31_CAPABILITY_AUDIT.md](31_CAPABILITY_AUDIT.md) §9 | L164; §9 accepted as authority, rest of 31 stays PROPOSAL; MASTER_TEST §BH pending |
| Ambient population and race-corridor clearing | [DECISION_RECORD.md](DECISION_RECORD.md#l177--provisional--ambient-population-is-built-in-two-layers-and-only-one-of-them-can-be-cleared-by-radius) plus CODE: `ncm/core/world/ambient.lua`, `ncm_world/server/ambient.lua` | L177 - PROVISIONAL, no live PASS; §BL owed. Supersedes the `BLOCKED` traffic row in [../research/open77/OPEN77_NCM_MATRIX.md](../research/open77/OPEN77_NCM_MATRIX.md) (`KB-164`) |
| Estimation, envelopes and confidence | **NOBODY - explicitly unbuilt** | L164 refuses it pending its own reviewed proposal (`IDEA-337`, `IDEA-338`) |
| Long-term PvE experience and personal/shared boundary | `DECISION_RECORD.md` L218-L224, L237; [PvE simulation-stack vision](../research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md) is PROPOSAL for architecture | Owner direction: individual adventures over shared Paddock/city sim; simulation-led stack performed by Night City through OPEN//77 and NCM's own native mods (L220); named physical NPC text dialogue with four primary intents and deeper choices. The Paddock is built on dev (doc 44); L237 rules emergent over authored and sets the life-sim build order M1-M6. No life-sim or physical dialogue system built yet. |

---

## Known conflicts - unresolved, do NOT silently pick

**C-1 - 01_ARCHITECTURE.md vs the code.** It describes five resources and nine core packages; the disk has
three resources and a different core layout. Open as IDEA-029 since 2026-09-21. It remains the best statement
of system shape, so it stays CURRENT with this flag rather than being demoted. Authority for the live layout
is the code.

**C-2 - duplicate document numbers.** Two 16_, two 17_. Renaming would break links and git history for no
functional gain now that this map exists. Left alone deliberately.

**C-3 - 02_ROADMAP.md sequencing vs 24 section 9.** Resolved by per-topic authority: 02 owns milestone
vocabulary, 24 owns what happens next.

**C-4 - Race Tags (IDEA-301), resolved by L169.** The owner recalled it as a shipped post-race feature; the
repository proved it was only an authored brick. Economy v1 has now admitted the vocabulary through a pure
runtime evaluator with separate capped presentation and authored bounty consumption. The original assignment
remains a SPEC artifact; current runtime behavior is the code and current economic behavior is document 40.

**C-5 - Racing Week length, RESOLVED by L309's addendum.** Doc 47 supersedes doc 45 §0.5-§0.6 (three days, no Day 4)
and amends §0.1. The code still implements fixed three-day runs until doc 47 §6 is built.

---

## Current (21)

- [59_NCM_RADIO.md](59_NCM_RADIO.md) - Race Week Live (L348): the deterministic talk-radio station in the game's own radio list; corpus (1,088 beats, 5,689 lines), trigger map, director, OmniVoice render, `ncm-radio` plugin + `ncm_radio` resource
- [radio/RACE_WEEK_RADIO_BIBLE.md](radio/RACE_WEEK_RADIO_BIBLE.md) - the owner's Race Week Live authoring bible, verbatim: cast, rules and every on-air line
- [55_NCM3_SINGLE_PLAYER.md](55_NCM3_SINGLE_PLAYER.md) - NCM 3.0 single player (L338): the NCM Host runs the dev server's resources unchanged inside Cyberpunk over SQLite; Race Week tapes (one continuity = one server_id), the present calculated on return (`week.catchup`), the deck, the Time Lab; the seam report (doc §8). Headless gates green; MASTER_TEST §TP NOT RUN
- [58_DETERMINISTIC_RACE_WEEK_RADIO_AUDIT.md](58_DETERMINISTIC_RACE_WEEK_RADIO_AUDIT.md) - SPEC / audit only (L346): source-by-source deterministic commentary inventory, provenance and knowledge boundaries, open writer questions; no implementation authorized by this audit
- [57_NIGHT_CITY_CHRONICLES.md](57_NIGHT_CITY_CHRONICLES.md) - prior Night City Chronicles narration work (L344-L346): audit of the NCM 2.0 bridge, Radio OS and Ribbon OS; a thin NCM-owned engine in `ncm/chronicles/`; retained as history pending owner disposition
- [01_ARCHITECTURE.md](01_ARCHITECTURE.md) - overall system shape - SEE CONFLICT C-1 in INDEX.md
- [02_ROADMAP.md](02_ROADMAP.md) - milestone vocabulary (M0-M12) ONLY; current sequencing is 24
- [07_NODE_NETWORK.md](07_NODE_NETWORK.md) - nodes, routes, ordered chains
- [08_ECONOMY.md](08_ECONOMY.md) - economy intent
- [11_WEATHER.md](11_WEATHER.md) - weather as world state
- [13_VEHICLE_COLLECTION.md](13_VEHICLE_COLLECTION.md) - discovery and collection
- [14_TEAM_ORGANIZATIONS.md](14_TEAM_ORGANIZATIONS.md) - organisations, team ownership, governance, grid slots
- [15_GENERATION_1_VEHICLE_ARTWORK_MANIFEST.md](15_GENERATION_1_VEHICLE_ARTWORK_MANIFEST.md) - vehicle artwork manifest
- [16_ENVIRONMENTS.md](16_ENVIRONMENTS.md) - environments, promotion discipline
- [16_MACHINE_INDEX.md](16_MACHINE_INDEX.md) - player-scoped machine knowledge
- [17_MARKET_NETWORK.md](17_MARKET_NETWORK.md) - markets, market discovery
- [24_FOUNDATION_RECONCILIATION.md](24_FOUNDATION_RECONCILIATION.md) - foundational primitives, contradictions, sequencing
- [40_ECONOMY_V1.md](40_ECONOMY_V1.md) - Economy v1 build contract: paid events, additional faucets, asset sinks and settlement
- [50_ENGINEERING_ARCHITECTURE.md](50_ENGINEERING_ARCHITECTURE.md) - the engineering architecture: one body grammar for car and city, sites/envelopes, the fitting rule, the drivetrain graph, cause/actuator/state/coarse model (L314); steps 2-5 built offline in `ncm/core/engineering/`
- [44_THE_PADDOCK.md](44_THE_PADDOCK.md) - the Paddock, NCM's persistent NPC motorsport world; adopted under L225; phases 1-2 and 4-5 built and running on dev (L226, L227); phase 3 skipped
- [43_RIG_BRIDGE_ASSESSMENT.md](43_RIG_BRIDGE_ASSESSMENT.md) - dedicated multi-vendor Rig Bridge boundary and live acceptance order; implemented under L191, §BU owed
- [OPS_STAGING.md](OPS_STAGING.md) - day-to-day operation of NCM Online
- [CARRIER_NEXT_STEPS_AND_UPGRADE.md](CARRIER_NEXT_STEPS_AND_UPGRADE.md) - bounded Carrier follow-up and exact in-place Production package upgrade
- [wp/QA_INSTRUMENTATION.md](wp/QA_INSTRUMENTATION.md) - mapping the QA corpus to instrumentation
- [wp/NPC_ECONOMY_AUDIT.md](wp/NPC_ECONOMY_AUDIT.md) - the NPC economy's actual state, measured on dev (L297); re-run with `tools/npc-economy-audit.ps1`

## Spec - owner intent, not authorised (20)

- [54_ENGINEERING_II.md](54_ENGINEERING_II.md) - Engineering II (L321): machines assembled from physical systems (SI kinds, wrench from mount points, per-axis authority, first failure); the hop is not a thruster (ground / stored / atmospheric / reaction as physical preconditions); lineage and reverse engineering across worlds; the seed tree and world composition; Snowglobe as a motorsport environment (3D courses, NPC racing through paddock.sim with provenance, sport from the capability distribution); host expression losses; part two (L322): Snowglobe Sprint, Fireball, Relay, Triathlon, the open point-to-point slot, NPC drivers across domains, one race at three fidelities, unseen history. L323: the six host boundaries cleared or narrowed -- contact, multiplayer, clock sync, the live cross-server link (Snowglobe hub) and Three Cities, life support and EVA, the Badlands Sky Sprint in Cyberpunk (`ncm_link`, `ncm_space` on dev). Built in core and live in `ncm_ls_space` 0.5.0; no live PASS yet
- [53_LOS_SANTOS_SPACE.md](53_LOS_SANTOS_SPACE.md) - NCM Los Santos' first build (L319): a local FiveM dev server for GTA V Legacy, NCM core running unchanged in FiveM, Snowglobe above Los Santos (physics lift from the F0 rig, torque attitude, server doorway and floating origin, universe altitude, inverse-square gravity, Earth/Moon/Sun stand-ins); built, not yet run
- [52_CROSS_WORLD.md](52_CROSS_WORLD.md) - cross-world: a possible second NCM racing server on GTA V / FiveM (Los Santos), Snowglobe as the shared protocol between the two (no third server), identity over representation, portable serialized parts, transactional consensual transfer, emergent cross-world motorsport, worlds vs wormholes; the interfaces today's NCM should preserve, with an audit (L318); direction only, nothing authorised
- [51_THE_CAUSAL_TUNNEL.md](51_THE_CAUSAL_TUNNEL.md) - the causal tunnel: hop → force part → attitude → ugly flight → altitude (S0) → snowglobe → orbit → seed swap (whole dev server follows) → anomaly → return; physics not flags; the wormhole is a seed transition, not the rollover; you keep the car you are in (L316 + addendum); F0 (NCM Thrust + Carrier 0.1.33 lift lever) and S0 instruments built, not run
- [06_CHROME_ROSTER.md](06_CHROME_ROSTER.md) - vehicle cyberware / quickhack roster
- [09_APPAREL.md](09_APPAREL.md) - apparel entitlement
- [10_SPECIAL_EVENT_FISHING.md](10_SPECIAL_EVENT_FISHING.md) - the fishing special event
- [12_CANONICAL_VEHICLE_ROSTER.md](12_CANONICAL_VEHICLE_ROSTER.md) - the canonical vehicle roster
- [17_MACHINE_PROFILE.md](17_MACHINE_PROFILE.md) - the individual machine biography
- [18_PARTS_ECOSYSTEM.md](18_PARTS_ECOSYSTEM.md) - the procedural component/parts ecosystem
- [19_ENGINEERING.md](19_ENGINEERING.md) - engineering as a career
- [20_WEAR_LIFECYCLE.md](20_WEAR_LIFECYCLE.md) - wear, condition and component lifecycle
- [28_MACHINE_KNOWLEDGE.md](28_MACHINE_KNOWLEDGE.md) - machine knowledge, discovery, documentation, observation and estimation envelopes
- [39_GHOST_REPLAY.md](39_GHOST_REPLAY.md) - lap ghost replay: what a ghost is, what it wears, and why poses are not telemetry samples
- [bricks/assignments/B-089-race-tags.v1.md](bricks/assignments/B-089-race-tags.v1.md) - original Race Tag component specification; admitted by L169, with runtime behavior now governed by code
- [41_QUEST_GRAPH_PASS1.md](41_QUEST_GRAPH_PASS1.md) - the quest graph: character conversation trees, triggers, re-entry rules and payoffs (authoring Pass 1, preserved unchanged), plus Appendix A reconciling it against shipped telemetry, `L171` and `L172`. **Partly authorised by `L183`:** the Dex / Stu / Rico slice is BUILT and governed by code; the other fifteen contacts remain SPEC. A.5's word ceilings are withdrawn by `L176`
- [46_NCM_OBSERVER.md](46_NCM_OBSERVER.md) - NCM Observer: a non-participating client that travels to races, makes them physical, films them with racer-relative and lane-generated cameras, feeds Radio OS and OBS, and loops the program back onto OPEN//77 televisions (L307). **Partly authorised by L308:** slices 1-2 (the mode, the exclusion, the director, the racer-relative lens) are BUILT in `ncm_observer` and governed by code; the rest remains SPEC
- [47_MOODY.md](47_MOODY.md) - Moody, the volatility engine, and the seven-day Racing Week history rarely allows: a 72-hour attractor, a state-read continuation probability at each noon, Moody's self-modifying D20 conditions, coupled reservoirs, vibe as output (L309); supersedes doc 45 §0.5-§0.6 and amends §0.1 (C-5, resolved). **§6 authorised and BUILT by L310** (timeline, verdicts, Moody, reservoirs, harness, racing radio) and governed by code; not deployed
- [48_ENGINEERING_ENVELOPE.md](48_ENGINEERING_ENVELOPE.md) - the engineering envelope: a car's multidimensional capacity instead of 11 slots, physical components, "it fits", the packaging puzzle, staged reverse engineering into lineages, NCM taking authority over systems; Engineering Architecture pass after the manual (L311); nothing built
- [49_CITY_MEMORY.md](49_CITY_MEMORY.md) - city memory and civil engineering: author Day 1 and let Day 3 be the evidence; a sparse server-side Campaign Scar Ledger (clustered by segment + radius, accumulated burden → levels 1-4, physical incidents only in v0, ends with the campaign), an Infrastructure Knowledge Ledger across runs, a hand-run Campaign A/B experiment before any automation (L312 + addendum, Q1-Q4 ruled); civil engineering as engineering pointed outward, with a six-piece snapping kit judged by the race, anyone builds and dismantles for modest money (L313, C1-C4 ruled); the end-of-cycle Night City seed map with danger heatmap and infrastructure pins, chosen publicly at rollover; infrastructure belief proportional to evidence. The spatial half of doc 47, not a new end rule; nothing built

## Proposal - no authority until ruled (20)


- [56_RND_OVERHAUL.md](56_RND_OVERHAUL.md) - **SPEC (L342)** for physical manufacturer R&D and the flight-parts market; §5 records the six owner rulings. Implementation and live PASS remain separate.
- [21_ENGINEERING_PROPOSAL.md](21_ENGINEERING_PROPOSAL.md) - engineering architecture - ACCEPTED; decisions live in L120
- [22_WEAR_PROPOSAL.md](22_WEAR_PROPOSAL.md) - wear architecture - ACCEPTED; decisions live in L120
- [25_MACHINE_ARCHITECTURE_PROFILE.md](25_MACHINE_ARCHITECTURE_PROFILE.md) - machine architecture profile - awaiting Q18/Q19; section 10 undecided
- [26_DOCUMENT_AUTHORITY.md](26_DOCUMENT_AUTHORITY.md) - this scheme - directionally accepted, executed as L125
- [27_ATTRIBUTION_AND_ORIGIN.md](27_ATTRIBUTION_AND_ORIGIN.md) - Stage 0 machine attribution and the origin retirement mechanics - awaiting a ruling
- [29_STATE_BAG_AUDIENCE_AUDIT.md](29_STATE_BAG_AUDIENCE_AUDIT.md) - replication audience of NCM player state-bag mirrors - audited, corrections not applied
- [30_MACHINE_KNOWLEDGE_DEEP_DIVE.md](30_MACHINE_KNOWLEDGE_DEEP_DIVE.md) - what the knowledge substrate already records, and the minimal additive change it needs
- [31_CAPABILITY_AUDIT.md](31_CAPABILITY_AUDIT.md) - what the platform exposes or lets NCM derive about a machine, classified (`IDEA-339`) - **§9 was RULED ON 2026-09-26 (`L164`) and is now authority**; the rest of the document remains a proposal. Its §6 finding (there are no engine components) stands and is now the *reason* `configuration_ref` is legitimate rather than the reason it was refused.
- [32_PARTS_ENGINEERING_REENTRY_AUDIT.md](32_PARTS_ENGINEERING_REENTRY_AUDIT.md) - existing-system audit plus lineage, reconstruction-knowledge and fabrication-ceremony feasibility; owner rulings now live in L134 / Report 33
- [33_PARTS_ENGINEERING_FINAL_RECONCILIATION.md](33_PARTS_ENGINEERING_FINAL_RECONCILIATION.md) - owner-ruling reconciliation, focused Gate 5 audit and Chrome/setPerformance Gate 6 proof plan
- [34_GATE6_INPUT_AUTHORITY_REQUIRED_MOD_AUDIT.md](34_GATE6_INPUT_AUTHORITY_REQUIRED_MOD_AUDIT.md) - companion input authority, OPEN//77 control limits, required-world-mod delivery and additional Gate 6 carrier proofs
- [35_REQUIREDMODS_FORENSIC_AUDIT.md](35_REQUIREDMODS_FORENSIC_AUDIT.md) - real RB15/livery package audit, exact public-HTTP `Unverifiable` cause, HTTPS correction and acceptance contract
- [36_DRIVEABILITY_MOD_CARRIER_ASSESSMENT.md](36_DRIVEABILITY_MOD_CARRIER_ASSESSMENT.md) - whether a hosted mod can widen vehicle control past the three exposed performance fields and carry FFB natively; three engine surfaces, spawn-caching, multiplayer integrity, licensing (`IDEA-453`) - **revision 2** adds the research pass that answered §AR without an experiment. **Its three open decisions were ruled on 2026-09-25 (`L146`): NCM owns native code, the carrier is one mod, the companion retires.** The assessment's findings stand; the decision lives in `DECISION_RECORD.md`, not here.
- [37_REPOSITORY_RECONCILIATION_SCHEDULE.md](37_REPOSITORY_RECONCILIATION_SCHEDULE.md) - **the single ordered execution schedule** for both repositories and both servers, including where the RB15 withdrawal safely lands - WRITTEN, NOT EXECUTED (`IDEA-459`)
- [38_FOUNDRY_VEHICLE_LINEAGE_ARCHITECTURE.md](38_FOUNDRY_VEHICLE_LINEAGE_ARCHITECTURE.md) - repo-aware Foundry review: existing-mesh lineages, deterministic Vehicle R&D, immutable factory BOMs, finite appearance reservoirs and Design-keyed bounded production - **awaiting owner review; no implementation authorised** (`L153`, `IDEA-519`-`IDEA-526`)
- [38_FOUNDRY_VEHICLE_LINEAGE_ARCHITECTURE.md](38_FOUNDRY_VEHICLE_LINEAGE_ARCHITECTURE.md) - vehicle lineage and procedural Vehicle R&D architecture review - **PROPOSAL, do not implement from it**. The owner invariants are `L153`; `L155` governs the narrower Machine-keyed Parts boundary.
- [42_PARTS_BEHAVIOR_AND_WEAR_EXPANSION.md](42_PARTS_BEHAVIOR_AND_WEAR_EXPANSION.md) - design-only Parts behaviour, tyre-compound, stress-aware Wear, warning-light and service architecture exploration; **PROPOSAL, no implementation authorised** (`IDEA-627`-`IDEA-634`, `KB-163`)
- [NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md](../research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md) - long-term PvE vision: five-layer simulation stack over Night City, three capability tiers incl. NCM native mods, and the five-engine review; owner direction is L218-L223, architecture and source-port map remain proposals (`IDEA-722`-`IDEA-734`)
- [PACE_ROAD_PATH_PROBE.md](../research/open77/PACE_ROAD_PATH_PROBE.md) - **CURRENT** 2026-09-30 verified native traffic graph and dev road-speed candidate; race PASS pending (`KB-239`, `IDEA-783`-`IDEA-784`)
- [45_RACING_WEEK.md](45_RACING_WEEK.md) - Racing Week, the three-day reconstruction: architecture map, persistence map, reset boundary, three meta-progression models plus a hybrid, character bands, dialogue tags, conditions with provenance, archive schema, recovery and the implementation ladder - **PROPOSAL, nothing ruled or built** (`L300`, `IDEA-857`-`IDEA-874`)
- [CARRIER_NEXT_STEPS_AND_UPGRADE.md](CARRIER_NEXT_STEPS_AND_UPGRADE.md) - **the canonical Carrier build/publish/verify/rollback runbook**. Every in-place Carrier replacement follows it; do not hand-copy the DLL and do not accept a warm reconnect as proof.

## Ledgers - living records (6)

- [BACKLOG.md](BACKLOG.md) - the idea ledger - every idea, with permanent IDs
- [DECISION_RECORD.md](DECISION_RECORD.md) - every decision NCM has made (L-lines)
- [KNOWN_BUGS.md](KNOWN_BUGS.md) - defects (KB-lines)
- [NOW.md](NOW.md) - the single next-action index
- [wp/MASTER_TEST.md](wp/MASTER_TEST.md) - live PASS/FAIL evidence
- [wp/OFFLINE_TEST_QUEUE.md](wp/OFFLINE_TEST_QUEUE.md) - offline test queue

## Superseded - archived, kept for history (5)

- [00_ORIENTATION_BRIEF.md](archive/00_ORIENTATION_BRIEF.md) - superseded by **INDEX.md + NOW.md**
- [03_PACKAGING_AND_COLLECTION.md](archive/03_PACKAGING_AND_COLLECTION.md) - superseded by **12_CANONICAL_VEHICLE_ROSTER.md + 13_VEHICLE_COLLECTION.md**
- [04_TESTER_WINDOW_1.md](archive/04_TESTER_WINDOW_1.md) - superseded by **14_TEAM_ORGANIZATIONS.md - the granted-equipment model is abolished**
- [05_DATA_MODEL.md](archive/05_DATA_MODEL.md) - superseded by **ncm/online/resources/ncm_league/server/schema/ - the CODE is the authority**
- [wp/BATCH-1-CATCHUP.md](archive/wp/BATCH-1-CATCHUP.md) - superseded by **NOW.md - self-declared superseded 2026-09-21**

## Historical - archived, evidence not architecture (24)

- [wp/ONLINE_NIGHT_2026-10-04.md](wp/ONLINE_NIGHT_2026-10-04.md) - Online's night of racing analysed: human races cut the NPC field in half, sim pace vs the owner, crash facts, money
- [SERVER_BASELINE_2026-10-02.md](archive/SERVER_BASELINE_2026-10-02.md) - read-only platform, required-mod, and NCM resource inventory of both running servers before the next platform update

- [23_OPEN_QUESTIONS.md](archive/23_OPEN_QUESTIONS.md) - the Q1-Q70 question set, answered 2026-09-24 (L123)
- [HANDOFF_2026-09-25.md](archive/HANDOFF_2026-09-25.md) - the cold-start handoff written 2026-09-24
- [TW1_RUN_SHEET.md](archive/TW1_RUN_SHEET.md) - Tester Window 1 run sheet
- [bricks/COMPONENT_ASSIGNMENT_TEMPLATE.md](archive/bricks/COMPONENT_ASSIGNMENT_TEMPLATE.md) - brick template - closed experiment
- [bricks/COMPONENT_GATE.md](archive/bricks/COMPONENT_GATE.md) - the brick methodology - a closed experiment (IDEA-301)
- [bricks/COMPONENT_INTEGRATION_REVIEW_TEMPLATE.md](archive/bricks/COMPONENT_INTEGRATION_REVIEW_TEMPLATE.md) - brick template - closed experiment
- [bricks/COMPONENT_MANIFEST_TEMPLATE.md](archive/bricks/COMPONENT_MANIFEST_TEMPLATE.md) - brick template - closed experiment
- [experiments/E0_2026-09-19.md](archive/experiments/E0_2026-09-19.md) - experiment record
- [experiments/E25_2026-09-21_walk-in.md](archive/experiments/E25_2026-09-21_walk-in.md) - experiment record
- [experiments/E26_2026-09-22_weather-sync.md](archive/experiments/E26_2026-09-22_weather-sync.md) - experiment record
- [experiments/E27_2026-09-22_vehicle-collection-encounter.md](archive/experiments/E27_2026-09-22_vehicle-collection-encounter.md) - experiment record
- [wp/BATCH-1.md](archive/wp/BATCH-1.md) - completed work package
- [wp/BATCH-2.md](archive/wp/BATCH-2.md) - completed work package
- [wp/M0.1-dev-loop-bootstrap.md](archive/wp/M0.1-dev-loop-bootstrap.md) - completed work package
- [wp/M0.2-database-and-probes.md](archive/wp/M0.2-database-and-probes.md) - completed work package
- [wp/M2.1-ncm-driver-identity.md](archive/wp/M2.1-ncm-driver-identity.md) - completed work package
- [wp/M2.2-issued-car.md](archive/wp/M2.2-issued-car.md) - completed work package
- [wp/M3.1-schedule-and-venue.md](archive/wp/M3.1-schedule-and-venue.md) - completed work package
- [wp/M3.2-the-race.md](archive/wp/M3.2-the-race.md) - completed work package
- [wp/M3.3-results-and-second-driver.md](archive/wp/M3.3-results-and-second-driver.md) - completed work package
- [wp/M4-lite-invitational-foundations.md](archive/wp/M4-lite-invitational-foundations.md) - completed work package
- [wp/M7-lite.0-staging-server.md](archive/wp/M7-lite.0-staging-server.md) - completed work package

---

## Where the archive is

docs/ncm-online/archive/ holds every SUPERSEDED and HISTORICAL document, moved with git mv so history is
intact. **Nothing was deleted and no stub files were left behind** - a stub would recreate the exact
equal-discoverability problem this map exists to solve. All 27 moves had their inbound and outbound links
repaired, and a gate assertion in tools/ncm-test.ps1 keeps them from dangling.
