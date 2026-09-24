# NCM Online — data model (as built, and the three migrations designed next)

Status 2026-09-20. Everything under **Built** exists on staging (migrations 001–007). Everything under
**Designed** is the shape agreed in the decision record (L52–L57, P39–P43) and lands with M8/M9/M10.
Rows are owned by the league server (`ncm_league`); `ncm_world` reads and writes the vehicle/venue tables.
All tables carry `server_id` so one database can serve several NCM worlds.

## Built

| Migration | Tables | What they hold |
|---|---|---|
| 001 identity | `ncm_driver`, `ncm_driver_binding`, `driver_profile` | NCM Driver ID (P2), platform user ↔ driver binding per server, display/number/dimensions/SR JSON, `onboarding_json` (006) |
| 002 garage | `issued_vehicle` | every car the server handed out: record, class, cost (zero), returned_at/reason |
| 003 events | `event`, `entry` | calendar events (series, route, venue, times, state), entries (checked_in / registered, team_id, seat_index, car_number) |
| 004 sessions | `session`, `session_result`, `ledger` | race sessions (formed/green/complete), results (position, time, penalties, state finished/dnf/dns/dsq), the money‑free ledger (L21) |
| 005 organized | `team`, `seat`, `rc_audit` | NCX teams, per‑event seats (offered/accepted), race‑control audit trail |
| 006 team cars | `team_car`, `message` | two numbered liveried cars per team; NCM Messages (seat offers persisted, P30) |
| 007 venue authoring | `venue_point`, `venue_route` | spots, chauffeur nodes, paddock, grid; authored `followRoute` point lists (P35/P36); `meta_json` now holds dressing (props/NPCs) |
| 008 competition | `discipline`, `format`, `class`, `class_vehicle`, `ruleset`; `event` + discipline/format/class/laps; `session` kind superset + `parent_session_id`, `ordinal`, `lap_count`, `format_id` | the vocabulary (L53), seeded from core lists; plans with several sessions |
| 009 dimensions | `driver_licence`, `driver_rating`, `driver_sr`, `accomplishment`, `incident`, `telemetry_chunk`; `session_result` + `corrected_ms`, `incident_ms`, `incident_count`, `best_ms` | dimensions (L54), zero-fault incidents (L56), telemetry as one row per driver per ~10 s (L57) |

Core (pure Lua) modules behind them: `vocabulary.ids`, `competition.driver/seasons/calendar/entry/teams`, `course.routes/gates`,
`session.grid/race`, `data.vehicle_pool/nodes/roots`, `world.provisioning`.

## The one sentence

**An event is discipline × format × class × venue × ruleset; a driver brings dimensions and a garage; a session produces
results, incidents and telemetry; the ledger records every transfer even at zero.**

## Season identity and historical scope (foundation)

The authoritative global competitive period is a UTC calendar quarter with stable id `YYYY-S1` through
`YYYY-S4`; boundaries are half-open at 00:00:00 UTC. `competition.seasons` resolves a UTC civil date or Unix
second to that identity and exact bounds. `competition.calendar` stamps each newly materialized event with
`seasonId` in its core value. Existing SQL events retain `starts_at`, so their quarter remains derivable; this
foundation does not rewrite deployed rows.

`series_id` is the enduring championship identity. A future championship-edition row must key the bounded
historical competition by series + season (and the required rules revision), finalize once, and retain its final
classification. A schedule may occupy any subset of the quarter. Never overwrite one edition to begin the next.

Reconstruction audit:

- `event.starts_at` links sessions/results to occurrence time; `practice_run.at` retains its own time.
- `vehicle_discovery.first_discovered_at` plus preserved source provenance supports seasonal and all-time
  discovery standings from the same rows. `ncm.inspired season` and `ncm.inspired YYYY-Sn` exercise that seam.
- incidents and telemetry join to session/event, so their competitive period follows the authoritative event.
- route-record best rows are derived current state, not a historical source. Historical/corrected record claims
  must remain traceable to session results; replacing a best row does not preserve history by itself.
- the current SP career's numbered eight-race “season” is a separate player-driven legacy concept. It is not a
  UTC NCM season and is not migrated or reinterpreted here.

Future consequential facts retain either `season_id` or an authoritative UTC occurrence time plus a durable
domain parent from which season is unambiguous. Current state alone is insufficient for reconstruction.

## Machine knowledge — migration 016

`vehicle_discovery` remains the first-identity summary and source for Discoveries Inspired; it is not the whole
knowledge model. `vehicle_knowledge_evidence` preserves player-scoped evidence with explicit source/epistemic
kind, occurrence time, optional `asset_id`, payload and unique retry key. Existing rows backfill as observed
identity reveals only. See [16_MACHINE_INDEX.md](16_MACHINE_INDEX.md).

Market must expose actual stock and call the server identity-reveal seam; canonical catalogue membership alone
does nothing. Before the first transfer, add immutable vehicle acquisition/transfer history: current
`vehicle_asset.ncm_driver_id` answers owned-now, but overwriting it cannot answer owned-ever.

## Market Network — starter foundation built locally

Inventory/allocation rows belong to a stable `market_id`; no unscoped global-shop query is authoritative. The
universally known Base Market is the first member, not a singleton architecture. Future player-market knowledge
records attach `(ncm_driver_id, server_id)` to `market_id` with first-known time and source; access eligibility is
kept distinct rather than encoded as discovery. Unknown markets have no client-visible placeholder or total.

Stock remains shared authoritative assets. Market discovery creates no asset and purchase transfers one existing
`asset_id` atomically. See [17_MARKET_NETWORK.md](17_MARKET_NETWORK.md).

Migration 017 implements that boundary: nullable title permits authored unsold assets, `market_inventory` scopes
each listing to a stable market, `vehicle_asset_transfer` preserves production/acquisition history, and ledger
idempotency keys prevent duplicate grants/debits. `player_market_knowledge` reserves the player-specific relation;
Base Market currently derives universal knowledge from policy rather than fabricating one row per Driver.

## As built — 008 competition vocabulary (Batch 1)

```
discipline   (id, name, course_adapter, classifier, laps_supported, judged)         -- street_sprint, ncx_formula, oval, drag, knockout, endurance, time_attack, kart, quad, rally_stage, drift
format       (id, name, sessions_json)                                              -- sprint | weekend(quali,race; practice on demand, P48) | two_race(reversed_top_n) | heats | stints
class        (id, name, pack_id, top_speed_kph, accel_scale, taper_kph, setup_window_json)   -- BoP ceilings applied via setPerformance at issue (L52)
class_vehicle(class_id, record, eligible, variants_json, min_licence)              -- which inert records may enter, their pre‑baked variants
ruleset      (id, version, json)                                                    -- penalties, incident bands, provenance policy, prize/fee schedule (zero), entry rules
event        + discipline_id, format_id, class_id, ruleset_id, laps
session      + kind ENUM(practice,quali,race,heat,stint), parent_session_id, lap_count
```
Core (built): `competition.discipline` (adapters p2p, laps/oval, lanes/drag; eliminations declared),
`competition.format` (session templates → event sessions), `competition.class` (eligibility + BoP → `setPerformance` profile).

## As built — 009 driver dimensions, incidents, telemetry (Batch 1)

```
driver_licence   (driver_id, discipline_id, level ENUM(rookie,licensed,pro), clean_sessions, earned_at)
driver_rating    (driver_id, class_id, rating, sessions)                            -- seeding only (L54)
driver_sr        (driver_id, sr, updated_at)                                        -- the badge (L54/L56)
accomplishment   (id, driver_id, kind, ref_kind, ref_id, at)
incident         (id, session_id, ncm_driver_id, other_driver_id NULL, kind ENUM(car,object,person,offtrack,cut,lane), band, delta_v, seconds, x, y, z, t, attributed ENUM(self,both,none), evidence_json, overridden_by)   -- zero-fault (P39): no "approaching"
telemetry_chunk  (session_id, ncm_driver_id, seq, t_from, t_to, n, samples_json)   -- as built: one row per driver per ~10 s of 5 Hz samples [t,x,y,z,v,gear,onGround,health]
session_result   + corrected_ms, incident_ms, incident_count                          -- corrected time decides the result (L56)
```
Core (built): `competition.incidents` (bands, zero-fault, escalation, dedupe, ledger), `session.quali`, `telemetry` (sampling spec,
progress along the course polyline, delta‑v detection, sector times), `driver.progression` (results/incidents → dimension
deltas). The live race graph (P40) reads `progress_m` and `incident_ms` per driver from the session publication.

## As built — 010 the Race Guide (Batch 2)

```
entry            + state 'interested' (a soft entry from the Guide, P52; upgrades to checked_in at the venue under the same id), 'dns'; interested_at
practice_run     (server_id, event_id, route_id, ncm_driver_id, session_id, run_ms, incident_ms, incident_count, at)   -- every completed on-demand practice run (P48)
session          kind 'practice' rows are the on-demand practice of an event (one per event, format_id 'practice'); never "raced"
```
Core (built): `competition.guide` (rows, interest, withdraw, practice window), `session.practice` (open-now run engine over
`session.quali`, join/leave/leaderboard/close).

## Designed — 011 garage and economy (with M10)

```
owned_vehicle      (id, driver_id, record, class_id, acquired_via ENUM(issue,prize,purchase,grant), ledger_id, condition, livery, active)
vehicle_setup      (id, driver_id, record, name, values_json)                        -- inside the class setup window (L52)
vehicle_assignment (entry_id, session_id, vehicle_kind ENUM(issued,owned,team,loaner), vehicle_ref, phase_from, phase_to)   -- L28
ledger             + scope ENUM(driver,team,server), team_id, schedule_ref            -- same table, team resources (L55)
```
Core: `garage` (acquisition and eligibility rules), `economy` (schedules on rulesets; all zero until switched on per server).

## Things the model deliberately does not do

- Store client handling settings (no client‑side physics in competition, L52).
- Gate the first world on any dimension (L54).
- Assume vanilla crowds/traffic are observable (P43): open‑world pedestrian incidents are client‑reported; sanctioned venues make them authoritative.
- Bake a prestige ladder (L22).
