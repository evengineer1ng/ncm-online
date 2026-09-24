# NCM → OPEN//77 capability matrix

Assessment: 2026-09-18; OPEN//77 documentation build 2.31.13+op77.78. Decisions are proposals, not completed ports. Evidence: [NCM execution map](NCM_ARCHITECTURE.md), [platform and pinned Race investigation](OPEN77_RECON.md). Experiment IDs refer to [the experiment plan](OPEN77_EXPERIMENT_PLAN.md).

## Classification

**KEEP** useful rules/data/concepts; **PORT** implementation plausibly moves after dependency isolation; **ADAPT** change semantics/ownership; **REWRITE** implementation boundary fundamentally unsuitable; **REPLACE WITH OPEN//77** delegate a verified platform primitive; **OPTIONAL** server policy; **NOT APPLICABLE ONLINE** specific single-player behavior has no online role; **NEEDS EXPERIMENT** feasibility unproved; **BLOCKED BY CURRENT OPEN//77** a necessary capability is explicitly absent/restricted in the inspected surface. Multiple labels deliberately separate a useful concept from an unsuitable implementation. None means delete the single-player version.

## Physical racing and course infrastructure

| Subsystem / NCM source | Classification | Reason, online owner and integration decision | Proof |
|---|---|---|---|
| Boot/service registry (`init`, MTE) | REWRITE | CET lifecycle and mutable singletons cannot represent many heats/accounts. Resource bootstrap owns services; race instances own transient state; manifest replaces server require loading | E0, E12 |
| Race lifecycle (`racing`) | KEEP, REWRITE | Preserve configuration/readiness/qualifying/countdown/race/resolution semantics; implement explicit server heat records and client projections. Do not network the 7K-line orchestrator wholesale | E2, E3 |
| Event bus (`events`) | ADAPT, REPLACE WITH OPEN//77 | Keep local domain notifications; use platform transport for validated commands/public updates. Local pcall callbacks do not make a result durable or authorized | E0, E7 |
| Route names, node IDs, roots/packs | KEEP, PORT, ADAPT | Convert coordinates/direction/profile metadata with a versioned exporter. Server validates imported routes; record original IDs and revision/hash | E1 |
| Endpoint telemetry polylines (`routes`) | REWRITE | Two-point line and thirds are insufficient road course geometry. Preserve legacy identity but generate explicit sectors from an authored sequence | E1, E8 |
| Circuit/checkpoint sequences | KEEP, ADAPT | Explicit NCM circuit data is a stronger conversion seed; target Race permits 96 checkpoints but AI route tasks only 64 destinations. Scoring gates and AI path nodes need separate arrays | E1, E4 |
| Checkpoint validation (`checkpoint`, Racing crossing) | REWRITE, REPLACE WITH OPEN//77 | Platform supplies positions/authority, not a turnkey fair NCM validator. Use server ordered 3D gates and swept crossing; independently strengthen reference Race against teleport-inside, wrong car/bucket and stale reports | E2 |
| Timing/finish resolution | KEEP, REWRITE | Server clock and acceptance ledger own human times. Define same-tick ties, DNFs, grace and disconnect rules. Never use NCM estimated finish to rank an unobserved human as physically finished | E2, E6 |
| Sprint/drag/endurance/knockout formats | KEEP, PORT, ADAPT | Preserve useful format rules behind a format contract. Reference Race covers sprint/circuit, not all NCM semantics. Per-participant knockout, endurance completion and drag false-start rules require new implementations | E2 then format-specific tests |
| Qualifying | KEEP, ADAPT, OPTIONAL | Per-entrant verified runs or dedicated qualifying sessions produce grid order. AI projected times may seed fictional competitors only and must be labeled; avoid combining unmarked simulated and measured qualifying records | E3, E6 |
| Grid geometry (`grid_solver`) | KEEP, ADAPT, NEEDS EXPERIMENT | Reuse placement ideas/offline calculations; server validates occupied slots, roads/elevation and capacity. OPEN//77 handles spawn/seat/readiness/control policies; rolling starts need an additional protocol | E3 |
| Vehicle lifecycle/mount fallbacks (`ai_vehicles`) | REPLACE WITH OPEN//77 | Canonical creation, occupant assignment, routing scope and cleanup belong to the platform. Existing native entities/handles are local and cannot become trusted network IDs by wrapping them | E3, E4 |
| Physical AI driving | ADAPT, REPLACE WITH OPEN//77, NEEDS EXPERIMENT | Use leased platform tasks for network motion; retain race-specific strategic decisions only where supported. Native chase/autonomous command branches should remain in SP adapter | E4–E6 |
| Empty-server physical AI races | BLOCKED BY CURRENT OPEN//77 | No eligible client means no vehicle physics. Use explicit off-screen simulation instead; actual headless autonomous racing needs platform changes or a continuously connected simulation client with its own operational costs | E5 confirms behavior |
| AI skill/personality/hardware pace | KEEP, ADAPT, NEEDS EXPERIMENT | Logical driver traits remain useful for simulation/selection. Platform speed/behavior does not expose a full racing skill controller; test measurable differentiation without unrealistic speed caps | E4, E9 |
| Ghost/projected fallback | KEEP for simulation, NOT APPLICABLE ONLINE for human finish substitution | Preserve availability of simulated fiction; distinguish `physical`, `simulated`, `estimated`, `DNF` provenance. Server policy may continue an AI event statistically, never silently rewrite competitive human observations | E6, E11 |
| Native traffic/ambient entities | NEEDS EXPERIMENT, BLOCKED BY CURRENT OPEN//77 for adopting arbitrary traffic | Registered server vehicles can be controlled; ordinary local traffic is not canonical. Do not port NCM entity scanning as online competitor discovery | E4, E10 |

## League, career and economy

| Subsystem / NCM source | Classification | Reason, online owner and integration decision | Proof |
|---|---|---|---|
| Career selection/progression (`careers`) | KEEP, ADAPT, REWRITE storage | Replace one active career/literal V with authenticated account and per-server career IDs. Separate personal unlocks from season points; client asks, server decides | E7 |
| Persistent roster (`roster`) | KEEP, PORT, ADAPT | Strong server-owned domain candidate. Seeded fictional IDs coexist with human account-backed competitors. Inject clock/RNG/store; remove active-career globals; preserve migration/provenance | E11, E12 |
| Population catch-up | KEEP, ADAPT | Advance once for a bounded server time interval, not once per joining player. Persist deterministic simulation cursor and seed; avoid multiplying catch-up after restart | E7, E11 |
| Named rivals (`named_rivals`) | KEEP, ADAPT, OPTIONAL visuals | Logical characters need no world NPC. Native Character records/localized archives are an optional representation requiring client asset compatibility | E4, E10 |
| Championships (`championships`) | KEEP, PORT, ADAPT | Shared season schedules/standings plus individual participation/unlocks. Define missed rounds, substitutes, AI vacancies, ties, rule revisions and admin corrections | E7, E11 |
| Team/faction standings | KEEP, ADAPT | Separate team membership and season scoring from district heat. Snapshot membership per event; authorize transfers to prevent retroactive point movement | E7 |
| Ambient race calendar (`ambient_races`) | KEEP, PORT, ADAPT | A valuable living-league service without physical cars. Server scheduler chooses simulated versus promoted-live state; claim an event once so the scheduler and live heat cannot both finalize it | E7, E11 |
| Driver management (`management`) | KEEP, ADAPT, OPTIONAL | Current one-driver contract is real; online ownership, availability and conflicts need server enforcement. Do not promise a full multi-car team manager from this implementation | E7, E11 |
| Box scores | KEEP, PORT, ADAPT | A primary shared read model for fictional and human events, with participant/source/route/rules revisions. Publish only after durable finalization; page and filter instead of shipping the entire history | E7, E10 |
| Records/history | KEEP, ADAPT | Key records by route revision, discipline, class/build rules and physical/simulated status. Server accepts verified event results; invalidated records need an audit trail | E2, E7 |
| Reputation/prestige/unlocks | KEEP, ADAPT, OPTIONAL policy | Retain progression concepts; server calculates rewards. Rebalance repeat-event farming and distinguish public competition from private sandbox events | E7 |
| Payouts/bounty/hype | KEEP, ADAPT, REWRITE effects | Replace Game inventory credit with a server ledger or explicit host-economy adapter. Validate hype inputs and use idempotent award IDs; no payout inferred from a client HUD/result | E7 |
| Betting (`betting`) | KEEP concepts, REWRITE, OPTIONAL | Server locks picks/odds/stakes before eligibility deadline, escrow and settlement atomic with result state. Specify cancellation/refunds, self-betting/collusion/admin policies. Defer until trusted results and ledger exist | E7 then separate adversarial betting tests |
| Heat/district effects | KEEP, ADAPT, OPTIONAL | Resolve global versus per-player/server heat explicitly; current wall-clock scaling differs from wording. Native police effects are a separate online compatibility question | E10, E11 |
| Quick Race/sandbox | KEEP, ADAPT | Casual event policy must state exactly which ledgers change. Existing finalizer isolation discrepancy must not become the server contract | E7, SP documentation playtest |

## Builds, presentation and platform support

| Subsystem / NCM source | Classification | Reason, online owner and integration decision | Proof |
|---|---|---|---|
| Parts/inventory/loadouts (`parts`) | KEEP, ADAPT, REWRITE persistence | Server inventory and eligibility can preserve useful build choices. Effects must be restricted to supported verified controls; cosmetic/simulation-only parts must be labeled honestly | E7, E9 |
| Tuning (`tuning`) | ADAPT, REPLACE WITH OPEN//77, NEEDS EXPERIMENT | Server performance ceilings support class balancing. Native TweakDB multipliers are not per-network-instance state and cannot be blindly ported | E9 |
| Full per-instance handling upgrades | BLOCKED BY CURRENT OPEN//77 documented performance surface | No verified equivalent for arbitrary tire/suspension/gear/power increases. Uniform mod packs may change baselines, but do not establish synchronized per-car NCM tuning | E9; platform request if required |
| Telemetry (`telemetry`, race_telemetry) | KEEP schemas, REWRITE acquisition, NEEDS EXPERIMENT | Server motion is owner-reported and less rich than client drivetrain/wheel data. Store sample time, age, units, owner epoch and source; optional client traces are diagnostic, not authoritative awards | E8 |
| Safety rating/incidents | KEEP concepts, ADAPT, NEEDS EXPERIMENT | Server can apply rules only to available evidence. Contact magnitude alone cannot determine fault; avoid automated punitive ratings based on unvalidated client reports | E8 |
| CET/ImGui dashboards | REWRITE online, KEEP SP | WebUI/read models suit server UI. Preserve useful information hierarchy, not draw-time side effects or local data ownership | E10 |
| Native HUD/maps/course presentation | REPLACE WITH OPEN//77, ADAPT | Use resource anchors/blips/world UI/props with ownership and cleanup. Keep semantic cues/locale text; course geometry owns matching visible and scoring volumes | E1, E10 |
| SMS/contact narrative (`phone_bridge`, contacts/fan) | KEEP narrative, ADAPT, REWRITE transport | Shared fictional contacts can react to league events; conversation/unlocks/offers are private per-player state. Targeted responses must not leak through public player bags | E7, E10 |
| Phone quest-fact command transport | NOT APPLICABLE ONLINE, REWRITE | Local quest facts/dedup sequence are not an authenticated network protocol. A future native phone view may call online commands, but cannot own their authority | E10 |
| Onboarding/quest assets | KEEP experience goals, ADAPT, NEEDS EXPERIMENT | Online guide must teach joining a server/heat and personal versus shared progression. Native journal assets need coexistence tests; a WebUI onboarding path reduces initial dependence | E10 |
| Localization/voice authoring | KEEP, PORT, OPTIONAL audio | Text IDs/fallback/placeholder checks are reusable; server sends semantic payloads, clients localize. Confirm asset rights/distribution separately; voice harness is not proof of runtime audio | E10 |
| Settings and extension data | KEEP, ADAPT | Separate operator rules/ACL, immutable course/rules packs and player presentation preferences. Clients cannot override competitive tuning, payouts or event format | E0, E12 |
| JSON storage and migrations | REPLACE WITH OPEN//77, REWRITE transactions | Scoped files suit packs; SQL transactions suit ledgers/results. Existing backup/migration behavior and multiple save calls do not support concurrent durable finalization | E7 |
| Optional MT/RadioOS adapters | OPTIONAL, NEEDS EXPERIMENT | Do not make personal integrations server requirements. Compatibility and permission review must precede signed server packaging | E9, E10 |

## Proposed ownership and minimum result contract

This is a design proposal, not an existing NCM or OPEN//77 schema. A reusable result envelope should include `serverId`, `raceId`, `seasonId?`, `routeId + revision`, `rulesetId + revision`, entrant identities, vehicle/build snapshots, start/finish observations, penalties/DNF reasons, finalization version and **provenance per entrant**. A deterministic unique settlement key prevents duplicate economy/progression effects. Keep private betting/account records out of the public box score.

The server owns acceptance, standings, seasons, inventory, bets, private narrative state and simulated drivers. Clients own input and presentation and provide physics observations within OPEN//77's trust model. Shared domain code owns formulas and state transitions only; persistence/network/native APIs live behind adapters. Client-shared formula code is public, so secret odds/state/anti-abuse decisions must remain server-side.

## Decision summary / status

The matrix supports a human-racing plus persistent-league product independently of physical AI. AI-only *simulated* seasons are feasible engineering; AI-only *physical* empty-server races are currently blocked by simulation ownership. Rich parts progression can survive as a domain system, but physical tuning parity cannot be promised. Next: use E0–E3 and E7 to validate the human/league foundation; E4–E6 and E9 determine optional product scope before major extraction.
