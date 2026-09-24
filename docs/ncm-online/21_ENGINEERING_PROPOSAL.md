# Engineering — proposal

**This is the answer to `IDEA-269`.** The spec is captured in `19_ENGINEERING.md`; this is what I propose in
response. Nothing here is built. No tuning values, no mechanical effects, no skill tree until the ontology is
agreed.

Written for the owner as a decision document: each section states a recommendation and the reasoning, and
flags where I am guessing.

---

## 1. The five disciplines — accepted, with one structural finding

I accept the five. Diagnostics/Inspection, Maintenance/Repair, Installation/Integration,
Fabrication/Crafting, Design/Manufacturing are coherent, they map to distinct player intentions, and nothing
in the repo argues against them.

**But the time regime does not follow discipline lines, and that matters more than the ontology.**

The spec asks for repair to stay fast while research and production take real time. Splitting on *discipline*
almost works — and then breaks on Diagnostics, which contains both the fastest operation in the system
(glancing at a component) and one of the slowest (destructive reverse engineering).

> **Recommendation: the OPERATION carries the time regime, not the discipline.**

| Regime | Operations | Character |
|---|---|---|
| **Bench** | inspect, characterise, fit, configure, validate, service, fault-correct, restore | synchronous, seconds, social, resolves immediately |
| **Project** | reverse-engineer, fabricate, design, tool, produce | asynchronous, committed, survives logout |

Every operation declares its regime in the catalogue. This is a one-word field, it prevents the "one generic
project table quietly swallows repair" failure the spec warns about, and it keeps Diagnostics whole instead
of splitting it to satisfy plumbing.

## 2. Skill families — 3 per discipline, 15 total

The organising intuition I propose: **a workmanship discipline's three skills are the floor, the spread and
the ceiling of its outcome distribution.** Where it fits, it makes the roll system fall out of the ontology
rather than being bolted on.

> **Diagnostics is deliberately NOT shaped this way** (owner, 2026-09-23: *"we should not force Diagnostics
> into workmanship semantics merely to preserve symmetry"*). It produces information, not workmanship, so its
> three skills are information axes — **breadth, precision, depth** — and the symmetry is allowed to break.
> Forcing a ceiling/floor/spread reading onto "what can you learn from looking at this" would be exactly the
> architectural neatness the spec warns against.

| Discipline | Skill | What it governs |
|---|---|---|
| **Diagnostics** *(information axes)* | Inspection | **breadth** — how many facts you can surface at all |
| | Characterisation | **precision** — how exact, and how confident |
| | Reverse Engineering | **depth** — how far beneath the surface, destructively |
| **Repair** | Servicing | routine restoration; baseline relief *(floor)* |
| | Fault Correction | resolving a specific identified condition; peak relief *(ceiling)* |
| | Restoration | working on badly degraded stock without making it worse *(spread)* |
| **Installation** | Fitment | did it go in correctly at all *(floor)* |
| | Setup | how much legitimate benefit is extracted *(ceiling)* |
| | Validation | catching a poor result before committing *(spread)* |
| **Fabrication** | Forming | producing a usable part at all *(floor)* |
| | Process Control | tightness of tolerance; consistency *(spread)* |
| | Finishing | peak attainable quality of one instance *(ceiling)* |
| **Design / Manufacturing** | Specification | design work; the potential embodied *(ceiling of the design)* |
| | Tooling | preparing for repeatability *(spread)* |
| | Production | running batches; sustained throughput *(floor at scale)* |

Fifteen names a player can hold in their head. No `CARBURETOR FLOAT ADJUSTMENT`.

**Discipline level is derived from its three skills and never stored.** It exists for presentation and for
coarse gating, nothing else.

## 3. Mechanical-family specialisation — a second, coarser track

Twelve families from the component ontology, one value each. **Not 5 × 12.** Family experience is orthogonal:
it modifies any discipline's work *in that family*.

So an engineer's competency is **15 skills + 12 families = 27 numbers**, and the interesting statement
*"highly developed in Diagnostics → Reverse Engineering → Power Unit"* is the composition of two of them
rather than a stored cell.

That composition is the answer to "how do broad specialisation and skills compose": **they are separate
inputs to the same resolution, never a matrix.** A matrix would be 180 cells, brittle, and would make every
new family a schema change.

## 4. Competency vs knowledge — different cardinality, therefore different storage

This is the cleanest structural distinction in the whole system, and it is a storage argument:

| | Competency | Knowledge |
|---|---|---|
| Question | what can I **do** | what do I **know about this design** |
| Cardinality | **bounded** — 27 per engineer, forever | **grows** — one row per driver × design |
| Changes via | completed work | exposure, inspection, analysis |
| Ceiling | yes | no (it is a ladder, not a level) |

They must be separate tables because one is bounded and one is not. Conflating them is how you end up with
`Makigai KX-17 Pump Skill`.

**Knowledge extends the existing `competition.machine_knowledge`**, which already separates source, epistemic
status, model identity and asset identity — deliberately, so an adapter cannot collapse them. The engineering
ladder (exists → specification → inspected → familiar → analysed → deeply understood → can fabricate → can
produce reliably) is that module's idea carried further, not a new invention.

**Gating rule: capability requires BOTH.** Fabricating a design needs the knowledge rung *and* the skill
level. Neither alone. That is what stops money buying mastery and stops a master fabricating something they
have never seen.

## 5. State model

Follow `driver.progression` exactly — it is already the right shape and it is proven.

**Core (pure):** `engineering.competency` with `newState()` / `apply(state, operation, ctx)` returning state
plus deltas, mirroring `driver.progression.apply`. No database, no clock, no randomness.

**Host (persistence):** two narrow tables, same shape as `driver_sr`:

```
engineer_skill  (ncm_driver_id, server_id, skill_id,  value, completed_count, updated_at)
engineer_family (ncm_driver_id, server_id, family_id, value, completed_count, updated_at)
```

At most 27 rows per engineer, ever. That is the answer to "without creating a giant brittle schema": the
schema does not grow with content — new designs, new components and new markets add **zero** columns.

## 6. Practice semantics

**Credit accrues on completion of legitimate work**, never on initiation.

```
gain = base(operation) × relevance(skill, family) × headroom(skill) × difficulty(work, skill)
```

- **headroom** — `(1 − value/ceiling)^k`. Asymptotic approach; the ceiling is never reached by grinding.
- **difficulty** — work far below current skill yields near-zero. This is the anti-grind mechanism and it is
  a curve, not a rule: repeating trivial operations stops paying without anyone being told off.
- **relevance** — an operation credits its own skill fully, its discipline's siblings marginally or not at
  all, and its mechanical family.
- **outcome does not gate credit.** A poor result still completed the work. This is the spec's most important
  invariant and it is satisfied by simply not passing the outcome into `gain`.

**Legitimacy** = committed resources (where the operation consumes them) + reaching completion. Cancelling a
project forfeits credit. Zero-cost repeatable operations get `base = 0`.

## 7. Ceilings

Every skill and family is `0 … CEILING` on one internal scale, never shown raw. Reached asymptotically, so
there is a real summit that a later starter can also stand on.

I am deliberately not proposing the number, the exponent `k`, or the base rates. Those are balance and they
need play data.

## 8. Projects

One table, and I propose reusing the pattern that already survived a live restart test —
`market_production_run`'s claim-then-verify-nonce:

```
engineering_project (
  project_id, server_id, ncm_driver_id, kind, state,
  committed_json,      -- inputs, frozen at start
  competency_json,     -- competency SNAPSHOT at start
  seed,                -- committed at start
  started_at, ready_at, resolved_at,
  result_json, claim_nonce
)
```

Three deliberate choices:

1. **Competency is snapshotted at start.** Finishing other work while a project runs does not change its
   result. Removes a whole class of ordering exploits and makes the outcome explainable months later.
2. **The seed is committed at start; the outcome is computed at resolution.** Same seed + same snapshot +
   same inputs = same result, whenever it is resolved. Nothing is stored that could be read early.
3. **Resolution claims the project by nonce**, exactly as a production tick claims its index — so a retry, a
   double-resolve or a restart mid-resolution cannot pay out twice.

**Capacity:** a `concurrentProjects` limit, initially a constant, later derived from tooling. It exists from
day one even as a constant, because retrofitting a limit onto a system players have learned to parallelise is
a nerf; having it from the start is just how the world works.

## 9. Destructive reverse engineering

**Commit (one transaction):**

```
component asset  → lifecycle 'consumed'
                 → transfer row kind = 'destructive_analysis'   (provenance preserved, never DELETE)
engineering_project created, committed_json names that assetId
```

The transfer row's idem key is the asset id, so an asset can be consumed exactly once — the same mechanism
that makes purchase idempotent today.

**Resolve:** knowledge rungs granted per the seeded outcome, gated by design sophistication and the analyst's
Reverse Engineering skill and family experience.

> This is **NCM's first true item sink.** Every existing flow conserves: production creates, purchase
> transfers, vehicle reclaim removes a *runtime* car but never the asset. Consuming a serialised asset is new
> and must stay provenance-preserving, consistent with L119's "terminal does not mean deleted".

## 10. Fabrication outcome

**A vector, never a scalar.** `outcome_json` on the produced component asset, with named dimensions drawn
from a validated vocabulary that is **empty today** and populated only after the effect audit (`IDEA-249`).

Until then fabrication still resolves and still produces individuality — it just records an empty vector, and
the *architecture* is exercised. That is deliberate: it lets everything else ship and be tested before any
effect exists.

**Correlated, not independent.** When dimensions exist, one roll should drive them through correlation rather
than N independent casino rolls — a well-made part is well made, not lucky in four places.

**Never retroactively improved.** Nothing recomputes an existing asset's outcome when its maker improves.
Enforced by simply never writing to it again.

## 11. Seeded uncertainty and anti-reroll

The repo already enforces the right philosophy: `ids.uuid4(rng)` refuses without an injected function and
core modules never touch ambient randomness. Extend it.

```
seed = hash(serverId, projectId, driverId, committedInputs, startedAt)
```

Derived from immutable committed facts, **never from the clock at resolution**. Therefore: reconnecting,
restarting, cancelling and re-starting (which creates a new projectId, and forfeits the resources),
transferring ownership, or resolving twice all produce either the same answer or no answer.

Bench operations have no project row, so their seed derives from `(serverId, driverId, targetAssetId,
operationId, monotonic counter persisted per target)` — the counter is what stops repeating an instant
operation on the same target until it rolls well.

## 12. Time and capacity

- **Bench:** resolves immediately. Friction comes from resources and cooldowns, not wall-clock.
- **Project:** `ready_at = started_at + duration(operation, design sophistication, competency, tooling)`.

Durations undecided. The only structural commitment is that competency and tooling **reduce** duration, so
progression buys throughput as well as quality — which is the economic reason a master is worth seeking out.

## 13. Player-manufacturing provenance

Reuse `NcmProvenance` with **separate sequence scopes** for components. A player-made part gets:

- a component ordinal in its design's sequence (so it is the 47th KX-17 ever made, by anyone)
- `made_by = ncm_driver_id` and `made_at`
- its fabrication outcome vector

That `made_by` is the seed of the attributed operation history (`IDEA-276`) and the mechanism behind *"their
name appears in provenance"*. It must exist from the first fabricated part — attribution cannot be
reconstructed later.

> Same lesson as `IDEA-236`: results not attributed at the time are results that biography will never
> contain.

## 13b. What a repair operation must emit (the reconciliation)

The owner identified that a binary "serviced" flag cannot distinguish a botched repair from a master's, and
that this is where the engineering and wear proposals meet. It is.

**A repair resolves like any other bench workmanship operation, and its outcome is one number with physical
meaning:**

```
relief_m = h( repair workmanship roll,
              Servicing / Fault Correction / Restoration,
              mechanical family experience,
              severity at the time of work,
              relief already granted to this condition )
```

- The **roll** is the usual seeded bench resolution, so the range can be shown before committing and the
  result shown landing inside it.
- **Severity at the time of work** means repairing something badly degraded is harder — which is what
  Restoration is for.
- **Prior relief** is the diminishing-returns term, so paying a master repeatedly cannot hold a component in
  permanent adolescence.
- The value is persisted on the service record and **never recomputed**, exactly like a fabrication outcome.
  A repair is a historical fact about a piece of work, not a live projection.

This is also what makes an engineer's reputation mechanically real rather than decorative: two engineers
service the same gearbox, and the difference is visible in how long it stays fixed.

## 14. Seams

| Seam | Contract |
|---|---|
| **Components** | engineering never mints or destroys outside the declared operations; installation moves, removal moves, analysis consumes |
| **Markets** | player output enters circulation through the same conservation rules as system supply; market access stays governed by discovery (`IDEA-251`) and is **not** granted by owning a part (`IDEA-257`) |
| **Trading** | fabricated parts are ordinary tradable assets; the barter envelope (`IDEA-247`) must treat them identically to purchased ones |
| **Provenance** | `made_by` / attributed operations extend `vehicle_asset_transfer`'s pattern rather than a parallel log |
| **Wear** | **the one place the two systems touch mathematically.** A repair operation emits a single
  `relief_m` — how much further out it pushed that condition's threshold — and that is the *only* value
  engineering hands the wear derivation. Workmanship never cancels exposure; it moves a threshold. See
  `22_WEAR_PROPOSAL.md` §6. |

## 15. Visible vs hidden

Per the amended stance (spec 2 addendum):

**Shown:** disciplines, areas of expertise, demonstrated competencies, current capabilities, known designs,
active projects and completion times, **the legitimate outcome range before committing**, and the resolved
result landing inside it.

**Hidden:** the formula, internal modifiers, distributions, thresholds, exact skill values, deeper
requirements.

The range is honest to show because it is a fact about *this opportunity*; the distribution inside it is not,
because publishing it turns progression into arithmetic.

## 16. The smallest first slice

> **Diagnostics — inspection of existing vehicle assets. Nothing else.**

Why this and not fabrication (which is the obvious first instinct):

- **It needs no components to exist.** There are 19 persistent vehicle assets in the live world right now,
  each with ordinals, paint, an odometer and provenance. That is enough to inspect.
- **It is not blocked on the effect audit**, because its output is information, not vehicle behaviour.
- **It exercises the entire substrate anyway**: competency state, the reducer, practice credit, headroom,
  ceilings, the seeded roll, the knowledge ladder, bench-regime timing, and visible-vs-hidden.
- **It is socially useful immediately** — one player can inspect another's car and tell them something true.

The slice is: two skills (Inspection, Characterisation), the twelve families, one bench operation, the
competency reducer, the two tables, and the knowledge ladder's lower rungs.

Explicitly **not** in it: projects, reverse engineering, fabrication, repair, installation, any component
asset, any mechanical effect, any market seam.

Everything after that is additive, and each later discipline plugs into a substrate that has already been
proven by play.

---

## Where I am guessing, and what would change my mind

- **Floor/spread/ceiling** fits Fabrication and Installation cleanly, Repair adequately, Diagnostics not at
  all. If it feels forced in play, keep the fifteen skills and drop the intuition — it is scaffolding for
  designing the roll, not a rule the system depends on.
- **Snapshotting competency at project start** is the right call for explainability, but it means a long
  project cannot benefit from a breakthrough mid-flight. If that feels bad, the alternative is snapshotting
  at resolution — which reintroduces ordering games. I would keep the snapshot.
- **27 numbers** is my judgement of "enough resolution without spreadsheet disease". If two engineers do not
  feel different enough in play, the lever is more *families* or more *knowledge*, not more skills.
- **Diagnostics-first** assumes inspecting cars is interesting enough to carry a release. If it is not, the
  fallback is Installation — but that needs components, which needs the whole parts substrate first.
