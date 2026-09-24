# Wear, lifecycle and odometer-driven aging — proposal

**This is the answer to `IDEA-288`.** The spec is captured in `20_WEAR_LIFECYCLE.md`; this is what I propose
in response. Nothing here is built. No mileage thresholds, no failure probabilities, no effects.

The central claim of this proposal, stated first because everything else follows from it:

> **Wear should be a pure function, not a process.**
>
> ```
> effectiveThreshold(c) = baseThreshold(profile, seed, c) + Σ relief(services on c)
> active(c)             ⟺ exposure ≥ effectiveThreshold(c)
> severity(c)           = g(exposure − effectiveThreshold(c))
> ```
>
> Nothing rolls. Nothing accumulates but exposure. Nothing is remembered that could drift — and the only
> value engineering contributes is `relief_m`, which moves a threshold and never cancels exposure.

---

## 1. Distance → exposure

The odometer already does the hard part. `ncm_world/server/odometer.lua` samples the vehicle at 1 Hz,
filters discontinuities through a pure function, accumulates in memory and **checkpoints additively**:

```sql
UPDATE vehicle_asset SET odometer_m = odometer_m + ?, odometer_at = ? WHERE asset_id = ?
```

**Proposal: the same checkpoint writes exposure to the components installed in that vehicle, in the same
transaction.**

```
BEGIN
  vehicle_asset      odometer_m  += d
  component_asset    exposure_m  += d   -- for every component installed in that vehicle
COMMIT
```

Why the same transaction and not a later fan-out: the vehicle's odometer and its components' exposure are the
same fact recorded twice. Split them and a crash between the two creates a vehicle whose parts have not
travelled as far as it has — a discrepancy nobody could later reconcile, because the delta is gone.

This also makes idempotency free. There is no "apply this distance event" to replay; there is one additive
write that either committed or did not.

**Exposure is per-component and additive only.** It is never reduced, never reset, and never recomputed from
the vehicle — because a component that spent 3,200 km in one car and 4,800 km in another has 8,000 km of its
own, and no vehicle knows that.

## 2. Component-local lifecycle state

Four fields, and deliberately no condition column:

```
component_asset:
  exposure_m       BIGINT   -- monotonic, additive only
  lifecycle_seed   CHAR(36) -- fixed at manufacture
  installed_in     CHAR(36) -- vehicle asset, or NULL
  installed_at     BIGINT
```

Plus a service log (section 6). **Condition is never stored** — see below.

## 3. Deterministic individuality without per-kilometre rolls

This is the question the spec cares most about, and I think the answer is stronger than "roll less often".

**Do not roll at all.**

At manufacture a component receives a `lifecycle_seed`. Its design carries an authored **wear profile**: which
conditions this family can develop, and roughly where. From those two, a pure core function derives the
component's **threshold points** — the exposures at which each condition appears:

```lua
-- pure, in ncm-core
conditionsFor(profile, seed, exposureM) -> { conditionId, sinceExposureM }
```

Properties that fall out for free:

| Requirement | How it is satisfied |
|---|---|
| individual variation | the seed shifts thresholds within the profile's authored bounds |
| deterministic | same inputs, same answer, forever |
| auditable | reproducible from two stored values and authored data |
| no reroll by reconnect/restart/transfer/reinstall | nothing is rolled, so there is nothing to reroll |
| no per-kilometre opportunities | evaluated on read, not on movement |
| idempotent | it is a function; calling it twice changes nothing |
| bounded both ways | the profile's bounds cap how early *and* how late a threshold can fall |
| monotonic | thresholds are fixed; exposure only rises, so conditions only accumulate |

The last two answer the spec's two failure modes directly: a new component cannot be catastrophically ruined
by an unlucky roll (there is no roll, and bounds are authored), and a very worn one cannot stay pristine
(exposure passes every threshold eventually).

**Derive the seed from the assetId.** It is already unique, already immutable, already deterministic — the
same trick `data.vehicle_config.paintFor` uses to give every car a stable colour. One less column, and
provably stable.

## 4. Removal and reinstallation

**Nothing to implement.** Exposure lives on the component and conditions are derived from it, so removing,
selling, storing and refitting preserve everything by construction. Installation sets `installed_in`; removal
clears it. Neither touches exposure.

The spec's worked example works without a single special case:

```
pump removed at 3,200 km  -> exposure_m stays 3,200,000
refitted to another car   -> continues accruing from 3,200,000
```

## 5. Future symptoms without inventing effects

`conditionsFor` returns **condition ids from an authored catalogue**. Today that catalogue is empty and the
wear profiles are inert, so the function returns nothing for everything.

That is the point: the whole mechanism can ship, be tested, accrue real exposure and be proven deterministic
**before a single effect exists**. When the effect audit (`IDEA-249`) establishes what the platform can
truthfully produce, conditions get effects and the system starts speaking without any schema change.

> The spec's rule holds: *if NCM says something is mechanically wrong, the driver should experience something
> mechanically wrong.* An empty catalogue says nothing, which is honest. A catalogue of text-only symptoms
> would be the lie.

## 6. Repair modifies condition without erasing history

Condition is not a column, so repair cannot overwrite it. Instead:

```
component_service (service_id, component_asset_id, at_exposure_m, condition_id,
                   by_driver_id, workmanship_json, relief_m, idem_key)
```

### Repair advances thresholds; it does not clear conditions

> **Superseded first draft.** This section originally read
> `active = conditionsFor(...) minus conditions serviced later` — a set subtraction. The owner rejected that
> on 2026-09-23, correctly: binary subtraction means a botched repair and a master's repair clear a condition
> **identically**, which flatly contradicts the engineering addendum's "a weak repair may restore
> functionality while leaving some disadvantage". This is the point where the two proposals have to meet
> mathematically, so the derivation is now graded.

**A repair does not delete a condition. It pushes that condition's threshold further out, by an amount its
workmanship earned.**

```lua
effectiveThreshold(c) = baseThreshold(profile, seed, c) + Σ relief(service_i)
overshoot(c)          = exposure − effectiveThreshold(c)
active(c)             ⟺ overshoot(c) ≥ 0
severity(c)           = g(overshoot(c))        -- bounded, monotonic, 0 at the threshold
```

Four lines, still a pure function of stored facts and authored data. Everything the original model gave us
survives — determinism, idempotence, restart-safety, no rolls — and the thing it could not express now falls
out for free:

| Repair quality | Relief | Result |
|---|---|---|
| botched | ~0 | condition stays, severity unchanged. Work happened; nothing was fixed. |
| weak | < overshoot | **condition persists at reduced severity** — "restored functionality, left some disadvantage" |
| competent | ≈ overshoot | severity returns to 0; it is due again soon |
| excellent | > overshoot | clears it, and buys real distance before it is due again |

**Exposure is still never reduced.** We move the threshold, not the odometer. The component still has
18,000 km on it; its gearbox condition is simply not due again until 23,000. That is exactly "repair does not
erase history", expressed arithmetically rather than as a rule someone has to remember.

**Relief must have diminishing returns**, or a wealthy owner pays a master repeatedly and the part never ages
— which would break "wear is monotonic pressure". Two candidate bounds, to be chosen with play data:

- each subsequent service on the *same condition* grants proportionally less; and/or
- cumulative relief on one condition is capped as a fraction of its base threshold interval.

I would author both and set one to infinity until we see behaviour.

Consequences, all of them wanted:

- **Exposure is never reduced.** A serviced component is still an 18,000 km component.
- **A serviced condition recurs** once exposure passes its advanced threshold — "pressure, not a milestone".
- **History is append-only.** `18,000 km, three previous services` is what the table says, and nothing can
  turn it into `NEW, 0 km`.
- **Repair workmanship is attributed** (`by_driver_id`) and recorded as its own layer, feeding `IDEA-276`.
- **Severity is derived too.** It is never stored, so no repair can write a number that later drifts from the
  exposure that justifies it.

## 7. Keeping the seven layers apart

The storage answer to "do not flatten this into one number" is that they are in different places and no query
ever sums them:

| Layer | Lives on | Mutable? |
|---|---|---|
| design characteristics | the design | no |
| manufacturing realization | `component_asset.outcome_json` | written once, never again |
| exposure | `component_asset.exposure_m` | additive only |
| condition | **nowhere — derived** | n/a |
| severity | **nowhere — derived** | n/a |
| installation workmanship | the installation record | per installation |
| repair workmanship | `component_service.workmanship_json` + `relief_m` | per service, append-only |
| provenance / history | transfer + service + operation rows | append-only |

There is no `health` column anywhere, and no vehicle-level aggregate. If someone later wants a summary
number for a UI, it is computed for display and never stored — otherwise it becomes the thing people reason
about and the layers collapse.

## 8. Determinism, persistence, idempotence

- **The only mutation is exposure**, and it is additive inside the odometer's existing transaction.
- **Conditions are derived**, so restart-safety is automatic: there is no lifecycle state to reload.
- **Services are idempotent** by `idem_key`, like every other transactional write in NCM.
- **Duplication cannot reset lifecycle** because a duplicated asset would need a duplicate assetId, which the
  primary key forbids — and the seed derives from the assetId, so even a hypothetical copy would carry the
  same trajectory rather than a fresh one.

## 9. Odometer integrity — the gate before any of this matters

The spec names our own finding, so I will be concrete about what "sufficiently robust" should mean.

**Already closed:** stationary jitter (KB-88 — speed is now an independent witness; under 0.2 m/s the delta
is rejected, above it a delta beyond what the speed allows is capped). Teleport, CALL materialisation,
restart and streaming jumps (all one discontinuity filter). Asset changes between samples. Unoccupied
vehicles.

**Not yet proven, and blocking:**

| Check | Status |
|---|---|
| §AG5 — drive, then confirm the odometer survives re-CALL, restart and transfer | **NOT RUN** |
| §AG6 — CALL far away, confirm no fake kilometres and the filter logs it | **NOT RUN** |
| A soak: hours of ordinary play with `ncm.odo.trace`, comparing accepted vs rejected totals | not designed |
| Installation toggling — can fitting/removing a part in a moving car double-count? | **not possible to test until components exist**, and must be designed against now |

> **Recommendation: exposure accrual may ship before conditions, but conditions must not ship before §AG5,
> §AG6 and a soak have passed.** Distance is about to become economic data; a measurement artifact would then
> be an exploit rather than a cosmetic error.

And the existing rule stands: **do not rewrite legitimate history to make this neat.** MaiMai #0000001 keeps
its 11,903 m, including whatever early jitter is inside it.

## 10. Core vs host

| | Core (`ncm/core`) | Host |
|---|---|---|
| wear profiles per family/design | ✅ authored data | |
| `conditionsFor(profile, seed, exposure)` | ✅ pure | |
| service subtraction / active-set rule | ✅ pure | |
| exposure arithmetic and bounds | ✅ pure | |
| writing exposure in the odometer transaction | | ✅ |
| service records, install/remove state | | ✅ |
| resolving which components are installed | | ✅ |

This is the same split the repo already enforces: rules, reducers and catalogues are core bricks; database
persistence and orchestration are host. `conditionsFor` being pure is what makes the whole design testable
offline against invented histories.

## 11. Seams

- **Components** (`IDEA-241`): exposure and seed are fields on the component asset; nothing else changes.
- **Engineering** (`21_ENGINEERING_PROPOSAL.md`): conditions are what Diagnostics reads and Repair addresses.
  Wear creates the demand; engineering is the supply. **This is where the two proposals touch
  mathematically** — a repair operation emits a `relief_m`, and that value is the only thing engineering
  hands the wear derivation. Wear and workmanship are still never *summed*: workmanship moves a threshold,
  it does not cancel exposure.
- **Markets** (`IDEA-254`): used parts carry exposure and service history into listings, which is what makes a
  secondary market meaningful rather than a price list.
- **Trading** (`IDEA-247`): exposure travels with the asset through barter, untouched.
- **Provenance** (`IDEA-276`): service records are attributed operations and belong in the same biography.

## 12. The smallest first slice

> **Exposure accrual, with no conditions at all — shipped in the same release as component assets, not after
> it.**

The argument is the one that has already bitten us twice today:

- Race results were never attributed to a machine, so no car can answer *"how many starts have I had"*
  (`IDEA-236`).
- Component exposure is worse, because there is no ledger to reconstruct it from at all. **A kilometre you
  did not record is a kilometre that never happened.**

So the slice is: `exposure_m` on the component asset, written inside the odometer's existing transaction, and
nothing else. No profiles, no conditions, no repair, no symptoms, no effects. It is a handful of lines and it
cannot be added retroactively.

Conditions then arrive on their own schedule, once the effect audit and the odometer gate have both passed —
and when they do, every component in the world already has an honest history to derive them from.

---

## Where I am guessing, and what would change my mind

- **"Wear as a pure function" is the strong claim here.** I believe it, because it makes determinism,
  idempotence and restart-safety structural rather than disciplined. The cost is that a condition cannot
  depend on *history* that is not captured in exposure — e.g. "this part was once installed badly" could not
  influence wear unless installation workmanship becomes an input to the function. That is solvable (add it
  as an input) but it should be decided deliberately rather than discovered.
- **Deriving the seed from the assetId** is elegant and saves a column, but it means a component's trajectory
  is fixed at manufacture and cannot be re-rolled even deliberately (e.g. a future "remanufactured" state).
  If that is wanted, the seed needs to be a real column that a remanufacture may change — and that decision
  is cheaper now than later.
- **Exposure as a single scalar** is the first-generation clock the spec asks for. Families that eventually
  need operational time or another dimension would want `exposure_json` instead. I would start scalar and
  migrate if a real second dimension appears, rather than build a general vector for a need that may not
  arrive.
- **One transaction for vehicle + components** assumes the installed-component set is small and cheap to
  query at checkpoint time. If a car ever has dozens of tracked components and checkpoints get expensive, the
  fallback is to write a single exposure row per checkpoint and fan out asynchronously — which reintroduces
  the reconciliation problem I opened by arguing against. I would keep it in one transaction until it
  measurably hurts.
