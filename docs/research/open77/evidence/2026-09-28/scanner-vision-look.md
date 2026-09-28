# Scanner look without the scanner: can NCM Online show the green filter and reticle?

> **STATUS: HISTORICAL** — read-only research, 2026-09-28. No production behaviour changed. Feeds `IDEA-624`
> (the Scanner's *interaction* half) and `IDEA-679`.
>
> **Outcome, same day:** the owner chose tier 2 as a new standalone mod. It was built as `ncm-vision`, redscript
> only, under `L196`. Live proof is owed at `MASTER_TEST §BY`. §7's Carrier probe is superseded, and the Carrier
> is not to be modified for this.

Owner question: *can we implement the visual greenish filter and reticle from the vanilla scanner, or a similar
experience, without time dilation, for NCM Online machine discovery?*

**Answer: yes, in two tiers.** The reticle, target lock and outline can be built today from published OPEN//77
Lua, with no new permission beyond the manifest. The real green filter is possible but needs NCM's own
client-native code (the Carrier, or a `.reds` in the world package) and a live probe. It cannot be switched on
from Lua. OPEN//77 already guarantees there will be no time dilation.

Sources: the build-pinned MCP devkit (index served for `op77.78`, the newest published at or below `op77.102`),
OPEN//77's shipped client redscript (`r6/scripts/Open77/Open77MultiplayerPolicy.reds`), CDPR's decompiled
`playerVisionModeController.script`, and Nexus metadata through GraphQL.

---

## 1. Why the vanilla scanner cannot simply be re-enabled

- `Open77MultiplayerPolicy.reds:285-334` wraps `PlayerVisionModeController.OnAction`, `VerifyActivation`,
  `OnInvalidateActiveState` and `VisionContextDecisions.EnterCondition`. Each one refuses when
  `Open77HudHidden(9)` is true.
- `Open77HudHidden(c)` is `Open77MultiplayerPolicyActive() || !Open77HudComponentVisible(c)` (`:2494`).
  **The session half is unconditional.** No resource claim or API can release it. The `hud-visibility` guide
  says the same thing: *"releasing your claim will not bring them back until the session ends."*
- The `input-blocking` guide lists `Scanner` and `Quickhack` as **already enforced**. *"Tab still reaches WebUI
  and key mappings."* So Tab is free for NCM to bind.

## 2. Time dilation is already solved, separately

`Open77MultiplayerPolicy.reds:336-370` refuses `TimeDilationFocusModeDecisions.EnterCondition` and swallows
`TimeDilationFocusModeEvents.OnUpdate` while the multiplayer policy is active. The same file refuses
`TimeDilationHelper.SetTimeDilationWithProfile` at the source (`:614+`). **The slow-motion is a
player-state-machine state, not part of the render.** Even if the green render is turned on, OPEN//77 will not
slow the world. NCM needs to do nothing for the "without time dilation" requirement.

## 3. What the green look actually is

In CDPR's `PlayerVisionModeController`, `ActivateVisionMode()` makes three independent calls:

```
GameInstance.GetVisionModeSystem(game).GetScanningController().EnterMode(owner, gameScanningMode.Heavy)  // scan-on-look + scanner HUD
GameInstance.GetVisionModeSystem(game).EnterMode(owner, gameVisionModeType.Focus)                        // THE GREEN RENDER
ApplyFocusModeLocomotionRestriction()                                                                     // walk-only status effect
```

`DeactivateVisionMode()` is the mirror: `EnterMode(owner, gameVisionModeType.Default)`, scanning `Inactive`,
remove the restriction. **The render call can be made alone**, without the scanning HUD and without the
movement restriction. OPEN//77 wraps only the controller. A grep of its redscript for `VisionModeSystem`,
`EnterMode` and `gameVisionModeType` finds nothing, and `Open77.dll`'s strings show no vision-mode detour
either. So nothing currently intercepts the lower layer. That is **static evidence, not a live result.**

The look itself is depot content. Nexus
[Scanner Visuals Customizer](https://www.nexusmods.com/cyberpunk2077/mods/27585) (2.31, updated 2026-08-30) names
its parts: **green LUT, vignette, scanlines, zoom pixelation**, plus gain/gamma/contrast/saturation.
[Preem Scanner](https://www.nexusmods.com/cyberpunk2077/mods/9215) (~850k downloads) restyles it with **one inert
`.archive`** and nothing else. So NCM could ship its own tint as inert content, which a secured world also
accepts. It would only show while vision mode is active.

## 4. Can NCM reach `VisionModeSystem.EnterMode`?

| Route | Verdict |
|---|---|
| OPEN//77 Lua (`Open77.*`) | **No.** There is no native for it, and client Lua has no engine RTTI (`L1`). |
| `Open77.vfx.screen` | **Not the scanner.** The curated catalogue is 18 aliases: drunk, drugged, health, pain, burning, blinded, blackout and so on. There is no focus/scanner alias, and raw engine names are refused (`unsupported_screen_effect`). `drugged.light` or `electrocuted` could stand in as a "scan pulse" flourish. |
| `Open77.debug.redscript` | **No.** Needs `debug.runtime` and the trusted `open77_debug` owner. Admin-only. |
| **NCM Carrier** (RED4ext DLL, already shipped via `requiredMods`) | **Yes, most direct.** It already runs native code in the client and already has a Lua↔plugin channel (`carrier_bridge.lua`). One new message, `vision on/off`, would call the two `EnterMode` functions through RTTI. |
| A `.reds` in a world package | **Yes, but it needs a trigger.** Redscript cannot hear NCM Lua directly, so the Carrier would still carry the signal. Executable class, so it needs an unsecured world or a verified attestation. The dev server is `unsecured: true` (`tools/open77/server/server.jsonc:127`). |

## 5. Building the experience now, with no native code

Everything here is published and client-local:

| Need | Native | Notes |
|---|---|---|
| Hold/toggle key | `RegisterKeyMapping` (`input.actions`) | Tab is free: the platform refuses the scanner controller, not the key. Rebindable. |
| What am I aiming at | `Open77.character.aimedEntity()` (`player.aim.read` + `world.query`) | The engine's own look-at target. It returns `vehicleId` when the target is an OPEN//77 network vehicle, which **answers `IDEA-197`'s "engine entity → network vehicle" question on paper**. It still needs a live probe from a moving car. |
| Outline the target | `Open77.inspector.outline(true)` | Uses `entRenderHighlightEvent`, *"the same event focus mode and scanning already use."* That is the genuine vanilla scan outline, but not the tint. |
| Reticle / brackets that track a moving car | `Open77.camera.project(pos)` → `{x,y,onScreen}`, `Open77.world.entityGeometry` for bounds | Draw corner brackets and a lock-progress arc in a transparent WebUI. |
| Screen tint | A full-screen WebUI layer | A CSS green multiply layer, a vignette gradient, scanlines. It sits over the world, not graded into it, so it is flatter than the real LUT. It will also tint anything drawn beneath it in the same page. |
| Pulse / flourish | `Open77.vfx.screen("drugged.light", {duration=…})` (`vfx.screen`), `Open77.sfx`, vanilla `ui_focus_mode_scanning_qh` sound | OPEN//77's own hacking presentation uses that sound (`Open77HackingPresentation.reds:157`). |
| Zoom | `Open77.camera.setFov` | Vanilla scanning narrows the FOV. Optional. |

The server must still revalidate: the client sends a candidate `vehicleId`, and the server checks range and
line of sight before writing `identity_reveal` / `observed_configuration` (`L174`, `IDEA-624`).

## 6. Risks and unknowns (each needs a live row, none are assumed)

1. **Focus render side effects.** `EnterMode(Focus)` also fires vanilla highlight callbacks on NPCs, devices and
   loot. In a sparse world that may be harmless or noisy. It may also toggle `UI_VisionMode` blackboard values
   that OPEN//77's HUD policy reads.
2. **Future platform interception.** OPEN//77 may start refusing `VisionModeSystem` too. It does not today.
3. **In-vehicle behaviour.** Vanilla allows driver scanning, but the render has not been observed from a moving
   NCM car.
4. **Racing fairness.** A full-screen filter reduces visibility, so it should be refused while the player is
   entered in a live session.
5. **`aimedEntity` from a cockpit.** Whether the look-at target resolves other cars while driving is unmeasured.

## 7. Next action

Two probes, cheapest first:

1. **Lua probe (no native code):** bind a key; on hold, log `aimedEntity()` every 100 ms, call
   `inspector.outline(true)` and draw projected brackets in a debug WebUI. Record whether `vehicleId` resolves
   for parked cars, moving cars and your own car from the driver's seat.
2. **Carrier probe:** a debug-only `vision` message that calls `EnterMode(player, Focus)` and then `Default`.
   Record: green render yes/no, time scale (expect 1.0), movement, HUD side effects, highlight noise, and
   whether the render survives entering and leaving a vehicle.
