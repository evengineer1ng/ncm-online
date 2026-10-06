// NCM Gearbox -- phase 3a: find where the engine keeps the gear (S2), read-only, then a guarded hold experiment.
//
// Holding a gear means writing the engine's gear state every frame, and nobody in this project knows where that
// state lives. Guessing an offset is how a mod crashes the game, so this asks the game first:
//
//   census()      every class, property, function and enum the game's RTTI knows whose name says gear, clutch,
//                 transmission, shift, neutral or rpm -- logged once at Running, with types and offsets.
//   observe()     while the player drives, the numeric RTTI fields of THEIR car whose names say the same, read every
//                 tick and logged next to the HUD's own gear, rpm and speed when the HUD gear changes -- the
//                 correlation that names the field.
//   hold()        OFF unless `ncm_gearbox_config.json` names a field: then that integer field is written every tick
//                 with the configured gear. The S2 experiment: does the car stay in it?
//
// Read-only by default. Only primitive fields (ints, floats, bools) found by RTTI on the instance's own class chain
// are ever read, and only the one configured field is ever written.
#pragma once

#include <cstdint>
#include <string>

namespace RED4ext { struct IScriptable; }

namespace ncm::gearbox::discover {

/// Load `ncm_gearbox_config.json` beside the DLL (missing = defaults: observe on, hold off).
void loadConfig(const std::wstring& path);
/// Re-read the config if the file changed (rate-limited to once a second). Called every frame from the script tick.
void pollConfig();

/// True when the config turns the S2 instrument (observe) on.
bool instrumenting();

/// Log the RTTI census. Once per process.
void census();

/// One observation of the player's car. `hudGear` / `hudRpm` / `speed` come from the HUD's blackboard in script.
void observe(RED4ext::IScriptable* vehicle, int32_t hudGear, float hudRpm, float speed);

/// The S2 experiment. Returns true when it wrote this tick.
bool hold(RED4ext::IScriptable* vehicle);

/// The player left the car: the scan reports what survived and starts over next time.
void leftCar();

/// A one-line status for the script side's log.
std::string status();

}  // namespace ncm::gearbox::discover
