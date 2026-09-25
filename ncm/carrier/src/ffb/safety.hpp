// NCM Carrier -- the force-feedback safety envelope.
//
// **Transcribed, not redesigned.** Every number and every rule here comes from `ncm-wheel.py:112-188` and
// `ncm/core/driver/feedback.lua`, which were arrived at by measurement on real hardware after the guessed
// values turned out to be badly wrong (`IDEA-411`). `L133` makes this the wrist protection rather than a
// default: a magnitude cannot leave this module above its device class's cap, whatever asked for it.
//
// If you are tempted to raise a ceiling because something "feels weak", raise the RUNG. That is what it is
// for, and it is bounded by the ceiling on purpose.
//
// ONE CAVEAT CARRIED FORWARD HONESTLY. These ceilings were measured against SDL's normalisation through the
// Python stack. This is the same library in a different host. Same numbers, same units, but re-check them on
// the first drive rather than assuming they transferred (Report 36 section 6.4).
#pragma once

#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

namespace ncm::ffb {

enum class DeviceClass { Gear, Belt, DirectDrive, Unknown };

// Measured, not chosen. A direct-drive wheel produces roughly four times the torque of a gear-driven one for
// the same normalised magnitude, which is why its ceiling is a quarter of the height.
constexpr double kCeilingGear        = 0.24;
constexpr double kCeilingBelt        = 0.20;
constexpr double kCeilingDirectDrive = 0.06;
constexpr double kCeilingUnknown     = 0.04;  // an unrecognised wheel is assumed to be the strongest one

constexpr double kFloor              = 0.02;
constexpr double kStep               = 0.02;
constexpr double kMaxSlewPerSecond   = 1.5;   // a spike is what hurts, not a sustained level

inline double ceilingFor(DeviceClass cls) noexcept
{
    switch (cls) {
        case DeviceClass::Gear:        return kCeilingGear;
        case DeviceClass::Belt:        return kCeilingBelt;
        case DeviceClass::DirectDrive: return kCeilingDirectDrive;
        default:                       return kCeilingUnknown;
    }
}

inline const char* nameOf(DeviceClass cls) noexcept
{
    switch (cls) {
        case DeviceClass::Gear:        return "gear";
        case DeviceClass::Belt:        return "belt";
        case DeviceClass::DirectDrive: return "direct_drive";
        default:                       return "unknown";
    }
}

/// **The only way a magnitude leaves this module.** Anything unreadable -- NaN, infinity, negative -- is
/// zero rather than a guess, because the failure mode of guessing is a wheel that fights someone's hands.
inline double clamp(DeviceClass cls, double requested) noexcept
{
    const double ceiling = ceilingFor(cls);
    if (std::isnan(requested) || std::isinf(requested) || requested < 0.0) return 0.0;
    return std::min(requested, ceiling);
}

/// No sudden full-scale step, ever. An unreadable target HOLDS rather than dropping to zero: a wheel that
/// goes slack mid-corner is as startling as one that kicks.
inline double slew(double previous, double target, double dt,
                   double maxPerSecond = kMaxSlewPerSecond) noexcept
{
    if (std::isnan(target) || std::isinf(target)) return previous;
    if (dt <= 0.0) return previous;
    const double limit = maxPerSecond * dt;
    const double delta = target - previous;
    if (delta > limit)  return previous + limit;
    if (delta < -limit) return previous - limit;
    return target;
}

/// Every permitted setting for a class, lowest first. The rung is a UNIT, not a widget (`L133`) -- it is
/// what a tester means when they say "two rungs more" across a T128, a G29 and a G923.
inline std::vector<double> ladder(DeviceClass cls)
{
    std::vector<double> rungs;
    const double ceiling = ceilingFor(cls);
    for (double v = kFloor; v <= ceiling + 1e-9; v += kStep) rungs.push_back(v);
    if (rungs.empty()) rungs.push_back(std::min(kFloor, ceiling));
    return rungs;
}

/// Torque is signed by design, so it cannot use `clamp()` -- which rejects negatives. Symmetric, same
/// ceiling, same rejection of nonsense.
inline double clampTorque(DeviceClass cls, double requested) noexcept
{
    const double ceiling = ceilingFor(cls);
    if (std::isnan(requested) || std::isinf(requested)) return 0.0;
    return std::max(-ceiling, std::min(ceiling, requested));
}

/// Substring classification, deliberately crude and deliberately pessimistic: a name we do not recognise
/// gets the lowest ceiling, not the most common one.
DeviceClass classify(const std::string& deviceName);

}  // namespace ncm::ffb
