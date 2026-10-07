# Kitten Space Agency as the host past NCM Deep: probe results (L335)

> **STATUS: RESEARCH (probe passed; the in-game flight not yet flown)** - 2026-10-07. Decision: [DECISION_RECORD L334/L335](../../ncm-online/DECISION_RECORD.md).
> Idea: IDEA-1169.

## What is installed (owner's PC)

| Piece | Where | Notes |
|---|---|---|
| KSA 2026.10.10.5554 | `C:\Program Files\Kitten Space Agency` | Ahwoo installer, Authenticode-signed by ROCKETWERKZ STUDIOS LIMITED. Self-contained .NET 10, custom engine "Brutal", Bepu physics. |
| StarMap 0.4.7 (MIT) | `%LOCALAPPDATA%\NCM\StarMap` | The community code-mod loader. It runs KSA in its own process. Config: `StarMapConfig.json`. |
| .NET 10 SDK 10.0.401 | `%LOCALAPPDATA%\NCM\dotnet` | Microsoft's signed `dotnet-install.ps1`, no admin, nothing system-wide. StarMap needs the .NET 10 runtime (`DOTNET_ROOT`). |
| NcmKsa 0.2.0 (NCM) | `Documents\My Games\Kitten Space Agency\mods\NcmKsa` | Source `ncm/ksa/NcmKsa`; build and install with `tools/ksa-build-mod.ps1`. It is enabled in KSA's `manifest.toml`. |

## How KSA works for us

These facts were read from the installed KSA. A decompile for reference stayed in a scratchpad and none of it is in the repository.

**Mods**
- KSA's own mods are content only: `mod.toml` plus XML, listed in `Documents\My Games\Kitten Space Agency\manifest.toml`. A newly found mod is added as disabled.
- KSA loads no code. Code needs StarMap: a `[StarMapMod]` class with attributed hooks (`[StarMapAllModsLoaded]`, per-frame `[StarMapAfterGui]`, `[StarMapUnload]`), loaded through the same manifest, with Harmony available.

**Start-up**
- KSA starts straight into a flight (`Controlling 'Rocket'`), with no menu. It has no command-line option to load a save; `GameSaves.LoadSaveGame(name)` exists for later.

**Frames**
- KSA's Earth-fixed frame (`Celestial.GetDirCcfFromLatLon`: x through 0°N 0°E, z north) is the same convention as NCM Deep's frame.
- KSA's mean radius is 6,371 km, the same as Deep's; mu is 3.98602e14, within 4e-6 of Deep's.
- `GetCcf2Cci(time)` rotates Earth-fixed axes into KSA's inertial frame.

**Placing a craft**
- `Orbit.CreateFromStateCci(parent, time, posCci, velCci, color)` followed by `Vehicle.Teleport(orbit, null, null)`: KSA's own pattern, from its EVA and correction-burn code.

**Earth's sphere of influence in KSA**
- `0.9431 a (m/M)^0.4` = **871,696 km**, not the textbook ~925,000 km.
- A state outside it is not an Earth orbit, and `CreateFromStateCci` throws "Cannot construct a UniverseTime from NaN".
- So NCM's border is 98 % of it, **854,262 km**, and KSA carries the craft out of Earth's sphere itself.

**A purely radial velocity**
- It has zero angular momentum, a degenerate orbit, and also throws.
- Any sideways part works (measured down to 1 cm/s). The mod nudges an exactly radial velocity 1 cm/s sideways and logs it.
- A real arrival is never exactly radial: a few m/s sideways remain from the Earth's spin.

## Probe results (2026-10-07, 01:14-01:27)

- **`/ksa/ping`, `/ksa/state`:** the mod answered from inside a flight, reporting the Rocket at 207 km, 7,784 m/s inertial, "Freefall".
- **Self-test, first cut (925,000 km, purely radial):** FAIL, with the two refusals above. KSA's craft was restored untouched.
- **Bisection:** at the border radius, zero speed works and any purely radial speed fails. Outward plus 2,000, 500, 300, 50, 3, 0.3 and 0.01 m/s sideways all placed exactly. Five seconds later the craft was flying outward under Earth.
- **Bridge `/ksa/selftest` from cold:** KSA launched through StarMap and reached a flight in **23 s**. It placed the craft at 854,262 km over Night City at 148 km/s and read it back: **0 m, 0.00003 m/s, 0° / 0°**. **PASS.**
- **Bridge `/ksa/embody` with NCM core's own handoff payload** (a Deep border state run through `inertialVel`): VERIFIED with **0 / 0 / 0 / 0** errors, and KSA was brought to the foreground.

## Not yet known

- The in-game Cyberpunk → border → KSA flight. The dev rehearsal (hold L3 with the KSA border selected in Guidance) does the whole handoff in about a minute.
- The craft in KSA is KSA's own starting vessel (the "Rocket"), not a Hella-like Machine. Building a KSA craft from the Machine's parts (L333) is the next KSA step, and it is stated here as a loss.
- KSA's terms for mods and outside tools; the planned switch to a fictional system.
- Returning from KSA into Deep (IDEA-1170).

## Next action

The owner rehearses the handoff on dev (§KS9): climb into Deep, open Guidance, select the KSA border, run the self-test with A, then hold L3. Then build the Machine as a KSA craft.
