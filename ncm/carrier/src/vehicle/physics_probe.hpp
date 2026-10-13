// NCM Carrier -- the physics-step probe. READ ONLY. It writes nothing to the game, ever.
//
// WHY THIS EXISTS, AND WHY IT IS NOT THE INPUT HOOK.
//
// `vehicle/hook.cpp` aims at `vehicle::BaseObject`'s final command fields -- throttle, brake, steer. That
// surface is INPUT-MEDIATED: it changes what the car is ASKED for, never what the car IS. Weather, tyres,
// drag and brakes do not live there.
//
// This probe aims one layer deeper, at `RigidBody::Recalculate` (RED4ext address hash 593628708). The game
// calls it once per rigid body per physics step, and its single argument is the body's `vehiclePhysicsData`
// -- the struct that holds the accumulated force and torque about to be solved. A March 2026 experiment of
// ours hooked exactly this and attenuated engine-driven forward force before the solve; the result was felt
// (no minimum speed in gear) and is the only first-party evidence we have of live per-instance physics
// mutation on this engine.
//
// This build does NOT reproduce that write. It reproduces only the reach. Four questions, one cold launch:
//
//   1. Does the detour fire on 2.31 at all, and at what rate?
//   2. Is the argument really `vehiclePhysicsData`? Velocity at +0x18 must track the speedometer and
//      total_mass at +0x1BC must look like a car. Both are self-validating: we already know what the
//      answers should be, so agreement is proof and disagreement is a clean refutation.
//   3. Can we identify the player's own body among all of them, via the back-pointer at +0x180?
//   4. Does any of it destabilise the game?
//
// Only after those are answered in a log does a write become a reasonable thing to propose.
//
// SAFETY, WHICH IS THE WHOLE DESIGN.
//
//   * `Resolve()` is FATAL on a miss. `RED4ext::UniversalRelocBase` calls `ShowErrorAndTerminateProcess`
//     when a hash is not in the address table -- a MessageBox and a dead process, not an exception. No
//     try/catch in this plugin can intercept it, so `main.cpp`'s stage wrapper would not save the game.
//     Therefore we read the game's own address table off disk FIRST and decline if the hash is absent.
//     That converts the carrier's worst failure mode into a log line.
//   * Every read of game memory runs under SEH. One access violation disables the probe permanently for
//     the session and is recorded. A diagnostic that can take the game down is not a diagnostic.
//   * The detour does no I/O, takes no lock and reads no clock. It updates atomics and returns. All
//     reporting happens on a separate 1 Hz thread.
//   * Deep reads (+0x180, +0x1BC) happen only when a body becomes the window's fastest, which is rare,
//     and never on the first sight of a pointer we have not already read shallowly.
#pragma once

#include <cstdint>
#include <string>

// THE FIRST WRITE, AND THE ONE RULE IT OBEYS.
//
// Everything above this line is read-only and stays that way. The single exception is the lateral scale:
// on a horizontal entry, the component PERPENDICULAR to travel is multiplied by `gripScale` and the force
// is written back. The component ALONG travel is passed through untouched, so the car still accelerates
// and brakes exactly as it did -- a value below 1.0 is a wet road, not a slow car.
//
// Why this is safe to do at all, and each point is a property of the design rather than a promise:
//
//   * Stateless. Recomputed from the game's own value on every call; nothing accumulates, so a call we
//     miss, or a thread we never see, costs nothing.
//   * Exactly reversible. At 1.0 the reconstruction is the original vector, identically, because there is
//     no stored original to drift from -- long*dir + lat*perp IS the decomposition of what was there.
//   * Inert by default, and the default is what ships.
//   * Clamped, so a typo cannot put a car on ice at 200 km/h.
//   * Only the latched player vehicle. Never traffic, never another player's car.
//   * Guarded by SEH like every read: one fault disables writing for the session and says so.

namespace ncm::vehicle::probe {

/// The RED4ext address hash for `RigidBody::Recalculate`, carried forward from the March experiment and
/// re-verified against this build's `cyberpunk2077_addresses.json` on 2026-09-25.
inline constexpr uint32_t kRecalculateHash = 593628708u;

/// Check the hash against the game's shipped address table before anything can resolve it. Returns false
/// when the table is missing, unreadable, or does not carry the hash -- all of which mean "decline".
bool addressTableCarries(uint32_t hash);

/// Resolve, attach, and start the reporter. Never throws; returns false when it declined.
/// Handle and sdk are RED4ext's; kept opaque so this header does not drag Windows into every translation
/// unit that only wants to read a counter. `dllDirectory` is where `ncm_carrier.json` is read from once a
/// second for the grip scale, so it can be changed while the game runs.
bool attach(void* pluginHandle, const void* sdk, const std::wstring& dllDirectory);

/// Stop reporting, stop observing, detach. Safe to call when attach() declined.
void detach(void* pluginHandle, const void* sdk);

bool attached() noexcept;
/// True only once the detour has actually fired. Attached and never-ticked is a real and distinct state.
bool ticking() noexcept;
uint64_t ticks() noexcept;

/// What NCM's own client says the player's speed is, in m/s, pushed from the bridge's telemetry frames.
/// Negative means "not in a car" or "not reported". This is the yardstick question 2 is measured against.
void noteReportedSpeed(double metresPerSecond) noexcept;

/// The driver's brake pedal, 0..1, with the arrival time recorded so a stale value can be refused.
/// `hasBrake == false` means "not told", which is NOT the same as "not braking" and is treated as
/// braking at the write site.
void noteBrakeInput(double pedal, bool hasBrake) noexcept;

/// ---------------------------------------------------------------------------------------------------
/// `L152`: THE DRIVER'S FITTED PARTS, AS LIVE FORCE SCALES.
/// ---------------------------------------------------------------------------------------------------
///
/// `ncm/core/parts/handling.lua` composed these from what the driver has fitted; the plugin interprets
/// none of it (`L135`). Three scales, because three quantities have been driven and confirmed: grip
/// across travel (AU5), drive force along it (AW1), brake force along it (AW2).
///
/// **This is the channel that makes Parts personal.** It writes only after `engineEntity` has positively
/// matched the `ent::EntityID` on a physics body's vehicle back-pointer. Speed, mass and proximity are
/// diagnostics, never identity. `assetId` remains the authoritative semantic identity and is retained in
/// the bridge contract/log; `engineEntity` is only the adapter join to the current live body.
///
/// Three properties worth stating because they are what make it safe to take orders from a socket:
///
///   * **Clamped here, again.** The server clamps while composing so it can warn a player; this clamps
///     because it does not trust the wire and should not. A malformed or hostile payload cannot put a car
///     on ice at 200 km/h.
///   * **It takes precedence over `ncm_carrier.json`.** Once a setup has arrived, the config file stops
///     driving these three levers for the session. Two writers on one value is not a design.
///   * **Losing the server restores inert.** `clearHandling()` is called when the bridge drops, so a
///     player does not keep a stale advantage -- or a stale penalty -- after the world goes away.
///
/// A non-finite value leaves that lever alone rather than zeroing it. Absent and inert are different
/// claims, and so are absent and malformed.
void applyHandling(const std::string& assetId, const std::string& vehicleId,
                   const std::string& authorityEpoch, uint64_t engineEntity,
                   bool hasGrip, double grip, bool hasDrive, double drive,
                   bool hasBrake, double brake, bool hasDrag, double drag,
                   bool hasTopSpeed, double topSpeedKph) noexcept;

/// Return the three Parts levers to inert and hand them back to the config file. Called when the bridge
/// drops, and safe to call when no setup was ever applied.
/// `releaseBenchConfig=false` is an authoritative NCM unbind/refusal: stay inert and keep the bench config
/// suppressed while the socket remains connected. Socket loss passes true and returns ownership.
void clearHandling(bool releaseBenchConfig = true) noexcept;

/// `L324`: installed components as a force on the bound Machine (world N, a lease of `ttlMs`), plus an optional pulse
/// (a new `pulseSeq` starts one: world N for `pulseMs` of physics time). Refused unless `assetId` is the Machine the
/// handling binding names; applied only at the positively bound, seated body's gravity entry, under the same gates
/// as every write. `supersedeLift` parks NCM Thrust's legacy lift lever while fresh. Returns false when refused.
bool applyWrench(const std::string& assetId, double fx, double fy, double fz, int ttlMs, bool supersedeLift,
                 bool hasPulse, uint32_t pulseSeq, double px, double py, double pz, int pulseMs,
                 bool av = false, double ncmMassKg = 0.0, double ax = 0.0, double ay = 0.0, double az = 0.0) noexcept;

/// 2026-10-12, the AV: the engine entity whose physics must be switched on now -- an `av` wrench lease is fresh, the
/// handling binding names an entity, and its body has not ticked through Recalculate lately (an AV is a scripted,
/// kinematic body until something calls ForceEnablePhysics). 0 = nothing to do. Cheap; called every game frame.
uint64_t avEntityNeedingPhysics() noexcept;

/// 0.1.40: the fresh `av` lease, for the game-thread AV writer. Returns false when there is none (or the wrench is busy
/// this instant). `entity` = the handling binding's engine entity; force world N; alpha world rad/s^2; the NCM mass.
bool avCommand(uint64_t& entity, float* forceN, float* alpha, float& ncmMassKg) noexcept;

/// One line, in the spirit of MtClutchDiag: everything the probe currently knows, cheap to call.
std::string status();

}  // namespace ncm::vehicle::probe
