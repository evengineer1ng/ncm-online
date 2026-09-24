# NCM COMPONENT GATE — gate version 1 (2026-09-22)

**Read this, then build the brick named in your assignment packet. You do not need, and will not get, the
repository.** Everything a brick may depend on is in this document plus the files attached to the packet.

NCM Online is a Cyberpunk 2077 multiplayer motorsport layer. Its rules engine is **ncm-core**: a set of pure Lua
modules that run unchanged in three hosts (the OPEN//77 dedicated server, the OPEN//77 client, and a local test
runner). A **brick** is one ncm-core module, delivered with its tests, that has not yet been admitted into the
repository. The repo-aware integrator moves it into place, wires it to the host, deploys it and validates it live.
You manufacture the piece; you do not attach it.

---

## 1. What a brick is — the three shapes

Every brick is one of these. Say which in `BRICK.md`. If your assignment does not fit any of them, stop and say so
under "unresolved questions" rather than inventing a fourth.

| Shape | Signature | Owns state? | Example |
|---|---|---|---|
| **Rule** | `M.evaluate(facts, opts) -> result` (pure) | no | post-event descriptors from a settled result |
| **Reducer** | `M.apply(state, event, ctx) -> state, deltas` (pure; returns the new state) | the `state` table it is handed, nothing else | career aggregates from one driving sample; badge tiers from aggregates |
| **Catalogue** | `M.ITEMS` (plain tables) + `M.validate(items) -> ok, problems` + lookups | no | a descriptor bank, a badge ladder, a region table |

Not brick shapes (integrator-only): host adapters (anything calling `Open77.*`, `MySQL`, `WebUI`, `GlobalState`,
events, commands), HTML/CSS pages, database schema, orchestration of a live session.

## 2. The module contract (this is what ncm-core already is)

```lua
-- ncm-core module: competition.race_tags        (brick B-089 v1)
-- One-paragraph purpose. Which IDEA it serves. Pure: (facts, opts) -> tags.
local Core = NcmCore

Core.define("competition.race_tags", function(C)
    local M = { version = "0.1.0" }

    -- Dependencies: only the modules the packet lists as PROVIDED, resolved lazily.
    local Ids = C.get("vocabulary.ids")

    M.DEFAULTS = { maxTags = 4 }            -- every tunable is here, named, and overridable through opts

    function M.evaluate(facts, opts)
        if type(facts) ~= "table" then error("competition.race_tags.evaluate: facts must be a table", 2) end
        opts = opts or {}
        -- ...
        return { tags = {}, diagnostics = {} }
    end

    return M
end)
```

Rules, all enforced by review:

1. **One global: `NcmCore`.** `local Core = NcmCore` at the top; nothing else at file top level. Register with
   `Core.define(name, factory)`; resolve dependencies with `C.get(name)` **inside** the factory or inside functions.
2. **Module name = its future path.** `competition.race_tags` lives at `competition/race_tags.lua`. The packet
   tells you the name; do not choose your own.
3. **Pure.** No `os`, `io`, `require`, `package`, `dofile`, `load`, `print`, no clock, no randomness. Time arrives
   in the input (`facts.now`, `ctx.now`). Randomness, if the packet allows it, arrives as `ctx.rng` (a function
   returning `[0,1)`), and every test seeds it via `vocabulary.ids.seededRng(seed)`.
4. **JSON-safe data only.** Inputs, outputs and state are strings, numbers, booleans, arrays (no holes), and
   string-keyed tables. No functions, no cycles, no metatables in data, no `nil` inside arrays.
5. **Never mutate inputs.** A Rule returns a new table. A Reducer may mutate and must return the `state` it was
   handed (that is the one sanctioned mutation); it never mutates `event` or `ctx`.
6. **Absent ≠ zero.** A fact the host could not compute is simply absent. Your module must tolerate absence by
   not concluding, never by assuming `0`. Never emit a result the input cannot support.
7. **Errors.** Programmer errors (wrong shape) → `error("module.fn: what was wrong", 2)`. Expected refusals →
   `return nil, "reason_slug"`. Nothing else. No logging — return `diagnostics = { "..." }` if the host may want
   to log something.
8. **Tunables** live in `M.DEFAULTS`, are read through `opts`/`ctx`, and are never hidden as literals in logic.
9. **Units.** Seconds (numbers, may be fractional), metres, metres per second. Ids are strings. Positions are
   `{ x, y, z }`. Money is integer eddies. Times are server epoch seconds unless the packet says otherwise.
10. **Deterministic.** Same input, same output, under both interpreters (below). Iteration order over string-keyed
    tables is not deterministic in Lua — sort before you emit.
11. **Version.** `M.version` is semver and matches `BRICK.md`.

## 3. Language: the Lua 5.1 / LuaJIT / Lua 5.4 intersection

The suite runs under **both** Lua 5.4 and LuaJIT 2.1 and both must pass. Stay inside the intersection:

| Do not use | Use instead |
|---|---|
| `//` integer division; bit operators `&` `\|` `~` `<<` `>>` | `math.floor(a / b)`, arithmetic |
| `goto`, labels | loops with flags, early `return` |
| integer-subtype assumptions (`math.type`, `%d` with a float) | `math.floor` first; format with `%s` / `%.3f` |
| `string.pack/unpack`, `utf8.*`, `table.move`, `coroutine.close` | plain loops |
| `table.unpack` **or** `unpack` alone | `local unpack = table.unpack or unpack` |
| `#` on a table with holes | track counts explicitly |
| `__gc`, `__close`, `<const>`, `<close>` | nothing |
| `os.*`, `io.*`, `require`, `print` | injected inputs; returned diagnostics |

Style: 4-space indent, `local` everything, `M.fn` for public, file-local helpers above the `define`, one
comment line per public function saying what it returns, comments explain *why* not *what*. Match the tone of the
provided modules; no banners, no decorative separators.

## 4. Package layout — a brick folder is a runnable mini core root

The test runner is used **unchanged**; your folder just has to look like a core root.

```
B-089-race-tags/                     <- brick id: B-<IDEA number>-<slug>
  BRICK.md                           <- the passport (COMPONENT_MANIFEST_TEMPLATE.md)
  MANIFEST.lua                       <- load order: provided modules first, then yours
  init.lua                           <- PROVIDED, byte-identical to ncm/core/init.lua. DO NOT EDIT.
  provided/vocabulary/ids.lua        <- PROVIDED read-only copies of the core modules you may depend on
  provided/vocabulary/json.lua
  competition/race_tags.lua          <- your module, at the path its name implies
  tests/run.lua                      <- PROVIDED. DO NOT EDIT.
  tests/test_race_tags.lua           <- your tests (may be several files, all test_*.lua)
  fixtures/settled_race_6cars.lua    <- deterministic fixtures: each file `return { ... }`
  QA.md                              <- the live QA procedure (or a section of BRICK.md)
```

`MANIFEST.lua`:
```lua
return {
    "provided/vocabulary/ids.lua",
    "provided/vocabulary/json.lua",
    "competition/race_tags.lua",
}
```

Run, from inside the folder: `lua5.4 tests/run.lua .` and `luajit tests/run.lua .` (optional filter as the third
argument). Exit code 0 under both is the offline proof. (Verified 2026-09-22: a probe brick in this exact layout
passes under Lua 5.4.6 and LuaJIT 2.1 with the runner unmodified.) If you only have one interpreter, say so in `BRICK.md`; the
integrator runs the other. Never modify `init.lua`, `tests/run.lua`, or anything under `provided/` — if you think one
of them is wrong, write it under "unresolved questions".

Fixtures are loaded from tests with `dofile` **only in tests**, and always relative to the core root the runner
was given (the integrator runs the suite from the repository root, so a bare relative path breaks there):

```lua
local ROOT = (arg and arg[1]) or "."
local fx = dofile(ROOT .. "/fixtures/settled_race_6cars.lua")
```

Modules never load files.

On integration the integrator deletes `provided/`, `init.lua`, `tests/run.lua`, moves your module to
`ncm/core/<path>` and your tests to `ncm/core/tests/`, adds one line to the real `MANIFEST.lua`, and runs the real
gate. That is the whole point of the layout: **zero edits to your code to admit it.**

## 5. Tests are cargo, not optional

Test files return a table of `name = function(T)`; `T` has `ok, eq, neq, match, errors, Core, show`. Every brick
ships, at minimum:

| Category | What it proves |
|---|---|
| happy path | the documented behaviour on the main fixture |
| boundary | empty input, field of one, exactly-at-threshold values, largest plausible field |
| invalid input | wrong shapes `error()` with the module name in the message; refusals return `nil, reason` |
| absence | every optional fact absent → the module declines rather than assumes |
| invariant | the "must never" list from the packet, each as its own test named `never_...` |
| determinism | run twice on the same fixture, deep-equal (`T.show`); under a seeded rng where applicable |
| regression | one test per bug/finding named in the packet, named after it (`kb38_no_accomplishment_on_a_dirty_run`) |
| purity | inputs are unchanged after the call (compare `T.show(before)` to `T.show(after)`) |

Fixtures are hand-readable Lua tables. When the integrator provides a fixture captured from real data, treat it as
canonical and do not edit it. Suggested integration tests and the live QA procedure (observable outcomes, exact
commands where you know them, PASS wording) go in `QA.md`. **External tests are candidate proof; only a live PASS
logged by the integrator validates anything.**

## 6. What you are not allowed to do

- Touch, assume, or emulate `Open77.*`, `MySQL`, `GlobalState`, `TriggerEvent`, `RegisterCommand`, WebUI pages,
  state bags, buckets, players, vehicles. Those are hosts. If the packet's input schema lacks something you need,
  say so; do not reach past it.
- Define a module name that already exists in core, or redefine a provided one.
- Change sporting semantics not named in the packet (what counts as finished, clean, a win, a time trial, a
  penalty). If your brick needs a semantic the packet did not give you, that is an unresolved question.
- Keep state anywhere but the Reducer `state` argument. No module-level caches, no upvalue accumulators.
- Persist anything, or design tables. Say what you need persisted in `BRICK.md` → *persistence*.
- Couple to a second feature "while you're there". One IDEA per brick.
- Add dependencies beyond the packet's PROVIDED list.
- Emit anything the input does not factually support.

The removal test: the integrator must be able to delete your file and your MANIFEST line and have nothing else in
the repository notice except the one host call site they wired.

## 7. What the host side looks like (so your outputs land somewhere real)

You never write these, but knowing the seams helps you shape outputs.

| Seam | When it runs | What it hands core | What it does with output |
|---|---|---|---|
| **Settlement** (`server/race.lua complete()`) | once, when a session completes | `results` from `session.race.classify(s)`, the session record, `now` | persists rows, announces, applies progression, publishes the `ncmResult` bag |
| **Progression** (`server/progression.lua`) | after settlement, per driver | `(state, resultRow, ctx{disciplineId, classId, sessionKind, fieldSize, sessionId})` | stores new state, inserts accomplishments |
| **Telemetry ingest** (`server/telemetry.lua`) | 5 Hz per driver during a session | decoded samples `{t, x, y, z, v, h?, …}` into a 12-second ring | incidents, progress, corrected time |
| **Calendar publish** | on change | events, entries | `ncmCalendar` global state, guide rows |
| **Presentation** (toasts, chat, WebUI) | after the above | plain strings and small tables | shows them; cannot be restyled from core |

A settled result row (input to most Rule bricks) currently carries:
`position, driverId, entryId, display, state ("finished"|"dnf"|"dns"|"dsq"|…), totalSec, penaltySec, jumpStart,
progress, gatesTotal, teamId, seatIndex, penalties[], incidentSec, incidentCount, incidents[] ({kind="car"|"object",
band 1..3, dv, other?, x, y, z, t, attributed}), correctedSec, gapSec?, dnfReason?`. Gate crossing times exist per
driver (`crossings[gateIndex] = t`). Position-over-time, overtakes and start reaction do **not** exist yet; a packet
that needs them will say whether the host will compute them or whether the brick must decline.

## 8. Versioning and identity

- Brick id `B-<IDEA>-<slug>`; revisions `v1, v2 …` recorded in `BRICK.md` with a changelog; the folder is not
  renamed between revisions.
- `gate: 1` in `BRICK.md`. If the gate changes incompatibly the version bumps and old bricks are re-reviewed.
- Core compatibility: the packet names the `NcmCore.VERSION` (`0.0.1` today) and the provided modules' versions.

## 9. Pipeline (integrator-owned; here so you know what happens to your brick)

`raw → shaped → specified (packet written) → candidate (brick delivered to ncm/bricks/) → review → built
(admitted to ncm/core + host wired + offline gate green) → validated (live PASS in wp/MASTER_TEST.md)`.

The existence of your code never advances the idea past *candidate*. A review comes back as
`COMPONENT_INTEGRATION_REVIEW_TEMPLATE.md` with one verdict and a numbered list; revise from that packet alone.
Candidates live in `ncm/bricks/<id>/`, which the build tool never reads, so a queued brick cannot ship by accident.
