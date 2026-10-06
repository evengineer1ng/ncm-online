# NCM Los Santos Recon 01: Grand Theft Space

> **STATUS: RESEARCH (reconnaissance only)** - 2026-10-05. Owner brief "NCM LOS SANTOS RECON 01: GRAND THEFT SPACE". No GTS file was installed, converted or copied into NCM.
> Source read from public GitHub archives into a scratch folder outside the workspace. Context: L317 (Snowglobe), L318 + addendum ([52_CROSS_WORLD.md](../../ncm-online/52_CROSS_WORLD.md)).
> Every finding below is marked **[C] confirmed in code or primary source**, **[I] reasonable inference** or **[U] unknown**.

## 1. Sources, provenance, license

| Source | What it is | License |
|---|---|---|
| [sollaholla/space-mod](https://github.com/sollaholla/space-mod) | **The GTS runtime source** (namespace `GTS`, folders `SpaceMod/`, `GTSCommon/`, `GTS Scene Creator/`, `Scenarios/`). 100 files, C# (ScriptHookVDotNet), pushed 2019-07-13 in one session: a late snapshot, not necessarily byte-identical to the 2017 1.0.0 release. **[C]** | **None declared**, so all rights reserved by default. **[C]** |
| [sollaholla/grand-theft-space](https://github.com/sollaholla/grand-theft-space) | A 2018 **rewrite** ("CoreGame": `RuntimeLevel`, `PlanetEntity`, `SpaceLevel`, a level editor). 54 files, commits 2018-01-04 to 2018-01-07 only; abandoned. Forks (Jitnaught, lucienlmy) frozen at the same commit. **[C]** | None declared. **[C]** |
| [GTA5-Mods: Grand Theft Space [.NET] 1.0.0](https://www.gta5-mods.com/misc/grand-theft-space-net-gts-devs) | The release: 2017-09-06, last updated 2017-09-13; "Currently does not work on the latest version of GTA V". Requires SHV, SHVDN, NativeUI, GameConfig, **NoBoundaryLimits**, the CWeaponInfoBlob limit adjuster, and OpenIV/.oiv dlcpacks. Team: Sollaholla, AHK1221, Unknown Modder, Shaezbreizh, nkjellman and others. **[C]** | No reuse statement found. **[C]** |
| `GTSLib.asi`, `NoBoundaryLimits.asi`, `RespawnFix.asi` | Closed native binaries credited "Unknown Modder (c) 2017" (`SpaceMod/Library/GtsLib.cs` header). Used for arbitrary world gravity, vehicle gravity, air drag and script stack control. **[C]** | Closed source; no license. **[C]** |
| [GTS - Another Fan Update](https://www.gta5-mods.com/misc/gta-space-another-fan-update) (Flash76) | The active continuation: v2.50 (2026-02-09). More planets, bases, a stargate system; **Legacy only**; .oiv install; **no source repository**. Known issues: freezes during planet loading, texture flicker, crashes on reloading the same planet. **[C]** | No license or source. **[C]** |
| [Chiheb-Bacha/NoBoundaryLimitsEnhanced](https://github.com/Chiheb-Bacha/NoBoundaryLimitsEnhanced) | An open re-implementation of the boundary patch, Legacy + Enhanced; memory-pattern ASI. **[C]** | **GPL-3.0.** **[C]** |
| `ahk1221/grand-theft-space-bot`, `nkjellman/Grand-Theft-Space-Website` | A Discord bot and the website. Not architecture. **[C]** | None. |

**Reuse boundary.**
- **Nothing in GTS (code, XML scenes, models, textures, `.asi`) is licensed for reuse or redistribution.** It is research reference only.
- Ideas (floating origin, player-following skybox, scene graph) can be independently implemented.
- NBL-Enhanced is GPL-3.0: reusable only under GPL obligations. It also cannot run on FiveM (§8).

## 2. Architecture reconstruction (original GTS)

**Runtime model.** A **Scene** is GTS's world unit.
- **[C] One XML `SceneInfo` per scene** (`GTSCommon/SceneInfo.cs`, `Scenes/*.space`): skybox model (`spacedome`), time (default 23:00, clock paused), weather (`EXTRASUNNY`), gravity on/off + level, timecycle modifier, clouds, wind, `GalaxyCenter` (default **(-10000, -10000, 30000)**), `Orbitals`, `AttachedOrbitals`, `Surfaces`, `Billboards`, `SceneLinks`, `Interiors`, `TimecycleAreas`, and `NextScene` / landing data.
- **[C] `Core`** (a ScriptHookVDotNet `Script`) runs either `DoEarthUpdate` (normal GTA) or `DoSceneUpdate` (inside a scene).
- **[C] A scene is built at a real GTA position:** every object spawns at `GalaxyCenter + data.Position` (`Scene.CreateOrbital`, `CreateSurface`).
- **[C] Higher-level position:** `Scene.SimulatedPosition = PlayerPosition - GalaxyCenter + _playerSimulatedOffset`. It is **scene-relative, not astronomical**; there is no universe coordinate across scenes.
- **[C] Scene-to-scene position is a logical handoff:** on exit, `Core.CurrentSceneOnExited` offsets the next scene's orbitals so the player appears beside the body they came from (`PreviousSceneInfo.DirToPlayer * ModelDimensions`).

**What "space" is: all of these, layered.**

| Mechanism | GTS does it? |
|---|---|
| Moves the player to another GTA coordinate region | **[C] yes:** to the scene at `GalaxyCenter`, z = 30,000 |
| Keeps the player near the origin and moves the environment | **[C] yes:** within a scene, `KeepInSafeZone` beyond 2,500 m (§4) |
| Sky shell attached to the player | **[C] yes:** `Skybox.Position = ViewFinderPosition()` every tick |
| Separate map/interior spaces | **[C] yes:** planet surfaces and interiors are separate scenes (IPLs or Map Editor XML) |
| Teleports/rebases | **[C] yes:** at every scene change, and the in-scene floating origin |
| Streams custom planetary maps | **[C] partly:** surfaces are tile props repositioned around the player; interiors via IPL/MapEditor |
| Changes time/weather/sky | **[C] yes:** clock set and paused, weather persisted, timecycle modifiers, clouds cleared |
| Suppresses or hides Los Santos | **[C] by distance plus a sky dome:** being 30 km up, inside an opaque dome; population density forced to 0; radar set to interior; `CLEAR_AREA` within 10 km |
| Changes gravity | **[C] yes:** `GTSLib_SetWorldGravity` (arbitrary float, closed ASI) + `HasGravity` per entity |
| Custom spacecraft physics | **[C] yes, scripted** (§6) |
| Its own higher-level position model | **[C] scene-relative only** |

## 3. The terrestrial ↔ space seam

**Ascent** (`Core.DoEarthUpdate`, `SetCurrentScene`, `CreateScene`, `Scene.Start`):
1. **[C]** Normal Los Santos. Each tick: `PlayerPed.HeightAboveGround > Settings.EnterOrbitHeight` (**10,000 m above ground**). Alternatively, the scripted shuttle burns until `HeightAboveGround > EnterOrbitHeight`.
2. **[C]** Deserialize the default scene (`1FullSolarSystem.space`).
3. **[C]** Player invincible; `FadeScreenOut(100)`; `Wait(100)`.
4. **[C]** `CurrentScene.Delete()`; `CLEAR_AREA` around the player within 10 km; vehicle or ped rotation zeroed.
5. **[C]** `Scene.Start()`:
   - timecycle and rendering configuration;
   - `ToggleAllIplsUnchecked(true)`;
   - gravity level;
   - audio scene `CREATOR_SCENES_AMBIENCE`;
   - `SET_CLOCK_TIME` + `PAUSE_CLOCK`;
   - `SET_WEATHER_TYPE_NOW_PERSIST`;
   - the skybox set to always prerender;
   - the vehicle made invincible and persistent;
   - the player reset to `GalaxyCenter`;
   - the sky dome, orbitals, surfaces, billboards and links spawned;
   - interiors, teleports and scenarios created.
6. **[C]** The player or vehicle is **teleported** to `GalaxyCenter + DefaultOrbitOffset`, with the default rotation.
7. **[C]** `FadeScreenIn(100)`. **Velocity:** not explicitly preserved at the seam. `SetCurrentScene` sets position only; the flight script then drives velocity.

**Re-entry** (`Core.EnterAtmosphere`, triggered by the scene link to Los Santos):
1. **[C]** `FadeScreenOut(100)`; delete the scene; `ResetWeather` (clear, 12:00).
2. **[C]** The vehicle's gravity is restored; teleport to a **fixed** `EarthAtmosphereEnterPosition = (-4000, 2000, 5000)` with rotation (-30, 0, -100); **`Speed = VehicleReentrySpeed` (150)**.
3. **[C]** `FadeScreenIn(100)`. The re-entry point is fixed, not derived from where in "space" the player was.

**Planet landing and launch** (`Scene.TryToExitScene`, `ConfigureVehicleForScene`, `ReturnToOrbit`):
- **[C]** Flying within `ModelDimensions.Length() / 3.5 × TriggerSizeMult` of an orbital (the planet prop) fires `Exited(nextScene)`, which loads the planet's surface scene (fade, teleport).
- **[C]** On a surface scene, the vehicle either does an "orbit landing" (`OrbitLandingPosition`, `OrbitLandingSpeed` via `SET_VEHICLE_FORWARD_SPEED`) or is placed at `VehicleSurfaceSpawn` with velocity zeroed.
- **[C]** Climbing above `OrbitLeaveHeight` (relative to that scene's `GalaxyCenter.Z`) exits back to the space scene.

**Compared with Snowglobe's problem.** "Real world loses visual authority, state captured, local transition, proxy environment gains authority":
- **[C] GTS solves visual authority by FADE + DISTANCE + DOME.** It cuts to black for 100 ms and moves you 30 km up, inside an opaque sphere. It captures almost no state: position comes from config, velocity is reset or fixed, gravity is a scene property.
- It does not try to make the seam continuous.
- **This is the owner's L317 addendum 7 position** ("we control the perspective of speed ... a loading screen is fine").

## 4. Coordinates and limits

- **[C] GTS lives at z = 30,000 m by default** (`GalaxyCenter`) and **requires `NoBoundaryLimits`** (release requirements, and the GtsLib credit). GTA's stock world rejects at least part of that region.
- **[C] The in-scene floating origin** (`Scene.KeepInSafeZone`). When `|PlayerPosition - GalaxyCenter| > 2,500 m`:
  - `_playerSimulatedOffset += drift`;
  - every orbital, attached orbital and billboard is shifted by `-drift` (`MoveWorld`);
  - the player is reset to `GalaxyCenter`;
  - **velocity and camera are explicitly restored.**
  - GTS kept local coordinates within about 2.5 km of a fixed point. **This is the same idea as NCM's Snowglobe**, done client-side in single player, where moving the player is free.
- **[C] Distances between bodies are logical, not physical.** A "far" planet is a scene file. Inside a scene, bodies are props near `GalaxyCenter`, and AttachedOrbitals ride with the camera.
- **[C] GTA's documented limits** (NBL-Enhanced page):
  - entities are capped at **150 m/s**, planes at **160 m/s**;
  - z < -200 in a vehicle out of water teleports you up;
  - z = -170 / -250 submarine limits;
  - several map, camera, player, task, global and "explosive" boundaries exist (NBL patches them all to ±10,000,000).
  - **Their exact stock values are not published** (NBL logs them at runtime). **[U]**
- **[I] Precision:** GTA uses 32-bit floats. At 30 km the step is about 2 mm, so GTS's choice is precision-safe. The binding constraints are the engine's bound checks, not float precision.
- **Contrast with Night City [C]:** REDengine/Open77 hard-capped z at 16,384 (§AX4). GTS shows that GTA single player, with bounds patched, works at z = 30 km. In both, the real wall is an engine bound, not maths.

## 5. Planets and space rendering

- **[C] The sky:** a model `spacedome` (a large inward-facing sphere prop) spawned at the player, `SET_ENTITY_ALWAYS_PRERENDER`, repositioned **every tick to the camera** (`Database.ViewFinderPosition()`: the gameplay or rendering camera position). Stars are its texture. GTA's sky is overridden by time/weather/timecycle and occluded by the dome.
- **[C] AttachedOrbitals** (Sun, distant bodies) ride with the camera at a fixed offset, with optional per-axis freeze to `GalaxyCenter` and a **parallax shift** (`ShiftAmount × _playerSimulatedOffset`). Distant bodies never get closer, except by deliberate parallax.
- **[C] Orbitals** (planets you can fly to) are large props at `GalaxyCenter + Position`, optionally rotating. Entering their trigger radius switches scene.
- **[C] Billboards** have `ParallaxAmount` / `ParallaxStartDistance`.
- **[C] Surfaces:** a grid of terrain tile props around the player (`Surface.Update`, `RePositionTerrainTiles`), snapped to tile multiples, for effectively endless ground. A surface is a **separate scene** with its own `GalaxyCenter`, weather, gravity and `OrbitLeaveHeight`.
- **[C] A planet therefore has two representations:** a prop in the space scene, and a surface scene. They are **swapped by a scene change**, not approached continuously.
- **[C] Wormholes:** orbitals flagged `WormHole` pull the player within 15 × `TriggerSizeMultiplier`, are escapable beyond 20 ×, and exit to `NextScene` within 1 ×.
- **[I] Lighting:** comes from the timecycle modifier, clock 23:00 and weather. There is no evidence of real Sun-direction lighting.
- **[U] Parallax and precision artifacts:** not documented in code. The fan update reports texture flicker on some planets.

## 6. Spacecraft and physics

- **[C] Free flight** (`Scene.EntityFlightControl`):
  - **attitude** is scripted: quaternion lerps from pitch/yaw/roll inputs, and `entity.Quaternion` is written directly.
  - **thrust** is either **direct velocity** (`entity.Velocity = Lerp(Velocity, Forward × flySpeed × throttle)`, the default) or, for vehicles with `NewtonianPhysics`, `ApplyForce(target, MinForce)`.
  - fly speed is about 35 by default (`VehicleFlySpeed`), per vehicle in `SpaceVehicles.xml`.
- **[C] Gravity:** world level via `GTSLib_SetWorldGravity` (arbitrary), and per entity via `HasGravity`. Low-gravity jumping is a velocity impulse.
- **[C] The shuttle launch** (`SpaceShuttle.Launch`): `ApplyForce(Forward × speed, gimbal (0, 0, 0.18))`, with speed ramped to `ShuttleNewtonsOfForce` (9.8). Boosters detach at **5 km** and the tank at **7 km** (`HeightAboveGround`). It stops at `EnterOrbitHeight`. These are GTA vehicles attached with `AttachTo`.
- **[C] Air drag:** `GTSLib_SetAirDragMultiplierForPlayersVehicle` (closed ASI).
- **What GTA exposes that Cyberpunk didn't** [C] (native DB):
  - `APPLY_FORCE_TO_ENTITY(entity, flags, x, y, z, offX, offY, offZ, bone, relDir, ignoreUp, relForce, ...)`: **force at an offset, so torque, officially**;
  - `SET_ENTITY_VELOCITY`;
  - `SET_ENTITY_HAS_GRAVITY` / `SET_VEHICLE_GRAVITY`;
  - `SET_GRAVITY_LEVEL(0..3)` = 9.8 / 2.4 / 0.1 / 0 (**presets only**);
  - `SET_ENTITY_MAX_SPEED`;
  - built-in aircraft, helicopters, VTOL and jetpack-class vehicles.
- **Comparison with Carrier:** NCM's F0 force model is far easier in GTA. What Carrier had to discover (the force accumulator, the unverified `+0x0C` torque) is a documented native there. **Harder in GTA:** arbitrary gravity values without a memory patch, and anything past the 150 m/s cap without a patch.

## 7. Streaming

- **[C] What loads when:**
  - per scene: models are requested and props spawned on start, and all deleted on scene exit (`Scene.Delete` / `ClearLists`);
  - interiors: `REQUEST_IPL` / `REMOVE_IPL`, or Map Editor XML spawned as props, peds and vehicles (`Scenes/Interiors/Interior.cs`);
  - `MapLoader` loads "LoadOnStart" maps once;
  - surface tiles are a fixed pool, repositioned rather than respawned.
  - Every scene change is a **full swap** behind a fade.
- **[C] Assets** ship as **dlcpacks** (models such as `spacedome`, planets and the shuttle) installed with OpenIV.
- **Single player vs FiveM:**
  - IPL requests, prop spawning, timecycle, weather and clock natives exist in FiveM client scripts **[I, high confidence]**;
  - custom models stream from FiveM resources (ydr/ytyp/ymap) **[I]**;
  - ASI-backed functions (arbitrary gravity, drag, bounds) do not exist without client plugins (§8).

## 8. FiveM compatibility

**Confirmed constraints:**
- **[C]** FiveM blacklists **ScriptHookVDotNet**, so GTS as written cannot run.
- **[C]** ASI plugins only run when a server enables "Allow Scripthook". That's a security-weakening opt-in, and FiveM blocks outdated plugins.
- **[C]** GTS's critical natives (arbitrary gravity, air drag, **boundary removal**) are memory patches in closed `.asi` files.

| Technique | Category |
|---|---|
| Player-following sky dome (client-local prop at the camera) | **A: directly feasible.** A non-networked object and a per-frame position. |
| Time/weather/timecycle override for the space view | **C: client-local.** Fine as a client-only view, but must not fight the server's weather sync. |
| Fade + reposition seam | **B: feasible differently.** The server must own the move of a networked vehicle (OneSync); the NC lesson §SG2 is likely to repeat. **[U] needs a probe.** |
| In-scene floating origin (move the world, keep the player near a point) | **C/D.** Moving *every networked player* is not possible client-side. Each client may move only its own **proxies**; the player's own entity moves need server authority. |
| Scenes at z = 30,000 | **E: unknown.** Depends on FiveM's stock bounds without NBL. **The first probe.** |
| Arbitrary gravity | **B:** use `SET_ENTITY_HAS_GRAVITY` + force, or the four `SET_GRAVITY_LEVEL` presets, not a memory patch. |
| Scripted / force flight | **A:** `APPLY_FORCE_TO_ENTITY`, `SET_ENTITY_VELOCITY` on owned entities. Speed past 150 m/s is **E** (`SET_ENTITY_MAX_SPEED` may suffice). |
| Custom models (dome, planets) | **A:** streamed from a resource. **Licensing: our own assets, not GTS's.** |
| Surface tile streaming | **A/C:** client-local tiles are fine for looks; collision for multiplayer racing must be identical on every client. |
| Remote players in space | **C:** proxies rendered from server state (the Snowglobe protocol), like the NC plan. |
| Boundary patching, ASI | **D: dangerous or incompatible** for a public server. |

## 9. Legacy → Enhanced fault lines

- **[C]** The fan update is **Legacy only**; GTS needs ScriptHookV + SHVDN (v2-era), memory patterns (`MemoryAccess.Pattern`, the GtsLib comments), and closed ASIs bound to game builds.
- **[C]** NBL-Enhanced keeps **separate patterns for Legacy and Enhanced** (`Pointers.cpp`): memory layouts differ between them.
- **[I]** Assets as dlcpacks/OIV need Enhanced conversion (Cfx's Alchemist for FiveM Enhanced).
- **Rule for NCM:** canonical NCM must not depend on memory offsets, ASI or ScriptHook. Only FiveM natives and streamed resources. The Legacy-specific things are build-pinned assets and any client plugin.

## 10. GTS vs NCM Snowglobe

| Problem | Grand Theft Space (SP) | NCM Cyberpunk Snowglobe (Online) | Possible NCM FiveM approach |
|---|---|---|---|
| Leaving the base map | Height above ground > 10 km, then fade 100 ms, then teleport | Game z ≥ 14 km while climbing, then the server's `setTransform` rebase (§SG8) | The server moves the owned vehicle at an altitude trigger, the same as NC |
| Hiding the base world | Distance (z 30 km) + opaque sky dome + density 0 | None yet (the city stays a blur below) | A client-local dome at the camera (A) |
| Universe position | Scene-relative only (`SimulatedPosition`) | `space.universe` (Earth frame, doubles) + per-car offset | The same `space.universe` model, server-side (shared protocol) |
| Local coordinates | Within about 2.5 km of `GalaxyCenter` | Game z 4-14 km band | A band inside FiveM's stock bounds (**probe**) |
| Stars/sky | `spacedome` texture on the dome | Not built | Our own dome asset |
| Planets | Prop in a space scene; surface = separate scene | Not built (proxy maths in `space.universe`) | Proxy at true angular size, then a surface region on approach |
| Planet approach | Trigger radius, then scene swap behind a fade | Not built | Proxy → a dedicated surface area (seam allowed per L317) |
| Gravity | Arbitrary via closed ASI; per entity `HasGravity` | Unchanged (REDengine gravity; F4 later) | `SET_ENTITY_HAS_GRAVITY` + force, or the 4 presets |
| Spacecraft movement | Scripted quaternion + velocity lerp, or `ApplyForce` | Carrier gravity-entry lift lever (F0) | `APPLY_FORCE_TO_ENTITY` with offsets |
| Rebasing | Client moves the world, keeps velocity | Server `setTransform`, speed lost (by ruling) | Server-owned; proxies rebased client-side |
| Streaming | Full scene swap; tile pool; IPL / Map Editor | Not built | Resource-streamed assets; client-local tiles; scene swap behind a fade |
| Multiplayer | None | Server authority; per-player bubble | The same, plus cross-server proxies (L318) |
| Re-entry | Fixed position (-4000, 2000, 5000), fixed 150 m/s | Rebase up below 3 km; home when offset 0 | Server move back over the matching point; speed is presentation |

## 11. Top 5 ideas worth carrying into NCM

1. **A camera-following sky dome** with always-prerender. A cheap, client-local "you are in space" with no world change. It works in FiveM (A) and is likely portable to REDengine as an NCM-spawned entity.
2. **A floating origin with velocity restore** (`KeepInSafeZone`). This confirms our L317 design. In multiplayer, keep the player's own move server-owned and rebase only client-local proxies.
3. **Two representations per body, swapped by distance:** a prop or proxy far away, a surface scene up close, with a fade allowed. That's L317's "Moon proxy → surface" path, proven workable in GTA.
4. **Camera-attached distant bodies with controlled parallax** (AttachedOrbital `ShiftAmount`). Distant objects don't need real coordinates, only a direction and an apparent size, as in `space.universe.proxy`.
5. **Scenes as data** (an XML scene: sky, time, weather, gravity, bodies, links). This matches NCM's "describe things, let runtimes express them" (L314). An NCM seed could generate scene records.

## 12. Top 5 GTS assumptions not to inherit

1. **Memory patches and closed ASIs** for gravity, drag and bounds. Not FiveM-safe, not Enhanced-safe, not licensed.
2. **A client-authoritative teleport of a networked vehicle.** It's fine in single player; on a server it is exactly the §SG2 `motion_jump` veto.
3. **Scene-relative position as the only truth.** GTS has no universe coordinate across scenes. NCM needs `space.universe` (L318 interfaces) for cross-world proxies.
4. **Fixed re-entry point and speed.** It erases where you were. NCM should return over the matching universe point (Snowglobe's rebase-up already does).
5. **Velocity-lerp flight as the physics.** It's arcade. NCM flight should come from force-producing parts (L314/L316), and GTA's `APPLY_FORCE_TO_ENTITY` makes that easier, not harder.

## 13. Top 5 unknowns needing our own GTA/FiveM probes

1. **FiveM's stock world bounds** on x/y/z without NBL: how high can an owned vehicle go, and what happens at the bound (teleport, kill, freeze)? The equivalent of our §AX4.
2. **A server-side move of an occupied vehicle in FiveM (OneSync):** does `SetEntityCoords` from the server keep the driver, velocity and ownership? Is there a `motion_jump`-style veto?
3. **The 150 m/s entity cap under FiveM:** does `SET_ENTITY_MAX_SPEED` lift it without a memory patch?
4. **A client-local sky dome and timecycle in FiveM** while the server syncs weather: do they coexist? Does a large streamed dome render without LOD or far-clip problems?
5. **Remote proxies at altitude:** does FiveM's OneSync culling/scoping still deliver other players' state at 10-30 km, or must the Snowglobe protocol carry it itself?
