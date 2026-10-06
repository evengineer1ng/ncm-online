# 48 - The engineering envelope: what can physically be built out of a Cyberpunk car

> **STATUS: SPEC** - owner intent, captured 2026-10-04 (L311). **Not authorised; do not implement; do not contradict.**
> **Q1-Q5 RULED (L311 addendum):** the envelope supersedes one-per-family; measure mass first; envelopes per car model; anchored cars survive as before; sequencing = manual audio and shift feel, then the pass.
> §2-§5 are coder notes: §2-§3 are evidence, and §4-§5 are PROPOSAL with no authority until ruled.
> Authority map: [INDEX.md](INDEX.md). Builds on: L120, L134 (knowledge, fabrication), L153 (Foundry), L162 (Parts as a
> conserved economy), L306 (NCM Gearbox), doc 47 (campaigns). Ideas: IDEA-959 to IDEA-972.
> Civil engineering (the same grammar pointed at the city: barriers, fences, sockets, load) is captured in [49_CITY_MEMORY.md](49_CITY_MEMORY.md) §7 (L313, SPEC).

---

## 0. The owner's statement (verbatim, 2026-10-04)

> Yes. I think the manual-transmission work just exposed the missing abstraction for **the entire engineering game**.
>
> And first, your physical intuition is right. A passenger-car transmission is not a little electronics module. Depending on architecture, a complete transmission/transaxle can easily live in roughly the **50–120+ kg** territory, with high-performance units varying considerably. An F1 gearbox is an exotic lightweight structural component, but even there you're dealing with tens of kilograms, not fairy dust. So carrying an additional conventional gearbox absolutely should hurt.
>
> But I would go one step further: **NCM should stop thinking primarily in terms of "11 part slots."** The car should have an **engineering envelope**.
>
> **The car becomes a physical engineering problem.** Every vehicle gets a hidden/visible engineering specification describing what can physically exist inside it. Think of the car from above, perhaps with additional side/elevation information later (cooling, power unit, gearbox, driveline, battery/fuel, rear systems). Components possess actual properties: **geometry, dimensions/volume, mass, mounting requirements, compatibility, connections, thermal output, power demand, structural load, and performance characteristics.** The chassis possesses: **available geometry, mounting points, weight capacity, cooling capacity, electrical capacity, driveline topology and perhaps eventually structural limits.** Now installing a component means answering: > **Can this thing physically and functionally live in this car?** That's the connective tissue you're describing. Your existing 11 categories don't disappear. They become the **major systems of the car**, while engineering determines what actually fits inside those systems.
>
> **Cyberware is exactly the useful analogy.** Cyberpunk's cyberware system gives you a fantastic UX vocabulary for this. A human doesn't merely have slots; there's also **cyberware capacity**. Call the broad concept something like **Engineering Capacity**, but don't reduce it to one number. A car might have: **Mass budget, Packaging volume, Power capacity, Cooling capacity, Structural capacity, Control/electronics capacity.** So the player sees something analogous to cyberware capacity, while underneath it is a multidimensional engineering model. A giant gearbox might fit geometrically but put the car overweight. A tiny experimental gearbox might fit beautifully but produce too much heat. An enormous power unit might physically fit after removing something else but exceed cooling capacity. A prototype controller might weigh virtually nothing but consume significant electronics capacity. That's where builds emerge.
>
> **Geometry is the killer idea.** I would absolutely prototype your **engineering CAPTCHA**. Not as a frustrating CAPTCHA, obviously. As a little tactile packaging puzzle. Give every significant component a simplified 2D footprint. Not CAD. Don't simulate bolt threads. Maybe components are composed from simple polygons (a standard 6-speed, a race transaxle, a micro range box). You drag it onto the car's engineering envelope. **Green:** valid. **Yellow:** possible with adaptation. **Red:** impossible. Rotation matters. Orientation might matter. Connections matter. Suddenly the sentence **"I think I can fit another gearbox in here"** becomes literal gameplay. That is infinitely more satisfying than: > Transmission Slot II unlocked at Engineering Level 37.
>
> **And now we return to your insane gearbox.** A normal street transmission might be: Mass 82 kg, packaging large, ratios 6, shift time 320 ms, torque capacity moderate, cooling passive/moderate. Someone tries installing another one. Sure. Now they're hauling **164 kg of transmission**. Congratulations on your twelve gears. Your car weighs as much as a small moon. Acceleration suffers. Braking suffers. Tire loading changes. Fuel consumption rises. Weight distribution moves. Perhaps cooling suffers. And importantly: **you haven't created horsepower.** A transmission transforms the relationship between engine torque and wheel speed. It can let the engine operate in advantageous regions and give you appropriate ratios for a much wider speed envelope, but another gearbox isn't another engine. So the stupid build is allowed. That's important. Don't say: > "You cannot install two transmissions." Say: > **"It fits."** And let physics deliver the punchline.
>
> **Then somebody discovers the ghost gearbox.** Maybe there's an absurd prototype transmission that players call a **ghost box** because it's unbelievably compact/light. Not literally zero kilograms. Standard competition gearbox 65 kg; advanced race gearbox 42 kg; prototype 2077 composite/electromechanical range box 14 kg. Fourteen kilograms isn't interesting because its stats say **LEGENDARY +25 SPEED**. It's interesting because an engineer immediately looks at it and thinks: > Holy shit. **I can put this somewhere nobody could put a gearbox before.** That's real item desirability. The geometry itself becomes a stat. A weird L-shaped component can be extremely valuable because it fits around another system. A long skinny battery might be preferable to a technically superior rectangular battery because the rectangular one blocks your second transmission. Now your parts market becomes a **Tetris market**.
>
> **Reverse engineering finally has a purpose.** Suppose somebody acquires that 14 kg prototype gearbox. A racer sees: > Great gearbox. An engineer sees: > **How the fuck did they make this gearbox?** They can tear it down. Reverse engineering reveals progressively deeper information: **Stage 1:** dimensions, mass, basic materials. **Stage 2:** ratio architecture, thermal properties, torque tolerance. **Stage 3:** manufacturing method, controller architecture, internal topology. **Stage 4:** reproducible design principles. But reverse engineering doesn't necessarily produce: > `Ghost Gearbox Recipe Unlocked` That's too videogamey for what you're building. Maybe the engineer learns enough to make: **Kimiko Experimental Rangebox Mk I** It's 22 kg. Worse than the original 14 kg specimen. But they fucking made it. Then engineering progression improves manufacturing tolerances, material use, packaging and reliability. Mk II becomes 19 kg. Someone else copies the architecture but changes the geometry because they need it to fit a Quadra. You've now created **actual engineering lineages**.
>
> **And gearboxes are only the first pillar.** This is the revelation from today's manual transmission work. You have just proven that a previously opaque Cyberpunk system can potentially become **NCM-owned simulation**. That suggests the engineering pillars aren't merely Parts 1–11. They're systems that NCM can progressively take authority over: **Powertrain** (engines/motors, power delivery, torque curves, rev limits, boost, energy systems); **Transmission** (ratios, final drive, gear count, shift behavior, clutch, sequential/H-pattern, range boxes, multi-transmission abominations); **Tires** (compound, dimensions, thermal window, wear, wet behavior, pressure eventually); **Brakes** (mass, heat capacity, stopping performance, fade, cooling); **Aero** (drag/downforce relationship, active systems eventually, physical packaging); **Cooling** (radiators, intercoolers, ducting, pumps, thermal capacity -- enormously important once power stops being free); **Suspension** (geometry abstractions, stiffness, damping, ride height, load transfer); **Fuel/energy** (tank/cell size, fuel mass, battery mass, consumption, range); **Electronics/control** (ABS, traction control, gearbox controllers, active aero control, telemetry, potentially vehicle quickhack defenses); **Structure** (chassis reinforcement, mounting capability, crash resistance and the thing everything else ultimately attaches to); and perhaps eventually **Human interface** (wheel, pedals, shifting hardware, assists, steering ratio -- which connects directly back to Devices and Rig Bridge). You have pieces of half of this already.
>
> **Engineering therefore has three layers.** **1. Acquisition:** find, buy, win, steal, salvage, trade or discover interesting technology. **2. Understanding:** inspect it, test it, measure it, reverse engineer it, learn why it behaves the way it does. **3. Integration:** make the damn thing work in a particular car. And **integration is where your geometry game lives**. The best engineer isn't necessarily the person possessing the highest-tier parts. They're the person who looks at: 41 kg remaining mass budget; an awkward wedge-shaped cavity; insufficient cooling; one spare driveline connection; a 19 kg range box; an undersized radiator; and a completely unreasonable customer request… and says: > **I can make that fit.** That's engineering.
>
> **And then your temporal campaign makes this even better.** Because NCM campaigns are temporary. Imagine the campaign starts. Nobody has much. Day 1 is junkyard engineering. Someone discovers a bizarre transmission. An engineer tears it apart. By Day 2, their team has produced a crude derivative. By Day 3, somebody has built the first viable dual-range car. If the campaign survives to Day 5, that architecture starts spreading through the paddock. By Day 7, the fastest cars may bear almost no engineering resemblance to what entered on Day 1. Then the campaign ends. **The cars disappear/reset appropriately.** But perhaps engineering knowledge doesn't disappear identically. That's an enormous progression-design question for later, because you can choose exactly what survives between campaigns: blueprints, engineering knowledge, manufacturer reputation, discovered principles, nothing, or some mixture. That gives your roguelite comparison real teeth. A campaign isn't merely races happening for 72–168 hours. It's a **compressed technological era**.
>
> And this gives me a very specific recommendation about when to tackle engineering: **Soon, but don't implement the whole thing soon.** Manual transmission should finish enough to establish what an NCM-owned drivetrain actually looks like. Then I would schedule an **Engineering Architecture pass** before you add another pile of unrelated part features. Because the question has changed. It used to be: > "What stats should our 11 part slots modify?" Now it's: > **"What can physically be built out of a Cyberpunk car?"** That's a much larger design space, but paradoxically a much clearer one. And the double/triple gearbox isn't the system. It's the first wonderfully stupid machine that **proves why the system needs to exist.** ⚙️📐🏎️

## 1. Invariants (SPEC, restated from §0; do not contradict)

1. **An envelope, not slots.** A car has multidimensional engineering capacity: mass, packaging (geometry), power,
   cooling, structure and electronics. The 11 families remain as the car's major SYSTEMS, and the envelope decides what
   fits inside them.
2. **Components are physical.** Geometry (a simple 2D footprint), mass, mounting, connections, thermal output, power
   demand, structural load and performance.
3. **"It fits."** A stupid build is allowed whenever it physically fits, and physics delivers the punchline. Nothing is
   refused by rule that physics could answer.
4. **Geometry is a stat.** A shape that fits where nothing else does is valuable for that alone; the market becomes a
   Tetris market.
5. **Packaging is a tactile puzzle,** not CAD and not a level gate: drag, rotate, orient; green / yellow / red; and
   connections matter.
6. **Three layers:** acquisition, understanding (staged reverse engineering, 1-4) and integration. The best engineer
   is the one who makes it fit, not the one with the highest-tier parts.
7. **Reverse engineering yields lineages,** not recipes: a worse first copy (Mk I), improving through manufacturing
   progression (Mk II), and forks reshaped to fit other cars.
8. **NCM takes authority over systems progressively.** The manual transmission is the first proof. The pillars are
   powertrain, transmission, tires, brakes, aero, cooling, suspension, fuel/energy, electronics/control, structure and
   human interface.
9. **A campaign is a compressed technological era.** What survives between campaigns is a later decision.
10. **Sequencing (owner's recommendation):** finish the manual enough to define an NCM-owned drivetrain, then hold an
    **Engineering Architecture pass** before adding more unrelated part features.

## 2. What already exists (evidence)

| Spec element | In the tree today | Where |
|---|---|---|
| 11 families / systems | Parts families with catalogue, compatibility, R&D, thermal, wear and handling (the instance channel). | `ncm/core/parts/*`; L162, L178 |
| Live physics levers | Carrier scales drive, brake, grip and drag, and caps top speed, per seated machine, every physics step (downward only). | `physics_probe.cpp`; MASTER_TEST §AU/§AW; L148-L152 |
| Record levers | Drive-model flats per record at spawn (machine.projection), gear-chain edits and the gear floor. | `machine.projection`; Carrier `TweakStore::applyGears` |
| An NCM-owned drivetrain | The manual: a clone with one long native gear and virtual gears through Carrier (0.2.x). The engine's gearbox is bypassed, not written. | L306 addenda; KB-330 |
| Understanding / reverse engineering | L134: knowledge is not capability; staged evidence; fabrication with poor / neutral / junk outcomes; a persistent failed asset; destructive analysis. | L134; docs 32-33 |
| Lineages | Foundry: vehicle R&D over existing geometry, design identity and lineages (L153; Proposal 38). | L153; doc 38 |
| Assets with provenance | Conserved parts economy: every part is an asset with an id, a maker and provenance. | L162 |
| Campaign reset | Racing Week archive: what moves with the run vs. what stays (knowledge stays, cars and parts go unless anchored). | doc 45 §P; doc 47 |
| Thermal | `parts.thermal` exists (family heat, not a vehicle cooling budget). | `ncm/core/parts/thermal.lua` |

## 3. What the spec needs that nothing in the tree has (evidence gaps)

| # | Need | State | How it would be answered |
|---|---|---|---|
| E1 | **Mass as physics.** A 164 kg double gearbox must slow acceleration, lengthen braking and change load. | No mass lever. Carrier reads body mass in its probe but has never written it. | Measure whether the rigid body's mass can be written per instance (Carrier's body, read-only first). Else approximate a mass delta through drive / brake / grip scaling (F = m·a): honest about being an approximation. |
| E2 | **Per-car envelope data:** cavity geometry, mass budget, cooling and electrical capacity. | None. | Author per body class (a handful of templates), then per model as needed; the machine catalogue is the anchor. |
| E3 | **Per-component physical data:** footprint polygon, mass, connections, heat, power demand. | Parts have families and effect directions, not physical properties. | Extend the part design record; generated from the family plus a design seed (L134: truth server-private). |
| E4 | **Multiple components of one family** (two gearboxes). | The fitting model is one part per family slot (L162). | The envelope replaces "slot" as the fitting rule; the family becomes a system that can hold several components. |
| E5 | **Connections / topology** (driveline in to out, cooling loops). | None. | A small graph per car: ports on components and on the chassis. |
| E6 | **The packaging puzzle UI.** | None. | A WebUI surface (the F6 shell pattern), 2D only, drag / rotate / snap, validity coloured live. |
| E7 | **What a second gearbox DOES** (range box / splitter: ratios multiply). | The manual has one virtual gear table. | Virtual gearbox composition: a range box multiplies the main box's table. That is data in `manual.cpp`, now that the drivetrain is NCM's. |

## 4. Tensions to rule on (PROPOSAL)

- **Q1 Slots vs envelope (L162).** L162's conserved economy keeps one fitted part per family. The spec's "it fits" needs
  the envelope as the fitting rule. *Recommendation:* the envelope supersedes the one-per-family rule; family
  identity stays.
- **Q2 Mass physics.** E1 decides whether mass is real physics or an approximation through drive and brake. Owner call
  after the measurement.
- **Q3 Authoring scale.** Per body class first (about 6-8 templates), or per model from the start?
- **Q4 What survives a campaign** (blueprints, knowledge, reputation, principles): explicitly deferred by §0; doc 45 §P
  already keeps knowledge and drops cars.
- **Q5 When.** §0 says: finish the manual first, then an Engineering Architecture pass before more part features.
  *Recommendation:* the manual's audio and shift feel, then the pass. The pass's first deliverable is a reviewable
  architecture doc, not code.

## 5. The Engineering Architecture pass, if authorised (PROPOSAL)

1. E1, the mass measurement (read-only, on Carrier's bound body).
2. The data model: envelope, component physics and ports, as pure `ncm/core` with tests. Two cars and five gearboxes as
   fixtures, including the 14 kg ghost box and the double gearbox.
3. The fitting rule (green / yellow / red with reasons) over that model, offline.
4. The puzzle surface, read-only first (show what is fitted and why), then drag and rotate.
5. Physics hookup: mass delta to Carrier; range-box composition to the Gearbox.
