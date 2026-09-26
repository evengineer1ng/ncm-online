# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-26 - `L156` rebuilt the Parts expression model and it is GREEN BUT NOT YET
DEPLOYED.** Eleven families now point in eleven different directions in the three-lever space instead of
four of them sharing one, and the levers constrain each other: drive and brake are capped against grip, so
an engine is worth less until the tyres can carry it. `KB-150` fixed the carrier log (one file per process,
Carrier 0.1.24) and §AZ-C PASSED, which settles `L155` point 1 and `KB-146` live.

> **Claim before writing:** decisions through **L156**; MASTER_TEST through **§AZ**; next QA letter **§BA**.
> BACKLOG next free **IDEA-534**; known issues through **KB-150** plus pre-existing duplicate labels noted
> by `KB-114`. Read the ledger tails before allocating an ID.

## One next action

**Deploy the `L156` resource change, then drive §AY15-16.** The code is committed and the gate is green
(400 core tests, 0 failed), but production is still running the `L154` table -- **nothing below is live
until the resources sync**:

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-staging.ps1
ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 \
    "sudo chown -R ubuntu:ubuntu /opt/ncm/server && find /opt/ncm/server ! -user ubuntu"
```

The `chown` is `KB-138` and the `find` must print nothing. **No carrier rebuild is needed** -- `L156` is
entirely server-side composition and the wire is still three floats, so a client already on Carrier 0.1.24
picks it up from the resource restart.

Then, in game:

```
/ncm.setup power_unit 2.0     -- expect drive 1.246, NOT 2.0, with the reason in chat   (AY15)
/ncm.setup tires 1.4          -- same engine, now 1.545. THIS is the test.              (AY16)
```

§AY16 is the assertion `L156` exists for: fitting tyres made the engine stronger without touching the
engine. If that lands, parts are a build rather than a menu.

**§AY18 is the aliasing test.** `transmission 1.4` then `drivetrain 1.4`, back to back, cleared between.
Nearly identical drive (1.183 vs 1.203); the difference is that transmission also brakes and drivetrain
costs turn-in. Before `L156` these two were literally the same part with two names, which is the defect the
whole line was written for.

**Expect four `L154` numbers to be wrong on purpose.** §AY1, §AY2, §AY6 and §AY14 were composed under the
old rules; the `L156` amendment at the end of §AY restates each one. A tester working from the stale table
will report a bug that is not one.

## What §AZ still needs

§AZ-C **PASSED** on 2026-09-26 -- Parts follow the Machine, not the driver, proven solo with two Machines
and the carrier log naming each `assetId` and entity. §AZ-A is a two-minute solo pre-check.

§AZ-B (§AZ6 / §AZ9 / §AZ12) needs a **second human**: concurrency, passenger-gets-no-binding, and physics
handover cannot be shown sequentially. `KB-4` remains open -- the second local client still renders no UI,
the race theory is retracted, and the decisive untested step is capturing the launcher-started process's
`CommandLine` while a working client runs.

## Then drive §AY

Twenty-three numbered operations in `wp/MASTER_TEST.md`, all through `/ncm.setup`. Everything below is
built and green; **none of it is live until the deploy above runs**, and none of it is *done* until a live
PASS sits beside it (`L69`). Every number here is the module's own output, read out of `parts.handling`
rather than estimated.

```
/ncm.setup                      what can be felt, split by fidelity, plus the CEILINGS line
/ncm.setup power_unit 2.0       drive 1.246 -- NOT 2.0. Traction-limited, and chat says why   (AY15)
/ncm.setup tires 1.4            the SAME engine now 1.545, grip 1.306 -- the build            (AY16)
/ncm.setup clear
/ncm.setup brakes 2.0           brake 1.200 -- a disc cannot beat the tyre                    (AY17)
/ncm.setup clear
/ncm.setup transmission 1.4     drive 1.183, brake 1.070, grip untouched                      (AY18)
/ncm.setup clear
/ncm.setup drivetrain 1.4       drive 1.203, grip 0.951 -- nearly the same power, opposite trade
/ncm.setup clear
/ncm.setup tires 1.4            brake 1.163 -- tyres shorten a stop. The old table missed this (AY19)
/ncm.setup aerodynamics 1.4     grip 1.183, drive 0.919, brake 1.052 -- drag also stops you   (AY23)
/ncm.setup aerodynamics 0.7     the trade REVERSES: grip 0.837, drive 1.093
/ncm.setup chassis 1.4          all three x1.144 -- mass touches everything equally
/ncm.setup power_unit           no multiplier: the family, its losses, AND the ceiling warning (AY21)
/ncm.setup steering 1.2         expect a NAMED REFUSAL citing KB-135
/ncm.setup power_unit 9.0       BOTH rules: clamped 9->2.00, then limited to ~1.14            (AY6)
/ncm.setup clear                back to standard
```

**The two that matter most.** §AY16 -- tyres making an untouched engine stronger -- is the whole of `L156`.
§AY18 is the regression test for the defect it fixed: `transmission` and `drivetrain` were the identical
direction at nearly identical magnitude, which is one part with two names.

**§AY5 changed meaning twice.** It was `suspension`, which `L152` refused; `L154` makes suspension work, so
the refusal case is `steering` -- the one family that cannot reach a force, refused for a mechanism
(`KB-135`) rather than a missing lever. `L156` does not change that.

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

## `L155` prerequisite: Machine-keyed Parts and a positive body binding -- SHIPPED

The owner approved the ten-point package and authorised the prerequisite immediately. It is built, green
and on Production. **Scope was held exactly where the ruling put it:** record cloning (point 4) and
per-instance `setPerformance(id)` (point 9) remain experiments and did not leak into this patch.

**`KB-146` was the reason this had to come first.** Every claim that the force write was *"scoped to the
latched player vehicle"* -- in `L148`, `L151`, `L152` and the probe's own header -- was false. The latch
condition was `mass > 200 && mass < 10000 && back != 0`, evaluated for whichever body was the window's
fastest. There was no player check anywhere in the file. Four sections of live testing passed because in
single-player your own car IS the fastest car-shaped body; put an AI racer or a leased peer car ahead of
you and your Parts would have started scaling theirs, silently.

**Three links, none inferred:**

| link | proved by | file |
|---|---|---|
| `assetId` -> live `vehicleId` -> physics-authority player | server, from the platform lease table | `vehicle_access.bindingForAuthority` |
| "I am really in that exact vehicle" | client, reading its own state (`KB-41`'s rule) | `client/carrier_bridge.lua` |
| that vehicle -> the live `ent::EntityID` | client snapshot, then exact equality at `+0x180` -> `+0x48` | `vehicle/physics_probe.cpp` |

The binding is a **2 s lease** re-sent at 2 Hz and expired on the physics thread itself, so a lost seat or
ownership change cannot leave another Machine tuned. An NCM-authored unbind keeps `ncm_carrier.json`
suppressed -- handing the levers back mid-session would let a stale bench value become a live car's
handling at the moment NCM said it should have none. Socket loss, which is a different event, does return
ownership. The fastest-body latch survives as **diagnostics only** and is disabled whenever a binding is
expected.

The engine entity crosses the wire as a **decimal string**: it is a 64-bit id passing through a WebUI page
that re-serialises JSON in JavaScript, where every number is a double, and a rounded identity matches
nothing.

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
topology is physics; the weights are a first pass awaiting play data (`IDEA-527`).

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
