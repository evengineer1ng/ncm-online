# 53 - NCM Los Santos: space above Los Santos (FiveM dev build)

> **STATUS: SPEC** - authority for: *NCM Los Santos' first build -- the local FiveM dev server, the GTA adapter for NCM core, and Snowglobe above Los Santos (lift, doorway, universe altitude, Earth/Moon stand-ins)* - owner direction 2026-10-05 (L319).
> Built and set up on this PC; **not yet run** (it needs the owner's FiveM license key and the FiveM client). MASTER_TEST §LS1-§LS6.
> Code: `ncm/fivem/resources/ncm_ls_space/`, `tools/fivem-server.ps1`. Research basis: [GTS_RECON_01](../research/los_santos/GTS_RECON_01.md). Direction: [52_CROSS_WORLD.md](52_CROSS_WORLD.md).

## 1. What it is

The same NCM core that runs Night City runs in a FiveM resource, unchanged:
- **147 core files are vendored** by `tools/ncm-build.ps1`, which now also recognises `fxmanifest.lua`.
- **One Earth, two cities.** `space.universe` 0.2.0 puts Los Santos on the same Earth frame as Night City: anchors `los_santos` (34.05, -118.24) and `night_city` (37.0, -122.0), about 473 km apart. Local axes are x east, y north, z up in both engines.
- **The resource is the GTA adapter.** GTA natives express what NCM describes. There is no ScriptHook, no ASI and no memory offset (GTS_RECON_01 §12).

## 2. The pieces

- **Server, the authority** (`server/space.lua`):
  - per car, an NCM **machine id** (UUID, a state bag; not the net id), an **offset** (altitude GTA no longer shows), and its moves;
  - universe altitude = `space.universe.altitude(cityToUniverse({x, y, z + offset}, "los_santos"))`;
  - **the doorway** (Snowglobe 0 on GTA): climbing through `up` moves the car to `low`, and the offset grows. Falling through `down` with an offset moves it up by up to `step`; home when the offset is 0.
  - **The move is the server's** `SetEntityCoords` under OneSync. The driver's client gets the pre-move velocity back to restore (continuity).
  - **Instrumentation:**
    - every second per flying car: game z (and peak), universe altitude, vz, speed, offset, owner;
    - after every move: the server's view at +100/500/1500/3000 ms (target reached, speed, owner, driver seated) and the client's report (arrived, control, speed restored).
- **Client thrust** (`client/thrust.lua`):
  - **lift:** the F0 lift rig (`engineering.fixtures.f0_lift_rig`, 36,100 N) → `engineering.actuate.lift(thrust, the car's handling mass)` → thrust-to-weight r, clamped at `maxTwr`. While held, the velocity gains r·g·dt along the car's own up axis.
  - **attitude:** a pure couple of offset forces (`APPLY_FORCE_TO_ENTITY`), pitch and roll, airborne only.
  - **every press is measured** against `engineering.actuate.hopPrediction`.
  - `SET_ENTITY_MAX_SPEED` is raised to test GTA's 150 m/s cap.
  - **Controls:** pad TRIANGLE/Y (exit disabled while armed; `/ncm.thrust off` to exit with Y); keyboard H (rebindable); left stick / WASD for pitch and roll.
- **Client space view** (`client/space.lua`), above the doorway, client-local:
  - night, clear, no clouds, empty roads;
  - GTA gravity off for the car, with **`space.universe.gravity` at universe altitude** integrated instead (inverse-square, not GTA's four presets);
  - **Earth, Moon and Sun stand-ins:** sphere markers at `space.universe.proxy` direction and true angular size. No assets.
- **HUD** (`client/hud.lua`): universe altitude (labelled IN SPACE above the doorway), CLIMB/FALL, speed, thrust-to-weight, g at altitude, and what's next.
- **Dev:** `/ncm.car [model]` spawns a car and seats you.

## 3. Provisional thresholds and what flight 1 must answer

`up 2500 / low 1000 / down 600 / step 1500` are **provisional**. GTA's stock ceiling under FiveM is unknown (GTS_RECON_01 unknown #1). They sit low so the loop works before the ceiling is found; flight 1 measures the ceiling and the thresholds move under it.

Open questions answered by the logs, not assumed:
1. **The ceiling** and what GTA does there.
2. **What a server move does to an occupied car** (driver, velocity, ownership).
3. **Whether `SET_ENTITY_MAX_SPEED` lifts 150 m/s.**
4. **Whether the client-local view coexists** with server weather.

## 4. Running it

1. **Owner, once:**
   - install the FiveM client;
   - get a license key at keymaster.fivem.net;
   - store it: `.\tools\ncm-secret.ps1 -Set fivem-license`.
2. `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\fivem-server.ps1 -Start`. The log goes to `tools\fivem\server-data\logs\`.
3. In FiveM: F8, `connect localhost:30120`. Then `/ncm.car`, and hold TRIANGLE.
4. Edits to `ncm/fivem/resources` are live through a junction: `restart ncm_ls_space` in the server console.

## 5. Gravity as a concept and the Snowglobe frame (L320; live 2026-10-05 17:45)

**The flight evidence (§LS1-§LS6):**
- **FiveM's server move kept the driver and ownership,** and the velocity was restored (129 against 127 m/s). That's cleaner than OPEN//77.
- **GTA's 150 m/s cap holds** (146.7 m/s peak; `SET_ENTITY_MAX_SPEED` does not lift it).
- **The Earth and Moon stand-ins rendered.**
- **Real-Earth g at 3.6 km felt like "still falling":** correct physics, wrong game.

**The model now:**
- Snowglobe Earth has a compressed radius (`earthRadius` 5 km, about 1 g at the surface; a seed constant, not canon).
- Above the doorway the client integrates the universe state {u, w} under radial gravity toward that Earth's centre plus the lift. The GTA body only presents it (velocity clamped at 140 m/s; GTA gravity off).
- Server moves keep the body in the local band 1,000-2,500 m.
- The frame follows the player.
- Home is at universe altitude below 2,000 m over the Los Santos patch.
- **Numbers on a 5 km Earth:** g is 2.45 at 5 km universe altitude and about 1.1 at 10 km. A circular orbit is about 181 m/s at 2.5 km and 156 m/s at 5 km.

**Open:** cross-world geography on a compressed Earth (L320 Q1): the anchors are about 370 m apart at 5 km.
