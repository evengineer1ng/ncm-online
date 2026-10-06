# 54 - Engineering II: physical machines, Snowglobe motorsport, one physics across runtimes

> **STATUS: SPEC** - authority for: *Engineering II (machines assembled from physical systems; the four ways to push; lineage and reverse engineering across worlds), the seed tree and world composition, Snowglobe as a motorsport environment (3D courses, NPC racing with provenance, sport formed from capability), and the cross-runtime physics contract (host expression losses)* - owner brief "NCM ENGINEERING / SNOWGLOBE / CROSS-RUNTIME EXPANSION", 2026-10-05 (L321).
> **L323:** the six L322 host boundaries cleared or narrowed (§Q, §S): contact, multiplayer, clock sync, the live cross-server link and Three Cities, life support and EVA, and the Badlands Sky Sprint in Cyberpunk.
> **Part two (L322):** Snowglobe disciplines (Sprint, Fireball, Relay, Triathlon, the open point-to-point slot), NPC drivers across domains, one race at three fidelities, unseen history (§L-§R); live in `ncm_ls_space` 0.4.0.
> The design sections are a PROPOSAL marked **KEEP / EXTEND / GENERALIZE / SUPERSEDE / NEW / UNKNOWN**. The built parts are tested in core (gate ALL GREEN) and live on the Los Santos dev server (`ncm_ls_space` 0.3.0); **no live PASS yet** (MASTER_TEST §EG1-§EG3, §SR1-§SR4).
> Code: `ncm/core/world/seed.lua`, `engineering/{systems,machine,dynamics,lineage,hosts}.lua`, `space/{course,genesis,racesim,sport}.lua`, `ncm/fivem/resources/ncm_ls_space/`. Related: [50](50_ENGINEERING_ARCHITECTURE.md), [51](51_THE_CAUSAL_TUNNEL.md), [52](52_CROSS_WORLD.md), [53](53_LOS_SANTOS_SPACE.md), [33 §11.3](33_PARTS_ENGINEERING_FINAL_RECONCILIATION.md).

**North Star.** A machine is understood from what it physically is:
- what it weighs and where;
- what produces force, where that force is applied, and which way;
- what that does to rotation;
- what stores energy, what carries propellant, what makes heat and what removes it;
- what it can therefore do, and for how long;
- what fails first;
- what another engineer can learn from it.

Everything else (sport, history, the week) is downstream of those answers.

## A. Archaeology: what already existed, and what this pass does with it

| Existing | Where | Verdict |
|---|---|---|
| Hash streams keyed by namespace, never by draw order | `vocabulary.hash`; `paddock.world` per-entity streams | **KEEP**. The seed tree is built on it. The robust hierarchical seed the brief asks for was half there. |
| Bodies with loads `{pos, dir, magnitudeN}`, 3D shape and CoM, an opaque `perf` per kind, never `allowsX` | `engineering.body` (L314) | **KEEP**. The machine's wrench table reads body loads directly. |
| Capacities and fit | `engineering.fit` | **KEEP** (cars); machines add a rated structural load. |
| Cause / actuator / state with expression losses | `engineering.actuate` (mass, lift) | **GENERALIZE** into `engineering.hosts` (per-host channels, measured limits, `express`). |
| 12 engineering families (L120 LOCKED: 27 numbers per engineer) | `engineering.competency`, `parts.ontology` | **KEEP / EXTEND** (§B). New physical families are open taxonomy (L314 R5); engineer competency for them is an **owner ruling** (§K). |
| Design / lineage / asset identity; reconstruction vs derived design | doc 33 §11.3; `competition.machine_knowledge` | **EXTEND** into `engineering.lineage` with origin worlds, `adapted_for`, and reverse engineering as estimation. |
| Seeded abstract race (incidents, DNFs, replay) | `paddock.sim` | **KEEP, reused unchanged**. Snowglobe racing is a Paddock race whose car term comes from physics. |
| Continuous race state, physical promotion via anchors, per-stretch provenance | `paddock.racestate` | **KEEP, reused unchanged**. Results say simulated / mixed / physical. |
| Planar gates (x, y, heading) | `course.gates` | **KEEP** for streets. **NEW** `space.course` for 3D gates. |
| Compressed Earth, radial gravity, integrator, anchors | `space.universe` 0.3.0 (L320) | **EXTEND** (0.4.0): an atmosphere (density by altitude, a world constant). |
| The F0 lift rig as "thrust" | `engineering.fixtures.f0_lift_rig`, Thrust, `ncm_ls_space` 0.2.0 | **SUPERSEDE as a technology**. It stays an **instrument** (`/ncm.machine instrument`) for measuring hosts. |

## B. The periodic table: what a part IS vs what it DOES

A body's **family** says what it IS (taxonomy, open). Its **perf kind** (`engineering.systems`) says what it DOES physically, in SI units. The two are independent: a ground ram can be family `suspension` and kind `ground_ram`, and a lift fan family `aerodynamics` and kind `propeller`.

**Families:**
- **KEEP:** the 12 L120 families: power_unit, cooling, transmission, drivetrain, tires, brakes, suspension, steering, electrical, aerodynamics, structure, chassis.
- **EXTEND** subfamilies within them:
  - cooling → radiators split into radiative and convective parts;
  - structure → a rated load;
  - aerodynamics → lift surfaces and propellers;
  - suspension → ground rams.
- **NEW** (open taxonomy; competency ruling pending): `propulsion` (reaction engines, tanks), `energy_storage` (batteries, flywheels, pressure), `avionics` (attitude control, guidance; reserved, nothing built).

**Kinds (what it does), as built in `engineering.systems`:**

| Kind | Push | Needs | Required (SI) | Optional |
|---|---|---|---|---|
| reaction_engine | reaction | propellant | thrustN (vacuum), ispS, propellant | seaLevelFactor, heatKw, minThrottle, throttleTauS |
| jet | atmospheric | atmosphere, propellant | thrustN (sea level), ispS, propellant | heatKw |
| propeller | atmospheric | atmosphere, energy | thrustN (sea level), powerW | heatKw |
| ground_ram | ground | contact, energy | energyJ, forceN, strokeM | chargeW, heatKw |
| energy_store | - | - | capacityJ, maxPowerW | rechargeW |
| propellant_tank | - | - | capacityKg, propellant | fill |
| power_source | - | fuel (optional) | outputW | propellant, consumptionKgPerJ, heatKw |
| radiator | - | - | radiativeKw | convectiveKw (scales with density) |
| aero_surface | - | atmosphere | areaM2, cl, cd | - |
| structure | - | - | ratedLoadN | impactJ |

## C. The canonical quantity table

| Quantity | Unit | Produced by | Consumed / limited by | Couples to | REDengine expression | RAGE expression |
|---|---|---|---|---|---|---|
| Mass, CoM, inertia | kg, m, kg m^2 | every body; propellant at its tank | propellant burn (mass falls) | acceleration, rotation, hop height | record mass (Carrier) | not written (handling mass read only) |
| Force (per device) | N, at a point, along a direction | engines, fans, rams | throttle, density, propellant, energy, derate | translation; torque about the CoM | lift lever 0..3 twr along up only | velocity change; force at offset |
| Torque | N m | off-CoM force; couples | inertia | attitude | **none** (loss) | paired offset forces (uncalibrated gain) |
| Propellant | kg by type | tanks | mass flow F/(Isp g0) | delta-v (Tsiolkovsky), burn time | (none) | (none) |
| Stored energy | J | batteries, flywheels | propellers (powerW), ram recharge (chargeW) | endurance, hop rate | (none) | (none) |
| Ground impulse | J per stroke | ground_ram | contact; stored energy | hop height E/(m g) | velocity add | velocity add |
| Air density | kg/m^3 | the world: rho0 exp(-h/H) | - | fan/jet thrust, convective cooling, drag, lift | (none) | (none) |
| Heat | kJ; K above ambient | engines, sources, rams | radiators (radiative + convective x density) | derating above 80 % of the limit; failure at the limit | (none) | (none) |
| Structural load | N | sum of device forces | rated load | "damage before performance" | (none) | (none) |
| Universe position/velocity | m, m/s (Earth frame) | the integrator | gravity (radial), forces | orbit, ballistic arcs | Snowglobe seam (z <= 16,384) | the frame, speed presented at <= 140 m/s |

## D. Ground to space: the four ways to push are physical preconditions, not flags

"The hop is not a thruster." Each mechanism has a precondition that `engineering.dynamics` enforces every step:

1. **Ground reaction** (`ground_ram`):
   - acts only with contact, and only with energy already stored in its stroke;
   - **a press in free air does nothing**: there is nothing to push against (tested: 10+ air presses, 0 fired; the peak equals E/(m g));
   - recharge draws from an energy store at `chargeW`.
2. **Stored impulse** (`energy_store`): bounded energy charged earlier; it feeds rams and propellers.
3. **Atmospheric reaction** (`propeller`, `jet`): thrust scales with air density. Full at sea level, under 5 % four scale heights up, zero in vacuum (tested).
4. **Reaction propulsion** (`reaction_engine`):
   - works anywhere and burns propellant at F/(Isp g0);
   - **stops when the tank is empty** (tested: the integrated delta-v matches Tsiolkovsky within 0.5 %).

And for every mechanism:
- heat accumulates against radiators and derates output above 80 % of the limit;
- **off-centre force spins the machine** (tested).

**Placement is physics.** `engineering.machine.assemble` builds a 6-axis wrench table from each device's mount point and direction. `authority` says which axes it can command in both directions. Four up-thrusters at the corners give **two** axes (pitch, roll): no yaw, no sideways, no braking. That holds whatever their thrust (the corner quad: thrust-to-weight 8.1 in vacuum, 2 of 6 axes, and the structure fails first). Sixteen RCS thrusters in opposed pairs at the extremities give six.

**Dev thrust is an instrument.** The F0 lift rig remains as `/ncm.machine instrument`: a measured, labelled device for probing a host. It is never a technology a machine has.

## E. Lineage and reverse engineering (`engineering.lineage`)

**Design records** are immutable. Each carries:
- an **origin world** (night_city / los_santos / snowglobe);
- a principal;
- parents with a declared relation:
  - `reconstructed_from`: "B reconstruction of A/X", never "X by B";
  - `derived_from`;
  - `adapted_for`: re-targeted at another site, host or world;
  - `successor`: the same lineage; not necessarily better;
  - `new_lineage`.

There is **no first-inventor field**: history is the chain. `renderAncestry` prints it, for example `ORB-THR-01 -> NC-THR-01 (reconstructed_from) -> NC-THR-02 (successor) -> LS-THR-01 (adapted_for)`.

**Reverse engineering is estimation, not copying:**
- **Error band:** each physical property is estimated within a band set by **knowledge** of the source (rumour 35 %, observed 20 %, measured 10 %, specimen 5 %, documents 2 %, at 1 sd) and **competency** (0..1000 → x1.5 down to x0.5).
- **Bias:** benefits are biased low (-band/2); costs and mass high.
- **Combining:** a second parent contributes its better benefit fields at the same error.
- **Physics bounds hold:** chemistry caps specific impulse (no hydrazine copy beats 240 s), and the result must validate as its kind.
- **Failure is real:** 2 %-90 % by knowledge and competency, and then nothing usable comes out.
- **Seeded:** draws come from a hash stream, iterating fields in a **fixed order** (KB-343).

## F. Seed architecture (`world.seed`)

**GENERATED BASE + PERSISTENT CAUSAL MODIFICATIONS = CURRENT WORLD.**
- **A tree, not a stream.** Every fact is drawn from a stream keyed by its path (`seed / snowglobe / station / 3`), never by its position in a sequence. Adding a subsystem, a station or a new kind of fact never reshuffles what existed (tested with 200 unrelated draws inserted).
- **Composition:** `compose(base, mods)`.
  - The base is pure and re-derivable.
  - Mods are committed `{id, at, path, op, value}` records (set / add / remove / append), applied in (at, id) order.
  - A mod naming a path the base lacks is refused and reported, never invented.
  - The base is never stored; only the history is.
- **Seeds differ in history, not arithmetic.** `space.genesis` does not roll a tech level:
  - it plants root designs in different worlds (some seeds never discover a family);
  - it runs a seeded history of reverse-engineering attempts between them;
  - organisations build machines from what their world's history gave them.

  So the capability distribution, and with it the sport, falls out of the history. Across 12 test seeds the station rings show different statuses.
- **Determinism across processes is a requirement, not a hope:**
  - every client and the server generate the same Snowglobe from `universeSeed`;
  - Lua 5.4 randomises `pairs` order per process, so seeded code iterates in fixed order (KB-343, found live and fixed);
  - verified by identical fingerprints across three Lua 5.4 processes and LuaJIT.

## G. Snowglobe as a motorsport environment

- **It exists in every seed, before any player** (`space.genesis`):
  - stations on compressed-Earth orbits (55-90 % of an Earth radius up, in planes over Los Santos or Night City; a period of about 5-6 minutes on a 5 km Earth);
  - a sky ring over each city at 350-650 m;
  - the anomaly's deterministic ephemeris (L315; not drawn, not announced);
  - 8-12 organisations with pilots (`paddock.names`, `paddock.attributes`) and their machines.
- **3D racing grammar** (`space.course`):
  - a gate has a centre, a normal and a radius; crossing means the plane's sign changes in the normal's direction within the radius;
  - a course is authored in its own frame and placed by `anchorFrame` (sky; fixed on Earth) or `lvlhFrame` (station; radial / along-track / orbit normal, co-moving);
  - timing happens in the course frame, so a station's 180 m/s orbit does not matter, only motion relative to the ring;
  - the **station ring is the first venue, not the scope limit**: the grammar takes any gate set.
- **NPC racing reuses Paddock** (`space.racesim`):
  - The machine's physics on the course becomes its pace.
  - **Vacuum:** speed is bounded by delta-v, since each turn of angle θ at speed v costs 2v sin(θ/2); acceleration sets turn time; missing axes cost time.
  - **Atmosphere:** thrust is re-derived at the venue's density; the machine must hover there, its spare thrust is cornering, and the battery must last.
  - That pace becomes `carPerf` on `paddock.sim`'s scale **exactly**: a machine 10 % quicker gets 10 % (tested). Heat and structural overload become hazard.
  - Machines that physically cannot fly the venue are **refused with the reason** ("thrust-to-weight 0.51 at 1130 m: cannot hold altitude"), never given a bad time.
  - The race is a `paddock.sim` run in a `paddock.racestate` model: physical promotion and **provenance per car** (simulated / mixed / physical).
- **Sport forms from the capability distribution** (`space.sport`):
  - fewer than 2 machines able to fly a venue: no event;
  - 2-5: an exhibition;
  - 6+: a **class** with a regulation envelope (delta-v for vacuum, thrust-to-weight for sky; the 10th-90th percentile);
  - never date-unlocked.
- **Race Week evidence:** Snowglobe contributes in doc 52 §5's common vocabulary (racing_intensity, technological_capability, participation, infrastructure_readiness, casualties_damage), `visibility = hidden`. The shared resolver that consumes it is **UNKNOWN / not built**.
- **Live seed `ncm-los-santos-dev-1`:**
  - 2 stations (3,941 m and 4,162 m; periods 339 s and 352 s);
  - Vinewood Sky Ring is a **class** (6 machines, twr 1.90-2.19);
  - both station rings are **exhibitions** (4 each);
  - Pacifica Sky Ring has **no event** (no machine in this history can hold altitude there).

## H. The cross-runtime physics contract (`engineering.hosts`)

**NCM's machine physics is canonical. A host expresses it through the channels it has.** Every quantity it cannot carry is an **expression loss** listed beside the commands, never folded back into the truth. A GTA car presented at 140 m/s does not make the NCM machine slower: the frame keeps the real speed.

| | REDengine (Carrier + Thrust) | RAGE (FiveM `ncm_ls_space`) |
|---|---|---|
| Record mass | yes | no |
| Lift | lever 0..3 twr along up | velocity change, any direction |
| Lateral force | **none** | yes |
| Torque | **none** | couples at an offset (**uncalibrated**: §SR1 logs commanded vs observed spin) |
| Speed limit | 99.70 m/s measured (KB-342) | 150 m/s measured (§LS2); presented at 140 |
| World height | 16,384 m hard (§AX4); seam above | **unknown** (GTS_RECON_01 #1) |
| Server move | velocity zeroed, lease revoked ~3 s | driver, ownership, velocity kept (§LS4) |
| Gravity | engine's; Snowglobe offset above 14 km | GTA off; NCM inverse-square integrated (presets only otherwise) |

**Measure both engines.** Unmeasured limits are `nil` with "unknown" as their source.

**Live wiring today:**
- **RAGE:** a machine drives the car (below the doorway it adds velocity; in Snowglobe the frame adds the machine's acceleration to the universe velocity).
- **REDengine:** only the declarations so far; rewiring Thrust/Carrier from machine state is §J.

## I. What was built (2026-10-05)

- **Core** (all tested under Lua 5.4 and LuaJIT; vendored to Online and FiveM):
  - `world.seed` 0.1.0;
  - `engineering.systems` / `machine` / `dynamics` / `lineage` / `hosts` 0.1.0;
  - `space.universe` 0.4.0 (atmosphere);
  - `space.course` / `genesis` / `racesim` / `sport` 0.1.0;
  - `engineering.fixtures` 0.2.0: designs (RCS, 30 and 45 kN engines, lift fan, ground ram, tanks, radiator, battery, spaceframe) and machines `ls_orbiter`, `corner_quad`, `ram_hopper`, `fan_car`;
  - tests `test_world_seed`, `test_engineering_machine` (8), `test_engineering_lineage` (4), `test_space_motorsport` (7).
- **FiveM `ncm_ls_space` 0.3.0** (live by rcon refresh + restart):
  - `client/machine.lua`: the machine drives the car through `engineering.dynamics`, with finite propellant, placement torque, heat and derating; HUD panel; `/ncm.machine`, `/ncm.refuel`;
  - `client/race.lua` and `server/race.lua`: the seeded Snowglobe on every client and the server; `/ncm.race` lists venues with your machine's eligibility; `/ncm.race N` starts a server-run NPC field; gates drawn in 3D and timed in the course frame; NPC ghosts along the racestate; station range and closing speed; a classification with provenance;
  - the F0 lift is now `instrument` mode.
- **Fixture correction found by physics:** the first orbiter (30 kN engine, two tanks) had a sea-level thrust-to-weight of 0.95 (it could not lift off), and its main engine sat off the CoM (lift pitched it). Fixed with a 45 kN engine (twr 1.41 sea, 1.66 vacuum, 625 m/s, 28 s burn) and a balanced layout (tested: no lift torque).

## J. Gating experiments and what is NOT built

**Live (owner), MASTER_TEST:**
- **§EG1:** fit `ls_orbiter`: liftoff, finite burn, the HUD's propellant and delta-v falling, PROPELLANT EMPTY.
- **§EG2:** `ram_hopper`: hop on the ground; air presses do nothing.
- **§EG3:** torque calibration (the `torqueGain` question).
- **§SR1:** the machine-driven Snowglobe (reach space on the orbiter's propellant).
- **§SR2:** Vinewood Sky Ring on `fan_car`.
- **§SR3:** a station ring (rendezvous, then race).
- **§SR4:** the classification's provenance.

**UNKNOWN / not built:**
- life support and sealing for on-foot vacuum;
- persistence of universe, race and lineage state across restarts;
- the cross-server proxy transport;
- the Race Week resolver that consumes Snowglobe evidence;
- mining, logistics and manufacturing in space;
- the Cyberpunk machine-driven thrust path (a Thrust/Carrier publish from machine state);
- yaw input on the pad;
- drag and lift for whole machines beyond aero surfaces;
- re-entry heating;
- engineer competency for the new families (owner).

## K. Biggest catches

1. **The seed tree was already there.** `vocabulary.hash` keys streams by namespace. `world.seed` only makes the path explicit and shared, and adds composition. No new RNG.
2. **Space racing is a Paddock race.** `paddock.sim` and `paddock.racestate` already had seeded incidents, continuous state, physical promotion and provenance. The only new thing is the car term, and it comes from physics exactly.
3. **Body loads were already a wrench.** L314's `loads {pos, dir, magnitudeN}` give torque about the CoM directly. "Four badly placed thrusters ≠ six-axis" is a tested property, not a rule.
4. **Physics found real design errors** (the 0.95-twr orbiter, the off-CoM engine, a 40-second fan-car battery). Machines that cannot do a thing are refused with the reason. That is the point.
5. **Cross-process determinism** (KB-343): `pairs` order differs per Lua 5.4 process. A seeded world would have differed between the server and clients, and it did on the first live boot. Seeded code now iterates in fixed order.
6. **Owner decision pending:** engineer competency for `propulsion` / `energy_storage` / `avionics` changes L120's locked 27 numbers per engineer. The new families work as open taxonomy without it.

---

# Part two (L322): Snowglobe motorsport disciplines and NPC drivers across domains

Owner update brief "NCM SNOWGLOBE MOTORSPORT UPDATE - FIREBALL, SPRINT, RELAY, CROSS-DOMAIN TRIATHLON", plus its addendum "SNOWGLOBE NPC DRIVER BEHAVIOR + AUTONOMOUS SPACE RACING" (2026-10-05).

**North Star.** Sprint: line them up and find out who is fastest. Fireball: put them around something, give them a huge legal volume and a distance, and let them lose their minds. Relay: a team carries continuity through several machines. Triathlon: race across machines, worlds and space.
- Each discipline has a simple reason to exist; physics, engineering, other racers and Race Week make the complexity.
- The machine supplies the possibility space, the driver supplies intent, and the physics supplies consequences.

**Terminology:** they are **NPCs** (owner, 2026-10-05), never "MPCs".

## L. Disciplines

**What already generalised (KEEP):**
- `space.course`: frames (anchor and co-moving LVLH), sign-flip crossing with an interpolated fraction;
- `paddock.sim` and `paddock.racestate`;
- `engineering.machine`, `engineering.dynamics`, `world.seed`, `space.genesis`.

**NEW:** `space.sprint`, `space.fireball`, `space.relay`, `space.multievent`.

### L.1 Sprint (`space.sprint`): deliberately simple

**Geometry:**
- the start plane is y = 0 and the finish plane y = D in a venue frame, with lanes as offsets in x;
- five lights; crossing the start plane before the lights is a **jump start** (5 s penalty, or DQ by rule);
- the **reaction time is measured** (the first sample moving forward after the lights), never assumed.

**Venue kinds:**
- **`vertical`:** the grid stands on the ground and the finish is a horizontal plane D metres up. The first one is the **LSIA Sky Sprint** (Los Santos airport, 1,000 m, 6 lanes): reachable today, no doorway, no pre-start hover.
- **`orbital`:** lanes across a station's orbit plane, racing along-track in its co-moving frame (2,000 m).

**Distance classes** are venue data scaled to the world.

**Photo finish.** The crossing instant is solved inside the sample interval by **cubic Hermite** interpolation from both samples' positions and velocities. It is exact for constant acceleration (tested to 1e-6 s at 60 Hz). Two racers 2 cm apart at 63 m/s are ordered by the right 0.3 ms; |Δt| < 0.1 ms is a declared dead heat.

**Across rebases.** All timing uses universe positions. A floating-origin rebase moves only the local origin, so a sample pair across a rebase is still exact (tested).

### L.2 Fireball (`space.fireball`): the validity mathematics

**Relative state.** Take r = racer − centre and v = velocity relative to the centre. Then:
- ω = (r × v)/|r|² is the instantaneous angular velocity about the centre;
- radial motion contributes nothing to ω.

**The credited axis m** is a unit vector that turns toward ω̂ at no more than `axisTurnRate` (default 0.02 rad/s). Credited angle: dθ = (ω · m) dt, which is negative when going backwards.

**Distance credit:**
- `angle` (default): θ × R_ref, with R_ref the shell's mid-radius. The inside line is shorter, as on an oval, and the inner wall is the contested place.
- `arc` (radius-neutral): θ × |r|.

**What it does (all tested):**

| Motion | Credit |
|---|---|
| Steady, any plane (equatorial / polar / inclined) | the full arc |
| Plane turning continuously (90° over 100 s) | ≥ 90 % |
| Oscillating in one patch (20 km flown) | < 3 % |
| Small loops in one patch | < 6 % |
| Out and back (1 rad each way) | ≈ 0 |
| Long out-and-back (15 km each way) | < 75 % (always worse than carrying on round) |
| Outside the shell | nothing; black flag after `oobMaxS` (10 s) |

**Test finding (recorded):** the first design used a lagged *mean* axis (an exponential average). After one time constant it flipped and paid for a long out-and-back. A turn-rate limit does not.

**Legal shell:** inner < |r| < outer. No lanes, no prescribed plane.

**Venues:**
- **Earth Fireball:** the centre is Snowglobe Earth; the shell is 2,600-6,000 m altitude; 60 km. Faster than circular speed costs continuous inward thrust, so the race is a propellant budget.
- **Station Fireball:** 150-900 m around a free-falling station; 20 km; curving costs v²/r all the time, so it is an endurance and heat event.

**A Sprint machine is not a Fireball machine.** The dragster (twr 7.3, 8 s burn, 2 of 6 axes) wins the LSIA sprint in 6.7 s and is refused at Fireball ("attitude: 2 of 6 axes"). The Fireball racer (1.7 km/s, 6 axes, three radiators) is slow off the line.

### L.3 Relay (`space.relay`): the baton is NOT decided

**Format:** N legs (data, not 4), team rosters, exchange zones.

**The one physical requirement every baton shares is built:**
- both machines are inside the zone;
- their relative speed is ≤ `vRelMaxMs` (2);
- for `holdS` (1 s);
- the outgoing leg counts only once the token has moved;
- **leaving the zone early is a fault.**

**Candidate batons, to be ruled by the owner:**

| Baton | For | Against |
|---|---|---|
| Physical object (an NCM serialized asset) | cheap; uses the existing asset identity | hosts must spawn and attach it |
| Cargo (mass that changes the machine) | real engineering: the receiving machine's mass and CoM change | needs mounts and capacity on both machines |
| Passenger or astronaut transferring between vehicles | the most physical, and the funniest | needs on-foot vacuum, life support, sealing (UNKNOWN), and host occupancy transfer in space |
| Official race token | simplest; no physics | the least interesting |

Each plugs in as the `transfer` rule (a passenger might need a longer hold and a lower relative speed).

### L.4 Point-to-point: OPEN, deliberately

The criterion: **there must be an interesting "between".** A straight A → B in empty space is a long Sprint.

Candidates are recorded and **not canonised**:
- moving destinations or intercepts (the anomaly is already a deterministic moving target);
- gravitational geography (slingshots, where the optimum is not a straight line);
- several bodies;
- atmosphere ↔ space transitions;
- naturally dangerous regions;
- changing reference frames.

Nothing is built.

## M. Triathlon (`space.multievent`)

- **The original multi-machine triathlon:** legs in different machine classes on one world.
  - The open-wheel Formula car is a third-party asset **without permission: never a dependency.** Bike + sports car is available.
  - Classes are whatever NCM can legitimately provide.
- **The cross-domain event:** a Night City leg, a Los Santos leg and a Snowglobe leg in one Race Week. It is the crown jewel. **Sanctioning formats are data:**
  - **`points`:** points per leg position (25-18-15-...); the best last leg breaks a tie;
  - **`sum`:** leg race times added; travel between legs is free; a DNF anywhere is out;
  - **`nonstop`:** one clock from the first green to the last flag, so traversal, runtime transfer, logistics and preparation are part of the race.
- **Discovery gates visibility:** `visibleTo` is false unless every non-Night-City leg's domain has been legitimately discovered. Nothing in terrestrial Race Week UI can spoil Snowglobe.
- **HOST BOUNDARY:** running a leg on another server needs the cross-server identity and result transport (doc 52). The schema and scoring are built and tested; execution waits.

## N. NPC drivers: one identity, every domain

**Inventory (KEEP):** the Paddock person (`paddock.world`, `paddock.attributes`):
- 16 SKILLS that grow toward `potential`;
- 7 TRAITS (aggression, discipline, ego, mettle, mistake_rate, confidence_volatility, loyalty);
- 5 FTB2 personality axes;
- morale and form (`paddock.progression`).

The traits are domain-free. Only `paddock.sim`'s outputs (segment time, dirty air, lane passes) are terrestrial.

**NEW `npc.behavior`** (domain-independent). From the traits and axes only, never from skills:
- `riskTolerance`, `marginScale`, `commitDelayS`;
- `clutch`: steadier under stakes;
- `volatility`: how hard provocation bites and how slowly it fades;
- `mistakeHazard`;
- a **mood**: being passed, blocked or touched raises provocation, which raises risk and narrows margins.

**NEW `npc.competency`** (per domain, stored on the same person, `person.domains[domain]`):
- **Snowglobe skills:** piloting, attitude, traffic3d, energy_mgmt, launch_reaction, fireball, sprint, plus per-machine familiarity.
- **Entry values:**
  - a terrestrial driver enters LOW, with a small transfer (launch → launch_reaction 40 %, racecraft → traffic3d 20 %, consistency → piloting 20 %);
  - Snowglobe natives start higher.
- **Learning:** headroom-shaped, per hour raced, faster for adaptable drivers who give good feedback (`Attr.modulate`), and weighted by fidelity (physical 1.0 > tactical 0.6 > abstract 0.25).

**Personality transfers; skill does not (tested):**
- a star road racer is still aggressive or clutch in Snowglobe, and starts as an attitude-control novice.

**NEW `space.pilot`:** MACHINE + DRIVER + RACE → a desired thrust acceleration, and `engineering.allocate` (shared with the player's machine) turns it into throttles through the real mounts.
- **Sprint:** reaction at the lights; everything along the lane; lane keeping; heat pacing by risk.
- **Fireball:**
  - a preferred radius (aggressive drivers hug the inner wall);
  - a speed bought from delta-v for the distance left;
  - a damped radius and speed controller;
  - **3D traffic:** relative position and velocity, time and distance of closest approach. Inside the margin, a cautious driver gives way and an aggressive one holds the line; a provoked driver escalates; closing on a rival ahead, they attack.
- Competency sets reaction, decision period (how late traffic is read) and execution noise.

**Machine truth (tested):**
- four up-thrusters cannot dodge sideways, whoever is flying;
- identical machines with different drivers give different times, starting at the lights.

## O. One race, three fidelities

**An event** = { id (a seed path), discipline, venue, rules, entrants }. Every fidelity runs **that** event:

| Fidelity | When | What | Provenance |
|---|---|---|---|
| Abstract | nobody near; bulk history | `space.racesim`: physics-derived pace (sprint kinematics; Fireball speed from delta-v and the centripetal deficit) through `paddock.sim` | `simulated` |
| Tactical | someone could watch; a player's race | `space.tactical`: every machine through `engineering.dynamics`, flown by `space.pilot`, judged by the discipline's judge, contact as an incident, at 20 Hz | `tactical` |
| Physical | in a player's bubble | the host flies it; samples go to `tactical.observe` | `physical` / `mixed` |

- **Deterministic and resumable:** every random draw is keyed by (event, entrant, step). A run equals the same run snapshotted at 6 s and resumed (tested). Results are bit-identical across Lua 5.4 processes and LuaJIT (fingerprinted).
- **Promotion / demotion:** `promote(id)` hands a host position, velocity, attitude, tanks and heat; `observe` takes the host's samples; `demote` resumes the simulation from where the host last saw it. Per-entrant provenance is the share of race time flown physically (tested: `mixed`).
- **The flag:** after the first finisher, the rest have `flagWindowS` (sprint 15 s, Fireball 90 s), then they are classified as `flagged`.
- **Stated simplifications at tactical fidelity:**
  - attitude is slewed kinematically at the rate the machine's torque authority and the pilot's attitude skill allow;
  - contact is a closest-approach event, not a collision solve.
- **Cost:** a sprint is 0.3 s of CPU; a 60 km Earth Fireball is 1.2 s.

## P. Race Week, records, unseen history, persistence

- **Unseen racing** (`space.calendar`): every `snowglobeEveryMin` (dev: 10) minutes of the shared clock a Sprint or Fireball venue is due, in turn.
  - The LS server runs it at abstract fidelity unless a player is racing it.
  - **The live dev server ran one on its first boot:** Nova Speed Sprint, 7 starters, in the harness.
- **Committed history:** each event's outcome is `world.seed` mods on a history base:
  - the event and its rows;
  - records;
  - Race Week facts (`race`, `race_crash`, `clean_race`, the `week.curve` vocabulary);
  - each driver's competency gain;
  - an **engineering response**: an org whose machine overheated adds radiator capacity to its next build.

  `compose(base, mods)` then `apply` rebuilds the world (tested). The FiveM server persists the mods in its resource KVP.
- **Path keys** are prefixed (`p_<id>`, `o_<id>`) because `world.seed` reads an all-digit path segment as an array index.
- **Race Week integration:**
  - Snowglobe facts and `space.sport.weekEvidence` stay hidden on the LS server;
  - **HOST BOUNDARY:** the shared cross-server resolver and transport (L318, doc 52) do not exist yet.

## Q. Host boundaries (exact; updated L323)

| Boundary (L322) | Status (L323) | Evidence |
|---|---|---|
| NPC cars colliding with the player, reported to NCM | **CLEARED** | The client reports touching + closing speed; the server checks it against the race (refused beyond 15 m) and applies `space.tactical.contactExternal` (momentum exchange with both machines' real masses, provocation, DNF hazard, a logged incident; the player's row counts contacts). Tested in core; harness: a claim from 32 m away is refused, one beside the NPC knocks it 34.7 m/s and puts it out. |
| Several players in one Snowglobe race | **CLEARED, differently than planned** | Races are keyed by EVENT; players join the same grid, and lights fire when all are ready or 30 s after the first. **Finding:** networked NPC cars cannot work above the doorway, because each client has its own floating origin and a networked GTA car sits at one local position, right for at most one viewer. So every client presents the NPCs AND the other players from server-streamed universe states and hides the others' real cars (and their collision) in its frame. At the city-frame venue (LSIA) real networked cars stay. Harness: 2 players, 6 NPCs, one race. |
| Remote players' photo finish | **CLEARED** | A min-RTT clock sync (5 pings, `space.sprint.clockOffset`, tested); samples stamped in server time and rejected beyond 0.5 s + RTT; resynced every 10 s. Night City needs none: the server observes positions itself. |
| Physical NPC space racing in Cyberpunk | **CLEARED for the first discipline** | `ncm_space` (dev): the Badlands Sky Sprint, a 1,000 m vertical sprint far below every REDengine limit. The NPC field runs tactically on the server (5 steps a tick, the KB-336 quota) and is drawn as client-local prop cars (the `ghost.lua` technique); the player is judged from server-observed positions. Harness: the Thrust-instrument car at its 99.70 m/s cap finished last, 14.6 s, against engined NPCs at 10.3-13.5 s -- honest. Still blocked: above 16,384 m (the seam), and machine-driven Cyberpunk thrust (a native publish path; the player flies the instrument). |
| Cross-domain triathlon | **LINK LIVE (dev); triathlon scoring live** | The LS FiveM server hosts the Snowglobe hub (loopback HTTP); the NC dev server's `ncm_link` reached it at 20:25 (HTTP 200, facts both ways). Link codes join `ncmDriverId` and the FiveM license; legs flow from both servers; Three Cities scoring is tested; discovery gates visibility. Still: one PC only (loopback; a token and TLS before anything else), and Online has no LS server. |
| Passenger relay | **CLEARED as a mechanism** | `life.breath` (outside air / sealed cabin / suit; hypoxia → blackout → death; real breathing rates), the pressure cabin and oxygen on three machines, the emergency suit and EVA pack, and boarding a car in space by the relay exchange rule (`/ncm.eva.drill`). The baton ruling is still the owner's (L322 Q1). |
| NPC presentation driven by GTA physics | still a host limit | GTA has no flying AI; NPCs are NCM's simulation, presented kinematically. |

## R. Biggest catches (part two)

1. **The existing driver already was the cross-domain driver.** Paddock TRAITS and FTB2 axes are domain-free. Only skills and `paddock.sim`'s outputs are terrestrial, so the split is "behaviour from traits, competency per domain", with no SpaceDriver.
2. **Fireball's first validity rule had a hole the tests found:** a lagged-mean axis flips and pays for out-and-back. The turn-rate limit closes it.
3. **The compressed Earth bites a flat city** (L320 Q1 again): LSIA sits about 770 m above the 5 km sphere on its tangent plane, so the tactical sim first thinned the air there and three fan cars stalled at 440-820 m. Flat-patch venues now take density from height in the city.
4. **The calendar's paths:** an all-digit pilot tag would have become an array index in `world.seed`; keys are prefixed.
5. **Cross-process determinism holds for whole races** (trigonometry included) across Lua 5.4 and LuaJIT. The KB-343 rule (no `pairs` while drawing) is kept.

## S. L323: clearing the boundaries

### S.1 The cross-server link (doc 52 made real, on one PC)

```
Night City dev (OPEN//77)                         Los Santos (FiveM)  -- the Snowglobe hub
  ncm_link  --- outbound HTTP (allow-list 127.0.0.1) --->  ncm_ls_space/server/link.lua (SetHttpHandler, loopback only)
    /ncm.link -> POST /link/code                             code (6 chars, 10 min, single use)
    ncm:week:fact -> POST /facts (every 5 min)   <-------   Snowglobe facts back (logged, hidden)
    ncm:paddock.human.result -> POST /results                legs; Three Cities scoring per Race Week
    ncm:space.result (Badlands) -> POST /results
                                                            /ncm.link CODE (in LS) -> the FiveM license joins the NCM driver
```

- **Pure core `world.link`:** issue and claim (claimed in the other world only, expiring, single use), `driverOf`, `discover`, `legMod`, `threeCities` / `scoreThreeCities`, `visible`. Committed as `world.seed` history in the hub's KVP.
- **Discovery:** Los Santos is discovered on claim or on a race there; Snowglobe at the doorway or at a Snowglobe venue. Until both other domains are discovered, `/ncm.tri` answers "Nothing here." -- no spoiler, not even a hint.
- **Security, stated:** loopback only (refused from anywhere else, 403, tested). There is no token yet: dev, one PC. A shared token from the DPAPI store and TLS come before any other topology.

### S.2 Life support and EVA

- **`engineering.systems`** kinds: `pressure_cabin`, `life_support`, `eva_suit`. `engineering.machine` exposes `cabin` and `o2Kg`.
- **Fixtures:** a 2-seat cabin and 1 kg of O₂ on `ls_orbiter`, `fireball_racer` and `sprint_dragster` (about 7 h for two working hard); the emergency suit (0.012 kg O₂, about 10 min working; 120 N EVA pack, 3 kg N₂, about 20 m/s).
- **`life.breath`:** breathable at rho ≥ 0.35 kg/m³ (about 1.5 km on the compressed atmosphere). Otherwise a sealed cabin with oxygen, or the suit. Without any, the time of useful consciousness runs from 15 s (vacuum) to 5 min (just below the line), then blackout, then death after 2 min.
- **FiveM `client/eva.lua`:**
  - the HUD's AIR panel;
  - the EVA pack drives the Snowglobe frame on foot;
  - **boarding = `space.relay.exchange`** (within 4 m, under 2 m/s, for 1 s);
  - `/ncm.eva.drill` puts a teammate car coasting on your orbit 20 m away: the passenger-baton transfer, end to end.

### S.3 The Badlands Sky Sprint (Cyberpunk)

- `space.genesis` appends the Night City venue last (every earlier venue keeps its number); `ncm_space` runs it on dev.
- The start plane is surveyed with `Open77.world.groundZ`. On an empty server the ray-cast has no collision, so the survey is retried when a player opens the sprint, in a thread, never inside the command.
- **Command:** `/ncm.sky`. Lights and results are server notifications and chat (`Open77.chat` is server-only); NPC cars are prop ghosts.
- The player's entrant is `instrument_car` (the Hella with the F0 rig): mass and identity, flown by the instrument and observed by the server.

