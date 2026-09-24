# 24 — Foundation reconciliation: Q1–Q70 against the repository

> **STATUS: CURRENT** - authority for: *foundational primitives, contradictions, sequencing* - affirmed 2026-09-24 (L123)
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**2026-09-24.** Reconciles the owner's answer pass (`23_OPEN_QUESTIONS.md`) against the actual schema, code,
production data, the full 297-row ledger and the two accepted proposals (`21`, `22`). **Nothing here is
implemented.** This is the review artifact the owner asked for before the implementation pass.

> **Correction that changes this document's inputs.** My earlier classification covered 177 of 297 ledger rows —
> a row-matching regex skipped every row whose ID was written `**IDEA-NNN**`, which was 119 rows (40%). Fixed and
> pushed before writing this. Corrected totals: **F1 58 · F0 24 · INV 38 · GATE 10 · SYS 69 · UI 38 · OPS 28 ·
> UP 21 · DSN 11**. Foundational work is **82 rows plus 38 invariants**, not the 35 I reported. The Q1–Q70 set was
> therefore drawn from a partial view; the answers all still hold, but several turn out to **reaffirm decisions
> already locked** rather than open new ones, which is the single most useful finding below.

---

## 1. The headline: much of this is already designed, and blocked on one missing primitive

The answers to **Q4, Q6, Q15, Q45, Q46, Q48, Q50** describe a world that `14_TEAM_ORGANIZATIONS.md` (L92/L93) and
ledger rows `IDEA-139/142/157/162/168` **already specify**. They are not new design. They are blocked, and they
are blocked on the *same* missing thing:

> **NCM has no concept of a principal that can hold title, money or custody. Everything is keyed to a driver.**

- `vehicle_asset.ncm_driver_id CHAR(36) **NOT NULL**`, FK → `ncm_driver` — a team cannot own a car
- `ledger.ncm_driver_id CHAR(36) **NOT NULL**`, FK → `ncm_driver` — a team cannot hold money (`IDEA-162`, blocked)
- no custody concept at all — a part cannot be *anywhere*

Migration 015 **anticipated this in writing**: *"`owner_principal_kind/id` (IDEA-168, team-owned cars). It is a
cheap later ALTER precisely because the primary key is the asset rather than the owner."* The foresight was
recorded and then never spent.

**One primitive unblocks Q4, Q6, Q15, Q45, Q46, Q50, Q51, `IDEA-162`, `IDEA-168`, and the whole L92/L93
organisation model.**

---

## 2. Consolidated architectural decisions established by the answer pass

**D1 — Every persistent car is a machine asset.** No species of car sits outside the asset system. Team, grid,
street, show and reward cars differ by ownership, custody, configuration and use — never by ontology. (Q2, Q4, Q6)

**D2 — There is no permanent "grant car".** Admin/debug spawning is tooling. TW2-era granted equipment is an
artifact of an obsolete event model, not architecture. (Q6, and the governing principle)

**D3 — Title, money and custody are held by a *principal*, which may be a Driver or an Organization.** (Q4, Q15,
Q50, reaffirming `IDEA-162`/`IDEA-168`/L92/L93)

**D4 — Physical things conserve.** Installation, removal, trade and service *move* assets. Destructive reverse
engineering is the single defined consuming exception. (Q14, Q38)

**D5 — Unknown history stays unknown.** Never manufacture provenance to eliminate a legacy null; backfill only
where existing evidence is authoritative. (Q3, Q26)

**D6 — Historical attribution is immutable.** Present ownership or configuration must never rewrite what produced
an old result. (Q8, Q9, and `IDEA-165`/`IDEA-194`, already locked)

**D7 — World identity and runtime identity are different concepts.** One NCM world is expected; do not bind
persistent progression to a server process. (Q35)

**D8 — Wear will have real mechanical teeth**, gated on validation — *not* permanently information-only. Persist
the real condition even while effects are inactive, so history is not lost waiting for a gate. (Q29)

**D9 — Prepare seams without simulating them.** Storage capacity, service contracts, escrow, workshop capacity and
multi-server hosting are architected and left unenforced. (Q13, Q37, Q49, Q51, Q35)

**D10 — Development proves; Online confirms.** (Q63)

---

## 3. The smallest set of shared primitives

Ten primitives satisfy the large majority of the seventy answers. Four of them carry most of the weight.

### The four load-bearing ones

**P1 — Owner Principal** `(principal_kind, principal_id)`
> Satisfies **Q4, Q6, Q15, Q45, Q50, Q51**; unblocks `IDEA-162` (team treasury), `IDEA-168` (team cars), L92/L93.
> Replaces bare `ncm_driver_id` on `vehicle_asset` and `ledger`. Migration 015 already named this exact shape.
> **One generalisation serves title, treasury, settlement recipient, storage custodian and market supplier.**

**P2 — Physical Asset** (the shared supertype of machine and component assets)
> Satisfies **Q2, Q9, Q10, Q11, Q14, Q17, Q32**. Identity, serial/provenance, owner principal, custody, lifecycle.
> A machine asset and a component asset differ in *what they are*, not in *how they are owned, moved or recorded*.

**P3 — Custody** (where a physical asset is: `installed_in` · `stored_at` · `in_escrow` · `listed_in_market`)
> Satisfies **Q12, Q13, Q15, Q16, Q17, Q49**. This is the primitive that makes install, remove, store, list and
> trade the *same operation shape* instead of five subsystems. It is also the only honest way to answer "where is
> my gearbox".

**P4 — Transfer Envelope** (one atomic settlement unit: N asset legs + N money legs, one idempotency key)
> Satisfies **Q16, Q45, Q46, Q48, Q49, Q50, Q51, Q52**; realises `IDEA-139` and `IDEA-142`.
> **Directly replaces the current blocker**: `vehicle_asset_transfer` is per-asset with a per-asset idempotency
> key, which cannot express "car + part + cash ↔ car + cash" atomically.

### The supporting six

**P5 — Attributed Operation** — work performed on an asset by a principal, with a seeded bounded outcome vector.
One shape for manufacture, install, remove, repair, diagnose, reverse-engineer. Satisfies **Q15, Q30, Q31, Q38,
Q39, Q40**, `IDEA-276`, and carries the `relief_m` of L120.

**P6 — Exposure Ledger** — monotonic accumulation per `(asset, dimension)`. Satisfies **Q21, Q22, Q25, Q26, Q27,
Q28**.

**P7 — Configuration Snapshot** — immutable reference to an asset's component set at a moment. Satisfies **Q8,
Q16, Q23**; extends `IDEA-150`/`IDEA-203` (factory vs current configuration), which already exist.

**P8 — World Identity** — `world_id` distinct from runtime/server instance. Satisfies **Q35**. Cheap now; 28 tables
are keyed `server_id` today and every additional table raises the cost.

**P9 — Knowledge Ladder** — per `(principal, design)` epistemic state. Satisfies **Q39, Q42, Q43, Q44**.
**Already exists for vehicles** (machine knowledge, `player_market_knowledge`); this is extension, not invention.

**P10 — Capability Set on rulesets** — permitted capabilities per ruleset. Satisfies **Q58**; `IDEA-068` notes
rulesets already carry format/penalties/eligibility, so this is one more field on an existing thing.

### Dependencies

```
P8 (world id) ──────────────── independent, cheapest, do it before more tables exist
P1 (principal) ──┬─► P3 (custody) ──┬─► P4 (envelope) ──► secondary market, service contracts
                 │                  │
                 └─► team treasury  └─► P2 (component assets) ──┬─► P6 (exposure) ──► conditions ──► effects*
                                                                 └─► P7 (config snapshot) ──► Q8 attribution
P5 (attributed operation) ──► engineering ops, repair relief (L120), provenance biography
P9 (knowledge) ─── independent of the above; finish the half-built market half first
P10 (capability sets) ─── independent, cheap
                                                       * effects gated by IDEA-249 AND the setPerformance finding
```

---

## 4. Contradictions with the current repo, schema and docs

| # | Contradiction | Evidence | Resolution |
|---|---|---|---|
| C1 | Team cars cannot be assets | `vehicle_asset.ncm_driver_id NOT NULL` + FK to `ncm_driver` | P1 (015 already named the ALTER) |
| C2 | Teams cannot hold money | `ledger.ncm_driver_id NOT NULL` + FK | P1; unblocks `IDEA-162` |
| C3 | Legacy equipment model still live | **40 `issued_vehicle` rows, 20 `team_car` rows in production**, none are assets | Migrate to machine assets under P1/P2 (`14_TEAM_ORGANIZATIONS.md` already says so) |
| C4 | Atomic multi-item trade impossible | `vehicle_asset_transfer` per-asset idem key; purchase is single-asset | P4 |
| C5 | `ORIGIN = { production, grant }` encodes the species Q6 abolishes | `ncm/core/data/vehicle_identity.lua:45` | **Q7 answer needed** — see §5 |
| C6 | Results not machine-attributed | `session_result` has no `asset_id`; nor do `entry`/`seat` | Q1 |
| C7 | Incidents not machine-attributed | `incident(session_id, ncm_driver_id, other_driver_id, band)` — no asset | Q1's sibling; same migration |
| C8 | No custody/storage concept exists | no storage table in any migration | P3 |
| C9 | Market discovery half-built | `player_market_knowledge` exists since 017 with **0 rows in production**; `markets.known()` tested and never called | `IDEA-251`, Q42 |
| C10 | `server_id` conflates world and runtime | 28 tables keyed on it, 93 `serverId()` call sites | P8 |
| C11 | **`setPerformance` is one profile per vehicle and does not stack — and class ceilings already claim it** | `IDEA-079`/`IDEA-102` | **Hard constraint on component effects.** Must be an explicit input to `IDEA-249`, not discovered during it |
| C12 | Duplicate ledger IDs | `IDEA-124/125/126` (known, `IDEA-190`); **`IDEA-239/240` (new, mine)** | `IDEA-296`; remedy is the owner's call under L68 |

**C11 deserves emphasis.** The engine-capability audit was scoped as "what can we manipulate". The real question
is narrower and harder: *given that the single `setPerformance` profile per vehicle is already spent on class
homologation ceilings, what mechanism can a worn or upgraded component use at all?* If the answer is "none
without giving up class ceilings", a large part of the component-effects design is constrained before it starts.

---

## 5. Genuine ambiguities still requiring clarification

**A1 — Q7, `origin` semantics (the owner asked to see this before answering).** Today:
```lua
M.ORIGIN = {
    PRODUCTION = "production",  -- primary-market manufacture, incl. the alpha launch allocation
    GRANT      = "grant",       -- admin / progression / test: a real persistent asset, no serial
}
function M.consumesOrdinals(origin) return origin == M.ORIGIN.PRODUCTION end
```
`origin` currently does **two unrelated jobs**: it describes how a machine entered the world, *and* it gates
whether a serial is consumed. Q6 abolishes the `grant` species. Proposed split, for approval:
`entry_route` (player-visible provenance: `manufactured`, `awarded`, `transferred`, `founding_stock`) and a
separate internal `is_tooling_artifact` boolean that suppresses serialisation for debug spawns only.
**Not implemented pending your answer.**

**A2 — Q5, allocator vs identity.** You asked me to clarify whether the question was about the internal allocator.
It was. Concretely: should a team-owned machine draw `NCM #`, `maker #` and `model #` from the same three
sequences as a purchased one? Under D1 ("a race car is still a car") the answer is presumably yes — but that
means league equipment consumes NCM serial space. Confirm.

**A3 — Q32, lifecycle vocabulary.** You asked to see the proposal first. Deferred to the implementation pass;
flagged so it is not silently chosen.

**A4 — Q3, what is actually recoverable.** I have not yet established whether any of the 29 results can be
authoritatively attributed. The only candidate evidence is "the driver owned exactly one asset at the time",
which is *inference*, not authority. **Under D5 I will not treat it as authoritative without your ruling** —
listed here rather than acted on.

**A5 — Q29 vs the AG gate.** You want real teeth, gated on validation. That means persisting conditions whose
effects are inactive. Confirm that a *player-visible* condition with no mechanical effect is acceptable in the
interim, or whether conditions stay entirely invisible until effects activate.

**A6 — Q45/Q46 scope.** "Players can supply markets" and "secondary market, yes absolutely" are directionally
clear, but qualification/admission mechanics are explicitly undesigned. P4 makes both *possible*; neither is in
the proposed sequence below.

---

## 6. Legacy assumptions and documents to supersede

| Document / artifact | What is now obsolete |
|---|---|
| `04_TESTER_WINDOW_1.md` | TW2-era grant assumptions — already marked superseded in scope; the *granted equipment* model it implies is now explicitly dead (D2) |
| `05_DATA_MODEL.md` | Driver-keyed ownership and the `issued_vehicle` equipment model |
| `08_ECONOMY.md` | Single-wallet-per-driver assumption (no team treasury) |
| `13_VEHICLE_COLLECTION.md` | Where it treats issued/team cars as a separate species |
| `ncm/core/data/vehicle_identity.lua` | `ORIGIN.GRANT` as a gameplay concept (see A1) |
| `team_car` / `issued_vehicle` tables | Superseded by machine assets under a principal — **but not dropped**; they are the migration source, and `IDEA-188`'s precedent (keep 012's table until 015 has a live PASS) applies |

`14_TEAM_ORGANIZATIONS.md` is **not** superseded — it is reaffirmed, and becomes the specification for the P1 work.

---

## 7. Migrations and backfills required

| # | Change | Risk | Notes |
|---|---|---|---|
| M1 | `session_result.asset_id` + `machine_source` enum | very low, additive | Stops C6. **Do first.** |
| M2 | `incident.asset_id` + `other_asset_id` | very low, additive | Stops C7, same pass |
| M3 | `vehicle_asset.owner_principal_kind/id`, backfilled from `ncm_driver_id` | low | 015 designed for this; keep the old column until a live PASS |
| M4 | `ledger.owner_principal_kind/id`, same shape | low | Unblocks team treasury |
| M5 | `world_id`, defaulted from `server_id` | low but **28 tables** | Cheapest now; cost rises with every new table |
| M6 | Migrate `team_car`/`issued_vehicle` → machine assets owned by team principals | **medium — the only genuinely risky one** | 60 production rows; needs serial decision A2 first |
| M7 | Component asset, custody, exposure tables | new, no data | Free until it exists |
| M8 | Factory-component backfill for the 19 existing machines, exposure seeded from each machine's odometer | medium | Q20/Q21; deterministic seeds from asset id (Q26) |

---

## 8. What is being lost right now, per race and per session

Measured against production, not estimated:

| Fact | Status | Rate of loss |
|---|---|---|
| **Which machine produced a result** | **29 results, none attributable, not reconstructible** | **+1 per finisher, per race** |
| **Which machine was involved in an incident** | **9 incident rows, driver-attributed only** | **+1 per incident** |
| **Which market a player has learned of** | `player_market_knowledge`: **0 rows**, table unused since migration 017 | +1 per player per first sight of a market |
| Which configuration raced | not captured | not yet lossy (no components); **becomes lossy the day components ship** |
| Behavioural facts (Q57) | **not being lost** — `incident` already records `session_id`, both drivers and a severity band | — |
| Odometer | **not being lost** — accruing correctly, 26,606 m across 19 assets | — |
| Telemetry | 343 rows; being captured. Risk is *future* deletion before derivation exists, not present loss | — |

**Honest correction to my own framing:** I flagged Q57 as urgent alongside Q1. Having checked, the behavioural
substrate largely exists — incidents are recorded per session with both parties and a band. What is missing is
*machine* attribution on them (row 2) and the derived behavioural history, which is reconstructible from what is
stored. **Q57 is real but it is not bleeding the way Q1 is.**

---

## 9. Recommended implementation sequence (NCM Development)

Each step is independently valuable and independently testable.

**Stage 0 — stop the bleeding (promote to Online early, see §10)**
1. **M1 + M2** — `asset_id` on results and incidents, plus `machine_source`. Additive, no behaviour change.

**Stage 1 — the principal, which unblocks the most**
2. **M3 + M4** — owner principal on assets and ledger, backfilled. Old columns retained until a live PASS.
3. **M5** — `world_id`, while it is still 28 tables and not 40.

**Stage 2 — finish what is already half-built**
4. **`IDEA-251`** — wire market discovery (P9). The table and the tested function both already exist.
5. **`IDEA-068`** — capability sets on rulesets (P10). One field on a thing that exists.

**Stage 3 — the engineering substrate, no components needed**
6. **P5 attributed operations** + the Diagnostics slice against the 19 existing machines (Q41 — explicitly an
   *engineering-substrate validation* slice, not the final component-diagnostics game).

**Stage 4 — the transaction spine, before parts calcify it**
7. **P3 custody** then **P4 transfer envelope**. Synchronous trade only (Q49).
8. **M6** — team cars become assets. Needs A2 answered.

**Stage 5 — components**
9. **P2 component assets** + `IDEA-240` architecture profiles (I propose, you review — Q18/Q19).
10. **M8** — factory-component backfill with odometer-seeded exposure.
11. **P6 exposure accrual** + **P7 configuration snapshots**, conditions persisted, effects inactive.

**Stage 6 — effects, gated**
12. `IDEA-249` audit **including the C11 `setPerformance` constraint as an explicit input**, then §AG5/§AG6, then
    conditions acquire teeth.

**Gates to schedule in parallel (Q65):** `IDEA-031` settlement replay — *"silently fine for months and then eats a
championship"* — before purses become real income (Q55). `IDEA-033` adversarial gates. `IDEA-032` "no 20 anywhere".

---

## 10. Promote to NCM Online early

Only **Stage 0 (M1 + M2)** qualifies. It is additive DDL plus two write sites, changes no behaviour, and every
race run without it permanently loses a fact. Under Q66 it should not wait behind a feature train.

Everything else waits for a deliberate promotion. In particular **M5 (`world_id`) and M6 (team cars) must not be
early-promoted** — M5 touches 28 tables and M6 is the only migration here with real data risk.

---

## Status

**Nothing implemented. Stopping for review**, as instructed. The five answers I need before Stage 1 can be
designed rather than guessed are **A1 (`origin` semantics), A2 (serial allocator for team cars), A4 (whether
ownership-at-the-time counts as authoritative attribution), A5 (visible conditions without effects), and the
Q18/Q19 profile representation you asked to see first.**
