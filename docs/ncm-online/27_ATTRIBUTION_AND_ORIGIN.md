# 27 — Machine attribution (Stage 0) and the retirement of `origin`

> **STATUS: PROPOSAL** - a recommendation with **no authority until ruled on**. Covers: *Stage 0 machine attribution (IDEA-236) and the A1 origin retirement mechanics*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

Two of the three items owed before foundation work. Both concern the same record — what a machine *is* and what
it *did*. Neither is implemented.

---

# Part 1 — A1: how to retire `origin` safely

L124 retired `origin` **conceptually** and asked for the safe mechanics before any production change.

## What is actually there

| | |
|---|---|
| declared | `origin VARCHAR(32) NOT NULL DEFAULT 'production'` (migration 023) |
| values | `production`, `grant` |
| in production | **19 assets, all `production`. `grant` has never been written.** |
| read by | one `SELECT` and one log line in `provenance.lua`. **Nothing branches on it.** |
| `consumesOrdinals()` | exists in `vehicle_identity.lua`, **called only by tests** |

The serialisation gate people assume `origin` provides is `local origin = ord and PRODUCTION or GRANT` — origin is
*derived from* whether an ordinal was allocated. It records the decision; it has never made it.

## Why no migration is needed, at all

Because the column is **`NOT NULL` with a default**, an `INSERT` that omits it succeeds and gets `'production'`.

> **Code can stop writing `origin` today with zero schema change and zero production risk.**

That is the whole safety argument, and it means retirement is a code change, not a migration.

## The staged retirement

**Stage 1 — remove the concept from code (safe, reversible, no DDL).**
Delete `M.ORIGIN` and `M.consumesOrdinals` from `ncm/core/data/vehicle_identity.lua` and their tests; drop
`origin` from the two `INSERT` column lists in `ownership.lua`; stop `SET origin = 'production'` in the
`provenance.lua` backfill; drop it from the provenance read and log line. The column keeps taking its default
and nothing observes it.

**Stage 2 — leave the column alone, indefinitely.**
A vestigial column with a uniform value costs one `VARCHAR(32)` per asset and confuses nobody once the banner-
equivalent exists in code: a comment on migration 023 recording that `origin` is retired as of L124 and is not
to be read or written.

**Stage 3 — drop it only if it ever becomes confusing.** `ALTER TABLE vehicle_asset DROP COLUMN origin` in a
future forward migration. **Not recommended now**: MariaDB DDL is not transactional, the forward-only runner
cannot un-drop, and the column is harmless where it sits. Retiring a concept does not require deleting its
storage — the same principle as `IDEA-188` keeping `owned_vehicle` until 015 had a live PASS.

## What replaces it: nothing, because the facts already exist

| the fact | where it already lives |
|---|---|
| was this machine legitimately manufactured, and what is its place in history | `production_ordinal`, `maker_ordinal`, `model_ordinal`, `manufacturer_key`, `produced_at` |
| how did this driver come by it | `acquired_via ENUM('grant','progression','prize','purchase','seed')` |
| has anyone acquired it at all | `acquired_via IS NULL` — migration 017 made it nullable **on purpose**, so unsold market stock reads "nobody has acquired this yet" |

`acquired_via` is already the player-facing provenance field, already has the right vocabulary, and already has a
meaningful NULL. **Inventing `entry_route` would have duplicated a column that works** — which is what L124
forbade, and the measurement confirms.

**Only open sub-question:** `acquired_via` still offers `'grant'` as a value. Under L123 a grant is not a species
of machine, but it remains a truthful *acquisition route* for a progression award. ▸ *Keep it; it describes how
ownership moved, not what the object is.*

---

# Part 2 — Stage 0: machine attribution (`IDEA-236`)

## What is being lost, measured

29 completed results, none attributable, **not reconstructible** — `session_result`, `entry` and `seat` all lack
any vehicle reference. 9 incident rows, driver-attributed only. **+1 per finisher per race, continuing.**

## The constraint that shapes the design

**`ncm_world` and `ncm_league` are separate Lua VMs.** The live player→asset mapping lives in
`ncm_world/server/odometer.lua` (`tracked[vehicleId] = { assetId, pid }`) and in `vehicle_access.lua`
(`active[assetId]`). `session_result` is written in `ncm_league/server/race.lua`.

> **The league cannot see which machine a driver is in.** A global in one resource is `nil` in the other — the
> defect class that bit three times in one day and is now gated by `tools/test-cross-scope.lua`.

So Stage 0 is **not** "add a column and read a variable". It needs a cross-resource channel, and the codebase
already has the idiom: `ncm_world` documents `TriggerEvent("ncm:odometer.track", assetId, vehicleId, playerId)`
as the way any resource announces a tracked machine. Stage 0 is the inverse of that event.

**▸ Push, do not pull.** `ncm_world` emits `ncm:machine.seated (ncmDriverId, assetId|nil, vehicleId)` whenever a
driver's seat context changes. `ncm_league` keeps a small in-memory `seatedAsset[driverId]` and reads it
synchronously at settlement. A request/reply would put an async round-trip inside settlement, which is the one
place that must stay deterministic and idempotent (`IDEA-164`).

**When to latch it:** at **green**, not at settlement — a driver who steps out of the car after finishing would
otherwise settle as `nil`. Refresh on each seat event during the session and write the value held at green. If it
changes mid-session, log it: a car swap mid-race is either a bug or a story, and either way we want to know.

## Proposed columns

```sql
-- session_result
asset_id          CHAR(36) NULL,                                   -- the machine fielded
-- machine_source: REMOVED by migration 027. See the note below.
attribution_basis ENUM('recorded','derived','unknown') NULL,       -- A4
attribution_rule  VARCHAR(64) NULL,                                -- names the rule when basis='derived'
configuration_ref CHAR(36) NULL                                    -- Q8: reserved, nothing writes it yet

-- incident
asset_id          CHAR(36) NULL,
other_asset_id    CHAR(36) NULL
```

All additive, all nullable, no behaviour change, no backfill required to deploy.

**No foreign key on `asset_id`.** A FK would be tidy, but it would also make a historical result depend on a row
in a table the lifecycle work may later reshape, and it buys little when the writer is a single server-side path.
Integrity comes from the write site, not the constraint.

**`configuration_ref` is reserved deliberately** (Q8). It costs one nullable column now. The lesson of `IDEA-236`
is that "we will add it later" is exactly how 29 results became anonymous.

## The existing 29 rows

> **CORRECTION, 2026-09-24 (L127).** An earlier draft of this document specified a `machine_source` enum
> carrying `team_equipment`. That was wrong twice over: Q2 offered it as option (b) and **the owner chose (c),
> "require every car to be an asset"**, and the value itself encodes the species distinction L123 forbids.
> **A team car is simply a car owned by a team**; an NCX car is simply a car; exclusivity lives in market
> access, not in the object (L124 A2, L126). Migration 027 drops the column. `asset_id` says WHICH machine and
> `attribution_basis` says HOW WELL WE KNOW IT -- there is no third fact.

| rows | proposal |
|---|---|
| 19 pre-purchase results + driver A's 2 | `attribution_basis='unknown'` |
| the 8 post-purchase results | **`attribution_basis='derived'`, `attribution_rule='exclusive_ownership_v1'`** |

**I am changing my earlier recommendation, and the reason matters.** On 2026-09-24 I recommended leaving all 29
unknown, because a derived attribution would have been stored as though it were a recorded fact. A4 then created
the vocabulary that makes it honest — `derived`, permanently distinguishable, carrying the rule that produced it.
With that mechanism the evidence is worth keeping rather than discarding.

`exclusive_ownership_v1` states: *the driver owned exactly one asset at the time; entry required owning an
eligible machine; substitution is forbidden (L83); the asset is the only one in the world with any odometer
distance, last checkpointed 3.5 minutes after the final race.*

**The residual gap, recorded with it:** NCM never stored the eligible record on the entry and never verified at
the grid which vehicle the driver occupied. A `/ncm car` loaner cannot be excluded. That is precisely why this is
`derived` and not `recorded`, and why the rule is versioned — if the standard of evidence ever changes, `_v2`
says so without rewriting what `_v1` concluded.

## Tests before deployment

- core: `attribution_basis` is never `recorded` without an `asset_id`
- core: a session with no seated asset settles `unknown`, never a guess
- host: the seat event updates the league map; settlement writes the value held **at green**
- cross-scope: `tools/test-cross-scope.lua` must stay green — this change spans both VMs and is exactly the shape
  it exists to catch
- live on Development: run a race in a called asset, confirm `recorded` + correct `asset_id`; run one in a team
  car, confirm `team_equipment`

## Promotion

Development proves; Online confirms (L121). This qualifies for early independent promotion under Q66 — additive
DDL, two write sites, no behaviour change, and every race run without it loses a fact permanently. **The one-time
UPDATE stamping the 29 legacy rows is a separate, reviewable step** taken after the column exists and the owner
has seen the derivation rule.
