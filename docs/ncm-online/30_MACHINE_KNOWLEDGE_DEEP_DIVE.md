# 30 — Machine knowledge: what already exists, and the one thing being lost

> **STATUS: PROPOSAL** - a recommendation with **no authority until ruled on**. Covers: *the near-term audit `28_MACHINE_KNOWLEDGE.md` asks for, and the minimal additive change it identifies*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**2026-09-24.** The deep dive the owner scheduled after `IDEA-319`. Scope is exactly what the spec's own
implementation warning asks for and nothing beyond it:

> *"determine what existing discovery/Market/Machine Index primitives already exist, what current schemas
> record, and what minimal additive changes preserve the irrecoverable evidence this design will eventually
> need… prioritize ensuring that any newly persisted empirical observations can retain world + serialised
> machine + coordinates + timestamp rather than storing only a naked number."*

**Nothing built when this was written.** The migration drafted in §5 was applied as **028** on
2026-09-24, and the write site now carries the position. `31_CAPABILITY_AUDIT.md` §6 later settled what
`configuration_ref` can point at: an NCM-authored record, because the engine has no component object at
all. Migration **029** added the observation basis and the discovery position that this dive missed.

---

## 1. Headline

**The substrate is far closer to the spec than the spec assumes — and exactly two irrecoverable facts are
missing.** `vehicle_knowledge_evidence` (migration 016) was built with asset-provenanced observation in mind
before the spec existed. It already carries the observer, the world, the model, the **serialised source
machine**, the knowledge kind, the source kind, the epistemic class and a timestamp — with a uniqueness key for
idempotent retry and an `(asset_id, observed_at)` index, so *"everything this machine has been observed doing"*
is already an indexed query.

What it does not carry is **where** and **in what configuration**.

## 2. Measured against the spec's own minimum provenance list (§24)

| Spec requirement | Column today | Status |
|---|---|---|
| observer / knowledge owner | `ncm_driver_id` | ✅ |
| world identity | `server_id` | ✅ |
| source machine asset id | `asset_id` (nullable, FK, indexed) | ✅ |
| observation type | `knowledge_kind` | ✅ |
| authoritative measured value | `evidence_json` | ⚠️ present but **unused and untyped** |
| **world coordinates** | — | ❌ **missing** |
| timestamp | `observed_at` | ✅ |
| configuration reference (§24 tail) | — | ❌ **missing** |

Supporting vocabulary also exists and is validated in core: `machine_knowledge.SOURCES` and
`EPISTEMIC = { observed, published, ownership_verified }`, refused on write if unknown.

## 3. Three things already built that the spec needs and does not know about

**`vehicle_discovery.encounter_count`** — the addendum's §30 insists familiarity and evidence are *different
variables*, and that envelopes narrow with familiarity. **Encounter count is already being recorded per driver
per model**, alongside `first_discovered_at`, `last_encounter_at` and `discovery_method`. The estimator's
familiarity input exists today; only the estimator does not.

**`vehicle_discovery.source_driver_id` / `source_holding` / `source_asset_id`** — discovery already records
*who* and *which machine* caused it. That is §3's "different discovery sources may convey different additional
knowledge", already persisted.

**`player_market_knowledge.access_state`** — the market-as-information-institution channel (§6) and the
restricted-access design (`IDEA-298`) both need this column. It has existed since migration 017 and **has never
been written** (0 rows, `IDEA-251`).

## 4. What is being lost right now

**14 evidence rows and 14 discovery rows on Online, none with coordinates.**

This is the same shape as `IDEA-236`, one level over: every observation persisted without a position is
permanently un-locatable, and §9/§10 of the spec are built entirely on position —

> *"Check the coordinates. Downhill." "Which serial?" "#47."*

Coordinates cannot be reconstructed afterwards. Neither can the configuration the machine was in. The rate is
low today (discovery only fires on encounter or market card view), which makes this the cheap moment rather
than a reason to wait.

**It is not urgent in the way `IDEA-236` was** — 14 rows, no races depending on it. It is simply irrecoverable,
and the columns cost nothing.

## 5. The minimal additive change — **applied** (migration 028, 2026-09-24)

```lua
-- migration 028: observation provenance (IDEA-329)
ALTER TABLE vehicle_knowledge_evidence
  ADD COLUMN IF NOT EXISTS obs_x DOUBLE NULL,
  ADD COLUMN IF NOT EXISTS obs_y DOUBLE NULL,
  ADD COLUMN IF NOT EXISTS obs_z DOUBLE NULL,
  ADD COLUMN IF NOT EXISTS configuration_ref CHAR(36) NULL;
```

Four nullable columns, no backfill, no behaviour change, and one write site
(`collection.lua`) gains the player position it *already has in hand* — the discovery path reads the
authoritative player snapshot for its anti-spoof bucket and distance checks, so the coordinates are already
fetched and then discarded.

**SETTLED SINCE, by `31_CAPABILITY_AUDIT.md` §6:** there is no engine object for `configuration_ref` to
point at -- build 2.31 has no mod slots, no wheel types and no component RTTI -- so it can only ever reference
an **NCM-authored** configuration record. Core now refuses every value by name until that record exists.

**`configuration_ref` is reserved, exactly as migration 024 reserved it on `session_result`**, and for the same
reason the owner gave in §24: *asset identity says which machine produced the observation; configuration history
may eventually say what that machine was at the time.* Nothing writes it until the configuration primitive is
settled.

## 6. What this dive deliberately does not propose

- **No estimator.** The envelope mathematics (§23–§32) must be *"proposed and reviewed separately before
  becoming permanent knowledge history"*, and its anti-midpoint and determinism invariants (`IDEA-337`,
  `IDEA-338`) deserve their own pass.
- **No observation vocabulary.** Frozen behind the capability audit (`IDEA-339`). `evidence_json` stays untyped
  until that audit says which characteristics NCM can honestly measure, derive or author. Typing it now would
  guess.
- **No scanner, component recognition, configuration history or engineering knowledge** — the spec's warning
  names all four as out of near-term scope.
- **No SP convergence.** A parallel audit exists at `docs/research/open77/NCM_SP_ONLINE_CONVERGENCE_AUDIT.md`
  and reaches a compatible conclusion about preserving provenance early; this dive does not touch it.

## 7. Recommended order

1. **Migration 028** (§5) — four nullable columns, plus passing position through the one existing write site.
   Cheap, additive, stops the only irrecoverable loss in this area.
2. **`IDEA-251`** — wire market discovery and start writing `access_state`. Already half-built, and it is the
   documentation-bearing channel §4 and §6 depend on.
3. **`IDEA-339`** — the capability audit. Everything numeric in the addendum waits behind it.
4. Only then the estimator, as its own reviewed proposal.

**One observation worth recording:** the parts of this spec that look most expensive — asset-provenanced
observation, per-driver knowledge, market-derived documentation, familiarity counting — are largely built. The
parts that are genuinely unbuilt are the ones the spec itself says to defer.
