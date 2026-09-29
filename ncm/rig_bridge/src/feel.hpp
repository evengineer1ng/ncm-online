#pragma once

// NCM Rig Bridge -- the feel model.
//
// This is a port of `tools/ncm-wheel.py` (NCM Wheel Support), which is the only code in this project that
// has ever actually moved the owner's wheel. Its weights, ceilings and slew rate are carried across. The
// DirectInput texture carrier is deliberately fixed because a restart-only driver cannot safely accept the
// companion's live frequency modulation at a 250 Hz pump.
//
// Do not "improve" these values here. Change them in the companion, drive it, and carry the result over.
//
// Four channels leave this file, matching the companion's four effects:
//
//   intensity  -> SINE magnitude       surface texture, slip and suspension. Fixed 125 Hz carrier.
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

// ---------------------------------------------------------------------------------------------------
// **Direct drive is budgeted in newton-metres, not in fractions.** A fraction of "the device's maximum"
// means 0.5 Nm on a G29 and 8 Nm on a 32 Nm base, so one fraction cannot be safe for both. Gear and belt
// wheels keep their MEASURED fractions above (their rated torque is small and similar). A direct-drive
// base gets a torque budget, divided by its rated torque; a base whose torque we do not know is assumed
// to be the strongest common one, so an unidentified base starts gentle, never violent.
//
// These are starting values, not measurements -- nobody on the project owns a DD base yet. Move them
// only on a report from someone driving one.
// ---------------------------------------------------------------------------------------------------
constexpr float kDirectDriveBudgetNm = 3.0f;    // full slider on any DD base
constexpr float kAssumedDirectDriveNm = 32.0f;  // unknown DD torque: assume the strongest common base

inline float ceilingFor(DeviceClass value, float ratedNm)
{
    if (value != DeviceClass::DirectDrive) return ceilingFor(value);
    const float rated = ratedNm > 0.0f ? ratedNm : kAssumedDirectDriveNm;
    return std::clamp(kDirectDriveBudgetNm / rated, 0.0f, 1.0f);
}

// Wheels recognised by exact USB VID:PID. **A row here must be certain.** For direct drive the listed
// torque must be the HIGHEST the product can be configured to -- overstating torque makes it gentler,
// understating it makes it stronger, so every doubt resolves upward.
struct WheelSpec {
    const char* key;      // "VID:PID", as the input provider reports it
    DeviceClass cls;
    float ratedNm;        // informational for gear/belt; the budget divisor for direct drive
    const char* model;
};

inline constexpr WheelSpec kKnownWheels[] = {
    {"046D:C24F", DeviceClass::Gear, 2.1f, "Logitech G29"},
    {"046D:C262", DeviceClass::Gear, 2.2f, "Logitech G920"},
    {"046D:C266", DeviceClass::Gear, 2.2f, "Logitech G923"},
    {"046D:C26E", DeviceClass::Gear, 2.2f, "Logitech G923 (Xbox)"},
    {"046D:C29B", DeviceClass::Gear, 2.5f, "Logitech G27"},
    {"044F:B66E", DeviceClass::Belt, 3.9f, "Thrustmaster T300 RS"},
    {"044F:B65E", DeviceClass::Belt, 4.5f, "Thrustmaster T500 RS"},
    {"044F:B677", DeviceClass::Belt, 2.5f, "Thrustmaster T150"},
    {"044F:B67F", DeviceClass::Belt, 2.5f, "Thrustmaster TMX"},
    {"044F:B696", DeviceClass::Belt, 3.5f, "Thrustmaster T248"},
    {"0EB7:0020", DeviceClass::DirectDrive, 8.0f, "Fanatec CSL DD"},
};

// Vendors whose EVERY force-feedback product is a direct-drive base. Torque unknown -> assumed maximum.
// (Fanatec, Logitech and Thrustmaster are absent on purpose: they sell belt and gear wheels too.)
struct DirectDriveVendor { const char* vid; const char* name; };
inline constexpr DirectDriveVendor kDirectDriveVendors[] = {
    {"346E", "MOZA"},
    {"2433", "Asetek SimSports"},
};

struct Recognition {
    DeviceClass cls = DeviceClass::Unknown;
    float ratedNm = 0.0f;       // 0 = unknown
    std::string model;          // empty = not recognised
    bool exact = false;         // matched a product, not merely a vendor
};

inline Recognition recognise(const std::string& key)
{
    Recognition out;
    const std::string bare = key.substr(0, key.find('#'));   // twin suffix
    for (const auto& w : kKnownWheels)
        if (bare == w.key) { out.cls = w.cls; out.ratedNm = w.ratedNm; out.model = w.model; out.exact = true; return out; }
    const std::string vid = bare.substr(0, 4);
    for (const auto& v : kDirectDriveVendors)
        if (vid == v.vid) { out.cls = DeviceClass::DirectDrive; out.model = std::string(v.name) + " direct drive"; return out; }
    return out;
}

/// The single point where a magnitude may leave this module. Nothing downstream re-derives a ceiling.
inline float clampToClass(DeviceClass value, float magnitude)
{
    const float ceiling = ceilingFor(value);
    return std::clamp(magnitude, -ceiling, ceiling);
}

inline float clampToCeiling(float ceiling, float magnitude)
{
    return std::clamp(magnitude, -ceiling, ceiling);
}

// ---------------------------------------------------------------------------------------------------
// The texture carrier. 125 Hz is the companion's refined carrier -- 25 Hz felt like a rumble pack. Engine
// revs still change the mixed intensity, not the DirectInput period.
// ---------------------------------------------------------------------------------------------------
inline constexpr uint32_t textureCarrierPeriodMicros()
{
    // Engine speed already changes magnitude in mix(). Keep the DirectInput carrier fixed: Logitech's
    // driver can restart a playing periodic effect when its type-specific period changes, and at a 250 Hz
    // feed that pins every wave near phase zero until a non-zero effect feels silent.
    return 8'000;  // 125 Hz
}

// ---------------------------------------------------------------------------------------------------
// **The engine follows the revs (`IDEA-422`, owner decision, reaffirmed 2026-09-28: "125 hz is the old
// one").** It has its OWN sine effect, so changing its period never touches the texture carrier above.
// A named band rather than the true firing frequency (rpm/30 for a four-cylinder, 233 Hz at redline, which
// is razor territory again): what hands read as an engine is the sub-harmonic. 12 Hz at zero revs, about
// 16 Hz at idle, 27 Hz cruising, 47 Hz at the limiter. Whole hertz, so a rev change is a step.
// ---------------------------------------------------------------------------------------------------
constexpr float kEngineHzIdle = 12.0f;
constexpr float kEngineHzSpan = 35.0f;

inline uint32_t enginePeriodMicros(float revRatio)
{
    const float hz = std::round(kEngineHzIdle + kEngineHzSpan * std::clamp(revRatio, 0.0f, 1.0f));
    return static_cast<uint32_t>(1000000.0f / hz);
}

// ---------------------------------------------------------------------------------------------------
// **Collisions.** Two parts, because a real impact has both: a THUD felt from any direction, on its own
// 30 Hz vibration, and a sideways KICK on the steering torque when the hit has a lateral component. The
// old path had only the kick, scaled by the lateral share alone -- so a head-on crash, the biggest hit
// there is, produced almost nothing. The curve is a square root so ordinary scrapes are felt at all:
// 1.5 m/s of delta-v is ~0.32, 6 m/s ~0.63, 15 m/s and up is full.
// ---------------------------------------------------------------------------------------------------
constexpr float kImpactFullDeltaV = 15.0f;       // m/s of delta-v that counts as a full-strength hit
constexpr int kImpactDecayMs = 250;

inline float impactIntensity(float deltaV)
{
    if (!(deltaV == deltaV)) return 0.0f;        // NaN is no impact, never a full one
    return std::sqrt(std::clamp(std::fabs(deltaV) / kImpactFullDeltaV, 0.0f, 1.0f));
}

inline constexpr uint32_t impactPeriodMicros() { return 33'333; }   // 30 Hz: a thud, not a buzz

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
    float collision = 0.80f; // impact thud and sideways kick
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
    // **One output per slider.** SLIP, ROAD and ENGINE HUM used to sum into a single intensity on a single
    // effect, so on the wheel they were indistinguishable and a tester could only say "too rumbly". Each is
    // now its own 0..1 value on its own DirectInput effect, and the panel shows each one live.
    float slip = 0.0f;       // SLIP slider   -> its own SINE, fixed 125 Hz carrier
    float road = 0.0f;       // ROAD slider   -> its own SINE, fixed 125 Hz carrier
    float engine = 0.0f;     // ENGINE slider -> its own SINE, period follows revs
    bool hasEngine = false;
    float revs = 0.0f;       // rev ratio, when hasEngine
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
    float slipSum = 0.0f;
    float roadSum = 0.0f;

    if (t.hasEngine) {
        // **A car should hum at idle.** Scaling straight from the RPM ratio meant an idling engine at 15%
        // of redline produced almost nothing. The floor keeps the machine perceptibly running.
        const float hum = 0.25f + 0.75f * std::clamp(t.engine, 0.0f, 1.0f);
        out.engine = std::min(1.0f, 1.2f * tune.engine * hum);
        out.hasEngine = true;
        out.revs = std::clamp(t.engine, 0.0f, 1.0f);
    }
    // Slip is MEASURED off the client snapshot, never derived -- that is what lets the feel model be
    // honest about grip without reaching for engine RTTI.
    if (t.hasSlipTotal) slipSum += 2.5f * tune.texture * unitOf(t.slipTotal);
    if (t.hasSlipLong)  slipSum += 1.5f * tune.texture * unitOf(t.slipLong);
    if (t.hasSlipLat)   slipSum += 2.0f * tune.texture * unitOf(t.slipLat);
    if (t.hasSuspLong)  roadSum += 1.2f * tune.road * unitOf(t.suspLong);
    if (t.hasSuspLat)   roadSum += 1.2f * tune.road * unitOf(t.suspLat);

    out.slip = std::min(1.0f, slipSum);
    out.road = std::min(1.0f, roadSum);

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
