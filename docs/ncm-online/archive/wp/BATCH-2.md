# Batch 2 — "Race Guide + host kit" (cut 2026-09-21; owner: build breadth first, validate once, TW1 tests breadth)

> **STATUS: HISTORICAL** - completed work package. A record of a moment, never architecture.
> Authority map: [INDEX.md](../../INDEX.md) - classified 2026-09-24 (L125)

**Status 2026-09-21: built and deployed to staging (deploy 7, 16:35 UTC) — every item below has core tests and/or a stub scenario; live validation is the master test doc.** Offline: 78 core tests, 17 stub scenarios (`guide`, `guide2`, `hostkit`, `rolling` new), `luac -p` clean.

Progression: **Batch 1 (built, mostly validated) → Batch 2 build → one big validation pass (Batch 1 leftovers + Batch 2)
→ TW1 controlled multiplayer QA/capture (3–5 testers, L59) → fixes → TW2 readiness → TW2 Formula showcase (L60).**

Owner direction (2026-09-21): be as close to beta as possible *before* TW1 — as feature complete as we can — so the
hour with real humans is spent on breadth, not on finding what a solo session would have found, and no emergency
"TW1.5" is needed before TW2. The Race Guide is core, not TW2 polish. Live validation of Batch 1's leftovers moves
into the single validation pass after Batch 2 is built (they are listed at the end so nothing is lost).

Architectural rules stand: nothing throwaway, core stays pure Lua with tests, every host feature has a stub
scenario, every interactive client surface has a chat/console twin (P46), network-safety per the architecture doc.

## Scope, in build order

### 1. Race Guide v0 (P47) — the spine

- **Guide page** (WebUI, `layer="menu"`, key + `/ncm.guide`): every posted event — series, discipline/format/class,
  route + venue, start time, state, entrants/interest count, my status. Street cadence and organized events in one
  list with a tier tag (L58) unless the owner asks for tabs.
- **Interest** (`/ncm.interest <n>` twin): the ordinary entry (P52). Records `entry` state `interested`; waypoints the
  driver to the venue (KB-1 kick only on foot); staging ring already there on arrival; entry becomes `checked_in` at
  the venue as today (L48). Interest is a soft list in v0 — no reservation; the grid is whoever checks in.
- **On-demand practice (P48):** for an event the driver has shown interest in, from posting until qualifying forms,
  the `session.quali` run engine runs per driver (no countdown, no window): cross the start, best time, practice
  leaderboard per event (P1/P2… relative to recorded practice runs) and per route (feeds records). Incidents count.
- **Event lifecycle from the Guide:** post → interest → (practice) → qualifying (one run, route-sized window, P49) →
  explicit route to the grid with the geography-aware gap (P50) → race → results → retire. The NCX invitational keeps
  its offer/accept/team-car presentation on top (P52); nothing else uses it.
- Core: `competition.guide` (list/derive rows from the calendar), `competition.entry` (`interested` state),
  `session.practice` (thin wrapper over `session.quali` with no window). Migration 010a: `entry.state` gains
  `interested`; `practice_run` (event_id, ncm_driver_id, run_sec, incident_ms, at) or reuse `session_result` with
  kind `practice` — decide at build.

### 2. Host kit (L63) — operate, reset, observe, debug

- **Scenario console** (Warden + `/ncm.host` chat twin): `ncm.scenario <discipline> <route> [format] [in <min>]`
  posts + auto-enters everyone connected; `restart` re-forms the same field; `stop` retires cleanly (cars back, venue
  undressed) — no resource restart; `field`; `ncm.grid <pid> <slot>`; `ncm.warp <pid> start|finish|<pid>|<x,y,z>`;
  `ncm.lights now`; `ncm.hold <sec>`. Every line logged with a scenario id.
- **Discipline/route switching:** each vocabulary discipline runnable as a short controlled run from one command —
  GT/road, Badlands (`quad`/rally-stage route), drift (timed run, incidents on; judging later), drag (two-lane strip,
  lanes P44), oval (roundabout ring, laps), Formula (NCX). Routes captured with `/ncm.au` / `/ncm.aw`; `ncm.route list`;
  per-discipline defaults. **Wires M8's oval/drag adapters (core exists) to the host.**
- **No "20" anywhere (L60):** audit seats, hold %, grid columns, boards, `reversed_top_n`, team-car pairs, HUD.
- **Readable session state:** one chat/toast line per state change per driver; `ncm.state` dump for the host.
- **Starts and checkpoints from the telemetry stream:** segment crossing between consecutive samples (no reverse
  crossings, no proximity-at-sample luck), capture radius per gate kind, optional facing check; the log shows every
  crossing.
- **Join / leave / reconnect:** late join into a formed session (spectate or late entry per ruleset), leave mid-race
  (DNF, car returned), reconnect (resume, car re-claimed), `ncm.kick`, `ncm.spectate`.
- **Deliberate incidents:** `ncm.incident <pid> <band>` injection; per-scenario rule overrides (`ncm.rules incidents
  off|on`, bands) for staged contact with and without scoring (E8).
- **Observe / debug:** `ncm.trace <pid> on`; per-scenario log file; `deploy-staging.ps1 -Logs -Scenario <id>`;
  client `/ncm.debug` (phase, next gate, distance, gps target, telemetry health).
- **Recover without restart:** `ncm.world reset` (return cars, undress, clear pickups/offers); the KB-5 drill documented.

### 3. Rolling start (owner ask 2026-09-21) — a start type on the ruleset

Formation behind a pace reference (pole car in v0; server car later for sanctioned events) in grid order under a
class speed cap over a formation stretch (start → authored green point, else the first N m of the course); green when
the leader reaches the green point with the field in order and under the cap; the race clock starts there. Faults —
passing before green, over the cap, > X lengths off the car ahead, a brake-check by the leader — are incident bands
(L56/P39), no restart in v0. Server-detected from telemetry (L57). Default for ovals and endurance, optional elsewhere.
Open before build: cap per class; formation distance rule; absent leader at green (next car leads).

### 4. Fix pass (carried from Batch 1 QA)

F7 rebind (pick a free key, keep the chat twin); first-crossing detection (covered by 2's telemetry gates); ~~DNS must
not cost SR~~ (misdiagnosed: the drop was two object incidents, by design); car floating at the Troll Pass start (KB-17: ground-snap slots from the authored point); stale pins
(KB-15: investigate with `blips.list`); message lifecycle (expire offers at event close, archive) and a phone-thread
presentation of the Messages page; log the resolved `npcs.damage` enum name; TW1 tester brief text incl. the private
Formula note (L61).

### 5. Run sheet + capture plan

`docs/ncm-online/TW1_RUN_SHEET.md`: the hour minute by minute (join, briefing, GT ×2, Badlands, drift, drag, oval,
Formula glimpse, staged incident, restart test, leave/rejoin test, wrap), console commands per segment, promo shot
list (L62). Tester instructions rewritten for a QA session in `04_TESTER_WINDOW_1.md` § tester install note (P34).

## Validation pass (after the build, before TW1)

One pass, solo then two clients, logged in **[MASTER_TEST.md](../../wp/MASTER_TEST.md)** (Batch 1 leftovers are already copied there; Batch 2 sections are added as each feature lands), covering:

- **Batch 1 leftovers:** hold-E warp (§3.2); one-run quali → route to the grid → race → results (§8); graph strip / F8
  (§7.4); `ncm.telemetry` mid-race `last client`, `refused=0` (§6.2) + client `telemetry fields:` (§6.1);
  `/ncm.profile` after a real finish (§10); two clients: `tworace` (§8.5), holding + `ncm.tp 2 venue` (§3.3–4),
  deliberate contact → `INCIDENT x2`, dirty car loses on corrected time (§7.1–3), `driver_sr` rows (§10); a street
  sprint regression.
- **Batch 2:** Guide browse/interest/waypoint; practice runs + leaderboard; every discipline as a scenario; restart /
  stop / reset without a server restart; late join / leave / reconnect; incident injection; rolling start on an oval.

## Not in Batch 2

Hosted-mod delivery (KB-8) — TW1 testers install by hand (P34); drift judging; economy amounts; sign-up/recruitment
tooling and paddock ceremony polish (TW2 readiness); the Collection.

## Open questions for the owner (answer before the Guide is built)

1. Guide list: one list with a street/sanctioned tag, or two tabs?
2. Practice availability: from posting until qualifying forms (default), or a fixed lead?
3. Practice leaderboard: per event only, or per route across events (feeds records)? Default: both.
4. Rolling start v0: pole car as the pace reference (default) or a server car from the start?
