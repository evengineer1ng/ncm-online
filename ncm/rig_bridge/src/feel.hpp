#pragma once

// NCM Rig Bridge -- the feel model.
//
// This is a port of `tools/ncm-wheel.py` (NCM Wheel Support), which is the only code in this project that
// has ever actually moved the owner's wheel. Every weight, ceiling and rate below is carried across
// UNCHANGED. A port that also retunes cannot be debugged: nobody could then say whether it feels different
// because it moved to a new transport or because somebody changed a number.
//
// Do not "improve" these values here. Change them in the companion, drive it, and carry the result over.
//
// Four channels leave this file, matching the companion's four effects:
//
//   intensity  -> SINE magnitude       surface texture, slip and suspension. 125 Hz, rev-modulated.
//   torque     -> CONSTANT level       self-aligning torque: the weight pulling back toward centre.
//   spring     -> SPRING condition     centring stiffness.
//   damper     -> DAMPER condition     resistance to being whipped around.
//
// A sine alone reads as nothing in the hands; the constant torque is what makes a wheel feel like a wheel.
// Both halves are needed, which is why a build with an unfed constant channel was only half a rig.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

namespace ncm::rig::feel {

// ---------------------------------------------------------------------------------------------------
// The ladder. MEASURED 2026-09-24 on the owner's G29 and mirrored from `ncm/core/driver/feedback.lua`,
// which is authoritative. Fractions of the DEVICE's own maximum, never anything absolute.
//
// The first set of numbers here were reasoned rather than tested; a full-ladder run with the constant
// centring effect in play was reported "fairly strong from first rung to too strong by the end", so the
// floor came down and the steps got finer. An unrecognised device is assumed to be the most powerful
// thing it could be, which is why `unknown` is the lowest ceiling of the four and not the highest.
// ---------------------------------------------------------------------------------------------------
enum class DeviceClass { Gear, Belt, DirectDrive, Unknown };

constexpr float kFloor = 0.02f;
constexpr float kStep = 0.02f;
constexpr float kMaxSlewPerSecond = 1.5f;

inline constexpr float ceilingFor(DeviceClass value)
{
    switch (value) {
        case DeviceClass::Gear:        return 0.24f;
        case DeviceClass::Belt:        return 0.20f;
        case DeviceClass::DirectDrive: return 0.06f;
        case DeviceClass::Unknown:     break;
    }
    return 0.04f;
}

inline const char* nameOf(DeviceClass value)
{
    switch (value) {
        case DeviceClass::Gear:        return "gear";
        case DeviceClass::Belt:        return "belt";
        case DeviceClass::DirectDrive: return "direct_drive";
        case DeviceClass::Unknown:     break;
    }
    return "unknown";
}

/// An unrecognised name is `Unknown`, which is the SAFEST class and not a neutral one. A typo in the
/// config must never silently unlock a higher ceiling than the device was declared to deserve.
inline DeviceClass classFrom(const std::string& value)
{
    if (value == "gear") return DeviceClass::Gear;
    if (value == "belt") return DeviceClass::Belt;
    if (value == "direct_drive") return DeviceClass::DirectDrive;
    return DeviceClass::Unknown;
}

/// Every permitted setting for a class, lowest first. A tuning session starts at [0] and stops the moment
/// another rung adds nothing.
inline std::vector<float> ladder(DeviceClass value)
{
    std::vector<float> out;
    const float ceiling = ceilingFor(value);
    for (float v = kFloor; v <= ceiling + 1e-6f; v += kStep) out.push_back(v);
    if (out.empty()) out.push_back(ceiling);
    return out;
}

/// The single point where a magnitude may leave this module. Nothing downstream re-derives a ceiling.
inline float clampToClass(DeviceClass value, float magnitude)
{
    const float ceiling = ceilingFor(value);
    return std::clamp(magnitude, -ceiling, ceiling);
}

// ---------------------------------------------------------------------------------------------------
// The engine hum band. Below idle it would read as a vibration and above the span as a tone; an engine is
// felt through a wheel, not heard. 125 Hz is the texture carrier -- 25 Hz was the companion's first
// attempt and it felt like a rumble pack.
// ---------------------------------------------------------------------------------------------------
constexpr float kEngineHzIdle = 12.0f;
constexpr float kEngineHzSpan = 35.0f;

inline uint32_t enginePeriodMicros(float revRatio)
{
    const float hz = kEngineHzIdle + kEngineHzSpan * std::clamp(revRatio, 0.0f, 1.0f);
    return static_cast<uint32_t>(1000000.0f / hz);
}

// ---------------------------------------------------------------------------------------------------
// Tuning. Every one of these is a slider, not a constant: the owner should never need an editor to change
// how their wheel feels, and one person's preference is not a fact about the hardware.
// ---------------------------------------------------------------------------------------------------
struct Tune {
    float spring = 0.55f;   // self-centring weight. The cure for "floaty".
    float damper = 0.35f;   // resistance to being whipped around. Stiffness.
    float texture = 0.60f;  // road and slip rumble
    float engine = 0.45f;   // engine hum, felt at idle as well as at speed
    float road = 1.00f;     // suspension movement
};

/// **An absent channel is ABSENT, not zero.** The companion draws this distinction everywhere and it is
/// load-bearing: a car we cannot read must hold, not be reported as a car sitting perfectly still.
struct Telemetry {
    bool hasEngine = false;    float engine = 0.0f;     // rev ratio 0..1
    bool hasSpeed = false;     float speed = 0.0f;      // m/s
    bool hasSteering = false;  float steering = 0.0f;   // -1..1
    bool hasSlipLong = false;  float slipLong = 0.0f;
    bool hasSlipLat = false;   float slipLat = 0.0f;
    bool hasSlipTotal = false; float slipTotal = 0.0f;
    bool hasSuspLong = false;  float suspLong = 0.0f;
    bool hasSuspLat = false;   float suspLat = 0.0f;

    bool any() const
    {
        return hasEngine || hasSpeed || hasSteering || hasSlipLong || hasSlipLat ||
               hasSlipTotal || hasSuspLong || hasSuspLat;
    }
};

struct Mixed {
    float intensity = 0.0f;  // 0..1 before the rung is applied -- what the SINE carries
    float torque = 0.0f;     // -1..1 before the rung is applied -- what the CONSTANT carries
    bool readable = false;   // false = hold the previous output rather than dropping to zero
};

inline float unitOf(float value) { return std::min(1.0f, std::fabs(value)); }

/// No sudden full-scale step, ever. An unreadable target HOLDS rather than dropping to zero.
inline float slew(float previous, float target, float dt, float maxPerSecond = kMaxSlewPerSecond)
{
    if (!(target == target)) return previous;            // NaN holds
    const float step = maxPerSecond * std::max(0.0f, dt);
    if (step <= 0.0f) return previous;
    const float delta = target - previous;
    if (delta > step) return previous + step;
    if (delta < -step) return previous - step;
    return target;
}

// ---------------------------------------------------------------------------------------------------
// The mix. Weights are the companion's, verbatim.
//
// **Rebalanced there after the first drive felt like nothing.** Engine RPM used to dominate, and at half
// redline that is a fifth of the scale -- so a car being driven hard produced a whisper. Engine is now a
// floor of presence rather than the signal, and what the hands should notice is the road: slip and
// suspension movement, both of which swing far harder while cornering and braking.
//
// Channel weights sum to roughly 0..1.8, so the rung IS the scale: at the lowest rung (0.02) a fully
// loaded car sits at about a fiftieth of the device maximum, which is where a tuning session starts.
// ---------------------------------------------------------------------------------------------------
inline Mixed mix(const Telemetry& t, const Tune& tune)
{
    Mixed out;
    if (!t.any()) return out;                            // nothing readable -> hold
    out.readable = true;

    // **The intensity channels and the torque channel are independent.** An earlier cut gated the whole
    // mix on "did any intensity channel arrive", which meant a frame carrying only steering and speed --
    // exactly what the native detour can see when the telemetry feed drops -- produced NO self-aligning
    // torque and the wheel went completely dead. Centring must survive on steering alone.
    float contributions = 0.0f;

    if (t.hasEngine) {
        // **A car should hum at idle.** Scaling straight from the RPM ratio meant an idling engine at 15%
        // of redline produced almost nothing. The floor keeps the machine perceptibly running.
        const float hum = 0.25f + 0.75f * std::clamp(t.engine, 0.0f, 1.0f);
        contributions += 1.2f * tune.engine * hum;
    }
    // Slip is MEASURED off the client snapshot, never derived -- that is what lets the feel model be
    // honest about grip without reaching for engine RTTI.
    if (t.hasSlipTotal) contributions += 2.5f * tune.texture * unitOf(t.slipTotal);
    if (t.hasSlipLong)  contributions += 1.5f * tune.texture * unitOf(t.slipLong);
    if (t.hasSlipLat)   contributions += 2.0f * tune.texture * unitOf(t.slipLat);
    if (t.hasSuspLong)  contributions += 1.2f * tune.road * unitOf(t.suspLong);
    if (t.hasSuspLat)   contributions += 1.2f * tune.road * unitOf(t.suspLat);

    out.intensity = std::min(1.0f, contributions);

    // **Self-aligning torque: the thing that makes a wheel feel like a wheel.** Magnitude grows with how
    // far the wheel is turned and how fast the car is going, and the sign always points BACK TOWARD
    // CENTRE -- it assists, the way a real car's castor does, and never fights the driver toward lock.
    if (t.hasSteering) {
        const float loading = std::min(1.0f, std::fabs(t.speed) / 20.0f);   // full effect by ~70 km/h
        const float direction = t.steering > 0.0f ? 1.0f : -1.0f;
        out.torque = -direction * unitOf(t.steering) * loading;
    }
    return out;
}

}  // namespace ncm::rig::feel
