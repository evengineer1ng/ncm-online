# Parts behaviour, compounds and Wear & Tear — exploration / design pass

> **STATUS: PROPOSAL** — reconnaissance and recommendation only. No implementation is authorised by this
> document. Existing authority remains `L120`, `L149`–`L163`, the Parts/Wear specifications, and shipped code.
> Authority map: [INDEX.md](INDEX.md).

**Prepared 2026-09-27. No production behaviour, schema, balance value or UI asset changed.**

The brief's central realization is correct and already has two footholds in the repository:

```text
component properties
  -> NCM behavioural reducers
  -> contextual machine/system state
  -> final grip / drive / brake / drag / top-speed expression
```

`parts.handling` already composes named layers (`parts`, `wear`, `weather`, `surface`, `thermal`, `chrome`,
`ruleset`) rather than treating the final physics values as ownership boundaries. `IDEA-532` already names the
missing step: levers must sometimes be functions of speed, load and time, not constants. The expansion should
make those seams real without constructing eleven unrelated simulators.

---

## A. Existing-system archaeology

### A.1 Authority and implementation status

| Area | State | What exists now | Important limit |
|---|---|---|---|
| Component ontology | **implemented** | Twelve canonical ontology families in `parts.ontology`, borrowed from `engineering.competency` | Ontology is broader than the market catalogue |
| Parts v1 catalogue | **implemented, deployed, live evidence owed** | Eleven supported/swappable families, 25 immutable launch Designs, serialized assets, factory backfill, primary supply, inventory and transactional fitting (`L162`–`L163`) | Steering is deliberately excluded; every Design has one scalar `effect` |
| Fitment | **implemented** | Nineteen authored positions; immutable Machine configuration revisions; displaced assets return to storage | No install workmanship; required positions cannot be empty |
| Physical expression | **implemented, bounded** | Live per-Machine `gripScale`, `driveScale`, `brakeScale`, `dragScale`; a separate top-speed target; authored family directions and couplings | Constant coefficients; no per-corner channel; top-speed live gate is still owed |
| Weather | **implemented** | Persistent server weather plan; engine synchronization; current weather and time feed the Machine | Wetness is presently binary: rain family = 1, everything else = 0 |
| Road/tyre temperature | **implemented** | One server-owned tyre temperature per Machine; air, track and tyre are separate; temperature and surface produce downward-only grip/brake multipliers | One tyre curve, no compound, no slip velocity, no brake temperature, no road inertia, no per-corner state |
| Odometer | **implemented** | Authoritative server sample at 1 Hz, discontinuity/jitter filters, additive checkpoints, persistent `vehicle_asset.odometer_m` | §AG5/§AG6 and long soak remain required before economic consequences |
| Component exposure | **implemented** | The same odometer transaction adds metres to every installed `component_asset.exposure_m` | Distance only; no condition; a pre-flush fit attribution defect exists (`KB-163`) |
| Wear/condition | **accepted architecture, unimplemented** | `L120`: immutable additive exposure, deterministic derived condition/severity, seeded trajectories, append-only service relief | No profile catalogue, conditions, service rows, symptoms or consequences exist |
| Maintenance/repair | **designed only** | Repair advances a condition threshold with workmanship-derived `relief_m`; exposure/history never reset | No operations, prices, capacity, UI or diagnosis implementation |
| Parts UI | **implemented v1** | Market and Machine Index expose Designs, physical assets, serials, fitment and installation | No condition, service history, diagnosis or used-part pricing |
| Driving HUD | **implemented** | Bottom-left cluster: steering, km/h, brake/throttle, one tyre-window gauge, odometer; 1920×1080 fixed canvas | No warning-lamp region or warning payload exists |
| Setup Stu | **implemented in SP; authored for Online, not wired** | SP reads build summary, names a weak axis, suggests parts/tunes; Online archaeology defines truthful claim bounds | Online Stu may interpret authored/configuration facts and observations, not invent driver feel |

### A.2 Eleven deployed families versus twelve ontology families

The discrepancy is intentional:

```text
Twelve-family ontology
  power_unit, cooling, transmission, drivetrain, tires, brakes,
  suspension, steering, electrical, aerodynamics, structure, chassis

Eleven-family Parts v1 catalogue
  all of the above except steering
```

Steering is retained as a real mechanical family but refused by `parts.handling`: steering changes response,
while the proven carrier changes force magnitude. Mapping it to grip would make a false promise, and taking over
steering input is explicitly outside current authority. This report therefore gives the requested matrix for the
**eleven current Parts families** and keeps steering as a future ontology entry, not a hidden twelfth product.

### A.3 What a component means today

`component_design` currently owns identity, lineage, manufacturer, family, tier, scalar `effect`, price,
fidelity, positions and fitment. `component_asset` owns physical identity, custody/location, serial ordinals,
factory-original status, acquisition, `exposure_m` and lifecycle. Machine configuration history is already
immutable. These are the right identity boundaries.

The weakness is concentrated: `effect` is the entire mechanical vocabulary. `parts.handling.EXPRESSION` maps that
one scalar into a family-specific direction in four-lever space. That creates distinct families, but not distinct
products within a family except by magnitude. It also forces cooling and structure to act directly on final
levers even though their honest role is to modify other systems.

### A.4 Current physics and contextual inputs

Available and server-measured now:

- Machine identity, fitted configuration, authoritative position, speed, heading, occupancy and distance;
- derived whole-car lateral acceleration at 1 Hz;
- persistent world weather, binary wetness and seconds of day;
- derived air and track temperature;
- whole-car tyre temperature and its window position;
- race/session context, gate progress, incident bands and result provenance.

Available only on the simulating client or Carrier:

- throttle, brake, steering, RPM, gear and some suspension fields from the client snapshot;
- per-frame speed, signed longitudinal/lateral impulse and mass at the Carrier write site;
- richer client race telemetry, but its persisted stream currently contains position, speed, gear, on-ground and
  health—not pedal/RPM/slip channels.

The authority distinction matters. Client-only values can produce local feel, but persistent economic wear cannot
silently treat them as server-measured truth. They need an attested provenance or a new authoritative probe.

### A.5 Previous Wear & Tear design — what was already decided

The new design must retain these decisions from `20_WEAR_LIFECYCLE.md`, `22_WEAR_PROPOSAL.md` and `L120`:

1. Wear belongs to the **physical component asset**, never to a vehicle health bar.
2. Vehicle odometer and component exposure are separate histories; neither resets the other.
3. Exposure is additive and immutable. Condition and severity are pure derivations, never mutable columns.
4. Wear is deterministic from authored profile, component seed, exposure and service history; no periodic rolls.
5. Repair advances the affected condition's threshold by persisted `relief_m`; it never erases exposure.
6. Removal, storage, sale, trade and reinstallation preserve the asset and its history.
7. Wear is monotonic pressure and never beneficial. Terminal failure is rare and downstream.
8. Sporting incidents and persistent property damage remain separate. No blame-based collision damage.
9. Component assets and exposure shipped together—which Parts v1 has now done.
10. §AG5/§AG6 plus a soak pass before condition has mechanical or economic weight.

No previous document defines dashboard warning lamps, named severity stages or a per-family symptom taxonomy.
The older work deliberately left presentation undecided. The warning design in section E is therefore new, but it
is built on the old authority rather than replacing it.

### A.6 Defect found during this pass

`odometer.lua` holds up to 250 m / 60 s in a Machine-keyed pending accumulator. Its later transaction credits the
parts installed **at flush time**. `components.install` does not flush that accumulator before changing the
installed set. A driver can therefore travel, park, fit a component before the checkpoint, and give the new part
distance accumulated by the old one. This is `KB-163`. The fix belongs at the configuration-change boundary:
settle the Machine's pending exposure successfully before the fit transaction may replace any component.

---

## B. Behavioural-property matrix — the eleven current Parts families

These are candidate vocabularies, not a mandate to expose every value or build every model. “Now” means an input
already exists in a trustworthy enough form to prototype; “probe” means the input exists only client-side, only in
the Carrier, or has not passed a live gate.

| Family | Useful properties beyond a flat scale | Context/input | Eventual expression | First-pass stance |
|---|---|---|---|---|
| **Power unit** | output shape, response, heat generation, heat capacity, derate onset/slope, cooling demand, mass cost | speed now; RPM/throttle/load **probe**; ambient now | drive, small mass/grip trade, stress derate, possibly top-speed ceiling | Add thermal headroom before attempting a torque curve |
| **Cooling** | heat rejection at rest and with airflow, thermal mass, duct split, wet/ambient sensitivity, protected-system weights | speed, track/air temperature and weather now | modifies tyre/brake/powertrain thermal reducers; direct output only as fallback | Make this the first second-order family; no permanent “+power” property |
| **Transmission** | torque multiplication bias, shift interruption, ratio range, efficiency, engine-braking share, thermal capacity | speed now; gear/RPM/shift events **probe** | drive/brake shape and top-speed trade, heat derate | Keep current constant direction until gear telemetry is proven |
| **Drivetrain** | loss, compliance, torque capacity, locking tendency, traction delivery, thermal tolerance | speed now; delivered work/slip **probe** | drive/grip relationship, stress inconsistency | No claim of torque split or differential lock without per-corner/yaw authority |
| **Tires** | dry peak, cold/base grip, optimum/window, heat-up, cooling, cold/hot sensitivity, wet sensitivity, wear rate, degradation curve | track/air/wetness, speed and lateral load now; slip **probe** | grip + brake + traction contributors through temperature/weather/wear | First complete behavioural vertical slice; one set of four |
| **Brakes** | cold bite, peak, heat generation/capacity, cooling, fade onset/slope, wet recovery, wear sensitivity | deceleration/speed now; pedal and brake impulse **probe** | brake contributor that varies with temperature and condition | A separate brake-temperature body is required; tyre temperature cannot stand in |
| **Suspension** | load sensitivity, transient support, rough-surface tolerance, thermal consistency, condition sensitivity | whole-car lateral load now; vertical/suspension travel **probe** | context-dependent usable grip/brake/drive, not a constant bonus | Whole-car only; no anti-roll/front-rear claims |
| **Electrical** | control response, voltage/thermal robustness, fault tolerance, sensor stability, parasitic load | runtime/heat cycles now in principle; response telemetry **probe** | consistency/response or power availability under stress | Do not author “better electronics = more power” as the main identity |
| **Aerodynamics** | low/high-speed coefficient curve, drag/downforce trade, cooling airflow contribution, yaw sensitivity | speed now; yaw/slip **probe** | speed-dependent grip/drag/brake plus cooling assistance | Speed dependence is the minimum honest upgrade over the current constant wing |
| **Structure** | stiffness support, load sensitivity multiplier, mounting stability, fatigue resistance | lateral/load cycles now; roughness/impact **not trusted** | modifies suspension degradation under load | Second-order only; routine wear may be none in v1 |
| **Chassis** | mass realization, rolling resistance, platform stiffness, mounting tolerance, environmental protection | speed/distance now; actual mass write **unapproved** | all-axis inertia proxy and compatibility root | Track replaceable subframes only; never make “replace chassis” replace Machine identity |

Two deliberate non-features keep this bounded:

- **No generic reliability stat.** Reliability emerges from authored condition thresholds and stress response.
- **No requirement that every family wears.** Aero, structure or chassis assemblies may have no ordinary lifecycle
  until an objective stress channel makes one meaningful.

---

## C. Concrete first-pass tyre-compound model

### C.1 Design vocabulary

A tyre Design should contribute one immutable compound profile:

```text
dryPeak                 nominal contact-patch capability
coldFloor               retained capability far below the window
optimumC                centre of its useful temperature region
coldWidthC / hotWidthC  asymmetric window shape
heatGain                work-to-temperature response
coolingTau              return toward track temperature
airflowCooling          speed sensitivity of cooling
coldPenaltyShape        temperature response below optimum
hotPenaltyShape         response above optimum
wetLossDepth            water sensitivity at reference condition
wetTemperatureCoupling  how cold/wet interaction changes the wet loss
baseWearRate            durable exposure conversion
hotWearSensitivity      extra irreversible pressure above the hot band
degradationShape        how derived wear changes peak/window/sensitivity
```

This is authored simulation data. It is not a list of eleven UI stats, and the final grip/brake/drive values remain
outputs.

### C.2 Relative Hard / Medium / Soft shapes — no balance numbers yet

| Property | Hard | Medium | Soft |
|---|---|---|---|
| Dry peak | lowest of the three | middle | highest |
| Cold/base grip | usable but not instantly “on” | moderate | best initial response or quickest route out of cold |
| Optimum temperature | highest or hardest to reach | middle | lower/easier to reach |
| Working window | broad, especially hot-side | balanced | narrowest |
| Heat-up | slowest | middle | fastest |
| Cooling | resists rapid swings; tune only after testing | middle | sheds/accumulates heat quickly enough to be lively |
| Overheat sensitivity | lowest | middle | highest |
| Wear rate | lowest | middle | highest |
| Wear degradation | gradual; consistency is the selling point | balanced | peak and hot-side window erode first |
| Best use | long runs, hot sustained work, longevity | mixed conditions | short attacks, cold starts, qualifying-like use |

Medium must not become the automatic answer. Its cost should be that it neither reaches Soft's best short-run pace
nor Hard's sustained consistency/life. Whether that trade is strong enough is a play-test question, not something
to solve by adding arbitrary rock-paper-scissors bonuses.

### C.3 Wet-oriented compound

The current environment supports only a coarse dry/rain wetness of 0 or 1. That is enough to prove a different
relationship to water, but not enough for drizzle, drying line, standing-water depth or aquaplaning.

A first wet Design should therefore alter `wetLossDepth`, cold behaviour, heat-up/cooling and dry overheating. It
does **not** receive “+X grip in rain.” In full wet it loses substantially less of its available grip than a dry
compound; on a drying/hot surface it overheats or degrades sooner. Until wetness becomes continuous, call this a
rain compound, not an intermediate.

### C.4 Flow into final physics

```text
weather + time
  -> air temperature
  -> track temperature + surface penalty

speed + whole-car lateral load + compound thermal properties
  -> tyre-set temperature
  -> compound temperature response

wetness + compound wet properties
  -> compound water response

component exposure + services + seed
  -> derived tyre conditions/severity
  -> peak/window/wear-response degradation

installed tyre Design base capability
  × temperature response
  × water response
  × condition response
  -> tyre contributor to gripScale / brakeScale / driveScale
```

The road surface layer remains independent. A perfect wet tyre does not warm the asphalt, and a tyre in its window
on a freezing road still pays the road's penalty. All contextual multipliers should remain downward-only relative
to the Design's authored peak; that preserves the existing “window is absence of penalty” rule.

The tyre temperature state must stop being implicitly owned only by the Machine once sets become behaviourally
different. The smallest safe rule is: key active thermal state to `(machineAssetId, tireComponentAssetId)`, settle
the outgoing set to its current temperature on removal, and initialize an unknown/newly fitted set at current track
temperature. Persisting exact transient temperature across a server restart is unnecessary if restart settling to
ambient is explicit; persistent **heat-cycle/wear exposure** is separate and must survive.

---

## D. Wear model

### D.1 Reconcile the old scalar with the new stress-aware brief

Keep `component_asset.exposure_m` exactly as it is: actual travelled distance, additive and historical. Add a small,
closed, versioned vector of objective cumulative exposure channels rather than replacing it with a mutable health
value:

```text
distance_m             authoritative accepted distance
operating_s            occupied/simulating time
high_speed_work_q      bounded integral derived from speed
cornering_work_q       bounded integral from speed × lateral load
drive_work_q           requires a trusted/proven source
brake_work_q           requires a trusted/proven source
thermal_over_q         time × amount above an authored system threshold
thermal_cycles_q       bounded hot/cold cycle count where meaningful
```

Not every channel ships at once. Distance, operating time, high-speed and whole-car cornering work can be derived
from the current server sampler. Brake/drive work, RPM, shifting and slip remain probes because the richer sources
are client-local or Carrier-local.

For each authored condition `c`, the wear profile converts the relevant vector into a monotonic
**wear-equivalent metre**:

```text
effectiveExposureM(c) = distance contribution
                      + stress channels converted by the condition profile

effectiveThresholdM(c) = seeded base threshold + sum(service.relief_m for c)
active(c)               <=> effectiveExposureM(c) >= effectiveThresholdM(c)
severity(c)             = bounded curve(effectiveExposureM - effectiveThresholdM)
```

This preserves `L120`'s accepted `relief_m` interface without pretending every part aged only because a wheel
turned. Actual `exposure_m` remains factual distance; “wear-equivalent metres” are a derived condition clock and
must never be displayed as odometer mileage.

“Aggressive operation” is not itself a channel. It is a subjective label. High temperature, braking work and
sustained speed are objective channels. Race distance should be recorded for provenance/economy analysis, but it
must not wear a part faster merely because a race flag was present; only the measurable work done during that race
may do so.

Collisions remain outside ordinary wear. Existing incident and vehicle-damage signals are useful sporting evidence,
but using them to destroy persistent property would contradict `IDEA-280` and invite multiplayer griefing. A future
crash-damage system would need its own decision and insurance/attribution design.

### D.2 Per-family accumulation and degradation

| Family | Initial wear inputs | Later input after proof | Derived degradation can affect |
|---|---|---|---|
| Power unit | distance, operating time, high-speed work, over-temperature | RPM/load/drive work | heat generation, derate onset, sustained drive consistency; avoid random misfire theatre |
| Cooling | operating time, thermal load handled, over-temperature cycles | measured flow/load | heat rejection, cooling tau, protected-system temperatures; indirect effects first |
| Transmission | distance, operating time, high-speed work | shifts, RPM mismatch, drive work | delivery efficiency, heat, shift/response consistency; no fake gear behaviour yet |
| Drivetrain | distance, cornering/high-speed work | delivered torque/slip | driveline loss and stress consistency; no per-axle claim |
| Tires | distance, cornering work, temperature, hot exposure, wet running | slip work | peak, window width/centre, hot sensitivity, wet response; faster lifecycle than assemblies |
| Brakes | distance as fallback, speed/deceleration work, brake temperature | authoritative pedal/retarding impulse | cold bite, fade onset/slope, recovery, peak within tyre ceiling |
| Suspension | distance, cornering/load cycles | vertical travel/roughness | load sensitivity and consistency, not a flat “broken = less grip” step |
| Electrical | operating time, heat cycles | voltage/control faults | response/consistency and protected-system availability; likely very slow lifecycle |
| Aerodynamics | **none initially** | only an objective non-collision stressor if one is found | condition may remain inspection-only; no mileage tax for a wing |
| Structure | **none initially** | fatigue only if a trustworthy load-cycle model is justified | support for suspension/load sensitivity; ordinary crash damage remains separate |
| Chassis assemblies | distance only for provenance, **no ordinary consequence initially** | roughness/load cycles if proven | subframe/mounting support; never Machine identity or generic car death |

### D.3 Condition vocabulary

Do not adopt generic stages such as “healthy / worn / critical” as stored truth. Store stable condition IDs such as
`tire_peak_loss`, `brake_fade_early`, `cooling_heat_rejection_loss` and derive their severities. Presentation can
collapse those facts into three operational states:

- **normal** — no lamp;
- **attention** — condition is observable/service-worthy, amber system lamp;
- **critical** — material effect or near-term service need, red system lamp with non-colour shape change.

That keeps diagnosis mechanical while keeping the driving HUD simple.

### D.4 Update and transaction boundary

The sampler should accumulate one Machine stress delta, then apply it to the component assets that were installed
during that interval. Configuration change is a hard accounting boundary:

1. stop/settle the current sampling interval;
2. atomically persist odometer + component exposure for the outgoing configuration;
3. only after success, commit the new immutable configuration revision;
4. begin the next interval against the new installed set.

This closes `KB-163` and prevents every future exposure channel from inheriting the same attribution bug.

---

## E. Warning-light taxonomy

The existing Wear documents define no lamp taxonomy. The clean mapping is system-level, not one lamp per family.
Eight marks are a plausible maximum for the identified space, but the initial useful set is seven system lamps plus
one master-service mark.

| Glyph/system | Triggering components | Attention condition | Critical behaviour | Detailed diagnosis |
|---|---|---|---|---|
| **Master service / wrench** | any; also unknown/unmapped condition | service-worthy condition exists, or several minor systems combine | filled/`!` variant when any critical condition exists | Parts Inventory summary, then Stu |
| **Engine / motive power** | power unit; related electrical control fault | output/thermal margin degraded | sustained drive materially derated | Machine detail + Stu |
| **Drivetrain / gearbox** | transmission, drivetrain | delivery/heat/consistency condition | substantial delivery loss or service-required state | component detail + Stu |
| **Brake** | brakes; cooling may contribute causally | fade threshold or available braking degraded | braking materially compromised | component detail; causal chain can identify cooling |
| **Tyre** | tire set | peak/window/wet performance degraded or set nearing service | material contact-patch loss | tire-set card, compound/wear history |
| **Temperature / cooling** | cooling, plus active power/brake/transmission overheat | system is running hot or heat rejection is degraded | current overheat/derate, not merely future service | live thermal panel + Stu diagnosis |
| **Electrical / control** | electrical | control/sensor/power condition | motive/thermal system materially affected | electrical component card + Stu |
| **Chassis / handling** | suspension, structure, replaceable chassis assemblies, aero where applicable | load response/structural support degraded | material handling compromise | Machine configuration/inspection; Stu |

Aerodynamics does not deserve a dedicated lamp merely to make the count match the parts catalogue. A passive wing
has no real dashboard sensor in the current model; its service condition belongs under chassis/handling or the
master wrench. Cooling may light both temperature and the affected system only when that communicates two distinct
facts: **the car is hot now** and **a component requires service**.

### E.1 Severity language

- Absent: normal.
- Amber outline: attention; service is worth investigating.
- Red filled/inner-mark variant: critical; performance is materially compromised or service is urgent.
- Do not rely on colour alone. Critical needs a changed silhouette or inset `!`; animation should be restrained.
- A new lamp may receive one brief toast/message when it first crosses state. It must not chatter each sample.

### E.2 HUD placement

`race.html` is a fixed 1920×1080 transparent page. The bottom-left `#inputs` cluster begins at `left:44px,
bottom:252px`, contains wheel, speed, brake/throttle and tyre gauge, and sits above the odometer. The vertical race
graph uses the same 152 px column farther up.

Add a compact, transparent `#wear-lamps` strip immediately above/over the speed-side of `#inputs`, flowing left
toward the pedal region. It must not change `#inputs` width, `min-width`, the graph, or the odometer. Use the existing
24×24 SVG grammar at roughly 14–16 px marks with a small fixed gap. If the initial seven/eight cannot remain legible,
wrap a second row over the steering-wheel half rather than widening the box. Exact geometry requires render-harness
and in-engine 1080p/1440p/ultrawide checks.

The HUD answers only: **which general system needs attention, and how urgent is it?** It never prints condition
percentages or failure thresholds while driving.

---

## F. Persistence model

| Scope | Owns | Must not own |
|---|---|---|
| **Component Design / type** | immutable behavioural profile, wear profile, compatibility, production spec, supported condition IDs and effect mappings | individual condition, exposure, owner, current temperature |
| **Physical component asset** | serial identity, manufacturing realization/seed, cumulative exposure vector, service history, installation/ownership history, lifecycle state | vehicle odometer; mutable generic health |
| **Machine / vehicle asset** | identity, odometer, provenance, current configuration pointer/history, vehicle-level transient context where genuinely shared | resetting component exposure; a summed car-health percentage |
| **Driver/account** | ownership/custody, engineering competency and design knowledge, diagnosis visibility, service authorship | mechanical truth about the asset; wear reset on transfer |

### F.1 Removal, sale, trade and refit

- Removing a part changes location only. Exposure, seed, service and provenance remain.
- Selling/trading transfers custody of the same `asset_id`; condition does not reroll and no replacement is minted.
- Installing on another compatible Machine resumes from the same cumulative history.
- Listings should expose only what the seller/buyer is entitled to know: serial/provenance and observable/inspected
  condition, not the hidden seeded threshold.
- A replaced power component never changes chassis odometer. A low-mile component in a high-mile Machine is valid.
- Configuration revisions already preserve which physical asset occupied each interface; future operation/service
  rows supply the biography without rewriting old revisions.

Transient temperatures are not the same as durable exposure. They may cool to ambient across long absence/restart;
hot-time and heat-cycle exposure, once checkpointed, remains permanent.

---

## G. Economy and service implications

### G.1 Service actions

Use a small operation vocabulary, not a refill button:

- **inspect/diagnose** — reveals condition IDs and causal relationships to the depth justified by Engineering
  knowledge;
- **service** — low-cost preventative work that may slow a not-yet-active condition or address a serviceable one;
- **repair** — a committed operation against one identified condition, producing the accepted `relief_m`;
- **replace** — swaps physical assets; removed hardware survives;
- **remanufacture** — later, high-cost project that may justify a new realization/seed only if explicitly ruled;
- **salvage/consume** — explicit irreversible operation, never an automatic consequence of removal.

### G.2 Used parts and pricing

A used component should be economically legible through evidence, not a universal discount formula. Useful listing
facts are exposure, service count/history, known active conditions, inspection confidence, factory-original status,
maker/design/serial and provenance. Markets may price that evidence differently:

- a general Base Market can prefer new/known stock;
- a salvage/Patch market can carry high-exposure or partially diagnosed assets cheaply;
- a historically meaningful factory-original part may retain collector value despite wear;
- an undiagnosed part is uncertainty, not automatically junk;
- a repaired part remains old and may be perfectly usable.

Automated NPC offer prices should use broad condition bands and market appetite, never reveal hidden thresholds via
perfect valuation. Player-to-player trade remains voluntary; NCM guarantees conservation and atomicity, not fairness.

### G.3 Pacing: maintenance must be a long arc

Calibration must start from `IDEA-234`: measure kilometres per hour of actual Night City play and race lengths.
Real-world service intervals cannot be imported blindly. Recommended pacing rules:

- ordinary driving should move exposure continuously but rarely light a lamp;
- tires and perhaps brakes are the circulation categories; major assemblies should span many sessions;
- severe, objectively measured thermal work accelerates only the relevant condition;
- no more than one or two systems should normally demand attention in the same play arc;
- preventative service may be bundled at natural garage/Setup Stu visits;
- the car remains driveable through attention states; critical conditions degrade behaviour before rare failure;
- no cascading failure in v1. Cooling may worsen temperatures elsewhere, but one neglected pump must not instantly
  destroy six serialized assets.

Stu is the correct diagnosis voice. He can connect causal layers—“the cooling setup is cooked and it is pulling
the power unit out of its window”—while remaining bounded by Machine Knowledge: configuration and authored effects
are facts, observations are phrased with their basis, and felt-driver judgments remain his clearly stated opinion.

---

## H. Smallest coherent architecture

### H.1 Four shared concepts, not eleven engines

1. **Behaviour profile** — immutable, versioned Design data. Family schemas validate a small property vocabulary;
   unknown properties fail closed. Existing scalar `effect` becomes a compatibility projection, not the source of
   truth for new Designs.
2. **Context reducers** — a few reusable pure kernels: thermal body/window, speed/load response, environmental
   response and derived wear pressure. Families configure or modify these kernels.
3. **Component state** — serialized asset identity plus additive exposure vector and append-only services. Runtime
   transient state is keyed to the Machine/system and, where swapping matters, the installed component asset.
4. **Expression adapter** — the sole existing `parts.handling` composer turns reducer outputs into bounded
   `gripScale`, `driveScale`, `brakeScale`, `dragScale` and top-speed target contributions, with trace/provenance.

```text
Design behaviour profile + manufacturing realization
                         + installed configuration
                         + derived component conditions
                                      |
                                      v
                 Machine behavioural profile (pure resolve)
                                      |
world state + motion/work samples --->+---> shared context reducers
                                      |       tyre thermal / brake thermal
                                      |       powertrain thermal / speed-load
                                      v
                         named contributor layers
                                      |
                                      v
                        parts.handling sole composer
                                      |
                                      v
                  carrier / governor / simulated outcomes
```

Cooling and structure prove why this layering matters: cooling modifies heat rejection in several reducers;
structure modifies suspension load sensitivity. Neither needs a bespoke physics engine or a dishonest permanent
direct-force bonus.

### H.2 Suggested delivery sequence after owner approval

1. Fix and live-test the exposure/configuration boundary (`KB-163`), then complete §AG5/§AG6 and soak.
2. Add profile validation and a **single tyre compound reducer** while retaining current factory/launch Designs via
   an exact legacy adapter.
3. Author Hard/Medium/Soft as test Designs; no market/economy tuning yet.
4. Add durable tyre exposure/derived condition with information-only presentation first, as `A5` permits.
5. Map tyre condition into the same compound properties, then enable the physical consequence only after live proof.
6. Add the lamp reducer/payload and compact HUD strip; detailed diagnosis stays in Parts/Stu.
7. Add a separate brake thermal body, then cooling as a modifier of tyre/brake/power thermal systems.
8. Generalize only the kernels the first three families actually share. Do not prebuild the full matrix.

---

## I. Risks, unknowns and required probes

| Probe / decision | Why it blocks safe implementation |
|---|---|
| **§AG5/§AG6 plus long odometer/exposure soak** | Accepted gate before wear has economic or mechanical consequence |
| **Flush-before-fit/restart/reclaim proof** | `KB-163` shows distance can currently cross a configuration boundary |
| **Current Parts §AZ/§BF live tests** | Wear must not be built on an unproven purchase/fit/restart/conservation path |
| **Compound thermal replay harness** | Must prove deterministic Hard/Medium/Soft ordering across cold, sustained, cooling and wet scenarios before balance |
| **Binary wetness limitation** | Current rain/dry signal cannot support intermediate, drying line or standing-water claims |
| **Brake-work authority probe** | Pedal and retarding impulse are client/Carrier-side; persistent wear needs explicit provenance and anti-reroll handling |
| **RPM/gear/shift availability and trust** | Blocks honest transmission and power-unit delivery/thermal properties |
| **Slip-velocity availability** | Current tyre load proxy over-heats pure rolling and under-heats a locked wheel |
| **State-dependent Carrier proof (`IDEA-532`)** | Speed-dependent aero and per-frame fade need fixed-formula coefficient evaluation, bounded cost and clean restoration |
| **Thermal ownership on part swap** | Current tyre temperature is Machine-keyed; compounds require explicit outgoing/incoming set semantics |
| **Top-speed live gate** | Aero/transmission properties must not promise a ceiling path that stores but does not enforce |
| **Per-corner boundary** | Still unavailable. No brake bias, anti-roll, torque split or individual tyre condition in the first model |
| **Checkpoint/database cost** | Eleven installed assets times several counters can multiply writes; benchmark before choosing row-per-channel storage |
| **Condition privacy/knowledge rules** | Market, owner, observer and Stu must not all receive omniscient hidden condition truth |
| **Pacing study (`IDEA-234`)** | Without real km/hour and race-distance data, any threshold is chore-simulator guesswork |
| **HUD visual/accessibility pass** | Fixed 1080p layout, small glyphs, colour-blind severity and ultrawide behaviour need render + in-engine evidence |

### Final recommendation

Proceed conceptually with the behavioural layer, but make **tyre compounds the only first complete slice**. They
reuse the server-owned thermal/weather model, have a proven live expression path, and expose the exact architectural
need: one Design changes a reducer's parameters, context changes the reducer's state, and only then do final physics
scales change.

For Wear & Tear, retain the accepted pure/derived lifecycle and widen its input from factual distance to a small
bounded set of objective additive stress channels. Do not store health, do not roll failures, do not punish “bad
driving,” and do not make all eleven families decay for symmetry. The odometer remains the Machine's distance.
Component exposure records what each physical part lived through. Derived conditions—and the way the car behaves
under temperature, weather, load and age—are how the Machine shows what that history did to it.
