# COMPONENT ASSIGNMENT — B-089-race-tags v1

> **STATUS: SPEC** - owner intent, captured and **NOT authorised for implementation**. Do not build from it; do not contradict it. Covers: *Race Tags - owner wants it integrated eventually; NOT yet integrated (IDEA-301)*
> Authority map: [INDEX.md](../../INDEX.md) - classified 2026-09-24 (L125)

*Written by the integrator 2026-09-22. This packet plus `COMPONENT_GATE.md` plus the attached files is everything
the author gets. Attach: `ncm/core/init.lua`, `ncm/core/tests/run.lua`, `ncm/core/vocabulary/ids.lua` (as
`provided/vocabulary/ids.lua`), `COMPONENT_GATE.md`, `COMPONENT_MANIFEST_TEMPLATE.md`, and this file.*

## Identity
- **Brick id:** B-089-race-tags   **Revision requested:** v1
- **Gate:** 1   **NcmCore.VERSION:** 0.0.1
- **Module name:** `competition.race_tags`  →  file `competition/race_tags.lua`
- **Shape:** Rule
- **Serves:** IDEA-089. Encodes L67 (solo = time trial). Regression targets: KB-35, KB-38. Known data limitation: KB-34.

## The idea, verbatim (BACKLOG.md, IDEA-089, 2026-09-22)
> **POST-EVENT DESCRIPTORS ("Race Tags") — replaces the `Clean Race` accomplishment's job at the end of an event.** **Not** badges, achievements, unlocks, titles, rewards or progression: ephemeral classifications generated from the telemetry of the event that just ended, answering *"what kind of race did I just have?"*. A player may receive the same descriptor every race forever. **Language rule: immediately understandable from the words alone** — `Clean Race`, `Good Start`, `Many Overtakes`, `Close Finish` yes; `Lights Out`, `Metronome`, `Sector One Demon` no. A little personality is fine only where meaning stays obvious (`Tough One`). Every descriptor must be **factually supported by telemetry** — no vague praise. **Mode-correct language: a time trial gets `Clean Run`, never `Clean Race`.** Show **2–4 maximum** in one compact post-event presentation, most distinctive first; **never one toast per descriptor**. No collection screen, no ownership, no prestige, no unlock animation, no completion tracking — that is badge territory. Telemetry stays canonical; descriptors are one-event interpretations of it. Owner's framing: **"they aren't little awards, they're labels on the tape."** Presentation target: `RACE COMPLETE · P4` / `CLEAN RACE · GOOD START · MANY OVERTAKES`. Ceremonial but small, then gone; counts may be logged to lifetime profile stats (e.g. *all-time clean races: N*). […] **Ruthlessly delete any descriptor telemetry cannot support cleanly** — `Strong Defence` and `Good Recovery` are named as the likely first cuts, because plain language does not rescue a mushy inference.

> Distinguish `Gained Positions` (can come from DNFs/penalties) from `Many Overtakes` (actual passes) — they are different facts.

## Domain semantics the author must know
- **L67:** a race session with a field of one is a **time trial**. It is real, recorded and classified, but it cannot be won — nothing position-based applies. The host tells you (`session.timeTrial = true`); you never decide it.
- **Session kinds** are exactly `"race"`, `"quali"`, `"practice"`. Quali and practice produce best-run results (`bestSec`, `runs`), not race positions.
- **Result states** are exactly `"finished"`, `"dnf"`, `"dns"`, `"dsq"` (settled rows; the live states `racing/suspended/ready/entered` never reach you).
- **Incidents** (`competition.incidents`): each record is `{ kind = "car"|"object", band = 1|2|3, dv, t, other?, attributed = "both"|"self" }`. Band = delta-v severity (×1 ×2 ×4). `incidentSec` is the total corrected-time addition; `correctedSec = totalSec + incidentSec` and **positions are decided on corrected time**.
- **KB-34 (open):** car-to-car contact is currently being recorded as `kind = "object"` in some cases. Until fixed, **do not word any descriptor as "wall" or "car"** — describe contact by severity only.
- **Penalties** are race-control additions: `{ seconds, reason, at }`. `jumpStart = true` means the driver crossed the start before green (+5 s, already inside `penaltySec`).
- **Grid slot** (`slot`, 1 = pole) is the starting position. **Gained positions ≠ overtakes**: a driver can gain positions because others crashed or DNF'd. Overtake facts do **not** exist yet.
- **Gates:** every route has `gatesTotal ≥ 2` gates in order; gate 1 is the start line, the last gate is the finish. Each driver has `crossings[gateIndex] = t` for the gates they crossed (server seconds). `session.greenAt` is when the lights went out. From crossings you can compute the order of the field at every gate — that is the only "position over time" fact available.
- **Personal best / route record** are supplied by the host **only when they exist** (`previousBestSec`, `routeRecordSec`, both *before* this session). Absent means no history — never infer "first time on this route".
- Vocabulary for labels is **English, title case, plain**. Every id is `lower_snake_case` and stable forever (it will become a profile counter key).

## Interface
```lua
M.evaluate(facts, opts) -> result         -- pure; whole session in, per-driver tags out
M.DEFAULTS = {
    maxTags        = 4,      -- hard cap per driver (2–4 shown; 0 or 1 is allowed when there is little to say)
    closeFinishSec = 0.5,    -- gap to the car directly ahead or behind at the finish
    clearWinSec    = 5.0,    -- P1's margin over P2
    gainedMin      = 2,      -- slot - position >= this
    lostMin        = 2,      -- position - slot >= this
    goodStartMin   = 2,      -- slot - (order at gate 1) >= this
    toughIncidents = 3,      -- incidentCount >= this
    priority       = { ... } -- ordered list of ids, most distinctive first (see Output)
}
M.CATALOGUE = { { id = "clean_race", label = "Clean Race", modes = { "race" } }, ... }   -- every id the module can emit
```

## Input schema (normalized; absent means "host could not compute it")
```lua
facts = {
  session = {
    sessionId   = "string",              -- required
    kind        = "race"|"quali"|"practice",   -- required
    timeTrial   = true|false,            -- required for kind == "race"; host-decided (L67)
    fieldSize   = 4,                     -- required; number of result rows
    disciplineId = "street_sprint",      -- required; see list below
    tier        = "street"|"sanctioned"|"both",  -- required
    gatesTotal  = 3,                     -- required for race
    greenAt     = 1000.0,                -- race only; absent if the race never went green
    routeId     = "string", routeName = "string",   -- informational
  },
  results = {                            -- required; in classified order (position 1 first)
    {
      driverId = "string", display = "string", position = 1, state = "finished",
      slot = 3,                          -- race only; grid slot, 1 = pole
      totalSec = 120.0, correctedSec = 120.0,      -- finished only
      penaltySec = 0, incidentSec = 0, incidentCount = 0,
      incidents = { { kind = "object", band = 3, dv = 14.2, t = 1090.0, attributed = "self" } },
      penalties = { { seconds = 5, reason = "race_control", at = 1050.0 } },
      jumpStart = false,
      gapSec = 0.4,                      -- finished, not leader: corrected gap to the leader
      progress = 3,                      -- gates crossed
      dnfReason = "left",                -- dnf/dns only
      crossings = { [1] = 1004.0, [2] = 1060.0, [3] = 1120.0 },   -- race; sparse: a missing gate is absent, never 0
      bestSec = 61.2, runs = 4,          -- quali/practice only
      previousBestSec = 123.4,           -- optional: this driver's best on this route before today
      formationFault = "pass_before_green", -- optional: rolling starts only
    },
  },
  routeRecordSec = 118.9,                -- optional: best ever on this route before today, any driver
}
```
Discipline ids in use: `street_sprint, ncx_formula, oval, drag, time_attack, quad, rally_stage` (plus disabled
`knockout, endurance, kart`). Treat unknown ids as valid input; disciplines do not change v1 logic.

Fixture attached below (synthetic; a captured fixture will be supplied at review).

## Output schema
```lua
result = {
  drivers = {                            -- same order as facts.results
    { driverId = "a", position = 1, state = "finished",
      tags = { { id = "clean_race", label = "Clean Race" }, { id = "gained_positions", label = "Gained Positions" } },   -- ≤ maxTags, priority order
      declined = { "personal_best:no_history" },   -- optional, for diagnostics only; never shown
    },
  },
  diagnostics = { "..." },               -- optional strings the host may log
}
```
Host consumption: `tags[].label` is joined with ` · ` under the result banner (`RACE COMPLETE · P4` / `CLEAN RACE ·
GOOD START`); `tags[].id` is counted into lifetime profile stats later — **ids must never change meaning**. Order
within `tags` is the display order; the host does not re-sort.

## The v1 descriptor set (only what the input can support)
| id | label | mode | condition (all of) |
|---|---|---|---|
| `clean_race` | Clean Race | race, not time trial | finished · `incidentCount == 0` · no penalties · not jumpStart |
| `clean_run` | Clean Run | time trial, quali, practice | same conditions (quali/practice: `bestSec` present, `incidentCount == 0` or absent-and-`incidents` empty) |
| `close_finish` | Close Finish | race, field ≥ 2 | finished · corrected gap to the finisher directly ahead **or** behind ≤ `closeFinishSec` (derive from `correctedSec`, not from `gapSec` alone) |
| `clear_win` | Clear Win | race, field ≥ 2 | position 1 · finished · P2 finished · P2's gap ≥ `clearWinSec` |
| `gained_positions` | Gained Positions | race, field ≥ 2 | finished · `slot - position ≥ gainedMin` |
| `lost_positions` | Lost Positions | race, field ≥ 2 | finished · `position - slot ≥ lostMin` |
| `good_start` | Good Start | race, field ≥ 2 | crossed gate 1 · `slot - orderAtGate1 ≥ goodStartMin` · not jumpStart |
| `led_every_gate` | Led Every Gate | race, field ≥ 2 | position 1 · finished · earliest crossing at every gate 1..gatesTotal among drivers who crossed it |
| `came_through` | Came Through | race, field ≥ 2 | position 1 · finished · **not** earliest at gate 1 |
| `heavy_contact` | Heavy Contact | any | any incident with `band == 3` |
| `tough_one` | Tough One | any | finished · `incidentCount ≥ toughIncidents` |
| `jump_start` | Jump Start | race | `jumpStart == true` |
| `penalised` | Penalised | race | `penalties` non-empty |
| `did_not_finish` | Did Not Finish | race | `state == "dnf"` |
| `personal_best` | Personal Best | any | finished (or `bestSec`) · `previousBestSec` present · time < `previousBestSec` |
| `route_record` | Route Record | any | finished (or `bestSec`) · `routeRecordSec` present · time < `routeRecordSec` |

Rules on top of the table:
- Position-based ids (`close_finish, clear_win, gained_positions, lost_positions, good_start, led_every_gate,
  came_through`) are **never** emitted for a time trial, quali or practice, whatever the numbers say.
- `dns` and `dsq` rows get **no tags** (the host announces those states itself).
- `clean_*` is exclusive with `heavy_contact, tough_one, jump_start, penalised` by construction — prove it with a test.
- `route_record` implies `personal_best` when both would fire; emit only `route_record`.
- `led_every_gate` and `came_through` are mutually exclusive by construction.
- If more than `maxTags` fire, keep the first `maxTags` in `DEFAULTS.priority` order. Propose the priority order
  yourself (most distinctive first — a record beats a clean race beats a close finish) and document it; the owner
  will tune it.
- **Deliberately not in v1 (decline, do not approximate):** Many Overtakes, Strong Defence, Good Recovery, Battle,
  Consistent Pace, Fastest Sector, Improved Each Run, anything needing weather, region or opponent telemetry.
  List them in `BRICK.md` → non-goals with the fact each one would need.

## Provided modules (the only allowed dependencies)
| Module | Version | File | Why |
|---|---|---|---|
| `vocabulary.ids` | 0.0.1 | `provided/vocabulary/ids.lua` | only if you need `seededRng` for a determinism test; v1 needs no randomness — it is fine to depend on nothing |

## Prohibited responsibilities (specific to this brick)
- Does not decide race vs time trial; does not compute positions, corrected time, incident bands or penalties — all are input.
- Does not distinguish wall from car contact in any label (KB-34).
- Does not rank descriptors across drivers, count anything across sessions, or know about badges/prestige.
- Does not produce toasts, chat lines or HTML; labels are plain strings only.
- Does not read `facts.results[i].incidents[*].other` to infer blame (`attributed` is zero-fault by design).

## Acceptance criteria
1. On the attached fixture, five ids fire for driver `a` (`clean_race, gained_positions, close_finish, came_through, personal_best`); with the default `maxTags = 4` the lowest-priority one is dropped (state which in `BRICK.md`), and with `opts.maxTags = 5` all five appear in your documented priority order. `b` gets `clean_race, close_finish`; `c` gets exactly `heavy_contact`; `d` gets exactly `did_not_finish`.
2. On the solo fixture with two incidents, the driver gets no `clean_*` tag and no position-based tag; with zero incidents the driver gets `clean_run` (never `clean_race`) and `personal_best` only when `previousBestSec` is present and beaten.
3. Every emitted id appears in `M.CATALOGUE`, and every catalogue id has at least one test that emits it.
4. `#tags ≤ opts.maxTags` for every driver, default 4, and `maxTags = 0` yields empty `tags` without error.
5. Inputs are byte-identical (`T.show`) after evaluation; two evaluations of the same fixture are `T.show`-equal.
6. Wrong shapes (`facts` not a table, `results` missing, a row without `driverId`/`state`) `error()` with `competition.race_tags.evaluate:` in the message. A session `kind` outside the three known values returns `nil, "unknown_session_kind"`.
7. Passes under Lua 5.4 and LuaJIT with `tests/run.lua` unmodified.

## Must-never list (each becomes a `never_...` test)
- never `clean_race` when `timeTrial` (KB-35 regression: label must be `clean_run`)
- never any `clean_*` with `incidentCount > 0`, or `penalties` non-empty, or `jumpStart` (KB-38 regression)
- never a position-based id for a time trial, quali or practice
- never `personal_best` / `route_record` when the history field is absent
- never a tag for `dns` or `dsq`
- never more than `maxTags`
- never a label containing "wall", "car", "barrier" (KB-34)
- never mutate `facts`

## Known edge cases the author must handle
- Field of two where P2 DNF'd: `clear_win` needs a *finished* P2 — decline.
- A driver with `crossings` missing gate 1 (client stall): no `good_start`, no `led_every_gate`; `came_through` still requires a known gate-1 order for someone else — if nobody's gate-1 crossing is known, decline both.
- Two drivers with identical crossing times at a gate: tie → neither "earliest" (`led_every_gate` declines).
- `correctedSec` absent on a finished row (should not happen; treat as `totalSec`).
- `previousBestSec == totalSec` exactly: not a personal best.
- Quali/practice rows with `runs = 0` / no `bestSec`: no tags.
- Field of one with `timeTrial` absent: treat as time trial and add a diagnostic (`"timeTrial absent; fieldSize 1 treated as time trial"`).

## Regression cases to encode
- **KB-35:** solo run, 3 object incidents, finished → no `clean_*`; solo run, 0 incidents → `clean_run`, not `clean_race`.
- **KB-38:** race, finished P2, 3 object incidents → no `clean_race`; `tough_one` fires.

## Live QA the integrator will run (author drafts `QA.md`)
- Solo time trial, dirty: result banner shows no Clean tag. Solo, clean: `CLEAN RUN`.
- Two humans, one clean, close finish: both show `CLOSE FINISH`; the clean one `CLEAN RACE`.
- One jump start: `JUMP START` shown, no `CLEAN RACE`, even with zero contact.
- Server log line per driver: `tags driver=<id8> <id,id,…>` (the host will add this; say what you expect in it).

## Test command
From the brick folder: `lua5.4 tests/run.lua .` and `luajit tests/run.lua .` — both exit 0.
(Integrator's run: `tools\ncm-test.ps1 -AllowMissing -CoreRoot ncm\bricks\B-089-race-tags`.)

## Deliver
Folder `B-089-race-tags/` exactly as `COMPONENT_GATE.md` §4: `BRICK.md`, `MANIFEST.lua`, `init.lua` (provided),
`competition/race_tags.lua`, `tests/run.lua` (provided), `tests/test_race_tags.lua`, `fixtures/*.lua`, `QA.md`.
Unresolved questions go in `BRICK.md`.

---

## Attached fixture — `fixtures/race_4cars.lua` (synthetic, street_sprint, 3 gates, green at 1000.0)
```lua
return {
    session = { sessionId = "fx-race-4", kind = "race", timeTrial = false, fieldSize = 4, disciplineId = "street_sprint",
                tier = "street", gatesTotal = 3, greenAt = 1000.0, routeId = "tip_trench", routeName = "Tip to Trench" },
    results = {
        { driverId = "a", display = "A", position = 1, state = "finished", slot = 3, totalSec = 120.0, correctedSec = 120.0,
          penaltySec = 0, incidentSec = 0, incidentCount = 0, incidents = {}, penalties = {}, jumpStart = false, progress = 3,
          crossings = { [1] = 1004.0, [2] = 1060.0, [3] = 1120.0 }, previousBestSec = 125.0 },
        { driverId = "b", display = "B", position = 2, state = "finished", slot = 1, totalSec = 120.4, correctedSec = 120.4,
          penaltySec = 0, incidentSec = 0, incidentCount = 0, incidents = {}, penalties = {}, jumpStart = false, progress = 3, gapSec = 0.4,
          crossings = { [1] = 1003.5, [2] = 1061.0, [3] = 1120.4 } },
        { driverId = "c", display = "C", position = 3, state = "finished", slot = 2, totalSec = 131.0, correctedSec = 139.0,
          penaltySec = 0, incidentSec = 8.0, incidentCount = 1,
          incidents = { { kind = "object", band = 3, dv = 14.2, t = 1090.0, attributed = "self" } }, penalties = {}, jumpStart = false,
          progress = 3, gapSec = 19.0, crossings = { [1] = 1003.8, [2] = 1065.0, [3] = 1131.0 } },
        { driverId = "d", display = "D", position = 4, state = "dnf", slot = 4, penaltySec = 0, incidentSec = 0, incidentCount = 0,
          incidents = {}, penalties = {}, jumpStart = false, progress = 2, dnfReason = "left",
          crossings = { [1] = 1005.0, [2] = 1070.0 } },
    },
    routeRecordSec = 118.9,
}
```
Expected: `a` → clean_race, gained_positions (slot 3 → P1), close_finish (0.4 s to b), came_through (b led gate 1),
personal_best (120.0 < 125.0) — five candidates, so the default cap of 4 drops one (the cap test). Not
route_record (120.0 > 118.9). `b` → clean_race, close_finish. `c` → heavy_contact only (one incident is below
`toughIncidents`). `d` → did_not_finish only.

## Attached fixture — `fixtures/solo_dirty.lua`
```lua
return {
    session = { sessionId = "fx-solo", kind = "race", timeTrial = true, fieldSize = 1, disciplineId = "street_sprint",
                tier = "street", gatesTotal = 3, greenAt = 2000.0 },
    results = {
        { driverId = "s", display = "S", position = 1, state = "finished", slot = 1, totalSec = 140.0, correctedSec = 146.0,
          penaltySec = 0, incidentSec = 6.0, incidentCount = 2,
          incidents = { { kind = "object", band = 1, dv = 3.1, t = 2030.0, attributed = "self" },
                        { kind = "object", band = 2, dv = 7.0, t = 2080.0, attributed = "self" } },
          penalties = {}, jumpStart = false, progress = 3, crossings = { [1] = 2003.0, [2] = 2070.0, [3] = 2140.0 } },
    },
}
```
Expected: no tags at all (nothing clean, nothing position-based, no history). Copy it to `solo_clean.lua` with
`incidents = {}`, `incidentCount = 0`, `incidentSec = 0`, `correctedSec = 140.0`, `previousBestSec = 141.0` →
`clean_run, personal_best`.
