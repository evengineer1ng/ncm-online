# NCM Online — staged implementation plan

> **STATUS: CURRENT** - authority for: *milestone vocabulary (M0-M12) ONLY; current sequencing is 24* - affirmed 2026-09-24 (L39-L42, L59-L63)
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

Date: 2026-09-19, amended 2026-09-20 (L39–L42: Race Guide, background-by-default, simultaneous events, tester window moved) and **2026-09-21 (L59–L63: TW1 is a controlled multiplayer QA/capture session; TW2 is the first showcase; priority = TW1 operability)**. Status: **approved with amendments; Batch 1 live validation in progress; Batch 2 = TW1 host kit.** Companion to [01_ARCHITECTURE.md](01_ARCHITECTURE.md); decisions in [DECISION_RECORD.md](DECISION_RECORD.md). Experiments (E#) are from [OPEN77_EXPERIMENT_PLAN.md](../research/open77/OPEN77_EXPERIMENT_PLAN.md) plus the additions in the decision record.

Rules of the plan: every milestone belongs to the architecture (no throwaway demos); each has entry dependencies and an exit gate; solo-runnable gates come first (P15: local server + up to two in-world clients on this PC); milestones needing more humans are batched into **tester windows**; an extracted core slice is not done until both hosts consume it (L26), tracked as SP re-adoption passes (R#) interleaved rather than deferred. Sizes are relative (S/M/L/XL); no calendar dates.

```
M0 ─► M1 ─► M2 ─► M3 ─► M4-lite ─► M7-lite ─► Batch 1 (opening, incidents, vocabulary) ─► Batch 2: Race Guide + host kit + rolling start ─► validation pass ─► [TW1: controlled multiplayer QA + capture, 3–5 testers]
            │      │                                └─► fixes/regression ─► M1-debt, M4 (rest), M5, M6, M7 (rest), TW2 readiness ─► [TW2: first showcase — the Formula event]
            │      └────────► M8 (disciplines) ──────────────► M9 ─► M10
            └─ R1 … R4 (SP re-adoption passes, after M1/M3/M4/M7)
   M11 (framework & operator surface), M12 (presentation/broadcast), M13 (integrity tier-up) trail as needed
```

Tester windows (revised 2026-09-21, L59–L63): **TW1** is a controlled multiplayer QA + footage-capture session with 3–5 OPEN//77 alpha testers — short controlled runs across disciplines, host-driven scenarios, stop/restart/reposition allowed; readiness = the host can create, reset, observe and debug sessions with a small variable field of remote clients. **TW2** is the first showcase and inherits the inaugural-race chain CONNECT → OFFER → ACCEPT → PICKUP → ARRIVAL → GRID REVEAL → ASSIGNED CAR → STAGING/LIGHTS → RACE → RESULT (L43, now TW2's), degrading gracefully below 20 cars. The earlier TW1 analysis in [04_TESTER_WINDOW_1.md](archive/04_TESTER_WINDOW_1.md) now describes TW2 readiness. Progression: local/internal QA → TW1 → fixes/regression → TW2 readiness → TW2.

Sequencing note (2026-09-20): M2/M3 were cut as a vertical slice ahead of M1's horizontal work (standings, points, box scores, SP fixtures, R1). That **M1-debt** is scheduled right after M3.3 passes, because M4 standings depend on it and it is the first time SP consumes core (L26).

---

## M0 — Foundations and harness (S/M)

**Goal:** a reproducible dev loop on this PC and the skeleton every later stage fills.

- Repo layout per architecture §1; `ncm/core` skeleton with the `Core` registry loader; CET `require` shim; build step that vendors core into resources.
- Local Lua 5.4 runner for core tests/fixtures (no game needed); fixture generator harness that loads current SP modules with `MTE`/`Game` stubs.
- OPEN//77 local stack via the agent-testing toolkit: master, dev server, one client; second client under a distinct identity profile; save-folder backup script (P15).
- Minimal `ncm_world` resource that loads, binds identity, holds readiness and prints `ncm.where` diagnostics; DB schema v1 migration runner (`Open77.database.ready`).
- **E0** executed: build pin recorded, event-bus semantics probed (VM-local vs host-wide), permission denial/allowance behaviour, restart cleanup, `Open77.tunables` round-trip.
- **E13 (part 1)**: required-mod pipeline dry run — host one inert NCM archive, confirm the launcher consent flow; confirm CET/redscript packages are refused unverified; **determine whether content requirements can be scoped/installed below whole-server join** (per-resource `preload_mod`, optional packages, late install). If not, record the platform constraint and present reference-server/profile options for decision (L25). No pre-emptive second profile.

**Exit gate:** two clients from this PC connect to the local server, both see each other, `ncm.where` answers for both, DB migrations apply, core test runner passes an empty suite, E0 record written.

## M1 — ncm-core slice 1: vocabulary, course, timing, standings (M)

**Goal:** the shareable heart exists with fixture parity (**E12**).

- `vocabulary` (ids, provenance, context, effects), `course.nodes/routes/gates/grid` (from nodes/roots/routes/checkpoint/grid_solver + new gate geometry), `timing` (countdown phases, classification, gaps, finish resolver, tie policy), `rules.points/rulesets` (from championships), `competition.standings/boxscore/record` (from championships/records), `packs` schemas + validator.
- `tools/export_pack`: SP nodes/roots/circuits → pack #1 candidate with diagnostics (**E1**, data half).
- Fixtures captured from SP for: schedule generation (seeded), standings from result sets, box-score envelopes, grid geometry cases, gap/classification cases, countdown phases.
- **R1 (SP re-adoption pass 1):** SP `championships.lua` standings/box-score computation calls core; behaviour identical under fixtures; SP playtest gate for championship UI unchanged.

**Exit gate:** fixture suite green; pack #1 candidate validates (with `incomplete` flags on endpoint-only roots); SP consumes the standings slice without regression.

## M2 — World layer v1: enter Night City as an NCM driver (M/L)

**Goal:** a person joins the reference world and *exists* as a persistent NCM driver (L10, L11).

- `ncm_world`: identity binding + NCM Driver ID minting (P2), driver profile (dimensions stub per Q19 default), zero-balance ledger accounts (L21), presence, places (venues/garages as content), activity feed stub.
- Provisioning v1: `issued` and `loaner` canonical vehicles at zero cost; `owned` schema present but unused; `vehicle_assignment` relation from day one (L28); vehicle return/cleanup on disconnect/restart.
- World is Night City (L30): places are content you can drive to; no hub-to-hub navigation model.
- Topology service v1: bucket allocator with reserved ranges; `isolated` (population/time/weather policy) and `open_world` (no-op); `controlled_world` stub pending **E15**.
- `ncm_hud` shell: profile panel, places/blips, notifications, `ncm` command surface; native HUD selectively hidden.
- **E15** executed: two clients drive Tip-to-Trench in bucket 0 with population on; log per-client traffic divergence (positions of vanilla cars near each client) → informs whether `open_world` is acceptable for which formats and how `controlled_world` should behave.

**Exit gate:** a tester (you) joins, gets a driver identity that survives reconnect and server restart, is issued a car, drives the city, sees NCM places and activity; instance allocation and cleanup verified across restart; E15 recorded.

## M3 — Session kernel v1: a proper NCM street event (L/XL)

**Goal:** humans run a real NCM race with server-authoritative gates, timing, five-light standing start, results and settlement (**E2, E3, E7**).

- `ncm_session`: heat instance state machine; observation tick; gates via core + `Open77.zones`; standing start with freeze/control lock, jump-start detection; live classification + gaps; finish resolver with grace; entrant lifecycle incl. `suspended` (disconnect grace, reconnect) and terminal states; result envelope.
- Formats: `point_to_point` (sprint, laps) and `circuit`; topologies `isolated` and `open_world`.
- Backends: `human` only in this milestone, but the backend interface is in place (P9).
- `ncm_league` settlement v1: transactional `settle`, settlement keys, outbox, records, box scores, zero-amount ledger entries; replay/concurrency tests (E7).
- `ncm_hud` race HUD: phase, lights, position/gap/interval, next gate marker (worldui) matching acceptance geometry, results screen.
- **Scheduler v1 (L34, P20):** street series with recurring small-race slots (every 15–30 min) posted ahead; wall-clock start; start venue = route start node area; pings at T−15/−5/−1 (P19); next-race HUD heartbeat (**prototype only — replaced by the tracked-event HUD of M4.1 per L39/L40**); venue prompt "Pay entry fee and enter?" → `checked_in` (L35, P21); AI backfill hook (L36 — the simulated backend arrives in M5, so M3 backfills from a stub that marks seats `simulated` on the timing screen, or runs human-only).
- Short-notice events (P17): "race from here to X" posts an event at T+N minutes through the same scheduler; no instant-start path.
- Practice overlay v1 (P18): map route preview, gate rings, local timer.
- Pack #1 courses authored with gates/grid slots (E1, authoring half) for 3–5 routes incl. Tip-to-Trench and the bundled circuit.
- **R2:** SP `checkpoint.lua`/finish-line semantics replaced by core gates where safe (SP keeps its radius fallback), SP timing text helpers from core.

**Exit gate:** E2 (two clients, ten valid runs, scripted invalid cases rejected, declared tie policy), E3 (ten clean lifecycle cycles incl. disconnect in each phase and resource restart), E7 (100× replay → one result; concurrent finalizers → one) all recorded as passed; a **posted** street event runs end-to-end — ping → drive to venue → enter at the prompt → race → result — from the HUD without console use.

## M4 — League v1: race guide, calendar, weekends, seats, race control, spectators (L)

*Split (2026-09-20): **M4-lite** (organized/invitation events with `registered` entries, teams/seats/rosters, race-control abort/DSQ with audit) runs before TW1; M4.1 Race Guide, spectators, standings HUD and HTTP routes follow TW1.*

**Goal:** organized motorsport with structure (L18, L19, L23, L24), discovered through the Race Guide (L39–L41).

- **M4.1 Race Guide and the interest model (first package of M4):** on-demand guide page (WebUI; key + command) listing the whole posted horizon across all series — series, start/countdown, venue, class/vehicle requirements, grid capacity, Interested count — served by request/response (not one `GlobalState` blob). `interest` relation (driver × event; no capacity effect; expires when entries close). **Tracked event** = the player's chosen interested event (client preference, default soonest): only it gets the countdown/distance HUD, the auto-waypoint and the T−15/−5/−1 pings; the persistent M3 heartbeat card is retired. Server publishes sessions keyed per session (`ncmSessions[sessionId]`) so simultaneous events (L41) have no single "server race"; the HUD follows the session the driver is entered in. Grid capacity per ruleset enforced at physical entry (L35); interest never reserves. Interest counts feed M5 backfill sizing.
- Events as first-class objects with sessions (practice / qualifying solo + shared / race); rare big events on the calendar (L37) with advance registration; entry rosters (exchange/endurance-ready); event → N sessions split policy in schema (L38; splitting logic later).
- Teams (content + player-created), seats, occupancy, reserves, displaced-fictional states; standings with ruleset-defined absence/substitution and provenance counting; audit log.
- Race control: automated director + ACL commands (`ncm.rc.*`) + decision log; consequences resolved by ruleset (SR, sporting/championship/grid penalties, DSQ).
- Spectators: bucket admission as non-entrant, spectator HUD (**E14**).
- Driver/event browser in HUD: calendar, register, standings, box scores; public HTTP read routes (`Open77.http.listen`) for standings/results JSON.
- **R3:** SP careers/records record-keeping consumes core `competition` and `record` keying (context = sp).

**Exit gate:** a grassroots street championship round (quali + race) runs with registered entries, a spectator, one race-control correction with audit trail, standings and records published; results visible in HUD and over HTTP.

*(Tester window 1 no longer sits here — see L43: after M4-lite → M7-lite → M7.5.)*

## M5 — Simulation service and the living league (M/L)

**Goal:** the world moves without you (L17, P7; **E11**).

- `ncm_sim`: server-world roster population (seeded, persisted, catch-up once per interval), ambient scheduler (district windows), statistical resolution, box scores/activity feed entries, fictional driver states.
- `simulatedAI` backend v1: simulated entrants appear on the live timing screen of a session (sector timelines), score with provenance `simulated`; **AI backfill of thin posted slots goes live (L36)**.
- Ambient events visible as *activity* (markers/feed/chatter) without physical cars.
- Restart/replay determinism tests; host-budget measurements.

**Exit gate:** identical seed → identical league; restart mid-schedule matches uninterrupted run; one event settles exactly once whether simulated or live; roster-scale workload within budget.

### ▶ Tester window 1 — moved (L43)
No longer after M5. TW1 is the inaugural NCX invitational race, placed after M4-lite → M7-lite → M7.5 (see the diagram and [04_TESTER_WINDOW_1.md](archive/04_TESTER_WINDOW_1.md)). The street-world tester journey of L32 becomes the goal of the **second** street-world window after M5 (fields never empty, Race Guide live).

## M6 — Physical AI backend and promotion (L; measurement-heavy)

**Goal:** fictional drivers physically appear where the platform can carry them (**E4, E5, E6**; L17).

- `physicalAI` backend: canonical vehicle + optional visible NPC driver (`record` + `appearance`), `followRoute` over course AI paths (chunked ≤64), speed/behaviour mapping from core driver traits within the 55 m/s cap, blocked/failed handling, fallback to `simulatedAI` with provenance change, owner-loss handling.
- Promotion orchestration: relevance (humans nearby in the right bucket) × suitability (route validated for AI) × budget → materialize an ambient event; demote preserving state; join/spectate a promoted event.
- `controlled_world`: population control around events; optional server-owned obstacle fleet (from E15 findings).
- Measurements: E4 (one AI on an NCM course, 9/10 completions), E5 (fleet 1→4→8 with two clients, handover, observer FPS), E6 (mixed human+AI timing, no provenance leaks).

**Exit gate:** measured fleet cap and route/class allow-list recorded in the street pack; a tester encounters a promoted ambient race and can enter it; mixed results are explainable.

## M7 — NCX content pack #2 (M/L)

*Split (2026-09-20): **M7-lite.0** = a Windows Lightsail staging server with a routable endpoint (the master publishes no catalogue row for loopback/private addresses, so hosted mods cannot be proven from a home LAN; wp/M7-lite.0-staging-server.md). **M7-lite** (E13 part 2 with unsecured consent, RB15 + livery delivery, 20 canonical liveried RB15s on a grid = E3b, ten-team seat data, **migration 006: `team_car`, `message`, `driver_profile.onboarding_json` — P29/P30**) runs before TW1; the rest of M7 (weekend template, fictional seats, shared-track qualifying, E9) follows TW1. **M7.5 TW1 slice** (new): **inaugural onboarding (L48): Driver Profile questionnaire → affinity hat, orientation film (E23), Messages v0 panel**, NCM Messages v0 (P23), sorting hat (L45/P31), pickup/convergence/reveal + holding stage (P24), dispersed spawn, invitation-only event class, **venue substrate (P26: VenueDefinition + loader + drafting export), **course primitive: stages with alternative gate groups + per-entry Route Plans + deviation policy (P32/P33, L49) and the Pacifica Stadium scouting pass (E24)**, venue scouting + inaugural venue build (L46), crowds and audio per E19–E21 (P27), traffic policy per E22 (P28), incident/damage time penalties + corrected-time classification, PA if it passes the quality bar (L47)**, ops kit, rehearsal.*

**Goal:** the same driver/world/platform issues a #77 Kimiko Formula car for a championship round (L27, L12, L13). Pack #2 introduces NCX Formula — cars, teams, liveries and canonical weekend content — **not a circuit-only discipline (L31)**: Formula entries may run circuits, point-to-point routes and other NCM event types where rulesets permit.

- **E13 (part 2):** `ncm_rb15_liveries` archive as `preload_mod`; RB15 base via player-fetch policy; verify the join flow with a second identity.
- **E3b:** 20 canonical RB15s with per-entry `appearance` on the grid, two clients observing.
- Pack #2: RB15 spec class, 10 teams / 20 seats with liveries, fictional roster seeds, authored circuits plus at least one point-to-point Formula-eligible route, canonical weekend template (format chosen at this point — Q21), works-team absence/substitution ruleset, simulated seats allowed, ceremony level high.
- Shared-track qualifying session kind; performance-ceiling profile for the class (**E9** first pass).
- Physical AI seats enabled only if E16 (cap raise) has landed; otherwise all fictional seats are `simulatedAI` on the timing screen.

**Exit gate:** an NCX round (per chosen template) runs with humans in seats, fictional drivers scoring, liveries correct on both clients, standings/box scores published.

### ▶ Tester window 2 — the NCX round
The contrast demo: street car through Tip-to-Trench in the morning, issued Formula car for an organized round in the evening.

## M8 — Discipline breadth (L, parallelisable after M3)

Drag (lanes, straightness penalty, official time), knockout (checkpoint eliminations), endurance (stints, driver substitution on entry roster), vehicle-exchange/triathlon (legs with server vehicle reassignment, Formula→bike→sports car), rolling and side-by-side starts, bike classes, `open_world` championship ruleset. Each format ships with core rules + fixtures + a pack #1 ruleset.

**Exit gate per format:** one full session of the format runs with two clients and (where allowed) simulated seats; fixture parity with SP where SP has the format.

## M9 — Driver dimensions, SR online, records and accomplishments (M)

Progression model per Q19 decision (design pass first): per-discipline grades, SR from server-observed incidents (E8 findings), accomplishments, public profiles; records browser; no gating in the first world unless a ruleset opts in. **R4:** SP SR math consumes core `rules.sr`.

## M10 — Ownership, garages, eligibility and economy switch (L)

`owned` vehicles via `getProperties` round-trip, garages as places, `byo` via adoption policy in world buckets, homologation/eligibility per ruleset, class performance ceilings (E9 complete). Economy design (Q20) then ledger activation per server; entry fees/payouts/rentals become non-zero without touching settlement.

## M11 — Framework and operator surface (M, continuous)

Tunables promoted to a documented set; server profile examples (street-only world, NCX-only server, broad world); pack schema and ruleset schema documented with validators; extension points for backends/read routes; second-server flavour test (an NCX-only profile boots without the street pack).

## M12 — Presentation and broadcast (M, platform-gated)

Public stats site fed by HTTP routes; replay/telemetry exports (E8); remote-camera spectating and world screens when `Open77.remoteCamera` is published; player models for drivers when available.

## M13 — Integrity tier-up (as needed)

Continuity thresholds, anomaly flags on results, `sanctioned` gating, ranked categories per ruleset, optional client attestation — all additive over M3's foundations (P11).

---

## Cross-cutting tracks

| Track | Content |
|---|---|
| **SP re-adoption (R1–R4+)** | After M1, M3, M4, M7/M9: bounded passes, fixture-verified, SP playtest-gated. A core slice is not done until SP consumes it. |
| **Platform requests** | E16 AI speed cap (owner, Discord); server-readable drivetrain (after E8); per-event mods (if needed); track `open77_changes` per build and re-pin the adapter. |
| **Content authoring** | Route authoring loop (export → author gates/grid/AI path → validate → drive-test) is a first-class tool from M3 onward; livery pipeline already exists. |
| **Documentation** | Player guide for the reference world before tester window 1 (now after M5); operator guide before M11 exit; decision record kept current. |

## Validation gates summary

| Gate | Milestone | Evidence |
|---|---|---|
| E0 | M0 | build/bus/permissions/restart record |
| E12, E1(data) | M1 | fixture suite, pack validator output |
| E15 | M2 | traffic divergence log |
| E1(authoring), E2, E3, E7 | M3 | ten-run logs, adversarial cases, replay/concurrency tests |
| E14, E10(field) | M4 / window 1 | spectator + race-control audit, tester feedback |
| E11 | M5 | determinism + budget measurements |
| E4, E5, E6 | M6 | AI completion rates, fleet cap, mixed-timing results |
| E13, E3b, E9(first) | M7 | mod pipeline, 20-car livery grid, ceiling measurements |
| E8, E9 | M9/M10 | telemetry dictionary, ceilings by class |

## What is deliberately not in the plan yet

Economy values (Q20), progression tuning (Q19), the canonical NCX format (Q21), what exists between races beyond hooks (Q22), a driver/contract market (Q23), cross-server identity infrastructure (L11 long-term), NCM-native racing line, MT verification. Each has a home in the architecture and a default so it can be added without re-architecting.
