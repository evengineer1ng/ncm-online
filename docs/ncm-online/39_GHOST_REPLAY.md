# 39 — GHOST REPLAY

> **STATUS: SPEC** - authority for: *lap ghost replay* - affirmed 2026-09-27 (L166)

A **ghost** is a replay of a lap a real player actually drove: a non-colliding car, local to one client,
moving along a stored pose stream. It gives a solo driver something to race without any of the machinery an
AI opponent would need — no pathfinding, no vehicle authority, no collision resolution, no simulator
ownership, no recovery logic, no synchronised physics.

This document is the authority for what a ghost **is**. `L166` is the authority for what it may **do**.

---

## The rule that makes it safe

**A ghost is not an entrant and not evidence.** It cannot affect timing, collision, standings, ratings,
results or settlement. It has no position, it is not counted in the field, and it is drawn outside the
standings table. It is a target to chase and a delta to read, and nothing else.

That boundary is what allows the client to assemble the payload at all. Poses come from the client because
only the client can see its own car's heading. Every *number* a stored ghost carries — the time, the
interval, the route, the machine — comes from the server's own record of the lap.

## Which sessions get a ghost

Practice, qualifying and time trials. **Not a contested race.**

| Activity | Kernel | Arrives as | Run bounded by | Ghost |
|---|---|---|---|---|
| Practice | `session.quali` | `formatId = "practice"`, phase `open` | start gate → finish gate | **yes** |
| Qualifying | `session.quali` | `kind = "quali"`, phase `open` | start gate → finish gate | **yes** |
| **Time trial** | `session.race` | `kind = "race"` with a field of **one** | `greenAt` → `finishAt` | **yes** |
| Contested race | `session.race` | `kind = "race"`, field > 1 | — | **no** |

**A time trial is not its own session kind.** `L67` / `IDEA-001` make a race with a field of one a time trial,
and `driver.progression.isTimeTrial` is the predicate — so a time trial reaches the client as an ordinary
race, on the race kernel, with the race phases. It is the same solo activity practice is under a different
name, so it gets a ghost on the same terms. A contested race is excluded deliberately, not incidentally:
there a ghost is visual clutter among real competitors and could be read as another entrant.

Two consequences follow from that, and neither is optional:

- **The trace must be requested before the run starts.** A time trial only becomes *recordable* at green,
  which is the same instant its single run begins — so asking for the stored ghost then would always be too
  late. The client asks as soon as a ghost-eligible session appears in **any** phase. A ghost that still
  arrives mid-lap is anchored to the lap already under way, rather than spawning at the start line however
  many seconds late.
- **Run boundaries come from different fields.** On the time-attack kernel a run is bounded by the start and
  finish gates and detected by `progress > 0`. On the race kernel there is one run, bounded by `greenAt` and
  the entrant's `finishAt`, detected by the state moving `ready → racing → finished`. The race kernel's
  result now carries that finish **instant**: `totalSec` folds in the penalty, so the moment a lap ended was
  not recoverable by subtracting it.

## What a ghost wears

**The player's own car.** `vehicle_asset.record` holds the exact TweakDB record per Machine, and the record
is latched when the **start line** is crossed, so a ghost wears the car the lap was actually set in.

Before this, practice attribution was read when the *session closed* — a driver who left practice, refitted
and came back had their lap credited to whatever car they happened to be sitting in minutes later. That is
fixed at the kernel, not worked around here.

## Why poses are not telemetry samples

`telemetry` is the incident and progress stream and stays exactly as it was. It is the wrong source for a
ghost on four counts, none of which is a defect in it:

| | telemetry sample | ghost pose |
|---|---|---|
| Source | `Open77.character.position` — the mounted **driver** | the **vehicle** snapshot via `NcmClientOwnVehicle` |
| Rotation | none | `yaw` |
| Stored precision | 10 cm (`%.1f` at persist) | 1 cm |
| Format version | **no column; unidentifiable after the fact** | `format`, and a reader refuses one it does not know |
| Rate | 5 Hz | 10 Hz, decimated |

Extending `SAMPLE_FIELDS` would have changed a persisted format nobody can identify retrospectively, in
three vendored copies, to serve a second consumer with different needs — and would still have left the
ghost half a metre sideways with no heading. So poses are their own versioned stream in their own table.

## Shape

- **`replay.pose`** — the pose schema, shortest-arc yaw interpolation, decimation, and rebasing to `t = 0`.
  Pure core.
- **`replay.lap`** — the manifest, the eligibility predicate, `better`, and the delta. Pure core.
- **`data.vehicle_templates`** — record → the model string a client-local prop draws that car with.
- **`ghost_lap`** (schema 034) — immutable. A faster lap is a **new row**; "my best" is a query. This is
  what lets telemetry retention be added later without a cleanup deleting the laps a leaderboard rests on.
- **`ncm_league/server/ghost.lua`** — claim, upload ingest, validation, store, stream down.
- **`ncm_world/client/ghost.lua`** — record, download, spawn, move, remove.

Transport is `vocabulary.chunks` in both directions, at 40 poses per packet. A lap is roughly 45 KB, which
is an order of magnitude past the state bag's measured ~4 KB ceiling; a ghost must never touch a state bag.

## The delta is measured at a place, not between two clocks

Comparing my elapsed time to the ghost's elapsed time answers *how long have we each been driving*, which
is the same number for both of us at every instant and says nothing. The question a driver is asking is *am
I ahead of where it was*, which is a comparison **at a position on the course**.

So the ghost's poses are indexed by progress along the course polyline once, when it loads, and the delta
is `my elapsed time` minus `the ghost's time at my current metre mark`. Negative means ahead. Off the
racing line, before its start and past its finish there is no answer, and the HUD shows a dash rather than
a number no lap supports.

## Tiers

| Tier | State | Needs |
|---|---|---|
| `PERSONAL BEST` | **built** | nothing beyond the driver's own accepted lap |
| `SESSION BEST` | vocabulary only, inert | server corroboration of another driver's line |
| `ROUTE RECORD` | vocabulary only, inert | corroboration, opt-in publishing, route revisioning |
| `OFF` | built | — |

The three public prerequisites are all refusals in `replay.lap.eligible` today, so turning a tier on is
adding evidence, not renaming a concept.

**Public ghosts reveal racing lines.** A personal ghost is automatic because it is the driver's own lap
handed back to them. Publishing a route record is a decision about exposing how you drive, and is opt-in.

## Known limits, stated rather than discovered later

1. **Props are yaw-only.** No pitch, no roll. A ghost does not bank into camber or dip under braking.
2. **Props have no opacity field.** The ghost is solid. A translucent hologram needs an authored `.app`,
   which is a presentation upgrade with its own asset and delivery chain, not a property to set.
3. **`props.create` returns a successful id for a model it cannot resolve** (`KB-14`). A missing ghost and
   a working one are therefore indistinguishable from the create return, which is why the model resolution
   is an ordered candidate list, every attempt is logged, and a fallback draw is reported on the HUD as
   `NO CAR MODEL` rather than left to look like a broken feature.
4. **Route geometry is unversioned.** `roots.register` replaces a route in place, so a stored ghost can
   silently belong to different geometry than the one it replays against. Tolerable for a personal best;
   `ROUTE RECORD` cannot ship without solving it (`IDEA-562`).
5. **Appearance is captured but paint is not.** Props take an `appearance` string; Cyberpunk's vehicle
   colour is a separate persistent struct with no prop counterpart, so a ghost wears the right model and
   variant, not the owner's paint.
6. **Recording starts on the published view**, which lags the kernel's gate timestamps by up to one
   publish. The stored lap time is always the kernel's; the buffer's own span is used only to check that the
   poses plausibly belong to that lap. Both kernels therefore report a **raw** gate-to-gate duration
   alongside the official time -- the official figure folds in incident seconds on the time-attack kernel and
   penalty seconds on the race kernel, so a caller that subtracted to recover the raw one would be right for
   one session kind and wrong for the other.

## Authority

- `L166` — a ghost is non-authoritative; poses are their own versioned format.
- `L57` — telemetry is a first-class stream whose consumers include *"ghosts and replays later"*.
- `IDEA-088` — the time-trial personal-best delta this unblocks.
- `IDEA-560`–`IDEA-563` — the intake rows for this work.
- `wp/MASTER_TEST.md §BI` — the live evidence. Nothing here is done until a PASS sits there (`L69`).
