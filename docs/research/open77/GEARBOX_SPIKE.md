# NCM Gearbox spike: our own manual transmission, phase 0

> **STATUS: RESEARCH (spike in progress)** - 2026-10-04. Owner direction L306: "our own manual implementation ...
> with the serial numbers of the cars, we assign manual or automatic ... we fuck with the gearbox, number of gears".
> Plan: phases 0-4 in [DECISION_RECORD L306](../../ncm-online/DECISION_RECORD.md). Ideas IDEA-923 to IDEA-927.
> Nothing in production changed. The spike package exists but is **not installed and not declared by any server**.

## Completed

- **Clean room.** We do not read or copy the community Manual Transmission mod's code or its `ManualClutch.dll`.
  What we carry over is what NCM learned while working with it:
  - `Vehicle/BlockChangeGear` must be **set**, never toggled. The RB15 desynced when it was toggled.
  - The gear `minSpeed` floor stops a car from braking to a halt. Carrier's `GEAR_FLOOR` already zeroes it.
  - The clutch thresholds: slip from 0.15, neutral from 0.80.
- **Gear record fields, from the RB15 TweakXL package** (`staging/checkpoint-04/.../rb15_f1_standalone.yaml`).
  - Each `gamedataVehicleGear_Record` has `minSpeed`, `maxSpeed` (m/s), `minEngineRPM`, `maxEngineRPM` and
    `torqueMultiplier`.
  - `gamedataVehicleEngineData_Record.gears` lists **reverse first**, then the forward gears.
  - The engine data carries `engineMaxTorque`, `gearChangeTime`, `gearChangeCooldown`, `gearCurvesPath`,
    `maxRPM`, `minRPM`, `resistanceTorque` and others.
- **Galena's native chain size, from Carrier logs.** 14 gear-floor writes = 2 flats × **7 gear entries**,
  i.e. reverse + 6 forward if reverse-first holds. The `_player` record shares its gear records with the base.
- **Core `machine.gearbox`** (`ncm/core/machine/gearbox.lua`, tests in `test_gearbox.lua`):
  - specs from 4- to 8-speed and a factory mix per model;
  - a deterministic roll per asset;
  - gear bands and a top-speed overdrive;
  - **coverage**, the share of peak power a box keeps on tap. A flat-torque curve with its peak at 85 % of
    redline gives 4-speed 95 %, 5-speed 96 %, 5-close 97 %, 6-speed 97 %, 6-overdrive 96 % (+10 % top),
    7-close 98 % and 8-speed 98 %.
- **Clone records.** `tools/gen-gearbox-records.lua` emits 44 TweakXL vehicle clones (`<record>_ncm_gbx_<spec>`,
  `$base` = the model) and the DLL's spec file. The gate checks parity (`tools/test-gearbox-records.lua`).
- **The clone is built at runtime.** The vanilla name of the Galena's engine-data record is not available offline:
  CET's `tweakdbstr.kark` is compressed, and no local YAML names it. So the DLL (`ncm/gearbox`, 0.0.1) does the
  following when the game reaches Running:
  1. Reads the model's engine data through `.vehEngineData`.
  2. Copies every property with a flat into `<clone>_engine`, sharing the pooled value offsets. The properties
     are enumerated from the record class's RTTI getters.
  3. Writes the spec's forward gears. Each takes the band, RPM range and torque multiplier of the model gear
     that first reaches its top speed, with `minSpeed` set to 0. The model's reverse is shared.
  4. Repoints the clone's `.vehEngineData`.

  It also dumps the model's engine data and chain to `red4ext/plugins/ncm_gearbox/ncm_gearbox-<pid>.log`.
  It builds with MSVC and has not run in-game yet.
- **Packaging.** `ncm/gearbox/pack.py` produces `dist/ncm-gearbox-0.0.1.zip`. On dev it installs with
  `python tools/dev-hand-install-mods.py --only none --extra-zip dist/ncm-gearbox-0.0.1.zip` and comes out with
  `--uninstall`.

## The questions (S1–S6) and their state

| # | Question | State |
|---|---|---|
| S1 | Do the clones spawn through OPEN//77 and drive on their own gear arrays? | **Half answered 2026-10-04: the DLL loads and builds all 44 clones; reverse-first confirmed from the dumps** (`red4ext/plugins/ncm_gearbox/ncm_gearbox-53060.log` (owner drove on dev, 2026-10-04 14:23)). Spawning and driving a clone is still owed: Install the zip and launch, then read `ncm_gearbox-<pid>.log`: the Galena dump, `m5`/`m6` built. Then call a manual Galena on dev with `ncm_gearbox_spawn_clones true` and run `/ncm.gears` in it. |
| S2 | Can we hold, then set, the native gear? | **Instrument built (0.1.0, phase 3a), installed on this PC, not yet run.** Three steps, each logged to `ncm_gearbox-<pid>.log`: an RTTI **census** at Running (`census prop/func/enum` lines: every class, field, function and enum whose name says gear, clutch, transmission, shift, neutral or rpm); a read-only **observe** of the player's car every frame from `r6/scripts/ncm_gearbox/NcmGearbox.reds` (`SHIFT` / `beat` lines: the HUD's `GearValue`, rpm and speed beside every gear-like numeric field of the car's class chain); and a **hold** experiment, OFF until `ncm_gearbox_config.json` names a field, which then writes the configured gear into it every frame. Redscript compiled against vanilla + every installed script mod (scratch cache); natives module-less (KB-182). |
| S3 | A real neutral? | Not started. Fallback: an authored N entry in the clone (`minSpeed` 0, a huge `maxSpeed`, `torqueMultiplier` ≈ 0). |
| S4 | Clutch and shift cut through the final throttle? | Not started. |
| S5 | Does the sound follow, locally and remotely? | Not started. It depends on S2. |
| S6 | Can AI drive a clone? | Not started. Until it is answered, NPC-owned manuals spawn as their model record. |

## Unresolved

- **Reverse first.** Reverse-first is assumed from the RB15. The S1 dump decides, and `reverseFirst` in the spec
  file flips it.
- **Carrier and clone records.** Carrier projects parts and the gear cap onto the asset's model record, not onto
  the clone. A manual therefore gets parts through the shared drive model, but not the gear-cap top-speed raise.
  The spec's overdrive stands in for it until phase 3 decides.
- **TweakXL and new properties.** TweakXL rejects unknown properties (KB-292), so a clone cannot carry an
  `ncmGearbox` marker flat. The DLL recognises clones by its own spec file instead.

## Next action

**Phase 3b (2026-10-04):** 0.1.0's census proved the gear is NOT an RTTI field of the vehicle object and no script-callable function sets it. 0.1.1 finds it by value: every frame it reads the car object's raw memory and one level into every object it points at (ReadProcessMemory, so a bad pointer is a failed read), keeping each u8/i32/f32 that equals the HUD gear plus a constant. A few shifts leave the gear's address path; the hold experiment then takes that path (`hold.path` in `ncm_gearbox_config.json`). If nothing survives, the gear lives deeper than one pointer and the next step is a native hook on the code that writes the HUD's `GearValue`.


**Phase 3a (2026-10-04):** launch, drive any car through its gears for a minute, and send `ncm_gearbox-<pid>.log`. Its census and SHIFT lines name the field (or prove the gear is not an RTTI field of the vehicle object, which moves the search to a native hook); then the hold experiment, then the manual's input, clutch, neutral and HUD. The text below is the phase 0 note.


The owner opts in: close the game, install the zip, launch single-player or dev, and send
`ncm_gearbox-<pid>.log`. That answers S1's first half. Then S2's hook and scan.
