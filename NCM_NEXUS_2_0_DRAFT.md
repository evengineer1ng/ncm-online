# Night City Motorsports 2.0 — Nexus Draft

> Local review artifact. Do not publish without explicit approval.

## Short summary

Build a racing career across Night City. Take calls for underground events, face persistent rivals, tune and upgrade your cars, climb championship standings, and watch every result reshape your reputation, opportunities, and enemies. Version 2.0 is a public beta; 1.84 remains available as the stable fallback.

## Description

Night City Motorsports turns Cyberpunk 2077's streets into a persistent underground racing scene.

This is more than a race launcher. Drivers remember results. Rivals develop careers and vehicle builds. District pressure rises. Championships move from round to round. Wins, losses, clean driving, wagers, parts, fans, and factions create reasons to care about the next start.

### What you do

- Follow the native NCM quest and contact Dex to enter the underground scene.
- Use Dex and the existing specialist contacts to arrange races, scout opposition, tune, bet, and review results.
- Take a car to the start and form up with a live AI grid.
- Race sprints, drags, endurance routes, and knockout events.
- Earn reputation, eddies, parts, records, and championship points.
- Learn recurring rivals and adapt your build to the field.
- Use Quick Race when you want a consequence-free sandbox event.

### Your first five minutes

1. Install NCM and its required frameworks.
2. Load a save and accept the native Night City Motorsports quest prompt.
3. Follow its first objective: **Contact Dex** through the existing NCM phone conversation.
4. Use Dex and the existing specialist network; the quest tracker guides the active race while NCM supplies the GPS route.
5. Arrange a race through the appropriate contact, follow the route, enter the start area, align the car, and wait for the grid.
6. Follow the native race HUD through the start, race, classification, and result.

The Cyber Engine Tweaks panel remains available for custom careers, route authoring, detailed tuning, diagnostics, and recovery. It is the advanced toolbox, not the intended normal race loop.

### What makes the career persistent

- A seeded roster of drivers with names, personalities, pace, precision, consistency, aggression, preferred regions, vehicle classes, hardware, form, and history.
- Five prestige tiers from Gonk to Edgerunner, with reputation that can rise or fall.
- Championship seasons and both driver and faction standings.
- Named rivals, bounties, district heat, fan reactions, and contact opportunities.
- Career-scoped parts, vehicle loadouts, setup profiles, records, telemetry, and safety rating.
- Live visible AI backed by simulated timing and recovery paths when Night City's open world refuses to cooperate.

### Race formats

- **Sprint:** point-to-point street racing with larger fields.
- **Drag:** straight-line events with lane and straightness rules.
- **Endurance:** multi-leg routes through checkpoints.
- **Knockout:** checkpoint racing with one-by-one elimination.
- Standing, rolling, and side-by-side starts are supported where the event permits them.

### 2.0 public beta

Version 2.0 adds the phone/SMS layer, richer management and ambient simulation, betting and fan systems, named-rival presentation, expanded garage/build behavior, and additional native integration.

It is currently a public beta because clean-install and upgrade coverage across other machines is still being expanded. Version 1.84 remains available as the stable fallback. Back up the NCM `save` folder before moving an established career between versions.

Known beta limitations:

- Some open-world locations are less reliable for large live grids than others.
- Recovery may use a reduced live field or simulated/ghost classification when AI cannot spawn or remain tracked.
- Most route-authoring and deep diagnostic tools still live in CET.
- Ambient races are substantially simulated; only eligible events can be promoted into live races.
- Live promoted knockout heats are not yet supported.
- Management is currently a focused one-driver contract system, not a full team-management game.

### Requirements

Required dependency list and supported versions must be verified against the final 2.0 release before publishing:

- Cyber Engine Tweaks
- RED4ext
- redscript
- ArchiveXL
- TweakXL
- Codeware
- Native Settings UI
- Input Loader
- Custom Map Markers

Follow each dependency's installation instructions and launch the game once after updating frameworks.

### Installation

1. Install and verify the required frameworks.
2. Install the NCM 2.0 archive with Vortex or extract it into the Cyberpunk 2077 game directory while preserving the included folder structure.
3. Start the game and load a normal playable save.
4. Follow the NCM quest objective and contact Dex through the phone.
5. If the phone contact does not load, open CET and use the NCM Overview/diagnostics before reporting a bug.

Do not copy development saves, logs, or backup files into the game. The release archive already contains only the intended runtime payload.

### Updating from 1.x

1. Back up `bin/x64/plugins/cyber_engine_tweaks/mods/MT_Ecosystem/save`.
2. Close the game completely.
3. Update all required frameworks.
4. Replace the old NCM runtime files with the 2.0 package; do not merge old Lua modules into the new version.
5. Load the career and verify its name, tier, roster, season, garage, and records before continuing.
6. If the upgrade fails, restore the backup and report the versions and log evidence listed below.

### Troubleshooting

**No phone contact:** verify redscript, ArchiveXL, TweakXL, Codeware, and the NCM archive/script folders. Open CET and check whether NCM reports the phone bridge as loaded.

**No NCM panel:** open CET bindings and assign/reassign the NCM panel hotkey. The panel is an advanced and recovery surface.

**Grid will not form:** remain near the start, stop the vehicle, align with the indicated direction, and let traffic/world state settle. Use Race Control or CET diagnostics if NCM reports a failed grid.

**Race uses fallback classification:** NCM may finish classification using tracked timing when live AI despawn or become stuck. Include the spawn/race log when reporting repeated cases.

**Career appears missing:** do not create repeated replacement careers. Back up the current save folder and attach the relevant NCM logs/configuration details to a report.

### Reporting a useful bug

Include:

- Cyberpunk and NCM versions;
- versions of all required frameworks;
- clean install or upgrade, and the previous NCM version;
- exact race mode, route/district, field size, start type, and vehicle;
- what the HUD/phone displayed before failure;
- repeatable steps and whether restart/reload reproduces it;
- CET/NCM log excerpt around the failure;
- other driving, traffic, vehicle, HUD, or phone mods;
- screenshots/video and a backed-up save fixture when practical.

Remove personal information and unrelated logs before sharing files publicly.

### Optional integrations

- Manual Transmission V10 for clutch and manual-shifting play.
- Custom vehicles and handling mods, with the understanding that balance varies.
- Sim-rig utilities such as `evengineer1ng/anyffb` for experimental audio-driven wheel feedback.
- Future curated Essentials and Essentials + Goodies collections.

Optional integrations are never required for the basic NCM career loop.

### Screenshots and video needed

1. NCM-online HUD toast and the native `Contact Dex` quest objective.
2. In-world signup interaction and first tutorial objective.
3. Live AI grid in a recognizable Night City location.
4. Native HUD during a close race.
5. Official result and career consequences.
6. Recurring named rival and faction identity.
7. Garage part/loadout and simplified setup recommendation.
8. Championship standings before a decisive round.
9. Short video: install-to-first-race journey.
10. Longer video: one event showing offer, staging, race, and fallout.

### Localization help

NCM contains more than 1,300 English runtime strings. Translators should work from the provided translator template and preserve IDs/placeholders. Static journal choices require the canonical WolvenKit source and are coordinated separately. Short, natural motorsport language is preferred over literal technical phrasing.
