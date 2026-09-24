# Wear, tear, component lifecycle and odometer-driven mechanical aging

**Status: SPECIFICATION CAPTURED 2026-09-23. Nothing built, nothing authorised.** Spec 3 of the owner's
batch, and the one that explains why the parts architecture exists at all.

**A proposal is owed** (twelve questions, listed at the end) — recorded as `IDEA-288`.

> Driving gives the odometer economic meaning.
> The odometer gives components history.
> Component history creates wear.
> Wear creates mechanical problems.
> Mechanical problems create demand for parts and engineers.
> Parts and engineers feed the economy back into driving.
> **That closes the loop.**

---

## What this is not

Not crash damage. Not insurance. Not a sporting-incident system. Those may exist separately.

**Wear is the ordinary mechanical consequence of using a machine over time and distance.** The authoritative
vehicle odometer is the starting clock.

## Wear belongs to the component, not the vehicle

There is no `vehicleHealth = 63%`. A vehicle is an assembly of persistent physical component assets, and
where a family or design has a meaningful lifecycle, its condition belongs to **that physical component**.

Removing it preserves that state. Selling it preserves it. Installing it elsewhere preserves it. Repairing it
changes condition without erasing history.

The owner's own example, which is the clearest statement of why serialised component identity matters:

```
vehicle at 8,000 km
  original gearbox        ~8,000 km of relevant exposure
  original cooling pump   removed at 3,200 km -> permanently retains ~3,200 km
  replacement pump        installed then      -> has accumulated ~4,800 km
```

> If that replacement is later removed, sold and installed in another compatible vehicle,
> **it does not become new again.** Its physical lifecycle follows the component asset.

The odometer stays authoritative *vehicle* history; component exposure is *component-local* history related
to vehicle use.

## Distance is the primary exposure source — and nothing else is

Ordinary wear derives from authoritative legitimate distance travelled. **Explicitly not** from collisions,
sporting incidents, penalties, reckless-looking driving, contact attribution, or any judgment about whether
someone is "abusing" their car.

> NCM must never be adjudicating whether a driver deserves persistent property damage because of how they
> drove.

Sporting incidents produce sporting consequences. Wear produces mechanical lifecycle consequences. **Keep
them orthogonal** — which also keeps multiplayer contact from becoming insurance litigation or a griefing
vector over permanent property damage.

## Not every component wears the same way

Not `wear += kilometres` for everything. A gearbox, a tire set, an electronic controller, a chassis assembly
and an aero component do not deserve identical lifecycle semantics.

The architecture supports **relevant exposure dimensions per design/family**, with distance as the
first-generation clock. Some components care strongly about distance; some may eventually care about elapsed
operational time or another measurable authoritative exposure; **some may have no meaningful wear lifecycle at
all**. Detailed rules deferred — the requirement is only that meaningless mileage wear is never forced onto
an object merely because it is technically a component.

**Fast-wear categories matter economically.** Some categories (tires being the obvious one) should cycle
substantially faster than major assemblies — otherwise a realistic automotive lifecycle takes hundreds or
thousands of gameplay hours before the parts economy feels any demand. **Do not solve that by making every
engine die absurdly quickly**; different families simply have different lifecycle scales.

## Deterministic individuality, without per-kilometre dice

Two things are both rejected:

- `every gearbox fails at exactly 10,000 km` — that makes mileage a disguised countdown.
- uncontrolled runtime RNG where identical state resolves differently after a restart.

Individual components should have different lifecycle trajectories, produced by **authoritative seeded state
or deterministic generation**, reproducible and auditable.

> A player must not be able to reroll component durability by reconnecting, reinstalling the component,
> restarting the server, transferring ownership, or repeatedly invoking an operation.

**Do not roll every kilometre.** Treating every odometer increment as a fresh failure roll creates enormous
numbers of opportunities, encourages probability weirdness and complicates replay/restart behaviour. Prefer:
a component carries a **seeded lifecycle profile** established at manufacture (or another legitimate
lifecycle boundary), and the system evaluates accumulated exposure against that stable profile.

Wanted: **persistent individuality + deterministic progression + bounded variation + no reroll exploits.**

### Pressure, not milestones — and bounded in both directions

Not `3,000 km: -2% / 5,000 km: -5% / 10,000 km: dead`. **The universal terminal-mileage model was
deliberately abandoned** (and is already struck from NCM's record — L119 amended).

Accumulated exposure progressively affects lifecycle state according to that component's deterministic
characteristics, so two equivalent components can begin showing problems at different points — a biography
rather than a published death schedule.

But variability is bounded **both ways**: a newly manufactured component must not spontaneously become
catastrophically ruined on an unlucky roll, and an extremely worn one must not stay magically pristine
because it once rolled well. Think **increasing deterministic pressure over accumulated exposure**, not
independent casino rolls.

## Wear is monotonic pressure, never a benefit

Ordinary wear must never improve a component. Engineering workmanship may eventually produce positive
characteristics; **wear itself is neutral-to-negative, always.**

> We must never create a reason for players to deliberately grind mileage because
> *"worn gearbox rolled +3% acceleration."*

## Wear should first create a problem to solve

The first consequence should not be `YOUR PART IS DESTROYED`. Wear creates **mechanical conditions**, and
those conditions should correspond to vehicle behaviour NCM can truthfully produce through available
OPEN//77 / Cyberpunk primitives.

> **If NCM says something is mechanically wrong with the car, the driver should experience something
> mechanically wrong with the car.** Avoid fake text-only simulation wherever possible.

The condition catalogue and any percentages wait on the mechanical-effect audit (IDEA-249).

### The lifecycle loop

```
use -> exposure -> wear -> condition/symptom -> diagnosis -> maintenance/repair OR replacement
```

A condition may exist **before the owner understands it**. Diagnostics determines what an engineer can learn.
Repair interacts with the persistent component and may use the engineering workmanship roll (IDEA-271).
Replacement removes the worn component and installs another physical asset — **and the removed component
still exists** unless an explicit process consumes it. It may be repaired, stored, traded, sold,
reverse-engineered or reinstalled.

### Repair does not erase history

```
Component #004821, 18,000 km, three previous services
                 must never become
Component #004821, NEW, 0 km
```

Service changes condition. Exposure, installation history, service history and ownership history all remain.
**That is what lets old components become mechanically meaningful historical objects rather than disposable
database rows.**

### Terminal failure is rare and downstream

Components may eventually become irreparable, but that is not the primary mechanic — maintenance and repair
need room to matter.

> The objective is **wear creates engineering demand**, not **wear periodically deletes people's property**.

**Broken does not mean nonexistent.** A broken vehicle or component remains persistent property unless an
explicit system consumes it.

## Seven layers, now

The engineering addendum named four; this spec extends them. A component may simultaneously have:

1. underlying **design characteristics**
2. **manufacturing / fabrication realization**
3. accumulated **exposure**
4. current **wear / condition**
5. **installation workmanship**
6. **repair / service workmanship**
7. persistent **provenance / history**

> A beautifully manufactured component can wear. A worn component can receive an excellent repair. An
> excellent component can be installed poorly. A mediocre component can be installed exceptionally well.
>
> **Do not flatten this into one quality or health number.**

## Odometer integrity becomes security-sensitive

Because distance becomes economically meaningful, mileage becomes an attack surface. Players must not be able
to create or avoid wear through teleportation, stationary physics jitter, reconnect behaviour, vehicle
spawning/despawning, installation toggling or other measurement artifacts.

> The spec names it directly: *"The existing odometer work has already exposed at least one issue where
> stationary vehicle jitter could accumulate false mileage."* — that is **KB-88**, found and fixed on
> 2026-09-23 by adding speed as an independent witness.
>
> **Before wear has economic consequences, the distance source must be verified robust for this role.**
> That promotes the owed odometer QA (§AG5 / §AG6) from nice-to-have to **prerequisite**.

And: **do not retroactively rewrite legitimate existing vehicle history to make the lifecycle system neat.**
(Already honoured — MaiMai #0000001 keeps its 11,903 m exactly as recorded.)

## Persistence and restart safety

Lifecycle state must survive server restart, disconnect, component removal, installation, ownership transfer,
and market listing/storage.

> **Applying the same authoritative distance or event twice must not double-apply wear.** Updates are
> idempotent / replay-safe, and component duplication must neither duplicate nor reset lifecycle state.

## Player-facing information stays undecided

No assumption that players see `Wear = 72.431% / Failure threshold = 81.392% / Remaining life = 842.6 km`.
NCM may expose only observable symptoms, inspection results, service history and progressively better
diagnostic information.

**A skilled engineer may understand substantially more about a component than an untrained owner.** The
authoritative server can know more than the UI reveals — keep simulation state separate from presentation.

## The economic metabolism

```
manufacturing -> distribution -> acquisition -> installation -> use -> wear
   -> diagnosis -> repair/replacement -> secondary circulation or consumption
```

Without lifecycle pressure, component supply mostly accumulates. With it, physical parts have reasons to move
through the world.

---

## What the spec asks back

A proposal covering: how vehicle distance feeds installed-component exposure; what component-local lifecycle
state must exist; deterministic seeded individuality without per-kilometre rolls; how removal/reinstallation
preserves exposure and condition; how lifecycle state supports future symptoms without inventing unsupported
effects today; how repair modifies condition without erasing history; how the model distinguishes wear,
condition, manufacturing quality and workmanship; how updates stay deterministic, persistent and idempotent;
how odometer integrity is validated first; what belongs in pure core vs host; how it connects to components,
engineering, markets, trading and provenance; and the smallest first slice.

**No mileage thresholds, no failure probabilities, no unsupported effects, no crash damage, no sporting
linkage, no insurance, no uniform wear, no single health percentage, no history resets, no beneficial wear,
no terminal-first consequences, no uncontrolled randomness.**

> And do not let this become a realism simulator that punishes people merely for enjoying their cars.
