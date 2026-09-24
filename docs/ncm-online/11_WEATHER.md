# NCM Weather

**Status:** platform synchronization validated on op77.87; pure core and persistent default-world server adapter
built and offline-tested; deployment/live validation remain. No competitive, economic, badge, Fishing, or
vehicle-performance consequence consumes weather yet.

## Product rule

Weather is persistent world state, not an authored race label. An open-world race encounters Night City's current
weather. Only an explicit isolated-event policy may create, pin, or override an environment. Current OPEN//77
weather is uniform within an environment scope; NCM must not draw geographic radar, storm cells, regional rain,
front direction, or coordinate-based intensity that the platform does not simulate.

The honest presentation is a **Weather Scope**: time-domain pit-wall instrumentation showing recent observations,
a strong NOW marker, future state bands and transitions, timestamps, forecast confidence, scope, and forecast
revision. Small surfaces use an eight-glyph technical family: Sunny, Light Clouds, Cloudy, Rain, Heavy Clouds, Fog,
Pollution, and Sandstorm.

## Ownership boundaries

```text
OPEN//77 environment authority  applies and synchronizes engine environment
NCM Weather Service             owns policy, canonical timeline, reconciliation, observations
Forecast layer                  derives player-visible information and uncertainty
Race/session system             captures immutable event weather provenance
Performance Authority           may later interpret weather as vehicle ceilings
Driving Ledger                  may later aggregate canonical driving facts
Fishing                         may later interpret weather for ecology/opportunity
Race Guide / Weather Scope      presents observations and forecasts
```

No single weather module owns downstream gameplay consequences.

## Completed gate: KB-6 synchronization retest

The temporary `ncm_weather_probe` compares `Open77.environment.getState(bucket)` with each client's projected
`open77_weather.getState()` without changing product behavior. Capture at least:

1. two clients in the default environment;
2. every supported preset forced with a visible transition;
3. one platform-scheduled natural transition;
4. a client joining/rejoining during an active transition;
5. both clients moved into one overridden bucket;
6. one client returned to the default scope;
7. the override cleared;
8. canonical and both projected states at every step.

A PASS requires matching authority epoch, scope, weather/weather preset, and compatible revisions, with transition
remaining time and projected clock differing only by expected latency/sampling delay. Any divergence stops work
before weather gains sporting or economic meaning. The executed evidence belongs in a dated `experiments/E##_*.md`
record; the old KB-6 row remains open until then.

**PASS 2026-09-22:** W1–W8 passed with two clients on op77.87. See
[E26](experiments/E26_2026-09-22_weather-sync.md). KB-6 is closed.

## Built core contract (2026-09-22)

`ncm/core/world/weather.lua` now supplies the host-agnostic portion of the first slice:

- validated configurable state weights, hold durations and transition duration;
- deterministic Park–Miller timeline generation with seed/generator/policy metadata;
- append-only horizon extension that refuses a policy-version mismatch and preserves published rows;
- point-in-time canonical lookup;
- time-band forecast projection with `OBSERVED` / `FORECAST` / `OUTLOOK` and `HIGH` / `MED` / `LOW` confidence;
- compact session provenance with transitions and duration totals by weather family.

The module takes clocks and persistence from its host and makes no OPEN//77 calls. Five dedicated tests pass under
Lua 5.4 and LuaJIT; the full gate is 128/128 under each interpreter with 98 resource Lua files parse-clean.
This is an offline-built component, not a deployed or live-validated Weather Service.

## Built server adapter (2026-09-22)

`ncm_league/server/weather.lua` and migration 013 now provide the default-world host for that core:

- `weather_plan`, `weather_transition` and bounded `weather_observation` persistence;
- explicit seven-day canonical rows with append-only extension below a 24-hour reserve;
- a configurable slow policy whose holds are measured in tens of minutes/hours;
- an explicit dependency on `open77_weather`, platform random scheduling frozen while NCM owns default scope,
  and ten-second reconciliation at planned boundaries or after external drift;
- restart recovery that loads the published rows and applies the current transition with only its remaining time;
- a bounded 24-hour Guide read model with current state, up to 16 recent canonical observations, forecast time
  bands, ordinal confidence, scope and revisions;
- `NcmWeather.provenance(...)` as the compact immutable session-envelope seam, without yet wiring classifications,
  badges or performance effects;
- `ncm.weather.status` as the operator read-only diagnostic.

The adapter retains at most 24 hours / 256 canonical observations in SQL and memory. The seven-day plan is not
copied into each event row. It has passed syntax and pure-core tests but has not run against the live database or
environment authority; §X is the required live gate.

## Smallest safe implementation after PASS

1. A pure, host-agnostic timeline generator and validator in `ncm/core/world/weather.lua`.
2. A server adapter in `ncm_world` with `world.environment`, responsible only for persistence, reconciliation and
   OPEN//77 calls.
3. Configurable slow policy and an approximately seven-real-day rolling canonical plan.
4. Platform random weather disabled while NCM owns the default scope; each planned boundary is applied through
   `Open77.environment.setWeather`.
5. Bounded recent observations plus current state and future-plan read models.
6. A forecast projection that exposes less precision at greater lead time.
7. Session start/transition/finish hooks that capture compact immutable provenance.
8. A minimal Guide/WebUI payload proving NOW plus near forecast before building the full Weather Scope.

Wet-performance profiles, Driving Ledger badges, Fishing effects, and long-range visual polish remain consumers,
not part of this first implementation.

## Canonical timeline and persistence

The plan is deterministic but should be **persisted explicitly**, not reconstructed from a seed alone. Persist:

- timeline epoch and policy version;
- seed and generator version for audit/reproduction;
- generated transition rows `{id, startsAtUtc, weather, transitionSeconds}`;
- the last applied transition ID;
- forecast revision metadata.

Seed-only reconstruction is unsafe across policy edits, generator fixes, clock discontinuities, and rolling-horizon
extension. Explicit rows guarantee that a server restart does not rewrite tomorrow's weather. Generation appends
beyond the retained horizon transactionally and never mutates already published canonical rows. On boot, NCM loads
the plan, identifies the transition covering current UTC, disables platform random scheduling, applies/reconciles
that state, and advances missed boundaries without replaying each one visually.

`open77_weather` has a lifecycle distinction: resource reload carries its live authority, while stop/restart returns
it to configured defaults. NCM must therefore reconcile after its own start, after environment authority becomes
available, and after relevant resource/server restarts. Calls must handle `environment_unavailable`. Bucket
overrides are cleared when their event ends; the platform supports at most 64 simultaneously.

## Scale and cost

The plan is a sequence, not per-tick simulation. With configurable states lasting roughly tens of minutes to a few
hours, a 24-hour horizon is likely tens of rows and seven days likely low hundreds. Even a conservative 336 rows at
roughly 200 bytes each is about 67 KiB serialized; normalized SQL storage and in-memory tables are similarly
trivial. Runtime work occurs at generation, reads, and transition boundaries—not every server tick.

Suggested bounds, configurable rather than balance locks:

- canonical future horizon: approximately 7 real days;
- regeneration threshold: extend when less than 24 hours remain;
- recent raw transition history: 24 hours or 256 transitions, whichever is smaller;
- immutable event provenance: retained with the event/result.

## Forecast model

Canonical future weather and player-visible certainty are different things. The first implementation should use
configurable ordinal confidence (`HIGH`, `MED`, `LOW`) and temporal resolution rather than fabricated precise
percentages:

- **OBSERVED:** canonical current/recent state;
- **FORECAST:** near future, exact or narrow state bands with high confidence;
- **OUTLOOK:** farther future, broader weather families and windows with declining confidence.

The projection is deterministic for a given plan, issue time, and model version. It does not roll fresh randomness
per viewer and never changes actual weather to surprise the forecast. As lead time shrinks it reveals narrower time
windows and more specific states. Farther-out output may honestly say `CLOUDY / RAIN POSSIBLE` when the canonical
window contains both; later issues converge to the actual state. Initial confidence should derive from configurable
lead-time bands, transition proximity, and whether a display window contains competing weather families.

## Observations and event provenance

The bounded recent buffer stores canonical changes—not per-client samples—with timestamp, scope, weather/preset,
transition duration, authority epoch, revision, reason, and plan transition ID where applicable. It supports UI,
debugging, and session capture but is not permanent history.

Each completed session keeps a compact immutable weather envelope:

```text
start: { utc, weather, scope, revision }
transitions: [{ offsetSec, weather, transitionSec, revision }]
finish: { utc, weather, revision }
durationByFamilySec: { dry, wet, obscured, hazardous }
```

This is normally a few rows/fields, not continuous telemetry. It preserves enough fact to reclassify an event later
as dry, wet, mixed, or rain-affected without depending on tomorrow's rolling buffer or reducing the race to finish
weather. Taxonomy remains interpretation and is not locked here.

## API and presentation seam

Expose one bounded read model rather than copying forecast facts onto every event row:

```text
weather.current
weather.recent[]
weather.forecast[]
weather.scope
weather.revision
weather.issuedAtUtc
weather.modelVersion
```

The Race Guide receives this once at payload top level and aligns scheduled event times against forecast bands.
An isolated event may carry a scoped environment reference, not a duplicate seven-day plan. Missing/unvalidated
weather produces an honest unavailable state, never invented icons or conditions.

## Explicitly deferred

- geographic radar or regional weather;
- finalized duration weights and seasonal policy;
- numeric probability calibration;
- full Weather Scope interaction/zoom design;
- wet vehicle behavior;
- badges and Driving Ledger aggregation;
- Fishing ecology/economy effects;
- final dry/wet/mixed classification vocabulary;
- permanent schema and settlement migration until the synchronization gate passes.

---

# Addendum — Race Guide integration boundary (2026-09-22, Guide side)

Written by the Race Guide owner after inspecting this document and the repository. **No Weather internals were
changed.** Reported here rather than assumed, per §"Ownership boundaries".

## UPDATE 2026-09-22 — the gate passed and the service shipped

This addendum was written when no Weather Service existed. Both halves have since changed:

- **KB-6 passed** on `op77.87` (W1–W8, [E26](experiments/E26_2026-09-22_weather-sync.md)) and is closed.
- **The service is built** — `world.weather` in core plus `ncm_league/server/weather.lua`, publishing the read
  model this document specified.

**The two gaps flagged below were both closed by the implementation, not worked around:** `forecast()` returns
**time bands** (`fromUtc`/`toUtc`/`weather`/`family`/`confidence`/`kind`), which is exactly what the Guide needed
to intersect an event against, and confidence is **ordinal** (`HIGH`/`MED`/`LOW`) as this document requires.

The Guide now consumes it: one read model at payload top level, plus a small per-event cue derived through new
core `weather.forEvent(forecast, startUtc, endUtc)`. Still open: **no event carries an authoritative duration**,
so `forEvent` is called without an end time — it reports the start honestly, sets `windowKnown = false`, and
flags a transition landing within ten minutes rather than guessing a race length (IDEA-134).

**The percentage conflict stands:** the Race Guide brief's mockup shows `Confidence: 81%`; this document defers
numeric calibration and the shipped service emits ordinal confidence. The Guide follows this document.

The original boundary report follows, kept because it is what the seam was designed against.

## What existed when this addendum was written

| Thing | State |
|---|---|
| `11_WEATHER.md` | Architecture and validated platform boundary; pure core contract built. |
| `ncm_weather_probe` | Temporary KB-6 comparison probe. Not referenced by `ncm_league` or `ncm_world`; it is not product policy. |
| A Weather Service / core module | Pure `world.weather` core plus default-world persistence/OPEN//77 adapter built; live validation pending. |
| The read model (`weather.current` / `.forecast[]` / …) | **Specified here, produced by nothing.** |
| KB-6 synchronization gate | **Passed on op77.87.** See E26. |

The Guide now consumes the adapter's one bounded read model when it reports `ready`, and stays honestly unavailable
on startup/database/environment failure. Presentation beyond the payload remains a Guide/UI task.

## What the Guide did instead

Exactly what §"API and presentation seam" prescribes, and nothing more:

- the guide payload now carries **one bounded `weather` block at top level**, never forecast facts copied onto
  event rows;
- it **passes through `NcmWeather.readModel()` if that ever appears**, and otherwise publishes
  `{ state = "unavailable", reason = "weather_service_not_implemented" }`;
- `capabilities.weather = false`, so the client can hide the ribbon rather than render an empty one.

**No forecast is fabricated, no glyph is chosen, no second source of truth is created.** When the service lands
and the gate passes, the Guide lights up by publishing a read model — no Guide rework.

## The consumer contract the Guide needs (missing today)

The seam in this document is the right shape. Two gaps the Guide would hit on day one:

1. **Forecast entries need a time band, not an instant.** The Guide's brief is explicit that a race starting
   15:55 with rain at 16:03 is not a dry race. `weather.forecast[]` should carry `{ fromUtc, toUtc, weather,
   confidence }` so the Guide can intersect a forecast band with an event window. An array of instants forces the
   Guide to interpolate, which is inventing weather.
2. **Event duration is not authoritative anywhere.** The Guide knows `distanceM` and can guess, but a guess would
   silently become a forecast claim. Until an event carries an expected duration, the Guide can honestly answer
   *"conditions at the start"* and must not claim *"conditions during the race"*.

## One conflict to resolve, flagged not decided

The Race Guide brief's mockup shows **`Confidence: 81%`**. This document says the opposite, twice: use
*"configurable ordinal confidence (`HIGH`, `MED`, `LOW`) … rather than fabricated precise percentages"*, and
lists *"numeric probability calibration"* under **Explicitly deferred**.

**The Guide will follow this document (ordinal), not the mockup**, until the owner says otherwise. A percentage
implies a calibrated model that does not exist, and inventing one in a presentation layer is precisely the
"competing state" this boundary exists to prevent.

## Deferred on the Guide side, deliberately

The weather ribbon on the schedule axis, the detail-card forecast block, My Races glyphs, and Past Races
provenance summaries are all **designed against this contract and not built**, because building them now would
mean rendering placeholder weather. Past Races in particular must read from the **finalized event envelope**
(§"Observations and event provenance"), never from today's service — so it waits for settlement capture, not just
for the service.

The Guide boundary remains correct after KB-6 passed. It should stay unavailable until the server adapter publishes
the read model; the existence of the pure core alone is not a live service.
