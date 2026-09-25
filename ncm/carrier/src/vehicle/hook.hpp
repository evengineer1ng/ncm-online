// NCM Carrier -- final-command authority.
//
// This is the one surface that is PER-INSTANCE and LIVE. The drive-model flats are per-record and
// spawn-cached, so they can say what a car IS but never what is happening to it right now. Writing the
// vehicle's final throttle, brake and steer values every tick is how a wheel steers, and it is also the
// only carrier that could ever express something that expires mid-stint.
//
// NAMING, WHICH IS NOT DECORATION (`L139`, Report 34 section 8). What this writes is
// **`brake_command_authority`** -- how much brake the car is being ASKED for. It is emphatically not
// `native_brake_force`, and withdrawing throttle is not reduced grip. Presenting one as the other is how a
// system ends up lying to its own designers about what it can do.
//
// WHY IT MAY DECLINE, AND WHY THAT IS CORRECT. The field names carry forward across game builds; the
// offsets do not. Direct Wheel found `maxWheelTurnDeg` at 0x1A4 on 2.31 where the 1.52 header says 0xC10.
// So everything here resolves through the game's own RTTI first, logs whenever it falls back, and refuses
// entirely rather than writing to an address that used to mean something. A carrier with no hook still
// applies effects and still produces force feedback; a carrier that corrupts memory takes the game down.
#pragma once

namespace ncm::vehicle {

/// Attempt to install. Never throws. Returns false when the game is not shaped the way we expect.
bool installHook();
void removeHook();
bool hookInstalled() noexcept;

/// The command NCM wants applied this tick, or "leave it alone".
struct Command {
    bool hasThrottle = false; float throttle = 0.0f;
    bool hasBrake = false;    float brake = 0.0f;
    bool hasSteer = false;    float steer = 0.0f;
};

/// Set by the input layer; read by the detour. Copied under a lock because the detour runs on the game
/// thread and input is polled elsewhere.
void setCommand(const Command& command);

/// Clear everything and stop writing. Called by the watchdog and on disconnect.
void releaseCommand();

/// How long since the detour last fired. The watchdog uses this; the panel displays it.
double millisecondsSinceLastTick() noexcept;

}  // namespace ncm::vehicle
