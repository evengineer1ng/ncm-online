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

    // Direct drive is a torque budget: the same slider may never mean 8 Nm on one base and 1 on another.
    near("DD 8 Nm base", ceilingFor(DeviceClass::DirectDrive, 8.0f), kDirectDriveBudgetNm / 8.0f);
    near("DD unknown torque assumes the strongest", ceilingFor(DeviceClass::DirectDrive, 0.0f),
         kDirectDriveBudgetNm / kAssumedDirectDriveNm);
    check("DD peak never exceeds the budget", ceilingFor(DeviceClass::DirectDrive, 25.0f) * 25.0f
          <= kDirectDriveBudgetNm + 1e-4f);
    check("a weak DD base is capped at its own maximum", ceilingFor(DeviceClass::DirectDrive, 1.0f) <= 1.0f);
    near("gear ignores torque (measured fraction)", ceilingFor(DeviceClass::Gear, 2.1f), 0.24f);
    check("G29 recognised as gear", recognise("046D:C24F").cls == DeviceClass::Gear && recognise("046D:C24F").exact);
    check("twin suffix still recognised", recognise("046D:C24F#2").cls == DeviceClass::Gear);
    check("MOZA vendor is direct drive, torque unknown",
          recognise("346E:0006").cls == DeviceClass::DirectDrive && recognise("346E:0006").ratedNm == 0.0f);
    check("an unknown device stays unknown", recognise("1234:5678").cls == DeviceClass::Unknown);
    check("Logitech is never assumed from vendor alone", recognise("046D:FFFF").cls == DeviceClass::Unknown);
    near("clamp negative", clampToClass(DeviceClass::Unknown, -1.0f), -0.04f);
    near("clamp passes small values", clampToClass(DeviceClass::Gear, 0.10f), 0.10f);

    // ---- absent is not zero -----------------------------------------------------------------------
    Tune tune;
    Telemetry empty;
    const auto nothing = mix(empty, tune);
    check("an empty frame is unreadable, not silent", !nothing.readable);
    near("an empty frame contributes no slip", nothing.slip, 0.0f);
    near("an empty frame contributes no road", nothing.road, 0.0f);

    // ---- the road and slip channels actually reach the output -------------------------------------
    // This is the regression that matters: these were parsed and then dropped, so the wheel was silent
    // over kerbs no matter how the panel was tuned.
    Telemetry road;
    road.hasSuspLong = true; road.suspLong = 0.5f;
    const auto roadMix = mix(road, tune);
    check("suspension alone is readable", roadMix.readable);
    near("suspension reaches ROAD", roadMix.road, 1.2f * tune.road * 0.5f);
    near("suspension does not leak into SLIP", roadMix.slip, 0.0f);

    Telemetry slip;
    slip.hasSlipTotal = true; slip.slipTotal = 0.4f;
    near("slip reaches SLIP", mix(slip, tune).slip, 2.5f * tune.texture * 0.4f);
    near("slip does not leak into ROAD", mix(slip, tune).road, 0.0f);

    Telemetry engine;
    engine.hasEngine = true; engine.engine = 0.0f;
    check("an idling engine still hums", mix(engine, tune).engine > 0.0f);
    check("the engine is its own channel", mix(engine, tune).slip == 0.0f && mix(engine, tune).road == 0.0f);
    check("the engine pitch follows the revs", enginePeriodMicros(1.0f) < enginePeriodMicros(0.0f));

    // ---- collisions: every impact is felt, including head-on ---------------------------------------
    near("no delta-v is no impact", impactIntensity(0.0f), 0.0f);
    check("a 1.5 m/s scrape is felt, not 7%", impactIntensity(1.5f) > 0.3f);
    near("15 m/s is a full hit", impactIntensity(15.0f), 1.0f);
    near("harder than full is still full", impactIntensity(40.0f), 1.0f);
    near("direction of delta-v does not matter", impactIntensity(-6.0f), impactIntensity(6.0f));
    near("NaN delta-v is no impact", impactIntensity(std::nanf("")), 0.0f);
    near("zero revs is 12 Hz", 1000000.0f / static_cast<float>(enginePeriodMicros(0.0f)), 12.0f);
    near("the limiter is 47 Hz", 1000000.0f / static_cast<float>(enginePeriodMicros(1.0f)), 47.0f, 0.01f);

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
    near("full slip saturates at 1.0", mix(everything, tune).slip, 1.0f);
    near("full road saturates at 1.0", mix(everything, tune).road, 1.0f);

    // The worst case a device can ever be asked for: everything at once, at the top rung of its class.
    const float worst = clampToClass(DeviceClass::Unknown,
                                     mix(everything, tune).slip * ladder(DeviceClass::Unknown).back());
    check("worst case on unknown hardware stays under its ceiling", worst <= 0.04f + 1e-6f);

    // ---- slew: an unreadable target holds, and nothing steps full scale ----------------------------
    near("slew moves at the bounded rate", slew(0.0f, 1.0f, 0.1f), 0.15f);
    near("slew reaches an in-range target", slew(0.0f, 0.05f, 1.0f), 0.05f);
    near("slew holds on NaN", slew(0.3f, std::nanf(""), 0.1f), 0.3f);
    near("slew holds when no time passed", slew(0.3f, 1.0f, 0.0f), 0.3f);

    // ---- the carrier cannot be restarted by rev-only period changes ---------------------------------
    check("DirectInput texture carrier is fixed at 125 Hz",
          textureCarrierPeriodMicros() == 8'000);

    if (failures) {
        std::cerr << failures << " feel assertion(s) failed\n";
        return 1;
    }
    std::cout << "NCM Rig Bridge feel tests passed\n";
    return 0;
}
