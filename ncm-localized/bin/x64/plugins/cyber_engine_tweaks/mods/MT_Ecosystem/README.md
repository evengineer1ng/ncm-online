# Night City Motorsports 2.0

Build a racing career, meet persistent rivals, tune your car, and change Night City's underground motorsport scene.

NCM supports live AI street racing, persistent careers, championship seasons, recurring rivals, vehicle builds, district heat, betting, records, telemetry, and safety rating. Version 2.0 is a public beta; keep a backup of the mod's `save` folder when upgrading an established career.

## Start here

The intended normal loop is:

1. Load a playable save and wait for the Night City Motorsports phone introduction.
2. Open **Phone → Messages → Dex - NCM Dispatch**.
3. Use Dex and the existing specialist contacts to choose a race, then follow the route to the start.
4. Enter and align with the start area, then wait while the AI grid forms.
5. Follow the native HUD through the countdown, race, classification, and result.
6. Use the existing NCM contact network to review results, tune, bet, scout rivals, or arrange another race.

**Quick Race** is the consequence-free sandbox option. **Race Control** manages a staged or active event. **Career** is the persistent mode where reputation, prestige, rivals, seasons, rewards, and losses matter.

The Cyber Engine Tweaks panel remains the advanced toolbox for custom careers, route authoring, raw telemetry, detailed tuning, diagnostics, and recovery. Normal racing should not require console commands.

> A native onboarding quest beginning with **Contact Dex** is a Phase 1 target. Until that build lands, the current 2.0 beta may still require opening the CET overlay and creating or selecting a career there.

## Installation and recovery

- Install current compatible versions of Cyber Engine Tweaks, RED4ext, redscript, ArchiveXL, TweakXL, Codeware, Native Settings UI, Input Loader, and Custom Map Markers.
- Install the NCM archive into the Cyberpunk 2077 game directory with its folder structure intact.
- When updating from 1.x, close the game and back up `bin/x64/plugins/cyber_engine_tweaks/mods/MT_Ecosystem/save` first.
- If the phone contact does not appear, open CET, verify that NCM loaded, and inspect the NCM log/diagnostic output.
- If a grid is delayed, remain close to the start, stop and align the car, and allow the world to settle. Use Race Control or diagnostics only if NCM reports a failure.

When reporting a problem, include game/NCM/dependency versions, clean-install versus upgrade status, race mode, route, field, start type, vehicle, reproduction steps, relevant logs, and other vehicle/traffic/HUD mods.

The remainder of this file is the advanced race and AI tuning reference.

## Contents

- [Race Tuning Overview](#race-tuning-overview)
- [Units](#units)
- [Settings Resolution](#settings-resolution)
- [AI Driver Speed](#ai-driver-speed)
- [Grid Solver Settings](#grid-solver-settings)
- [Race Settings](#race-settings)
- [Tuning Advice](#tuning-advice)
- [Future Documentation](#future-documentation)

## Race Tuning Overview

Race and grid tuning fields are registered in [`modules/settings.lua`](modules/settings.lua). Global values are persisted in [`save/config.json`](save/config.json) under the `raceTuning` object.

Root-specific route profiles can override those globals through `profileSettings`. At runtime, modules read resolved values through `Settings.getTuningValue`, which merges global tuning with any active root profile override.

Important runtime consumers:

- [`modules/settings.lua`](modules/settings.lua): declares tunable fields, defaults, clamps, persistence, and profile resolution.
- [`modules/ai_vehicles.lua`](modules/ai_vehicles.lua): spawns visible AI cars, builds live AI drive profiles, places grids, and issues vehicle commands.
- [`modules/racing.lua`](modules/racing.lua): owns race configuration, staging flow, simulated AI timing, DNF windows, drag validation, finish resolution, and HUD race state.
- [`modules/ui_routes.lua`](modules/ui_routes.lua): lets route roots stamp or override tuning profiles.

## Units

Most speed settings use meters per second and end with `Mps`.

Quick conversions:

| m/s | mph | Notes |
| ---: | ---: | --- |
| 10 | 22 | Slow city speed |
| 20 | 45 | Rolling-start approach range |
| 30 | 67 | Default expected player pace |
| 60 | 134 | Fast highway race pace |
| 100 | 224 | Hypercar-level race speed |
| 200 | 447 | Extremely high; likely arcade/unstable |
| 300 | 671 | Extreme cap; use with care |

Formula:

```text
mph = mps * 2.237
```

## Settings Resolution

There are two layers of tuning:

1. Global tuning in [`save/config.json`](save/config.json), under `raceTuning`.
2. Optional root-specific tuning in a route/root `profileSettings` table.

Resolution order:

```text
resolved value = root profile override, if present
              or global raceTuning value
              or field default from modules/settings.lua
```

This matters when a route feels different from the global settings. A root profile may be overriding the value. In the Routes UI, `Stamp Current Globals` copies the current global tuning into that root, and `Clear Root Profile` returns the route to global tuning.

## AI Driver Speed

There are two separate AI speed systems:

- Live visible AI speed: the actual spawned cars driven through Cyberpunk AI vehicle commands.
- Simulated/projected AI timing: qualifying estimates, standings, ghost fallback, finish resolution, and DNF timing.

Changing only one can make visible racing and results feel inconsistent.

### Live Visible AI Speed

Live AI speed is built in [`modules/ai_vehicles.lua`](modules/ai_vehicles.lua) inside `buildDriveProfile`.

Mental model:

```text
live AI max speed =
    aiBaseSpeedMps
  * driver pace
  * urgency
  * hardware/control modifiers

then clamped by:
  aiRaceMaxSpeedMps during races
  aiCruiseMaxSpeedMps outside active races
```

Driver stats, personality, tier, vehicle hardware, race type, and urgency all modify the final result. The global settings are the baseline and cap, not the whole formula.

High-impact live speed settings:

| Setting | What It Does | Raise It To... | Lower It To... |
| --- | --- | --- | --- |
| `aiBaseSpeedMps` | Main live AI speed baseline before driver modifiers. | Make all visible AI faster. | Tame the whole field. |
| `aiRaceMaxSpeedMps` | Hard race-speed cap for live AI. | Allow elite/boosted AI to reach higher speeds. | Put a ceiling on runaway cars. |
| `aiCruiseMaxSpeedMps` | Hard cap for non-race AI driving. | Make non-race AI movement faster. | Keep non-race behavior calmer. |
| `aiMinSpeedFrac` | Minimum speed as a fraction of max speed. | Make AI maintain pace harder and slow down less. | Let AI back off more. |
| `aiRecommandIntervalS` | How often healthy AI receive fresh drive commands. | Usually leave alone; higher means fewer refreshes. | Make AI more persistent/reactive. |
| `aiStallSpeedThreshMps` | Speed below which an AI car is considered stalled. | Detect slow/stuck cars sooner. | Avoid over-correcting slow launches. |
| `aiStallTimeThreshS` | How long stall speed must persist before recommanding. | Give AI more time before correction. | Correct stalls faster. |

### Simulated AI Timing

Simulated AI timing is built in [`modules/racing.lua`](modules/racing.lua) inside `Racing._computeAITime`.

Mental model:

```text
projected AI time =
    race distance / projected AI speed
  + launch delay
  + variance
  + crash/discipline modifiers
  + drag straightness penalty, if any
```

High-impact projected timing settings:

| Setting | What It Does |
| --- | --- |
| `aiProjectedBaseSpeedMps` | Baseline projected rival pace for qualifying, AI finish estimates, ghost fallback, and standings resolution. |
| `expectedPlayerRaceSpeedMps` | Baseline player pace used for expected race time and DNF windows. |
| `dnfExpectedTimeMult` | Grace multiplier applied to the player's projected finish time. |
| `dnfSlowestAiMult` | Grace multiplier applied to the slowest projected AI finish time. |
| `dnfSlowestAiGraceS` | Extra seconds added after the slowest projected AI finish. |
| `dnfMinTimeS` | Absolute minimum sprint DNF window. |
| `dnfMaxTimeS` | Absolute maximum race DNF window. |

If visible cars are fast but results are slow, raise `aiProjectedBaseSpeedMps`. If results are brutal but visible cars are manageable, lower `aiProjectedBaseSpeedMps` or increase DNF grace.

### Launch Behavior

Launch-release settings only affect the first command out of the grid. After that, normal live AI speed logic takes over.

| Setting | What It Does |
| --- | --- |
| `aiLaunchGraceTimeS` | Delay after green before stall and recommanding logic starts judging launches. |
| `aiLaunchReleaseMaxSpeedCapMps` | Maximum speed cap on the first release command. |
| `aiLaunchReleaseMinSpeedCapMps` | Minimum speed cap on the first release command. |
| `aiLaunchReleaseForcedSpeedCapMps` | Initial forced start speed cap. |
| `aiLaunchReleaseTargetDistanceM` | Short target distance used to pull AI cleanly off the line. |

If AI launch too violently, reduce `aiLaunchReleaseForcedSpeedCapMps` and `aiLaunchReleaseMaxSpeedCapMps`. If they bog down or fail to clear the line, raise them slightly or increase `aiLaunchGraceTimeS`.

### Chase And Follow Behavior

Some AI use chase/follow commands against the player instead of only driving to a point.

| Setting | What It Does |
| --- | --- |
| `aiChaseDistanceMinM` | Baseline closest chase gap before aggression/player-bias adjustments. |
| `aiChaseDistanceMaxM` | Baseline farthest chase gap before racecraft/player-focus adjustments. |
| `aiFollowDistanceMinM` | Baseline minimum follow gap for non-chase AI. |
| `aiFollowDistanceMaxM` | Baseline maximum follow gap for non-chase AI. |

Smaller values make AI feel more glued to the player. If rivals feel too clingy but not necessarily too fast, increase these before lowering speed.

### Rolling Start AI

Rolling starts have a controlled formation zone before open racing.

| Setting | What It Does |
| --- | --- |
| `rollingPaceBaseMps` | Baseline pole pace in the rolling zone. |
| `rollingPaceMinFloorMps` | Minimum controlled rolling pace. |
| `rollingPaceMaxCeilMps` | Maximum controlled rolling pace. |
| `aiRollingControlIntervalS` | Cadence for re-issuing rolling-start pace/order commands. |
| `aiRollingWarmupIntervalS` | Cadence for pre-green rolling warmup rev behavior. |
| `aiRollingWarmupMaxBlips` | Max warmup rev-ready bursts per tick. |
| `aiRollingWeaveSpeedBiasMps` | Speed bias caused by rolling-start aggression/weaving. |
| `aiRollingCreepMaxMeters` | Maximum forward pressure inside rolling formation. |

## Grid Solver Settings

Grid solver settings control staging, orientation, spacing, traffic cleanup, and where AI cars appear. AI placement is calculated in [`modules/ai_vehicles.lua`](modules/ai_vehicles.lua) by `calculateFormation` and the grid solver pipeline.

### Player Staging

| Setting | What It Does |
| --- | --- |
| `startReadyRadiusM` | How close V must be to the start node to count as staged. |
| `startCaptureRadiusM` | Radius around the start node where auto-stage approach logic can begin. |
| `startSnapMaxSpeedMps` | Maximum player speed allowed before stage snap can fire. |
| `startTeleportZLiftM` | Vertical lift applied when snapping V to reduce clipping. |
| `startTeleportBackoffM` | Places V slightly behind the node instead of directly on it. |
| `startSlotHeadingOffsetDeg` | Yaw offset used when aligning V to the staged slot orientation. |

### Grid Stability

| Setting | What It Does |
| --- | --- |
| `gridSpawnStableTimeS` | Clean staged-window time required before live grid spawn begins. |
| `gridSpawnStableTicks` | Consecutive clean update ticks required before live grid spawn begins. |

Increasing these can make staging more cautious. Lowering them can make grids spawn sooner, but may increase spawn weirdness if the world is still settling.

### Grid Orientation

| Setting | What It Does |
| --- | --- |
| `gridHeadingOffsetDeg` | Rotates the resolved grid basis before slots are laid out. |
| `gridLateralShiftM` | Moves V and the whole staged grid left or right. |
| `gridForwardAlignmentDot` | How closely player forward must match route heading before it influences grid basis. |
| `aiGridForwardAlignmentDot` | Same idea, but for AI grid basis. |
| `aiSlotHeadingOffsetDeg` | Yaw offset applied to staged AI cars. |

Use these when cars are lined up sideways, backward, or one lane off. Start with heading offsets in 90-degree chunks, then fine tune lateral shift.

### AI Grid Spacing

| Setting | What It Does |
| --- | --- |
| `aiGridRowSpacingM` | Distance between AI rows in a standard standing grid. |
| `aiGridColOffsetM` | Left/right column offset in two-wide grids. |
| `aiGridStartSetbackM` | How far the first visible AI row sits behind V. |
| `aiRollingRowSpacingM` | Row spacing used for rolling starts. |
| `aiSideBySideSpacingM` | Lateral spacing between cars in side-by-side starts. |
| `aiSideBySideSetbackM` | Fallback setback when side-by-side starts have no explicit player slot. |

If cars overlap, increase row/column spacing. If the field is too spread out, reduce spacing carefully.

### Traffic Cleanup

| Setting | What It Does |
| --- | --- |
| `trafficClearRadiusM` | Radius around the start node scrubbed during staging. |
| `trafficClearRetryIntervalS` | Cadence for repeated ambient-traffic cleanup during staging cooldown. |

If grid spawns are blocked by ambient traffic, increase `trafficClearRadiusM`. If cleanup feels too aggressive, lower it.

## Race Settings

### Finish Detection

| Setting | What It Does |
| --- | --- |
| `finishLineWidthM` | Default lateral distance from the finish node that counts as a crossing. |
| `genericRoadFinishLineWidthM` | Fallback finish width for user or generic road nodes. |
| `finishArmDistM` | Distance from finish where crossing detection arms. |

If finishes fail to trigger, increase width or arm distance. If finishes trigger from nearby roads, reduce width.

### Rolling Starts

| Setting | What It Does |
| --- | --- |
| `rollingStartMaxSpeedMps` | Maximum speed V may carry while entering a rolling start. |
| `rollingCountdownSeconds` | Release delay once the rolling field is formed. |
| `rollingZoneLengthM` | Controlled discipline zone before open racing. |
| `rollingPlayerWarningIntervalS` | Cadence for rolling-start give-back and pace-window warnings. |
| `rollingPlayerProgressGraceM` | Tolerance before V is treated as materially ahead of order/progress. |

### Drag Race Validation

Drag route settings decide whether a start/finish pair is eligible for drag mode and how many lanes it can support.

| Setting | What It Does |
| --- | --- |
| `dragRouteMinDistanceM` | Minimum strip length accepted for drag mode. |
| `dragRouteMaxDistanceM` | Maximum strip length accepted for drag mode. |
| `dragRouteMaxGrade` | Rejects drag strips steeper than this grade. |
| `dragRouteMaxPathDeviationM` | Reference maximum sampled path deviation for straightness scoring. |
| `dragRouteAvgPathDeviationM` | Reference average sustained bend for straightness scoring. |
| `dragRouteHardRejectLoad` | Straightness load above which a strip is rejected outright. |

### Drag Penalties

| Setting | What It Does |
| --- | --- |
| `dragStraightnessPenaltyMaxS` | Maximum time penalty for eligible but imperfect strips. |
| `dragStraightnessPenaltyExponent` | Higher values punish crooked strips more aggressively. |

The same straightness logic is used for static route scoring and live drag straightness updates.

### Drag Lanes And Widths

| Setting | What It Does |
| --- | --- |
| `dragMinSupportedLanes` | Minimum supported lanes required to allow drag mode. |
| `dragMaxAiRivals` | Maximum AI rivals allowed in the current drag field. |
| `dragDefaultMinRoadWidthM` | Fallback width for non-road drag candidates. |
| `dragDefaultUrbanRoadWidthM` | Fallback width for urban drag nodes. |
| `dragDefaultOpenRoadWidthM` | Fallback width for open-road drag nodes. |
| `dragGenericVehicleWidthM` | Nominal vehicle width used for lane calculations. |
| `dragLaneCenterSpacingM` | Distance between lane centers in drag mode. |
| `dragLateralMarginM` | Lane edge buffer used in drag width checks. |
| `dragMinFinishWidthM` | Minimum finish-line width for drag traps. |
| `dragFinishWidthPerLaneM` | Extra finish-line width allocated per active drag lane. |

### DNF Behavior

| Setting | What It Does |
| --- | --- |
| `dragDnfMinTimeS` | Absolute minimum DNF window used for drag races. |
| `dnfExpectedTimeMult` | Grace multiplier applied to the player's projected finish time. |
| `dnfSlowestAiMult` | Grace multiplier applied to the slowest projected AI finish. |
| `dnfSlowestAiGraceS` | Fixed extra seconds added on top of the slowest projected AI finish. |
| `dnfMinTimeS` | Absolute minimum sprint DNF window. |
| `dnfMaxTimeS` | Absolute maximum race DNF window. |
| `dnfNearFinishDistanceM` | Distance to line that arms one-shot near-finish grace. |
| `dnfNearFinishGraceS` | Extra seconds granted after entering near-finish window. |

### Finish Resolution

Finish resolution controls how long the race waits for visible trailing rivals after V finishes before simulated timing fills the rest.

| Setting | What It Does |
| --- | --- |
| `finishResolveMinWaitS` | Minimum live classification wait after V crosses. |
| `finishResolveMaxWaitS` | Maximum wait before trailing field is simulated. |
| `finishResolveVisibleGapCapS` | Maximum projected visible-rival gap that can extend live wait. |
| `finishResolveGapBufferS` | Extra cushion added over projected trailing visible gap. |
| `finishResolveSimTailStepS` | Tail spacing applied when simulated visible rivals are resolved. |
| `finishResolveUntrackedOffsetS` | Base offset applied to untracked rivals behind live field. |

### AI Navigation And Runoff

| Setting | What It Does |
| --- | --- |
| `aiAutonomousTargetDistanceM` | Baseline autonomous target distance for race AI commands. |
| `aiFinishRunoffDistanceM` | How far sprint/knockout AI continue beyond the finish. |
| `aiDragFinishRunoffDistanceM` | How far drag AI continue beyond traps before settling. |

## Tuning Advice

For AI speed, tune in this order:

1. Set `aiBaseSpeedMps` to the rough live speed you want.
2. Set `aiRaceMaxSpeedMps` as the hard ceiling.
3. Adjust `aiMinSpeedFrac` if AI slow down too much or refuse to back off.
4. Adjust `aiProjectedBaseSpeedMps` so standings and finish timing match the visible race.
5. Adjust launch-release settings if the issue is only the first second off the line.
6. Adjust chase/follow distances if the issue is clinginess rather than raw speed.

Example warning signs:

| Symptom | First Settings To Check |
| --- | --- |
| AI are absurdly fast everywhere | `aiBaseSpeedMps`, `aiRaceMaxSpeedMps` |
| AI launch like rockets, then settle | `aiLaunchReleaseForcedSpeedCapMps`, `aiLaunchReleaseMaxSpeedCapMps` |
| AI results are too fast, but visible cars are fine | `aiProjectedBaseSpeedMps` |
| Visible cars are fast, but results are too slow | `aiProjectedBaseSpeedMps` |
| AI stick to V's bumper | `aiChaseDistanceMinM`, `aiFollowDistanceMinM` |
| AI overlap on grid | `aiGridRowSpacingM`, `aiGridColOffsetM`, `aiSideBySideSpacingM` |
| Cars face the wrong way | `gridHeadingOffsetDeg`, `aiSlotHeadingOffsetDeg`, `startSlotHeadingOffsetDeg` |
| Finish does not trigger | `finishLineWidthM`, `genericRoadFinishLineWidthM`, `finishArmDistM` |
| Drag routes are rejected too often | `dragRouteMinDistanceM`, `dragRouteMaxDistanceM`, `dragRouteMaxGrade`, `dragRouteHardRejectLoad` |

Current global configs can be inspected directly in [`save/config.json`](save/config.json). Be careful with extremely high values such as `aiBaseSpeedMps=200` or `aiRaceMaxSpeedMps=300`; those are roughly 447 mph and 671 mph.

## Future Documentation

Planned sections for this README:

- [NCM 2.0 Systems](NCM_2_0_SYSTEMS.md).
- Installation and load order.
- Required Cyber Engine Tweaks / NativeSettings setup.
- Quick Race flow.
- Careers and championship flow.
- Routes, roots, curated nodes, and user nodes.
- Driver roster, tiers, prestige, and vehicle selection.
- Vehicle tuning and parts.
- Knockout and endurance race modes.
- Telemetry files and HUD bridge state.
- Common troubleshooting and log signatures.
