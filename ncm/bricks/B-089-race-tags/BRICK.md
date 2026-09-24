# BRICK.md — B-089-race-tags

```yaml
brick: B-089-race-tags
version: 1.0.0
revision: v1
gate: 1
core_version: 0.0.1
module: competition.race_tags
file: competition/race_tags.lua
shape: rule
serves: [IDEA-089, L67, KB-35, KB-38, KB-34]
author: OpenAI external component author
delivered: 2026-09-22
interpreters_run: [lua5.4]
status: candidate
integrated_as: null
```

## Purpose
`competition.race_tags` answers the one-event question “what kind of race/run did this driver just have?” after a session is settled. It turns only facts present in the normalized whole-session input into a small, ordered set of stable-id, plain-English descriptors for each result row. The tags are ephemeral presentation labels; their stable ids may also be counted later by the host as lifetime statistics.

## Scope
- Emits only the sixteen v1 descriptors named by the assignment packet.
- Evaluates the whole settled session and returns one driver output in the same order as `facts.results`.
- Enforces L67 mode-correct language: a time trial may emit `clean_run`, never `clean_race`.
- Derives close finishes from adjacent finishers’ corrected time, falling back to `totalSec` only when corrected time is absent.
- Derives gate-1 order conservatively from crossing telemetry for `good_start` and uses strict earliest-at-gate evidence for `led_every_gate`.
- Keeps descriptor output at `maxTags`, in deterministic `priority` order.
- Treats `route_record` as stronger than `personal_best`; when both conditions are true, only `route_record` is emitted.
- Uses contact severity only; no emitted label distinguishes wall, barrier, object, or car contact while KB-34 is open.

## Explicit non-goals
- **Many Overtakes:** needs actual pass/overtake telemetry, which v1 does not receive. Gate crossing order changes are not approximated as overtakes.
- **Strong Defence:** needs opponent attack/proximity/pass-attempt telemetry plus a sporting definition of defence.
- **Good Recovery:** needs causal position-loss/recovery telemetry sufficient to distinguish actual recovered places from DNFs, penalties, and sparse snapshots.
- **Battle:** needs opponent proximity/side-by-side or sustained contest telemetry.
- **Consistent Pace:** needs a sequence of comparable lap/run times, not only `bestSec` and `runs`.
- **Fastest Sector:** needs sector timing data.
- **Improved Each Run:** needs per-run times in order, not only run count and best time.
- Weather-, region-, or opponent-derived descriptors need those facts supplied explicitly.
- Does not create badges, achievements, unlocks, titles, rewards, progression, profile ownership, toasts, chat, HTML, or persistence.
- Does not decide race vs time trial except for the packet-required defensive fallback when `fieldSize == 1` and `timeTrial` is absent.
- Does not compute classification, corrected time, penalties, incident bands, or blame.

## Files
| Path | Role |
|---|---|
| `competition/race_tags.lua` | Rule module |
| `tests/test_race_tags.lua` | 48 offline test cases |
| `fixtures/race_4cars.lua` | Synthetic four-car race fixture from the packet |
| `fixtures/solo_dirty.lua` | Synthetic dirty solo time-trial fixture from the packet |
| `fixtures/solo_clean.lua` | Synthetic clean solo variant required by the packet |
| `QA.md` | Live QA procedure for the integrator |
| `init.lua` | Provided byte-identical core loader; unmodified |
| `tests/run.lua` | Provided byte-identical test runner; unmodified |
| `provided/vocabulary/ids.lua` | Provided read-only module; shipped as packet cargo, not used by this brick |

## Public interface
`M.evaluate(facts, opts) -> result` — pure whole-session evaluation; returns per-driver ordered tags, or `nil, "unknown_session_kind"` for an unknown session kind.

`M.CATALOGUE` — the complete sixteen-id v1 descriptor catalogue, with stable ids, labels, and applicable session-kind vocabulary.

`M.DEFAULTS.maxTags = 4` — maximum tags emitted per driver; `0` emits none.

`M.DEFAULTS.closeFinishSec = 0.5` — maximum corrected-time separation to the directly adjacent finisher for `close_finish`.

`M.DEFAULTS.clearWinSec = 5.0` — minimum corrected-time P1-to-P2 margin for `clear_win`.

`M.DEFAULTS.gainedMin = 2` — minimum `slot - position` for `gained_positions`.

`M.DEFAULTS.lostMin = 2` — minimum `position - slot` for `lost_positions`.

`M.DEFAULTS.goodStartMin = 2` — minimum provable `slot - gate1Order` for `good_start`.

`M.DEFAULTS.toughIncidents = 3` — minimum `incidentCount` for `tough_one`.

`M.DEFAULTS.priority` — display priority. v1 proposes: `route_record`, `personal_best`, `clean_race`, `clean_run`, `clear_win`, `close_finish`, `led_every_gate`, `came_through`, `good_start`, `gained_positions`, `lost_positions`, `heavy_contact`, `tough_one`, `jump_start`, `penalised`, `did_not_finish`. This is presentation priority only and does not alter descriptor meaning. On `race_4cars.lua`, driver `a` has five supported candidates; the default cap therefore drops `gained_positions`. With `maxTags = 5`, all five are emitted.

## Inputs
Implemented exactly against the packet’s normalized `facts` shape:

```lua
facts = {
    session = {
        sessionId = "string",
        kind = "race" | "quali" | "practice",
        timeTrial = true | false,
        fieldSize = number,
        disciplineId = "string",
        tier = "street" | "sanctioned" | "both",
        gatesTotal = number,
        greenAt = number,
        routeId = "string",
        routeName = "string",
    },
    results = {
        {
            driverId = "string", display = "string", position = number,
            state = "finished" | "dnf" | "dns" | "dsq",
            slot = number,
            totalSec = number, correctedSec = number,
            penaltySec = number, incidentSec = number, incidentCount = number,
            incidents = {}, penalties = {}, jumpStart = boolean,
            gapSec = number, progress = number, dnfReason = "string",
            crossings = {}, bestSec = number, runs = number,
            previousBestSec = number, formationFault = "string",
        },
    },
    routeRecordSec = number,
}
```

Fields documented optional in the packet are treated as absent facts. `formationFault`, `penaltySec`, `incidentSec`, `gapSec`, `progress`, `dnfReason`, `greenAt`, `routeId`, `routeName`, `display`, `disciplineId`, and `tier` are not needed by v1 tag logic. `incidents[*].other` and `attributed` are not used to infer blame.

## Outputs
```lua
result = {
    drivers = {
        {
            driverId = "string",
            position = number, -- omitted by Lua table semantics if input position is absent
            state = "string",
            tags = { { id = "stable_id", label = "Plain English" }, ... },
        },
    },
    diagnostics = { "..." }, -- present only when a diagnostic exists
}
```

`drivers` order is stable and matches `facts.results`. Tag ids and their meanings are stable. Labels are the v1 English title-case vocabulary from `M.CATALOGUE`. Tag order is presentation order and may be tuned in a later version through the documented priority setting. `#tags` never exceeds the effective `maxTags`.

## Dependencies
None. `provided/vocabulary/ids.lua` is included because it was attached to the assignment packet, but `competition.race_tags` does not resolve or use it.

## State owned
None. This is a Rule.

## Persistence requirements
None for the brick itself. The host may later persist counts keyed by emitted stable tag id, as described in the assignment, but this rule neither owns nor writes those counts.

## Assumptions
- `facts.results` is in classified order, as specified by the packet.
- `position`, when present, is already the settled classified position; the brick never re-ranks drivers.
- `correctedSec`, when present, is canonical for finish-gap descriptors; `totalSec` is the packet-required fallback when it is absent.
- For race personal-best and route-record comparisons, `totalSec` is the comparison time, matching the packet’s `previousBestSec == totalSec` boundary case. Quali/practice use `bestSec`.
- A present `incidentCount == 0` is sufficient evidence of no incidents unless a contradictory non-empty `incidents` array is also supplied; contradictory data suppresses a clean tag.
- Missing crossings are absent facts. `good_start` uses a worst-case gate order for missing opponents so it fires only when the improvement threshold is still provable.
- `led_every_gate` uses the packet’s wording “among drivers who crossed it”; the subject driver must have a crossing at every gate, and an equal crossing time prevents a strict earliest conclusion.
- `came_through` requires the winner’s gate-1 crossing and at least one known strictly earlier crossing by another driver.
- Unknown discipline ids are valid and do not change v1 behavior.

## Invariants
- Every emitted id exists in `M.CATALOGUE`.
- No driver receives more than `maxTags`.
- `dns` and `dsq` rows receive no tags.
- No position-based descriptor is emitted for a time trial, quali, or practice.
- `clean_race` is never emitted for a time trial.
- No clean descriptor coexists with supported evidence of incidents, a race-control penalty, or jump start.
- `route_record` suppresses `personal_best` when both conditions hold.
- `led_every_gate` and `came_through` cannot coexist.
- No v1 label contains “wall”, “car”, or “barrier”.
- Race DNF rows cannot receive `personal_best` or `route_record` even if a stray time/history field is present.
- Evaluation does not mutate `facts`.
- Repeated evaluation of the same input and options is deterministic.

## Failure behaviour
Programmer-shape errors use `error("competition.race_tags.evaluate: ...", 2)` for non-table `facts`, non-table `opts`, missing/non-table `session`, missing/non-table `results`, non-string `session.kind`, malformed result rows lacking `driverId`/`state`, invalid `maxTags`, and invalid priority shape/entries.

Expected refusal: `nil, "unknown_session_kind"` when `session.kind` is a string outside `race|quali|practice`.

Absent facts suppress conclusions. Notable examples: no history means no personal/route record; missing subject gate 1 means no good start/led-every-gate/came-through; no quali/practice `bestSec` means no run tags. The one explicit packet exception is race `fieldSize == 1` with absent `timeTrial`: treat as time trial and return diagnostic `timeTrial absent; fieldSize 1 treated as time trial`.

## Edge cases handled
- P2 DNF prevents `clear_win` — `edge_clear_win_requires_finished_p2`.
- Missing `correctedSec` falls back to `totalSec` — `edge_corrected_time_falls_back_to_total`.
- Missing gate 1 on the subject suppresses start/lead/comeback descriptors — `edge_missing_gate_one_suppresses_start_and_led`.
- Equal gate crossing time is not strict earliest — `edge_gate_tie_is_not_led`.
- Quali/practice with no `bestSec` / zero runs gets no tags — `edge_quali_without_best_has_no_tags`.
- Quali/practice may prove clean from an explicitly empty incidents list when `incidentCount` is absent — `edge_quali_clean_run_with_absent_incident_count`.
- Solo race with absent `timeTrial` uses the required L67 defensive fallback and diagnostic — `edge_missing_time_trial_solo_fallback_diagnostic`.
- Exact personal-best equality is not an improvement — `boundary_personal_best_equal_is_not_best`.
- Threshold comparisons are inclusive — `boundary_thresholds_are_inclusive`.

## Tests included
Categories below partition the 48 cases; several cases also prove more than one property.

| Category | Count | Names |
|---|---:|---|
| happy / descriptor coverage | 18 | `happy_fixture_default_cap`, `happy_fixture_max_five`, and all sixteen `emits_*` cases |
| boundary | 3 | `boundary_max_tags_zero`, `boundary_thresholds_are_inclusive`, `boundary_personal_best_equal_is_not_best` |
| invalid / refusal | 4 | `invalid_facts_shape_errors`, `invalid_results_missing_errors`, `invalid_row_identity_errors`, `refusal_unknown_session_kind` |
| absence / edge | 9 | `edge_clear_win_requires_finished_p2`, `edge_corrected_time_falls_back_to_total`, `edge_missing_gate_one_suppresses_start_and_led`, `edge_gate_tie_is_not_led`, `edge_quali_without_best_has_no_tags`, `edge_quali_clean_run_with_absent_incident_count`, `edge_missing_time_trial_solo_fallback_diagnostic`, `never_history_tags_without_history`, `never_tags_dns_or_dsq` |
| invariant | 9 | `catalogue_every_id_is_known`, `catalogue_modes_use_session_kind_vocabulary`, `never_clean_with_dirty_or_penalised_or_jump_start`, `never_position_tags_outside_multicar_race`, `never_more_than_max_tags`, `never_contact_specific_label_words`, `never_clean_conflicts_with_dirty_tags`, `never_led_and_came_through_together`, `never_personal_or_route_record_on_race_dnf` |
| regression | 3 | `kb35_solo_dirty_has_no_clean`, `kb35_solo_clean_is_clean_run`, `kb38_dirty_race_tough_one_not_clean` |
| determinism | 1 | `determinism_same_input_same_output` |
| purity | 1 | `purity_facts_unchanged` |

Last author run:
- Lua 5.4 runtime: `48 passed, 0 failed`.
- LuaJIT 2.1: not available in the author environment; not run. The integrator must run the required second interpreter leg.
- Supplemental syntax/logic run under the available LuaTeX Lua 5.3 runtime also produced `48 passed, 0 failed`; this is not claimed as a gate interpreter.

## Integration points (author's understanding — integrator corrects)
The natural host seam is settlement after the host has normalized the whole session/result set and before the compact post-event presentation is assembled. The host should pass the whole `facts` object once, join each driver’s `tags[].label` with ` · ` for presentation, and may later count `tags[].id` into profile statistics. The brick does not call, emit to, or know about the presentation/profile host itself.

## Live QA required
See `QA.md`. Offline tests cannot prove that the live host supplies the normalized facts at the expected seam, that the compact result banner renders the intended labels, or that the server log records the same stable ids the rule returned.

## Known limitations
- No actual overtake telemetry exists in v1; gate-order changes are intentionally not called overtakes.
- KB-34 remains open, so contact labels stay severity-only.
- Sparse crossing telemetry can suppress `good_start`, `led_every_gate`, or `came_through` rather than guessing.
- Priority is a v1 proposal and is expected to be owner-tunable; it is not a sporting rule.
- LuaJIT was not available for the author-side gate run.

## Unresolved questions
1. None blocking the candidate. The integrator still owes the required LuaJIT leg and captured-fixture review named in the assignment packet.

## Rollback / removal
On admission, delete `competition/race_tags.lua` and its MANIFEST line; remove the single settlement/presentation host call site the integrator adds, falling back to the pre-tag post-event result presentation. The candidate itself owns no persistence or host wiring.

## Changelog
- v1 (2026-09-22): initial candidate delivery for IDEA-089; 48 author-side tests, Lua 5.4 green, LuaJIT pending integrator environment.
