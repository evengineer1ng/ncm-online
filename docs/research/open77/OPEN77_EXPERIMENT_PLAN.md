# Experiments before a port commitment

Date: 2026-09-18. **Designed, not executed.** No multiplayer access/server or test clients were available/used during reconnaissance. Numerical targets below are proposed acceptance gates, not platform guarantees. Review them against intended server size and competitive standard.

All work should start in an isolated prototype after reconnaissance review. Keep NCM production payload and saves unchanged. Pin server/client build, Freeroam/reference commit if used, mod pack, resource hash, hardware, course revision and test identities. Record logs plus observations from both clients; a successful API return is not successful gameplay.

## Order and decision gates

E0 → E1 → E2 → E3 establishes the physical human baseline. E7 proves persistence before any reward feature. E4 → E5 → E6 determines whether physical AI belongs in initial scope. E8/E9/E10 test telemetry, tuning and presentation. E11 validates off-screen league value independently of physical AI. E12 selects shared-core versus native implementation. Do not build a championship UI to compensate for unresolved race acceptance.

## E0 — Reproducible runtime and authoritative boundaries

- **Question:** Can this team deploy and inspect the actual preview, and do the documented contracts match it?
- **Minimum:** Approved two-client access, isolated local server, minimal resource with pinned dependencies, readiness/log output and one authorized request/response. Query official MCP for every used API. Probe local versus host-wide events, server exports, player identity, and teleport permission behavior. Record required ports/resource distribution and one restart. Review NCM redistribution and Race source license before packaging either.
- **Success:** Both clients load the same signed resource set; build IDs and persistent identities recorded; denied/allowed command tests behave as documented or an explicit discrepancy is captured; resource restart cleans up. Secrets excluded from logs/evidence.
- **Failure:** Access/install issues block runtime conclusions, not further pure-domain work. API mismatch triggers pin/change/retest; do not invent compatibility shims around unknown behavior.

## E1 — Convert one NCM course, without pretending endpoints are a road

- **Question:** What can be preserved automatically, and what needs authoring?
- **Minimum:** Read-only exporter for one explicit NCM circuit/ordered route and one endpoint-only root. Preserve source IDs, coordinates, direction, labels and revision hash. Produce a target-schema candidate plus diagnostics. Require explicit grid slots/checkpoint radii/Z bands and separate AI destinations. Mark endpoint-only output incomplete. Do not overwrite original packs.
- **Success:** Every source coordinate/ID maps predictably; no silent omission. Invalid/missing nodes and checkpoint count limits fail clearly. Two clients can visually inspect all gates, including a stacked-road case. A human can complete the authored course without ambiguity. Manual additions are recorded, not hidden in code.
- **Failure:** If too much geometry is absent, scope the first release to validated course packs and provide author tooling. This is not a reason to discard route names/metadata or hand-copy every valid sequence.

## E2 — Two humans, server acceptance and adversarial checkpoint cases

- **Question:** Are ordered progress and timing credible under actual replicated motion?
- **Minimum:** Two fixed cars, one short course, server state per entrant, canonical vehicle/bucket validation and logs of sample/acceptance times. Implement or isolate ordered swept gates with continuity checks. Test legitimate fast passage; wrong order/direction/elevation; wrong car/seat/bucket; repeated/replayed/spammed intent; large jump into a checkpoint; stale samples; disconnect/reconnect; both finish in one tick. Include the reference geometry's endpoint-inside bypass as a regression case.
- **Success:** Ten valid runs each complete without missed gates; all scripted invalid cases are rejected or explicitly quarantined. Client-submitted elapsed time cannot affect ranking. Every accepted gate has an auditable observation. Same-tick ties follow a declared deterministic policy. Report measured timing uncertainty; do not promise millisecond accuracy from 100ms polling.
- **Failure:** Tighten geometry/sample protocol or narrow competitive claims. If canonical observations cannot distinguish required cheating cases, ranked/payout systems remain gated; casual events can be a separate policy.

## E3 — Grid, readiness, countdown and cleanup

- **Question:** Can a heat start fairly and restore every participant after failures?
- **Minimum:** Two human grid slots, assigned cars, ready/seat confirmation, freeze/control lock, authoritative start time, jump-start detection, timeout/DNF/cancel and return cleanup. Repeat with one slow-loading client, late join, disconnect in each phase and resource stop. One optional qualifying run changes slot order.
- **Success:** Ten complete cycles leave no orphan cars/locks/bucket membership. No entrant gains accepted progress before start; slow readiness does not silently change another entrant's clock. Both clients show the same phase, and aborted starts have an explicit result/refund policy.
- **Failure:** Keep staging conservative; do not port standing/rolling grid sophistication until the basic lifecycle is robust. Rolling starts require their own future gate and speed-envelope tests.

## E4 — One physically driven AI on an NCM course

- **Question:** Can platform AI follow this road course usefully, with an observable driver?
- **Minimum:** One server vehicle, optional owned visible NPC driver, one nearby client, short validated destination sequence with bends/elevation. Use platform AI task APIs only. Log task/owner epochs, waypoint/arrival events, speed, stuck duration and checkpoint observations. Compare at least two legal pace/behavior settings and confirm AI speed limit relevance.
- **Success:** At least 9/10 runs complete in order without teleport/rescue; driver seat/appearance is correct on a second observer; completion comes from server race observations rather than trusting the task's arrived event. No persistent combat/seat interference. Measured pace is adequate for the chosen class.
- **Failure:** Restrict AI to suitable routes/classes, use simulation-only competitors, or submit a precise platform issue. Do not reintroduce unsynchronized local NCM spawns to make the test look successful.

## E5 — Fleet, handover and no-observer behavior

- **Question:** Does AI remain coherent with several cars and changing simulation owners?
- **Minimum:** Scale 1 → 4 → 8 AI vehicles with two clients; both stay, owner leaves, authority transfers, clients separate across the course, late observer joins, then all observers leave. Test bucket isolation. Capture frame/tick latency, ownership transitions, task duplication and collisions. Observe documented lack of physical progress without eligible clients.
- **Success:** At intended launch size, at least 9/10 observed heats complete under E4 rules; no duplicate drivers/tasks or phantom results; handover does not accept discontinuous checkpoint progress. Provisional observer client p95 frame-time regression ≤20% against the same scene baseline and no resource budget violations. Empty-server state pauses or switches explicitly to a defined simulation policy, never claims physical completion.
- **Failure:** Set a measured fleet cap or omit physical AI. Empty-server physical operation is a platform capability request; off-screen statistical racing remains independent.

## E6 — Mixed human and AI timing

- **Question:** Can both entrant types share fair race rules and understandable results?
- **Minimum:** Two humans + two tested AI on the same course. Use one acceptance pipeline and race clock; retain different observation/provenance metadata. Test AI stall/owner loss, human disconnect, finish grace and a simulated fallback policy disabled/enabled.
- **Success:** Ten heats produce explainable ranking/DNFs, no human projected finish, and no double result when an AI transitions to simulation. Public results visibly distinguish nonphysical outcomes; ranked eligibility is explicit. Vehicle class/speed rules produce a useful race rather than an uncatchable or inert AI field.
- **Failure:** Separate physical human events from simulated league events, or offer mixed fields only as unranked/experimental. Do not erase provenance to create apparent parity.

## E7 — One durable result, driver and ledger settlement

- **Question:** Can result publication/rewards survive replay, concurrency, crash and database failure?
- **Minimum:** Small schema for accounts/competitors, event/result, standings delta and ledger; server-generated race ID and unique settlement key. Commit using supported SQL transaction API; publish box score only after commit. Replay same result, race two finalizers, disconnect during commit, restart after commit before publication, and fail storage. Use test credits only. Prototype one canceled stake refund before real betting scope.
- **Success:** Replaying a result 100 times and concurrent duplicate submissions produce one result/award. Restart preserves identity and settled standings; pending publication resumes without duplicated effects. Storage failure never reports a paid result. Reject client-selected winner/payout/account; private ledger stays private. Back up and restore the fixture successfully.
- **Failure:** Freeze economy/betting/progression integration until transaction/idempotency design is corrected. Do not fall back to the current multi-file save sequence for online money.

## E8 — Telemetry availability and trust classification

- **Question:** Which NCM measurements can be collected, and with what age/accuracy/trust?
- **Minimum:** Record simultaneous server vehicle snapshots and optional client drivetrain/wheel/input readings for acceleration, braking, turns, collision, handover and no-owner state. Map units and missing fields; sample at a bounded chosen cadence. Compare logs with video/known events, not solely one API against itself.
- **Success:** A field dictionary identifies origin, units, sample age, update rate, missing-value behavior and whether each field can affect competition. Distinguish zero from unavailable. Bounded buffers survive a full heat. Proposed motion freshness target p95 ≤250ms under test conditions is measured, not assumed.
- **Failure:** Reduce online analytics to reliable motion/time fields. Keep richer client traces opt-in diagnostics and avoid authoritative safety/fault penalties based on unverified signals.

## E9 — Performance translation and ownership

- **Question:** What portion of NCM tuning has a real, synchronized physical effect?
- **Minimum:** Two baseline vehicles, three legal server ceiling profiles, stock/NCM build metadata mapping. Measure repeated acceleration/top-speed runs from both clients; swap physics owner. Test client-local instance override precedence and resource coexistence. A separate uniform mod-pack baseline test may follow; never assume arbitrary TweakDB changes replicate per instance.
- **Success:** Selected legal profile survives owner change and has repeatable measured effect. Every proposed part is classified as supported physical, eligibility/cosmetic, simulation-only or unsupported. No advertised power increase derives from a scale API capped at 1. One authority is responsible for handling policy; override behavior is documented.
- **Failure:** Start with spec-car/class-cap racing. Full tuning parity requires a verified new platform primitive or separately validated mod architecture, not additional UI sliders.

## E10 — Presentation, native assets and private narrative

- **Question:** Can NCM's depth become discoverable without destabilizing the multiplayer client?
- **Minimum:** Next-gate anchor matching validation geometry, staging prompt, simple race/results WebUI and one paged box score. Test daylight/night, stacked roads, different aspect ratios and restart cleanup. Send one private contact reply to one account while another observes. Separately add minimum NCM localization/phone archive/redscript layers one at a time; keep native integration optional. Add one prop only after ring behavior is reliable.
- **Success:** A new tester joins, starts and finds results using in-world/UI guidance; accepted gate and displayed gate agree. No private reply appears on another client/state bag. Resource reload removes owned UI/props and restores input. Native asset experiment compiles/loads without breaking platform UI; server delivery manifests are reproducible.
- **Failure:** Use WebUI for the initial online edition; preserve native phone concepts as content rather than importing an incompatible journal stack. Do not block league features on exact SP UI parity.

## E11 — Living league without physical races

- **Question:** Can NCM produce consistent, useful persistent racing activity with bounded cost?
- **Minimum:** Seed a small fictional roster and season; inject server time/RNG; simulate scheduled events, write standings and box scores, restart midway and replay catch-up. Race a scheduler resolution against promotion to a live event. Then scale to the actual NCM roster size and an explicitly recorded larger workload.
- **Success:** Identical seed/events yield identical domain results; restart matches uninterrupted state. One event produces one result whether live or simulated. Catch-up is bounded/chunked, measures no host-budget violations, and does not advance once per client login. Public history identifies simulated events; private career rewards follow declared policy.
- **Failure:** Simplify scheduling/population workload or choose C for this component. Physical AI failure does not invalidate this experiment.

## E12 — Bounded shared-core extraction

- **Question:** Does architecture B deliver useful reuse without dragging engine coupling into the core?
- **Minimum:** In an isolated branch/copy, extract one standings/result-envelope function with plain inputs, explicit identities and injected time/RNG where needed. Run fixed fixtures through SP and server packaging. Compare current NCM outputs and deliberately documented rule changes. No wholesale racing/AI rewrite.
- **Success:** Shared slice has no Game/CET/TweakDB/MTE/save/network dependency; multiple race/account fixtures remain isolated; both hosts use it without environment emulation. Review effort and API clarity against a small independent implementation.
- **Failure:** Select C for heavily coupled components, or reduce the shared boundary. Line-count reuse is not a success metric.

## Experiment record template

Create `experiments/E##_YYYY-MM-DD.md` only when executed: question; build/resource/mod hashes; exact setup and identities (redacted); input fixture/course revision; expected behavior; observed logs/video links; pass/fail/partial by criterion; performance conditions; cleanup; API/documentation discrepancies; product decision; next smallest test. Keep failure evidence. No experiment is marked passed in this reconnaissance.

Status: ordered experiment design complete. Next practical action after review is E0 access/build verification, followed by one course conversion—not a production NCM port.
