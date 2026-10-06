# 51 - The Causal Tunnel: from a 20 cm hop to a new Night City

> **STATUS: SPEC** - authority for: *the flight ladder, the altitude/space hand-off (NCM Snowglobe), the wormhole as a seed transition, and the dev-only experiments that walk them (F0-F4, S0, W0)* - owner direction 2026-10-04 (L315, L316 + addendum).
> Owner intent, not production authority. **L316 lifted L314's "not to be implemented" for dev-only experiments, not for production.** F0 and S0's instruments are built (§F0, §S0); nothing else is.
> Ideas: IDEA-1025 to IDEA-1046. Code: `ncm/thrust/`, Carrier 0.1.33's lift lever (`ncm/carrier/src/vehicle/physics_probe.cpp`), `engineering.actuate.lift`, `ncm_world/client/altitude.lua`.

## 0. What this is for

The owner, playing as god, walks the whole path once in ugly dev form, so that every later system has somewhere physical to live. The path:

**hop → force part → attitude → ugly flight → altitude → snowglobe → orbit → seed swap → anomaly → return**

After that, the work is replacing cardboard with real systems. Then the engineering progression gets deep enough that a player who doesn't know any of this exists can spend hundreds of hours discovering the same path (L316 addendum).

Two rules hold on every rung:
- **Physics, not flags.** No `vehicle:setFlying(true)` and no `allowsFlight` (L314). Lift is a force from a part. Its limit is the part, never a world barrier (IDEA-1029).
- **Cause / actuator / state / coarse model** (L314). The cause is a body's load in newtons. The actuator is whatever REDengine lever expresses it today. The state keeps the modelled truth whatever the lever can express. The coarse model is what an off-screen simulation reasons with.

## 1. The ladder (each rung gated on the previous rung's live PASS)

| Rung | What | Exists today | The gap | Proves |
|---|---|---|---|---|
| **F0** hop | a measured upward force on the seated car | **BUILT**: NCM Thrust 0.0.1 + Carrier 0.1.33 lift lever; `engineering.actuate.lift`, `hopPrediction`; `f0_lift_rig` fixture | the live run (§FL1-§FL4) | NCM can push a stock Cyberpunk car upward with its own force model, independent of the wheels |
| **F1** force part | the lift lever driven by a fitted body's thrust load instead of config `twr` | `engineering.body` loads, `actuate.liftN` | engineering hookup (L314 step 8); a runtime path from the composed build to NCM Thrust | the hop is a consequence of what is bolted on |
| **F2** attitude | pitch, roll and yaw from physically explainable actuators | the `+0x0C` torque candidate is instrumented (Carrier, unverified) | verify torque, or find an off-centre force path; the lift lever has no application point today | thrust off the centre of mass turns the car |
| **F3** ugly sustained flight | an awful contraption that stays up because its engineering works | - | F2, plus energy and heat budgets on the force body | flight as an emergent build |
| **S0** altitude expedition (parallel) | how high Night City goes, and what is up there | **BUILT**: `/ncm.altlog`, `ncm.lift`, server-side replication comparison | the live run (§AX1-§AX5) | the evidence that decides the snowglobe's architecture (§2) |
| **F4** altitude regime | gravity and air changing with height | F0's gravity-entry write (once proven) is the actuator for gravity scaling | S0's ceiling | road-car physics becoming aerospace physics |
| **Snowglobe 0** | something above Night City: a planet beneath you, stars, reference bodies; a continuous climb | the weather probe; WolvenKit authoring | S0; meshes; the `ncm-snowglobe` package (its own mod) | space exists |
| **Orbit 0** | a free-flight or orbital relationship with the globe | - | F4 | space is not just a very tall map |
| **W0** seed swap | `ncm.wormhole`: save the current universe, roll a new seed, the **whole dev server** follows | Paddock genesis seed (`paddock/world.lua`), Racing Week `runSeed` (`week.lua`), both separate | the universe seed record (IDEA-1042); genesis that yields (KB-336) | the Ouroboros mechanism |
| **Anomaly 0** | a black sphere at a seeded position replaces the command; physical traversal | - | Snowglobe 0 + W0 | the wormhole is a place |
| **Return** | old universes stay addressable (IDEA-1045) | - | W0's archive | leaving is not deleting |
| **Nessie** | the anomaly is hard to find, mapped and beaconed by mature civilizations (L315 amendment) | - | everything above | discovery |

## 2. Rulings that shape the ladder (L316 addendum)

- **Snowglobe architecture is NOT ruled.** The requirement is that traversal *appears physically continuous*. The player points the nose up and keeps going: no loading screen, no menu. Whether that is the same coordinate space or an invisible hand-off is for S0 to decide. A hand-off must carry:
  - position, velocity and attitude;
  - vehicle state and occupants;
  - energy, heat and damage;
  - build state.

  "The ground can't curve" is unproven, not a premise.
- **The wormhole is a dimension/seed transition, not the Racing Week rollover.**
  - Rollover: Week → verdict → regeneration → next Week.
  - Wormhole: traversal → preserve the old seed → new universe seed → rematerialise. It bypasses verdict mechanics; it may interrupt a Week and have consequences.
  - The two may share regeneration machinery underneath.
- **You bring what physically traverses.** The vehicle you are in comes with you. Anchored cars (IDEA-1032) govern the ordinary loop; your garage stays with the old seed, which is saved.
- **Dev first, server-wide.** On the dev server, the whole server follows the owner through the wormhole (IDEA-1039). The single-player mod lets each player go alone (IDEA-1040). An online server never splits players across dimensions.

## 3. F0 in detail (built)

**The physics.** Carrier's force channel carries impulses (force × dt). The gravity entry fires once per frame per body, with Z = -m·g·dt (§AU4). So a thrust-to-weight ratio *r* is exact with no knowledge of mass or step:

    z_written = gravZ × (1 - r)      r = 0 untouched · r = 1 weightless · r = 2 a 1 g net climb

**The prediction, from rest, burning at r for t seconds:**

    a = (r - 1)·g      peak dv = a·t      apex = a·t²/2 + (a·t)²/(2g)  =  r(r - 1)·g·t²/2

- r = 2, 143 ms → 1.40 m/s, **0.20 m**.
- r = 3, 143 ms → 2.81 m/s, **0.60 m**.
- r = 1 → no rise, weightless only.

On the ground, the unloading suspension adds roughly half its travel, so a measured rise somewhat above prediction is expected.

**Parts:**
- **NCM Thrust 0.0.1** (`ncm/thrust/`, its own package). A DLL that polls the fire key (default `H`, this window only) and publishes the request into `Local\NCM_Thrust_Levers_<pid>`. `ncm_thrust_config.json` is re-read live; a bad file keeps the last good values. Fields:
  - `enabled`;
  - `fireKey`;
  - `twr` (0-3);
  - `burnMs` (≤ 2000);
  - `holdMode` (burn while held: the S0 elevator).
- **Carrier 0.1.33.**
  - At the bound, seated car's gravity entry, the lever rewrites Z. The gates are the same as every write: KB-146 binding, the session kill switch, SEH.
  - A stale publish (200 ms) ends a burn. The burn is timed in physics time.
  - Each burn logs one measured line: frames, seconds, mass, vz start → peak beside the predicted dv, the integrated rise beside the predicted apex, faults, and why it ended.
  - A press with no bound car logs `burn requested but NOT applied`.
  - It is the first lever that adds force. Every earlier lever only takes away.
- **Core.** `f0_lift_rig` (a body whose thrust is a load at the centre of mass). `actuate.liftN` (the vertical share of a body's thrust loads). `actuate.lift` (cause → expressed ratio, clamped at 3, with the rest kept in state and listed as unexpressed). `actuate.hopPrediction`.
- **Known limits (listed by `actuate.LIFT_LOSSES`):** no application point, so no torque; and lift is vertical in the world frame, so a tilted car still lifts straight up.
- **If the gravity-entry write turns out to be ignored**, the fallback is adding Z on a horizontal entry, which writes are proven to take. It is not built until the log shows it is needed.

## 4. S0 in detail (instruments built)

- `/ncm.altlog` (client): once a second it logs z, peak z, x/y, in car or on foot, speed and onGround. Every ten seconds it adds the platform weather state. Each line goes to the server.
- The server logs each sample as `altlog player=N client z=… server z=… | gap … m`. That gap is the replication answer at that altitude.
- `ncm.lift <pid> <metres>` (server console): teleports straight up from where the player stands. Teleport dismounts (KB-12), so it probes the world on foot.
- **The in-car climb is NCM Thrust's hold mode** (`holdMode: true`, `twr` 1.3-1.5). It is ugly, and has no attitude control.
- A second client (`ncmtester2`) watches from the ground.

**First answer (§AX4, 2026-10-04, L316 addendum 3):**
- **The ceiling is z = 16,384 m (2^14).** The owner flew the Hella there by mashing TRIANGLE (92 m/s peak climb). It sat pinned at 16,383.9 m on both the client and the server.
- At the ceiling, multiplayer authority breaks down and the session drops to the menu (KB-338).
- The vanilla boundary teleport was already disabled by Open77, so this is a deeper bound.
- **Snowglobe budget:** the hand-off happens below about 16 km, or space lives elsewhere in the coordinate space.
- **Open:** is 2^14 the engine's or Open77's? Repeat the climb in single player.

The answers S0 must produce:
- the streaming ceiling;
- what the sky becomes;
- coordinate jitter;
- physics at altitude;
- replication.

## 5. Not built, not authorised for production

Everything from F1 onward. The universe seed record and `ncm.wormhole` (W0). The `ncm-snowglobe` package, star field and planet. The anomaly. The single-player wormhole.

## 6. The ceiling is a doorway (L317, SPEC, not ruled)

Above a transition altitude, the server owns each traveller's universe position. REDengine simulates only a local bubble recentred under the car (a floating origin), so the 16,384 m bound stops mattering. The first prototype is **the seam**: Night City → Space Test Bubble → Night City, with no loading screen and no lost state.

Coder's constraints, from the tree:
- **Night City cannot be shifted.** A rebase is invisible only when everything in view is NCM's, so the city must leave view, or become a proxy, before the first rebase.
- **Moving an occupied car while keeping its velocity is unproven.** This is SEAM-1. KB-12 rules out the player teleport.
- **The horizontal bounds are unknown** (SEAM-3).
- **The platform's authority revoke at the ceiling** (KB-338, SEAM-4) must not fire in the bubble.

Experiments and open questions: L317.

**Ruled (L317 Q1): the seam comes before F2-F3. Built offline:**
- `space.universe` 0.1.0: bodies, the anchor, phases, the bubble and its rebase invariant, proxies, gravity.
- NCM Snowglobe 0.0.1, SEAM-1: the dev key `J` moves the occupied car 2 km down mid-air with the game's `TeleportationFacility` and measures velocity and seat before and after (§SG1-§SG3).
