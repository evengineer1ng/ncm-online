// NCM Carrier -- the only thing in this plugin that can move a wheel.
//
// Four effects, all infinite-length and continuously updated rather than re-triggered:
//
//   CONSTANT  self-aligning torque -- the weight that pulls the wheel back toward centre
//   SINE      texture and slip, at 125 Hz, period modulated by engine revs
//   SPRING    centring stiffness. Condition effects ARE stiffness; simulating it with constant force is a
//   DAMPER    fight against the player's own hands.
//
// 125 Hz is not arbitrary. 25 Hz was the first attempt and felt like a rumble pack; 125 Hz is what `anyffb`
// uses on this exact hardware and it is the difference between "a motor is running" and "the tyres are
// letting go".
//
// THREE DEFECTS THIS FILE EXISTS TO NOT REPEAT:
//
//   `KB-103`  effects were run once at arm time and never again, so the first `stop()` silenced the wheel
//             for the rest of the session. `resume()` is the fix and it is regression-tested.
//   `KB-104`  resolution must be relative to what the DEVICE can produce, not an abstract 0..1. A direct
//             drive's whole range is 0.06, so a 1/500 grain of the full scale is most of its dynamic range.
//   `IDEA-412` an SDL haptic effect OUTLIVES ITS PROCESS. After `stop()`, process exit and `SDL_HapticClose`,
//             the wheel stayed powered and pulled to one side. Teardown must DESTROY, not stop.
#pragma once

#include "ffb/safety.hpp"

struct _SDL_Haptic;

namespace ncm::ffb {

// The rev-linked band for the engine hum. Below idle it would be a vibration; above the span it would be a
// tone. Both are wrong for the same reason -- an engine is felt, not heard, through a wheel.
constexpr double kEngineHzIdle = 12.0;
constexpr double kEngineHzSpan = 35.0;

inline int enginePeriodMs(double revRatio) noexcept
{
    const double hz = kEngineHzIdle + kEngineHzSpan * (revRatio < 0.0 ? 0.0 : (revRatio > 1.0 ? 1.0 : revRatio));
    return static_cast<int>(1000.0 / hz);
}

class Output {
public:
    explicit Output(DeviceClass cls) : class_(cls) {}
    ~Output();

    bool arm(_SDL_Haptic* haptic);
    void write(double level, double torque, double revRatio);
    void stop();
    void destroy();

    bool armed() const { return armed_; }

private:
    bool resume();

    DeviceClass class_ = DeviceClass::Unknown;
    _SDL_Haptic* haptic_ = nullptr;
    bool armed_ = false;
    bool playing_ = false;

    int constantId_ = -1;
    int sineId_ = -1;
    int springId_ = -1;
    int damperId_ = -1;

    double lastLevel_ = -1.0;
    double lastTorque_ = -1.0;
    int lastPeriod_ = -1;
};

}  // namespace ncm::ffb
