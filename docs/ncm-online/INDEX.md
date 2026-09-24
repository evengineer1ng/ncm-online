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
| Organisations, team ownership, governance, grid slots | [14_TEAM_ORGANIZATIONS.md](14_TEAM_ORGANIZATIONS.md) | L92, L93; reaffirmed L123 |
| Foundational primitives, contradictions, build sequencing | [24_FOUNDATION_RECONCILIATION.md](24_FOUNDATION_RECONCILIATION.md) | L123 |
| Environments, promotion discipline (Online vs Development) | [16_ENVIRONMENTS.md](16_ENVIRONMENTS.md) | L112, L121 |
| **Database schema** | CODE: `ncm/online/resources/ncm_league/server/schema/` | - |
| Overall system shape | [01_ARCHITECTURE.md](01_ARCHITECTURE.md) | L28-L33 - see conflict C-1 |
| Milestone vocabulary (M0-M12) only | [02_ROADMAP.md](02_ROADMAP.md) | L39-L42, L59-L63 |
| Nodes, routes, ordered chains | [07_NODE_NETWORK.md](07_NODE_NETWORK.md) | - |
| Economy intent | [08_ECONOMY.md](08_ECONOMY.md) | L84, L85 |
| Markets and market discovery | [17_MARKET_NETWORK.md](17_MARKET_NETWORK.md) | L106, L117 |
| Player-scoped machine knowledge | [16_MACHINE_INDEX.md](16_MACHINE_INDEX.md) | - |
| Discovery and collection | [13_VEHICLE_COLLECTION.md](13_VEHICLE_COLLECTION.md) | - |
| Weather as world state | [11_WEATHER.md](11_WEATHER.md) | - |
| Vehicle artwork | [15_GENERATION_1_VEHICLE_ARTWORK_MANIFEST.md](15_GENERATION_1_VEHICLE_ARTWORK_MANIFEST.md) | - |
| Day-to-day operation of NCM Online | [OPS_STAGING.md](OPS_STAGING.md) | - |
| QA instrumentation mapping | [wp/QA_INSTRUMENTATION.md](wp/QA_INSTRUMENTATION.md) | - |
| Driver Card and Fingerprint direction | [DECISION_RECORD.md](DECISION_RECORD.md#l130--locked--driver-card-expression-and-fingerprint-authority-stay-separate) | L130 |

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

**C-4 - Race Tags (IDEA-301).** The owner recalled it as a shipped post-race feature; the repository shows it
was authored as a brick and never admitted, wired or tested. Owner ruled 2026-09-24 that the repository is
correct and it should be integrated eventually. So bricks/assignments/B-089-race-tags.v1.md is SPEC (wanted,
unbuilt) while the brick methodology itself is HISTORICAL (a closed experiment).

---

## Current (14)

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
- [OPS_STAGING.md](OPS_STAGING.md) - day-to-day operation of NCM Online
- [wp/QA_INSTRUMENTATION.md](wp/QA_INSTRUMENTATION.md) - mapping the QA corpus to instrumentation

## Spec - owner intent, not authorised (10)

- [06_CHROME_ROSTER.md](06_CHROME_ROSTER.md) - vehicle cyberware / quickhack roster
- [09_APPAREL.md](09_APPAREL.md) - apparel entitlement
- [10_SPECIAL_EVENT_FISHING.md](10_SPECIAL_EVENT_FISHING.md) - the fishing special event
- [12_CANONICAL_VEHICLE_ROSTER.md](12_CANONICAL_VEHICLE_ROSTER.md) - the canonical vehicle roster
- [17_MACHINE_PROFILE.md](17_MACHINE_PROFILE.md) - the individual machine biography
- [18_PARTS_ECOSYSTEM.md](18_PARTS_ECOSYSTEM.md) - the procedural component/parts ecosystem
- [19_ENGINEERING.md](19_ENGINEERING.md) - engineering as a career
- [20_WEAR_LIFECYCLE.md](20_WEAR_LIFECYCLE.md) - wear, condition and component lifecycle
- [28_MACHINE_KNOWLEDGE.md](28_MACHINE_KNOWLEDGE.md) - machine knowledge, discovery, documentation, observation and estimation envelopes
- [bricks/assignments/B-089-race-tags.v1.md](bricks/assignments/B-089-race-tags.v1.md) - Race Tags - owner wants it integrated eventually; NOT yet integrated (IDEA-301)

## Proposal - no authority until ruled (7)

- [21_ENGINEERING_PROPOSAL.md](21_ENGINEERING_PROPOSAL.md) - engineering architecture - ACCEPTED; decisions live in L120
- [22_WEAR_PROPOSAL.md](22_WEAR_PROPOSAL.md) - wear architecture - ACCEPTED; decisions live in L120
- [25_MACHINE_ARCHITECTURE_PROFILE.md](25_MACHINE_ARCHITECTURE_PROFILE.md) - machine architecture profile - awaiting Q18/Q19; section 10 undecided
- [26_DOCUMENT_AUTHORITY.md](26_DOCUMENT_AUTHORITY.md) - this scheme - directionally accepted, executed as L125
- [27_ATTRIBUTION_AND_ORIGIN.md](27_ATTRIBUTION_AND_ORIGIN.md) - Stage 0 machine attribution and the origin retirement mechanics - awaiting a ruling
- [29_STATE_BAG_AUDIENCE_AUDIT.md](29_STATE_BAG_AUDIENCE_AUDIT.md) - replication audience of NCM player state-bag mirrors - audited, corrections not applied
- [30_MACHINE_KNOWLEDGE_DEEP_DIVE.md](30_MACHINE_KNOWLEDGE_DEEP_DIVE.md) - what the knowledge substrate already records, and the minimal additive change it needs
- [31_CAPABILITY_AUDIT.md](31_CAPABILITY_AUDIT.md) - what the platform exposes or lets NCM derive about a machine, classified (`IDEA-339`)

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

## Historical - archived, evidence not architecture (22)

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
