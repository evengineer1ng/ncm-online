// The feel model's offline contract. These assertions exist because the previous build shipped a
// constant-force channel that nothing ever fed and a ceiling that nothing ever enforced, and no offline
// test could have caught either -- the only test covered axis maths.

#include "feel.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>

namespace {
int failures = 0;

void check(const char* name, bool ok)
{
    if (ok) return;
    std::cerr << "FAIL " << name << '\n';
    ++failures;
}

void near(const char* name, float actual, float expected, float epsilon = 0.001f)
{
    if (std::fabs(actual - expected) <= epsilon) return;
    std::cerr << "FAIL " << name << ": expected " << expected << ", got " << actual << '\n';
    ++failures;
}
}

int main()
{
    using namespace ncm::rig::feel;

    // ---- the ladder is the measured one, and `unknown` is the SAFEST class -------------------------
    near("gear ceiling", ceilingFor(DeviceClass::Gear), 0.24f);
    near("belt ceiling", ceilingFor(DeviceClass::Belt), 0.20f);
    near("direct drive ceiling", ceilingFor(DeviceClass::DirectDrive), 0.06f);
    near("unknown ceiling", ceilingFor(DeviceClass::Unknown), 0.04f);
    check("unknown is the lowest ceiling of the four",
          ceilingFor(DeviceClass::Unknown) < ceilingFor(DeviceClass::DirectDrive) &&
          ceilingFor(DeviceClass::DirectDrive) < ceilingFor(DeviceClass::Belt) &&
          ceilingFor(DeviceClass::Belt) < ceilingFor(DeviceClass::Gear));

    // An unrecognised class name must never unlock a higher ceiling than it was declared to deserve.
    check("garbage class falls to unknown", classFrom("G29 Racing Wheel") == DeviceClass::Unknown);
    check("empty class falls to unknown", classFrom("") == DeviceClass::Unknown);
    check("gear parses", classFrom("gear") == DeviceClass::Gear);

    const auto gear = ladder(DeviceClass::Gear);
    near("ladder starts at the floor", gear.front(), kFloor);
    check("ladder never exceeds the ceiling", gear.back() <= ceilingFor(DeviceClass::Gear) + 1e-6f);
    check("ladder steps by STEP", std::fabs((gear[1] - gear[0]) - kStep) < 1e-6f);
    check("unknown ladder is short", ladder(DeviceClass::Unknown).size() == 2);

    // Nothing may leave the model above its class ceiling, in either direction.
    near("clamp positive", clampToClass(DeviceClass::Unknown, 1.0f), 0.04f);
    near("clamp negative", clampToClass(DeviceClass::Unknown, -1.0f), -0.04f);
    near("clamp passes small values", clampToClass(DeviceClass::Gear, 0.10f), 0.10f);

    // ---- absent is not zero -----------------------------------------------------------------------
    Tune tune;
    Telemetry empty;
    const auto nothing = mix(empty, tune);
    check("an empty frame is unreadable, not silent", !nothing.readable);
    near("an empty frame contributes no intensity", nothing.intensity, 0.0f);

    // ---- the road and slip channels actually reach the output -------------------------------------
    // This is the regression that matters: these were parsed and then dropped, so the wheel was silent
    // over kerbs no matter how the panel was tuned.
    Telemetry road;
    road.hasSuspLong = true; road.suspLong = 0.5f;
    const auto roadMix = mix(road, tune);
    check("suspension alone is readable", roadMix.readable);
    near("suspension reaches intensity", roadMix.intensity, 1.2f * tune.road * 0.5f);

    Telemetry slip;
    slip.hasSlipTotal = true; slip.slipTotal = 0.4f;
    near("slip reaches intensity", mix(slip, tune).intensity, 2.5f * tune.texture * 0.4f);

    Telemetry engine;
    engine.hasEngine = true; engine.engine = 0.0f;
    check("an idling engine still hums", mix(engine, tune).intensity > 0.0f);

    // ---- self-aligning torque points BACK TO CENTRE ------------------------------------------------
    Telemetry turning;
    turning.hasSteering = true; turning.steering = 0.8f;
    turning.hasSpeed = true; turning.speed = 20.0f;
    const auto right = mix(turning, tune);
    check("turning right pulls left", right.torque < 0.0f);
    turning.steering = -0.8f;
    check("turning left pulls right", mix(turning, tune).torque > 0.0f);

    // A stationary car has no castor effect at all.
    turning.speed = 0.0f;
    near("stopped car has no self-aligning torque", mix(turning, tune).torque, 0.0f);

    // ...and it is fully loaded by roughly 70 km/h, not before.
    turning.steering = 1.0f; turning.speed = 10.0f;
    near("half loading at 10 m/s", mix(turning, tune).torque, -0.5f);
    turning.speed = 40.0f;
    near("loading saturates", mix(turning, tune).torque, -1.0f);

    // ---- intensity is bounded before the rung is even applied --------------------------------------
    Telemetry everything;
    everything.hasEngine = true;    everything.engine = 1.0f;
    everything.hasSlipTotal = true; everything.slipTotal = 1.0f;
    everything.hasSlipLong = true;  everything.slipLong = 1.0f;
    everything.hasSlipLat = true;   everything.slipLat = 1.0f;
    everything.hasSuspLong = true;  everything.suspLong = 1.0f;
    everything.hasSuspLat = true;   everything.suspLat = 1.0f;
    near("a fully loaded car saturates at 1.0", mix(everything, tune).intensity, 1.0f);

    // The worst case a device can ever be asked for: everything at once, at the top rung of its class.
    const float worst = clampToClass(DeviceClass::Unknown,
                                     mix(everything, tune).intensity * ladder(DeviceClass::Unknown).back());
    check("worst case on unknown hardware stays under its ceiling", worst <= 0.04f + 1e-6f);

    // ---- slew: an unreadable target holds, and nothing steps full scale ----------------------------
    near("slew moves at the bounded rate", slew(0.0f, 1.0f, 0.1f), 0.15f);
    near("slew reaches an in-range target", slew(0.0f, 0.05f, 1.0f), 0.05f);
    near("slew holds on NaN", slew(0.3f, std::nanf(""), 0.1f), 0.3f);
    near("slew holds when no time passed", slew(0.3f, 1.0f, 0.0f), 0.3f);

    // ---- the engine band stays inside the felt range ------------------------------------------------
    check("idle period is the slow end", enginePeriodMicros(0.0f) > enginePeriodMicros(1.0f));
    near("idle is 12 Hz", 1000000.0f / static_cast<float>(enginePeriodMicros(0.0f)), 12.0f, 0.1f);
    near("redline is 47 Hz", 1000000.0f / static_cast<float>(enginePeriodMicros(1.0f)), 47.0f, 0.1f);
    check("out-of-range revs are clamped, not extrapolated",
          enginePeriodMicros(5.0f) == enginePeriodMicros(1.0f) &&
          enginePeriodMicros(-5.0f) == enginePeriodMicros(0.0f));

    if (failures) {
        std::cerr << failures << " feel assertion(s) failed\n";
        return 1;
    }
    std::cout << "NCM Rig Bridge feel tests passed\n";
    return 0;
}
