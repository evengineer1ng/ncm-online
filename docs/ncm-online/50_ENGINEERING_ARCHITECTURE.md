# 50 - The Engineering Architecture: one grammar for what can physically be built

> **STATUS: CURRENT** - authority for: *the engineering architecture (body grammar, sites/envelopes, fitting rule, drivetrain composition, cause/actuator/state/coarse model)* - affirmed 2026-10-04 (L314). Directionally approved, with amendments. **§11 governs where it differs from §0-§10**
> (the four-concept boundary; R2's canonical 3D body; R4's drivetrain graph replaces "36 ratios, de-duplicated and pruned").
> §1-§10 are the proposal as reviewed. Code: `ncm/core/engineering/{body,envelope,drivetrain,fit,actuate,fixtures}.lua` (§12).
> Originally the first deliverable of the
> Engineering Architecture pass that [48_ENGINEERING_ENVELOPE.md](48_ENGINEERING_ENVELOPE.md) §5 proposed and L311 Q5 scheduled
> ("audio and shift feel then the engineering"). L311 ruled that the pass's first output is a reviewable architecture, not code.
> Doc 48 (the car) and [49_CITY_MEMORY.md](49_CITY_MEMORY.md) §7-§8 (civil engineering, L313 C1: "one grammar serves cars and
> city") are SPEC. This document must not contradict them, and it does not re-argue anything they rule.
> Authority map: [INDEX.md](INDEX.md). Builds on: L162 (conserved Parts economy), L134 (knowledge is not capability), L153
> (lineages), L306 (NCM Gearbox), L311 (Q1-Q5), L313 (C1-C4). Ideas: IDEA-1009 to IDEA-1016. Owner questions: §9.

---

## 0. In one paragraph

A car is a **plan-view envelope**: cells grouped into zones (front bay, tunnel, rear bay, underfloor, cabin), with mounts,
ports and five capacities (mass, cooling, electrical, control, structure). A component is a **body**: a footprint made of
cells, a mass, mounts, ports, heat, power draw and control needs, plus one family-specific performance block. A build is a
**layout**: bodies placed, rotated and connected. The fitting rule returns **green / yellow / red with reasons**. Only
geometry and topology can be red. Everything a capacity says is a *consequence* (heavier, hotter, derated) that physics
delivers ("it fits"). The same `Body` (footprint, mass, material, sockets/ports, load, durability, cost) serves civil engineering's barriers,
fences and decks. A car layout and a city placement are two **sites** for one grammar.

---

## 1. E1 - is mass real physics? (evidence so far)

L311 Q2: "lets measure". What is known without a new drive:

| Finding | Evidence |
|---|---|
| The live body's mass at `+0x1BC` **is the drive-model record's `total_mass`**. | Every 2026-10-04 Carrier log (7 sessions) reads round record values: 1800 kg for the bound Hella (its record: 1800), 1470 Quadra Turbo, 1895 Outlaw, 2100, 2350, 2860, 960, 300. All of them appear in the 2026-09-26 architecture dump wherever that dump covers the car. |
| The physics therefore **loads** its mass from the record at spawn. | As above. `insert1` is also fed from the drive-model record (IDEA-503, the `LoadSomeVehiclePhysicsStuff` slot). |
| Carrier's record channel can already write `.total_mass` and `.chassis_mass`. Nothing ever has. | `effects/tweak.cpp` takes any suffix as a multiplier against the captured original. `machine.flats` already lists `mass` (0.70-1.40). `machine.expression`: "alive on this build and not yet written by anything". |
| Whether the **solver uses** a changed record mass is **not known**. | The force-budget check in today's logs cannot answer it: it divides the tracked car's impulses by the *fastest* body's mass, which is often traffic. |

**The instrument (built 2026-10-04, dev, no Carrier change):**
- `/ncm.mass <0.70-1.40>` writes both mass flats on the car you sit in, through the existing record channel, then you call the car again (the channel is spawn-cached). `/ncm.mass off` restores.
- `/ncm.massrun` logs 0-100 km/h and 100-0 km/h (time and distance) for ten minutes.
- §EN1 is the A/B.

**What each answer buys:**
- **Positive** (the Carrier log reads the new kg, and 0-100 and braking both lengthen roughly in proportion): mass is real physics. Weight transfer, collisions and load all follow from it for free.
  - The catch is **scope**. The record channel is keyed by *record*, so on one client every car of that model shares the value (`parts.ontology`, `record` channel). In OPEN//77 each player's client simulates its own car, so this mostly lands per player. The exceptions are traffic copies of your model on your client, and how collisions with other players' cars are resolved (unknown, §8).
  - Making it per instance would need per-mass clones (the Gearbox's TweakXL clone pattern, in buckets of, say, 25 kg).
- **Negative** (the log moves, the car does not): mass becomes an **approximation on the instance channel**. Drive and brake are scaled by `m0 / (m0 + dm)` (F = m·a). Lateral grip stays unchanged, because friction scales with load, so cornering acceleration is mass-independent to first order.
  - What it loses has to be stated honestly: no weight transfer, no collision mass.
  - Carrier's instance levers only scale *down*, so a car **lighter** than stock cannot be expressed. That is acceptable, because almost every build adds mass, and a "lightweight" kit can be read as giving back a share of the stock car's own budget.

Either way the **model** below is the same. Only §6's hookup changes.

---

## 2. The grammar (one vocabulary, two sites)

| Term | Car site (doc 48) | City site (doc 49 §7-§8) |
|---|---|---|
| **Body** | a component: gearbox, radiator, battery | a barrier, fence, post, panel, deck, net |
| **Footprint** | cells on the car's plan grid | the prop's plan bounds on the road |
| **Mass / material** | kg; material class (steel, alloy, composite, exotic) | kg; concrete, steel, mesh |
| **Ports / sockets** | driveline in/out, coolant, power, data | snap sockets: end, top, anchor |
| **Mounts / anchors** | chassis mount points with a load rating | ground anchor; another body's socket |
| **Load** | structural load on its mounts | impact load, measured by the race |
| **Durability** | wear, exposure (`parts.wear`, L162 exposure) | damage taken, survives or not |
| **Cost / availability** | asset, market, custody (L162) | placement and dismantling cost (C4) |
| **Site** | the car's envelope | a road segment and cluster (doc 49 §6) |
| **Judge** | fitting rule, then physics | the race (doc 49 §7: "physics files the complaint") |

One pure module, `engineering.body`, owns the shared fields and their validation. `engineering.envelope` (the car) and a
later `city.site` (the road) are two consumers. Civil engineering adds no new grammar; it adds a site.

---

## 3. The car's envelope (per car model; L311 Q3)

```
envelope = {
  model    = "archer_hella",                 -- data.vehicle_catalogue key; per MODEL, not per body class (Q3)
  grid     = { cell = 0.10, w = 18, l = 44 }, -- 10 cm cells; plan view only in v1 (side elevation later, doc 48 §0)
  zones    = { front_bay = {cells...,  heightClass = 3, heat = "open"},
               tunnel    = {cells...,  heightClass = 1},
               rear_bay  = {...}, underfloor = {...}, cabin = {..., reserved = "driver"} },
  mounts   = { {id, cell, kind = "drivetrain"|"cooling"|"aux", ratedKg} ... },
  ports    = { {id = "engine_out", cell, kind = "driveline"}, {id = "diff_in", ...}, {id = "rad_core", kind = "coolant"} },
  capacity = { massKg = 1800 (stock) + budget, coolingKw, electricalKw, controlChannels, structureKg },
  stock    = { layout = {...} },             -- the factory layout L162's factory components already imply
}
```

**Authoring** is per model (Q3). The outer bounds come from the mesh (WolvenKit can export each model's bounding box).
The zones are hand-drawn on top of a body-class template as a starting point. The template is an authoring aid, not the
truth (Q3 says per model). Every value carries provenance like `parts.architecture`: `derived` / `authored` / `unknown`,
and **unknown fails closed** as a *red with reason "not yet surveyed"*, never as a guess.

The 19 L162 positions do not disappear. Each becomes the **default placement** of a factory component in the stock layout,
so existing Machines and their configuration revisions migrate without inventing anything (L162 rule 4).

## 4. The component's body

```
body = {
  design   = "kimiko_rangebox_mk1",          -- component_design (L162), unchanged identity and lineage (L153)
  family   = "transmission",                 -- one of the 12 (engineering.competency.FAMILIES); a SYSTEM, not a slot
  footprint= { {0,0},{1,0},{2,0},{2,1} },     -- cells (a polyomino); rotation 0/90/180/270; mirror only if declared
  heightClass = 1, massKg = 22, material = "composite",
  mounts   = { {cell = {0,0}, kind = "drivetrain", loadKg = 22} },
  ports    = { {id = "in", kind = "driveline", cell = {0,0}, side = "W"}, {id = "out", kind = "driveline", cell = {2,1}, side = "E"} },
  heatKw = 1.5, powerKw = 0.2, controlChannels = 1,
  perf     = { kind = "range_box", ratios = {1.00, 1.38}, shiftMs = 180, torqueNm = 650 },
}
```

The body is **design data** (server-private truth per L134; clients see what their understanding stage reveals, §7). An
asset (L162) is one physical instance of a design: same body, its own wear and exposure.

## 5. The fitting rule

Placements and connections are checked in this order. Each check returns reasons, not just a colour.

| Check | Red (impossible) | Yellow (possible with adaptation) | Green |
|---|---|---|---|
| **Geometry** | overlaps another body; leaves the envelope; enters a reserved zone (driver) | crosses an `adaptable` cell (a cut or a fabricated bracket: costs money and time, adds kg) | fits inside its zone |
| **Height** | taller than every zone it occupies | fits only with a raised cover (adds drag) | fits |
| **Mounting** | no mount reachable from its footprint | a fabricated mount (adds kg; structural load counts double) | a matching mount |
| **Topology** | a driveline that does not run engine to wheels | an adapter shaft or a port mismatch an adapter fixes (adds kg and loss) | ports meet |
| **Capacities** | **never red** | over budget: shown as the *consequence* | within budget |

**"It fits."** Capacities are never refusals (doc 48 invariant 3). Over mass makes the car heavier (§6). Over cooling makes
it heat (`parts.thermal`) and derate. Over electrical browns out control features. Over structure wears mounts faster
(`parts.wear`). The packaging puzzle colours a capacity overrun amber and **names the punchline** ("+164 kg: about +11 %
0-100, +9 % braking distance"), and it never stops you.

## 6. What the build does to the car (the hookup)

| Quantity | From the layout | Channel |
|---|---|---|
| **Mass** | sum of body masses minus the stock layout's | §1: the record (if E1 is positive) or `m0/(m0+dm)` on drive and brake (instance) |
| **Gear table** | the driveline graph composed: boxes in series **multiply** (a 6-speed into a 2-speed range box = 12 ratios; two 6-speeds = 36, de-duplicated and pruned to the usable ladder) | NCM Gearbox virtual spec (L306). The DLL already owns the table. A composed table needs a per-asset spec delivered at runtime, not just `specs.json` at load (§9 R4) |
| **Shift time** | the slowest box in the chain, plus the controller if one is fitted | Gearbox `shiftMs` |
| **Heat** | sum of `heatKw` against `coolingKw` | `parts.thermal` (simulated), then derating through drive (instance) |
| **Electrical / control** | draw against capacity | simulated: which control features (TC, launch, a smart shifter) actually run |
| **Torque limit** | the weakest box's `torqueNm` | wear and failure (`parts.wear`), not a power cap |

**A second gearbox is not a second engine.** Composition changes ratios and mass. It never adds drive force. Doc 48 §0
says this verbatim, and the model enforces it by construction: no transmission `perf` block has a power field.

## 7. Understanding and lineage (already ruled; how this model plugs in)

L134 stages map onto the body's fields:
- stage 1 reveals footprint, mass and material;
- stage 2 reveals `perf` and heat;
- stage 3 reveals ports, mounts and control;
- stage 4 is what lets you **derive**.

A derived design (Mk I) is a new design in the same lineage (L153):
- it is worse (mass ×1.2-1.6, a coarser footprint);
- manufacturing progression narrows the gap (Mk II);
- a **fork** may change the footprint to fit another car, which is exactly doc 48's Quadra example.

Nothing here is new authority. It is where those rulings attach to fields.

## 8. What is unknown, and what is not ours to decide yet

- **E1** (§1), §EN1.
- **Collisions between players' cars of different mass.** Whose client resolves the contact is platform behaviour nobody has measured. It matters only if E1 is positive.
- **E19** (does a placed barrier stop a car?). This blocks the city site, not the car site.
- **What survives a campaign** (doc 48 Q4, deferred by §0).

## 9. Owner questions

- **R1 Yellow means "adaptation".** Is adaptation a cost (money, time, kg) the integrator pays, and is the integrator's skill (`engineering.competency`, transmission and chassis) what lowers it? *Recommendation: yes. That makes "the best engineer is the one who makes it fit" literal.*
- **R2 Grid.** Is a 10 cm plan grid, with three height classes and no side elevation, right for v1? *Recommendation: yes. Elevation later, as doc 48 §0 allows.*
- **R3 Mass channel.** If E1 is negative, is the instance approximation (drive and brake only, heavier-only, its losses stated) acceptable? *Recommendation: yes.*
- **R4 Composed gearing at runtime.** A layout's composed gear table has to reach the Gearbox DLL per asset. Is a new channel for it, in the Gearbox package and not in Carrier (the new-features-new-mods rule), acceptable? *Recommendation: yes. The DLL already reads a local spec, so the client resource writes the composed spec and the DLL reloads it on entry.*
- **R5 Twelve or eleven.** The code has twelve families (`engineering.competency`). Doc 48's pillars list eleven plus Human interface. *Recommendation: the twelve families stay the systems, and Human interface stays outside the envelope (Devices / Rig Bridge).*

## 10. The ladder (after the rulings)

1. **E1 A/B** (§EN1). Instrument built.
2. **`engineering.body` + `engineering.envelope`**, pure core with tests. Fixtures:
   - the Hella and the Quadra;
   - five gearboxes: street 6-speed 82 kg, competition 65 kg, advanced race 42 kg, the ghost range box 14 kg, and Kimiko Mk I 22 kg;
   - the double street box (164 kg).
3. **`engineering.fit`**: §5 over those fixtures, with every reason string tested. The ghost box fits where nothing else does, and the double box fits and is heavy.
4. **`engineering.compose`**: the driveline graph to a gear table and a mass delta, tested against the Gearbox's spec format.
5. **The puzzle surface, read-only** (the F6 WebUI shell): what is fitted and why. Then drag, rotate and snap.
6. **Hookup**: mass (per E1), composed gearing to the Gearbox (R4), heat to `parts.thermal`.
7. **The city site** reuses steps 2-3 once E19 has run.

---

## 11. Owner ruling on R1-R5 (L314, 2026-10-04)

### 11.0 The owner's ruling (verbatim, 2026-10-04)

> # OWNER RULING — R1–R5 + architecture clarification
>
> The proposal is directionally approved, with amendments below.
>
> The larger design discussion since this proposal was written has clarified why `engineering.body` must be shared. This does **not** expand the current implementation pass into flight, spacecraft, offline simulation, or a general construction game. Those are not current deliverables.
>
> It does change what abstractions we are allowed to freeze now.
>
> The engineering architecture should be built as a small physical grammar that the current car-envelope implementation consumes, rather than as a car-packaging model that we later attempt to generalize.
>
> The current target remains: **make the Hella/Quadra engineering envelope, gearbox composition, fitting rule and physical hookup work.**
>
> However, do not encode assumptions that make the following impossible later:
>
> - a component applying force at a position and direction;
> - vertically assembled structures;
> - selectable/discrete rather than purely serial gearboxes;
> - construction sites other than cars and roads;
> - authoritative NCM physical state whose REDengine representation is only one actuator;
> - coarse/offline causal simulation of the same physical objects.
>
> ## R1 — Yellow / adaptation: APPROVED WITH CLARIFICATION
>
> Yellow means physically possible through adaptation.
>
> Adaptation has real consequences. Money, time and added mass are current examples, not an exhaustive hard-coded list.
>
> Engineering competency may improve an adaptation where physically meaningful: less fabrication time, less waste, a lighter bracket, a better adapter, etc. Competency must not erase conservation or physical consequences.
>
> Prefer adaptations eventually becoming explicit construction artifacts where useful. An adapter shaft, fabricated mount, reinforcement or converter should be capable of existing as a body/component rather than permanently living as an invisible RPG surcharge.
>
> For v1, an adaptation may remain summarized as a consequence if explicit artifact construction is not yet implemented.
>
> ## R2 — 10 cm plan grid: APPROVED FOR V1 REPRESENTATION, NOT AS CANONICAL PHYSICS
>
> Use the proposed 10 cm plan grid, three height classes and no side-elevation editing for the first car-envelope implementation.
>
> However, `Body.footprint = polyomino` must not become the permanent definition of physical geometry.
>
> The canonical body model must leave room for:
>
> - 3D dimensions/bounds or shape reference;
> - local transform;
> - center of mass;
> - connection/socket position;
> - connection/socket orientation;
> - force/load application positions.
>
> The v1 cell footprint is a simplified projection/authoring representation of that body.
>
> Reason: later physical components may care about where and in what direction a force or load is applied. Civil structures may also extend vertically. We should not require an ontology migration merely to express this.
>
> Do not implement 3D construction now. Preserve the abstraction boundary.
>
> ## R3 — Mass channel: APPROVED AS FALLBACK
>
> Run E1.
>
> If REDengine genuinely responds to changed physical mass, use the real mass channel.
>
> If E1 is negative, the proposed heavier-only drive/brake approximation is acceptable for v1, with the stated limitations retained explicitly.
>
> New invariant:
>
> **NCM's canonical physical state records the actual modeled mass regardless of the current REDengine hookup.**
>
> Carrier/REDengine is an actuator for presenting that state. It is not the authoritative definition of the object's physics.
>
> Example: if the engineering model says a build is 1,947 kg, NCM stores 1,947 kg even if today's runtime representation must approximate its acceleration/braking through scales.
>
> This distinction is required for future simulation/reconstruction work and should exist now even though that work is not part of this pass.
>
> ## R4 — Runtime composed gearing: APPROVED, BUT COMPOSITION MODEL MUST CHANGE
>
> A per-asset runtime channel to NCM Gearbox is approved and belongs with the Gearbox package rather than Carrier.
>
> However, reject the current assumption:
>
> > two 6-speeds = 36 ratios, de-duplicated and pruned to one usable ladder
>
> That is only one possible drivetrain topology.
>
> The architecture must support at least these conceptual relationships:
>
> 1. **Series / supplementary** — ratios compose/multiply; example: 6-speed × 2-range box.
> 2. **Range** — one box changes the operating range of another; range changes may have their own shift procedure/time/constraints.
> 3. **Discrete / selectable** — two gearboxes remain separate ratio sets; the driver/controller selects which transmission/path is active; overlapping ratios are intentional and must not be de-duplicated merely because they produce similar overall ratios.
> 4. **Adapter / prerequisite stage** — a component can exist primarily to make otherwise incompatible ports/topologies connect, with its own mass/loss/geometry.
>
> Therefore `engineering.compose` should conceptually produce a **drivetrain graph/spec**, not merely a flattened `gearTable`.
>
> The Gearbox runtime may derive an active table from that graph as an implementation detail.
>
> A transmission still never creates engine power by existing. It transforms/routes power and introduces its own mass, losses, limits, heat, shift behavior, etc.
>
> ## R5 — Twelve engineering families: APPROVED PROVISIONALLY
>
> Keep the twelve existing `engineering.competency` families.
>
> Human Interface remains outside the vehicle envelope under Devices / Rig Bridge.
>
> Do not, however, make the shared `Body` grammar closed over exactly twelve families.
>
> `family` is taxonomy used by current engineering competency and UI. It is not a fundamental law of the physical ontology.
>
> Future component families must be addable without redesigning `engineering.body`.
>
> No new family is being requested in this pass.
>
> # ADDITIONAL ARCHITECTURE CLARIFICATION — CAUSE, ACTUATOR, STATE, COARSE MODEL
>
> For physical systems added from this point forward, keep four concepts separable:
>
> 1. **Physical cause** — what NCM says is physically happening.
> 2. **Runtime actuator** — how the current game/runtime is made to express that result.
> 3. **Persistent authoritative state** — what NCM records as true about the object/build/world.
> 4. **Coarse simulation representation** — the reduced description from which NCM could reason about the object without requiring live REDengine physics.
>
> This is an architectural boundary, not a request to implement offline simulation now.
>
> Examples:
>
> **Mass.** Physical cause: 1,947 kg vehicle mass. Runtime actuator: real REDengine mass if E1 succeeds; otherwise Carrier approximation. Persistent state: `massKg = 1947`. Coarse model: mass contributes to acceleration/braking/energy/collision estimates according to the fidelity available.
>
> **Gearbox.** Physical cause: ratios, torque transmission, shift interruption, losses, mass, topology. Runtime actuator: NCM Gearbox DLL + Carrier. Persistent state: installed transmission bodies and their connections/configuration. Coarse model: ratio envelope, shift behavior, efficiency/limits and driver proficiency.
>
> **Barrier.** Physical cause: a body with geometry, mass/material, connections and structural/impact behavior. Runtime actuator: placed Cyberpunk collision object, assuming E19 succeeds. Persistent state: body design + transform + connections + damage/provenance. Coarse model: its observed effect on incidents and loads.
>
> The purpose is simple: **NCM owns the meaning; REDengine supplies the current physical presentation.**
>
> # FUTURE-PROOFING NOTE — GENERAL FORCE COMPONENTS
>
> This is context for the ontology only. Do not implement it in this pass.
>
> A later component may produce a force rather than directly modifying a named vehicle statistic.
>
> The desired primitive is conceptually: `force + direction + application point + power/energy demand + heat + operating limits` — not: `allowsFlight = true`.
>
> A downward/upward/sideways/rearward force can have different emergent uses depending on installation and control. Mount position also creates torque.
>
> This is why R2 must not permanently reduce bodies to plan-view cells and why ports/sockets need eventual orientation.
>
> No flight system is currently requested.
>
> # FUTURE-PROOFING NOTE — CONSTRUCTION
>
> Civil engineering and vehicle engineering share a **grammar**, not necessarily the same parts.
>
> A barrier and a gearbox are both Bodies because both can have: geometry; mass/material; sockets/connections; loads; durability; cost/provenance.
>
> That does not mean barriers become vehicle parts.
>
> Likewise, a future constructed machine could use structural bodies, propulsion bodies, energy bodies and control bodies under the same grammar without requiring `engineering.body` to know what a "spaceship" is.
>
> The architecture should describe what has physically been assembled.
>
> Capabilities should be derived from the assembly wherever practical rather than granted by categorical flags.
>
> # FUTURE-PROOFING NOTE — CAUSAL REGENERATION
>
> Long-term single-player direction now includes persistent simulation state that may continue progressing while the player is absent.
>
> This is context, not current scope.
>
> The important implication for #50 is that engineering objects must have enough machine-readable state to be reasoned about without requiring their Cyberpunk representation to exist.
>
> An installed component cannot be meaningful only as "Carrier driveScale +0.08."
>
> Its authoritative meaning should be the physical/design state from which the current Carrier effect is derived.
>
> Similarly, provenance matters: design, asset instance, lineage, configuration, wear/exposure and observed performance remain separable.
>
> This supports future causal simulation and historical reconstruction without changing today's implementation target.
>
> # CURRENT IMPLEMENTATION SCOPE REMAINS SMALL
>
> Proceed after these rulings with: 1. E1 mass A/B. 2. `engineering.body`. 3. `engineering.envelope`. 4. `engineering.fit`. 5. drivetrain graph/composition supporting the ruled transmission relationships. 6. read-only Hella/Quadra puzzle surface. 7. drag/rotate/snap. 8. physical hookup. 9. city-site reuse after E19.
>
> Do **not** implement: flight; thrusters; spacecraft; orbital physics; offline causal regeneration; historical reconstruction; generalized 3D construction; procedural component invention.
>
> Those ideas currently constrain the architecture. They are not the task.
>
> The design principle behind the pass is now:
>
> > **Describe physical things, how they connect, and what they cause. Let sites, runtimes and simulations decide how those facts are expressed.**
>
> The immediate proof remains mundane and valuable: fit real gearboxes into real NCM cars, connect them in more than one topology, and make the resulting car behave accordingly.

### 11.1 The rulings, distilled

- **The principle:** describe physical things, how they connect and what they cause. Sites, runtimes and simulations decide how those facts are expressed. **NCM owns the meaning; REDengine supplies the presentation.**
- **Four concepts stay separate** for every physical system: *physical cause*, *runtime actuator*, *persistent authoritative state*, *coarse simulation representation*.
- **R1:** yellow = physically possible through adaptation. Consequences are real (money, time and mass are examples, not a closed list). Competency improves an adaptation and never erases conservation. Adaptations should be able to become explicit bodies; in v1 they may stay summarised.
- **R2:** the 10 cm grid, three height classes and no elevation editing are the v1 *projection*. The canonical body leaves room for 3D bounds or a shape reference, a local transform, a centre of mass, socket position and orientation, and load and force application points.
- **R3:** run E1 and use real mass if it works, else the heavier-only approximation. **The canonical state records the modelled mass whatever the hookup.**
- **R4:** a per-asset runtime channel in the Gearbox package. Composition produces a **drivetrain graph/spec** that supports series, range, discrete/selectable (no de-duplication across paths) and adapter stages. A transmission never creates power.
- **R5:** keep the twelve families. Human interface stays outside. `family` is open taxonomy, not physics.
- **Not this pass:** flight, thrusters, spacecraft, orbital physics, offline causal regeneration, historical reconstruction, generalised 3D construction, procedural component invention. They constrain the architecture. They are not the task.

## 12. What is built (steps 2-5 of the ruled scope; offline, pure core, 2026-10-04)

| Module | Holds | Where a ruling lands |
|---|---|---|
| `engineering.body` | validation; the grid projection (`place`: cells, ports, mounts and sides rotate together); `asset` (instance, separate from design) | R2: `shape`, `com`, port `pos`/`dir`, `loads` are canonical and optional, and the footprint is a projection. R5: `family` is an open string |
| `engineering.envelope` | a SITE (`kind`), zones (reserved / height / adaptable / fabricable / coverable), mounts, ports with `reach`, capacities, stock, provenance | unknown fails closed; nothing car-specific beyond `kind` |
| `engineering.fit` | green/yellow/red with reasons; adaptation records (cut, cover, bracket, adapter, shaft) with mass, time, cost, loss and an `artifact` slot; capacity consequences; **`state`**, the canonical physics | R1, R3 |
| `engineering.drivetrain` | `compose` produces paths of stages (gearbox / range / selector / adapter), each with its own procedure, efficiency and torque limit; `combinations`, `ladder` and `virtualGears` are the runtime derivation, kept apart | R4: series multiplies, range has its own procedure, selectable paths are never merged, adapters are stages; power can split only at a selector; a perf block that declares power is red |
| `engineering.actuate` | mass on the `record` or `instance` channel; `stateKg` vs `expressedKg` vs `unexpressedKg`; stated losses | R3, the four-concept boundary |
| `engineering.fixtures` | Hella and Quadra sites (**fixture** geometry, real record masses), the owner's five gearboxes, a selector and combiner, spline adapters | test fixtures only, never a survey |

`tests/test_engineering_envelope.lua` has 15 cases under Lua 5.4 and LuaJIT. They cover:
- the double street box (fits; 164 kg; 36 series combinations);
- the ghost box in the rear pocket where no other box fits;
- a 6-speed into a range box (12 combinations, two procedures);
- two identical boxes behind a selector (two paths, six ratios each, nothing merged; hotter than the car can cool, which is a consequence and not a refusal);
- a split without a selector (red);
- an Archer box in a Quadra (yellow with summarised adapters; green with adapter bodies);
- overlap, reserved, outside, and kind mismatch;
- an unsurveyed site;
- competency;
- no power from a transmission;
- 1,947 kg staying 1,947 kg whatever the actuator.

**Not built:** the puzzle surface (6, 7), the hookup (8, which waits on E1 and the R4 channel), the city site (9, which waits on E19), and surveyed envelopes for real cars. Nothing here is a live PASS (L69).
