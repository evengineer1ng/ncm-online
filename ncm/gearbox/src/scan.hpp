// NCM Gearbox -- phase 3b (L306 S2): find the gear by VALUE, because it has no name.
//
// 0.1.0's census proved the gear is not an RTTI field of the vehicle object and that no script-callable function sets
// it (log 2026-10-04 14:23: `vehicleCarBaseObject has 0 gear-like numeric field(s)`; the 72 gear-named functions are
// UI listeners and TweakDB getters). Native code writes the HUD's `GearValue` from somewhere it does not name.
//
// So this reads the player's car object's raw memory -- and one level into every object it points at -- every frame,
// and keeps each byte / int32 / float whose value moves in lockstep with the HUD gear (value = hudGear + a constant,
// the constant -3..+3 so an index-encoded gear also matches). Every HUD gear change kills the fields that did not
// follow it; after a few shifts the survivors are the gear. Reads go through ReadProcessMemory on our own process, so
// a stale or bad pointer is a failed read, never a crash. Nothing here writes unless the config turns on the trial
// (`hold.trial`) or names a path (`hold.path`).
#pragma once

#include <cstdint>
#include <string>

namespace ncm::gearbox::scan {

/// One frame of the player's car. `objectSize` = the RTTI class size (0 = a default). rpm/speed feed the trial's log.
void step(const void* vehicle, uint32_t objectSize, int32_t hudGear, float rpm, float speed);

/// 0.1.2: the automatic hold trial (config `hold.trial`): once the scan settles, each survivor holds the current gear
/// for 6 s in turn, logged every 0.5 s.
void setTrial(bool enabled);

/// Out of the car: report and reset.
void reset(const char* why);

/// The hold experiment by address path: "root:0x2C4:i32" or "0x5C8:0x1F4:u8" (pointer slot in the car object, offset
/// in what it points at, width i8|u8|i32|f32). Returns true when it wrote. Empty path = never writes.
bool hold(const void* vehicle, const std::string& path, int32_t gear);

/// The live address of a path on this car (readable now), for the physics-step hold. False when it does not resolve.
bool resolve(const void* vehicle, const std::string& path, uintptr_t& address);

}  // namespace ncm::gearbox::scan
