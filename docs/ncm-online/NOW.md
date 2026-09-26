# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-26 - Two independent threads. (1) Foundry architecture review 38 is complete and
awaiting owner ruling; `L153` locks the existing-geometry scope and abandons the AI/generative branch; no
Foundry implementation began. (2) `L152` built the path from a fitted part to a live force, and `L154` then
widened it from three families to eleven by allowing approximation. Carrier 0.1.20 on Production awaiting
§AY.**

> **Claim before writing:** decisions through **L153**; MASTER_TEST through **§AY**; next QA letter **§AZ**.
> BACKLOG next free **IDEA-527**; known issues through **KB-145** plus pre-existing duplicate labels noted by
> `KB-114`. Read the ledger tails before allocating an ID.

## One next action

**Drive §AY.** Fourteen numbered operations in `wp/MASTER_TEST.md`, all through `/ncm.setup`. Everything
below is built, deployed and green; none of it is *done* until a live PASS sits beside it (`L69`).

```
/ncm.setup                      what can be felt at all, split by fidelity
/ncm.setup power_unit 1.5       then drive     -- acceleration        [direct]
/ncm.setup brakes 0.5           then brake     -- stopping distance   [direct]
/ncm.setup tires 1.3            then corner    -- grip                [direct]
/ncm.setup suspension 1.3       then corner    -- grip x1.17          [approximated]
/ncm.setup aerodynamics 1.4     grip x1.18 AND drive x0.92 -- the trade, from one part
/ncm.setup aerodynamics 0.7     the trade REVERSES: grip x0.84, drive x1.09
/ncm.setup chassis 1.25         all three levers x1.09 -- mass touches everything
/ncm.setup aerodynamics         no multiplier: explains the family AND what it CANNOT do
/ncm.setup steering 1.2         expect a NAMED REFUSAL citing KB-135
/ncm.setup power_unit 9.0       expect clamp to 2.00, logged as CLAMPED
/ncm.setup clear                back to standard
```

**§AY5 changed meaning.** It used to be `suspension`, which `L152` refused; `L154` makes suspension work,
so the refusal case is now `steering` -- the one family left that cannot reach a force, and refused for a
mechanism (`KB-135`) rather than for a missing lever.

## Foundry architecture review — awaiting owner ruling

[38_FOUNDRY_VEHICLE_LINEAGE_ARCHITECTURE.md](38_FOUNDRY_VEHICLE_LINEAGE_ARCHITECTURE.md) is the repo-aware
review requested by the owner. It is **PROPOSAL**, not implementation authority. `L153` separately records the
binding scope: Foundry uses existing validated vehicle geometry; Parts R&D, Vehicle R&D and manufacturing stay
distinct; a Vehicle Design freezes one historical factory specification; appearance is a finite authored
reservoir; and new substrates/lineages are drip-fed rather than exhausted.

The review's central recommendation is to preserve permanent `assetId` and the tested
`record -> vehicleKey` catalogue invariant, then add explicit `lineage_id` and immutable
`vehicle_design_id`. The existing production scheduler is extended to Design ID rather than duplicated. Full
factory materialisation waits on Parts Gate 5, immutable component Designs/assets and configuration snapshots.

Four isolated experiments are specified before implementation: two Designs sharing one record with distinct
per-instance configurations; exact appearance-recipe replication; distinct record clones over one existing mesh
where record-channel separation is required; and the actual installed-game substrate inventory. No catalogue,
schema, runtime package, server or database was changed by the review.

## `L154`: approximation is allowed, and that took Parts from three families to eleven

`L152` shipped in the morning refusing nine of the twelve families outright. The owner's challenge -- *"why
cant we approximate. strip pureness from 100% to 05%"* -- was correct, and the error was a category one
worth remembering because it will recur in other forms.

**Two rules had been collapsed into one.** The rule worth keeping is *do not promise a felt effect a channel
cannot carry* (`IDEA-505`). The rule actually enforced was *do not express a family at all unless a lever
literally IS its quantity* -- far stricter, and it defends nothing. A stiffer suspension really does raise
usable grip; a wing really does add grip and cost straight-line speed. Those are coarse models of real
effects, not fabrications. The fabrication would be calling a suspension part *roll balance*, which is a
MOMENT and refuted by §AW3.

So fidelity became a property rather than a gate:

| | families | |
|---|---|---|
| `direct` | 3 | the lever IS the quantity -- tyres, power unit, brakes |
| `approximated` | 8 | a real effect, coarsely modelled, every one enumerating its **losses** |
| refused | 1 | `steering` -- response is not force magnitude, and input authority is the driver's |

**The honesty moved into `losses`**: each family lists what it provably cannot express, and the module
refuses to load if any list is empty. Aero has no speed dependence. Cooling has no time dependence, which is
the entire point of cooling. Chassis does not change actual mass. Every moment-shaped effect is named as a
loss wherever it is adjacent.

**The mechanism is `effect ^ weight`**, which is what lets one number on a wing add grip *and* cost drive
force at once, and keeps composition commutative so a car cannot depend on table iteration order. The
topology is physics; the weights are a first pass awaiting play data (`IDEA-519`).

**An unplanned result:** the four families with no drive-model flat all now reach `driveScale`, and steering
-- the one family the instance channel cannot carry -- turns out to have a flat. The two channels cover the
periodic table between them with **no family left at simulation-only**, down from four. `test_parts` asserts
it, because a coincidence that useful would otherwise break silently.

The carrier did not change: still three levers, same clamps, still clamping again because it does not trust
the wire. Approximation is entirely server-side composition, which is `L135` working as intended.

## What changed earlier today, and why it is the thing that was missing

Three force levers were proven live yesterday and this morning. **Nothing connected them to Parts.** They
were readable only from `ncm_carrier.json` -- a file on one person's disk -- so a proven capability was
reachable by the owner with a text editor and by nobody else.

`L152` built the path end to end:

```
fitted parts -> parts.handling.compose -> player state bag -> client -> WebSocket -> applyHandling -> force
```

| lever | family | status |
|---|---|---|
| `gripScale` | tires | PROVEN §AU5, now reachable from a fitted part |
| `driveScale` | power_unit | PROVEN §AW1 (owner's March anti-crawl hook is prior art) |
| `brakeScale` | brakes | PROVEN §AW2 |

**This is the per-player channel, and that answers the standing question** -- *"do we care about machine
flats if it affects every car in the server?"* The record channel is keyed by RECORD, so one client cannot
hold two setups for one model. The instance channel scales force on ONE BODY, the latched player vehicle,
so two drivers in the same Galena with different engines feel different. Per-player by construction.

**Nine families are refused rather than approximated.** Suspension, steering, aerodynamics and mass have no
live quantity: moments need a torque channel and §AW3 refuted the per-corner load entries with a mechanism.
A part naming one of them fails the whole compose with a named reason. `parts.ontology.INSTANCE_QUANTITIES`
was corrected from one family to three, and `parts.handling` asserts at load that the two agree.

## What does NOT exist, said plainly

**There is no parts inventory.** Ownership, acquisition, fitting, wear and the garage UI are Parts layer 4
and are not authorised. `server/handling.lua` holds an in-memory table and exposes `NcmHandling.setParts`
for whatever eventually owns that truth; nothing persists across a restart (`IDEA-518`, recorded as
deliberate). `/ncm.setup` fits synthetic components through **the same call the inventory will make**, so a
§AY PASS is a PASS of the real mechanism rather than of a shortcut around it.

Parts is not a game system yet. What exists is the half that was hardest and least certain: the one where a
component changes how a car feels.

## Live state

- Carrier **0.1.20** on Production, manifest digest `b3e0f520...`, `requiredMods` enabled.
- `ncm_world` deployed; `[ncm_world/handling] ready -- 3 live famil(ies) on the instance channel`.
- `KB-138` chown run and verified: `find /opt/ncm/server ! -user ubuntu` is empty.
- Gate green: 380 core tests, 183 resource files, docs authority OK.

## Next after §AY

1. **§AY itself.** A lever that moves in the log but not in the car is the failure this design is most
   exposed to, and it is a different failure from §AW3's. Check both claims separately (`KB-142`).
2. **`IDEA-516`** -- make the carrier log an unknown `cmd`. Three lines. The relay page whitelists event
   names and `ncm:machine.handling` was nearly lost to it; the next message will hit the same wall silently.
3. **`KB-145`** -- seven `machine.flats` entries do not resolve. Lower priority than it looked this morning
   now that the instance channel carries Parts, but `parts.ontology` still derives its record channel from
   that table, so wrong entries mean the ontology overstates what the record channel can do.
4. **`IDEA-511`** -- build-script guard against overwriting a published dist version. Two collisions in one
   day; a third is a matter of time.
