#include "ffb/output.hpp"

#include "log.hpp"

#include <SDL_haptic.h>

#include <algorithm>
#include <cmath>

namespace ncm::ffb {
namespace {

constexpr Uint32 kInfinite = SDL_HAPTIC_INFINITY;

Sint16 toMagnitude(double normalised)
{
    return static_cast<Sint16>(std::clamp(normalised, 0.0, 1.0) * 32767.0);
}

Sint16 toSignedMagnitude(double normalised)
{
    return static_cast<Sint16>(std::clamp(normalised, -1.0, 1.0) * 32767.0);
}

}  // namespace

Output::~Output() { destroy(); }

bool Output::arm(_SDL_Haptic* handle)
{
    haptic_ = handle;
    if (!haptic_) return false;
    auto* haptic = reinterpret_cast<SDL_Haptic*>(haptic_);

    const unsigned int features = SDL_HapticQuery(haptic);

    if (features & SDL_HAPTIC_CONSTANT) {
        SDL_HapticEffect effect{};
        effect.type = SDL_HAPTIC_CONSTANT;
        effect.constant.type = SDL_HAPTIC_CONSTANT;
        // Cartesian, straight along X. Direction is carried in the sign of the level, always toward centre.
        effect.constant.direction.type = SDL_HAPTIC_CARTESIAN;
        effect.constant.direction.dir[0] = 1;
        effect.constant.length = kInfinite;
        effect.constant.level = 0;
        constantId_ = SDL_HapticNewEffect(haptic, &effect);
    }

    if (features & SDL_HAPTIC_SINE) {
        SDL_HapticEffect effect{};
        effect.type = SDL_HAPTIC_SINE;
        effect.periodic.type = SDL_HAPTIC_SINE;
        effect.periodic.direction.type = SDL_HAPTIC_CARTESIAN;
        effect.periodic.direction.dir[0] = 1;
        effect.periodic.length = kInfinite;
        effect.periodic.period = 8;   // 125 Hz
        effect.periodic.magnitude = 0;
        sineId_ = SDL_HapticNewEffect(haptic, &effect);
    }

    // Condition effects are what stiffness IS. Without them, centring has to be synthesised from constant
    // force against the player's own movement, which feels like fighting rather than like weight.
    if (features & SDL_HAPTIC_SPRING) {
        SDL_HapticEffect effect{};
        effect.type = SDL_HAPTIC_SPRING;
        effect.condition.type = SDL_HAPTIC_SPRING;
        effect.condition.length = kInfinite;
        for (int axis = 0; axis < 3; ++axis) {
            effect.condition.right_sat[axis] = 0xFFFF;
            effect.condition.left_sat[axis] = 0xFFFF;
            effect.condition.right_coeff[axis] = 0;
            effect.condition.left_coeff[axis] = 0;
        }
        springId_ = SDL_HapticNewEffect(haptic, &effect);
    }

    if (features & SDL_HAPTIC_DAMPER) {
        SDL_HapticEffect effect{};
        effect.type = SDL_HAPTIC_DAMPER;
        effect.condition.type = SDL_HAPTIC_DAMPER;
        effect.condition.length = kInfinite;
        damperId_ = SDL_HapticNewEffect(haptic, &effect);
    }

    armed_ = (constantId_ >= 0 || sineId_ >= 0);
    if (!armed_) {
        NCM_WARN("haptic device accepted no usable effect -- nothing will be felt");
        return false;
    }

    NCM_INFO("force feedback armed: constant %s, sine %s, spring %s, damper %s; class %s, ceiling %.2f",
             constantId_ >= 0 ? "yes" : "no", sineId_ >= 0 ? "yes" : "no",
             springId_ >= 0 ? "yes" : "no", damperId_ >= 0 ? "yes" : "no",
             nameOf(class_), ceilingFor(class_));
    return resume();
}

bool Output::resume()
{
    // KB-103. Running an effect once at arm time is not enough: after any `stop()` the effect is no longer
    // playing, and every subsequent update writes parameters nobody is listening to. The wheel goes quiet
    // for the rest of the session and nothing reports an error.
    if (!haptic_) return false;
    auto* haptic = reinterpret_cast<SDL_Haptic*>(haptic_);

    bool ok = true;
    for (int id : { constantId_, sineId_, springId_, damperId_ }) {
        if (id < 0) continue;
        if (SDL_HapticRunEffect(haptic, id, 1) != 0) {
            NCM_WARN("could not run effect %d: %s", id, SDL_GetError());
            ok = false;
        }
    }
    playing_ = ok;
    return ok;
}

void Output::write(double level, double torque, double revRatio)
{
    if (!armed_ || !haptic_) return;
    auto* haptic = reinterpret_cast<SDL_Haptic*>(haptic_);

    if (!playing_ && !resume()) return;

    // The two exits. `clamp()` is the only way a magnitude leaves the safety module; torque is signed and
    // therefore uses the symmetric clamp, which enforces the same ceiling.
    const double texture = clamp(class_, level);
    const double aligned = clampTorque(class_, torque);

    // KB-104: resolution relative to the device, not to an abstract full scale. A direct drive's entire
    // permitted range is 0.06, so an absolute grain would quantise it to nothing.
    const double grain = std::max(0.0002, ceilingFor(class_) / 500.0);

    if (constantId_ >= 0 && std::abs(aligned - lastTorque_) >= grain) {
        SDL_HapticEffect effect{};
        effect.type = SDL_HAPTIC_CONSTANT;
        effect.constant.type = SDL_HAPTIC_CONSTANT;
        effect.constant.direction.type = SDL_HAPTIC_CARTESIAN;
        effect.constant.direction.dir[0] = 1;
        effect.constant.length = kInfinite;
        effect.constant.level = toSignedMagnitude(aligned);
        SDL_HapticUpdateEffect(haptic, constantId_, &effect);
        lastTorque_ = aligned;
    }

    const int period = enginePeriodMs(revRatio);
    if (sineId_ >= 0 && (std::abs(texture - lastLevel_) >= grain || period != lastPeriod_)) {
        SDL_HapticEffect effect{};
        effect.type = SDL_HAPTIC_SINE;
        effect.periodic.type = SDL_HAPTIC_SINE;
        effect.periodic.direction.type = SDL_HAPTIC_CARTESIAN;
        effect.periodic.direction.dir[0] = 1;
        effect.periodic.length = kInfinite;
        effect.periodic.period = static_cast<Uint16>(period);
        effect.periodic.magnitude = toMagnitude(texture);
        SDL_HapticUpdateEffect(haptic, sineId_, &effect);
        lastLevel_ = texture;
        lastPeriod_ = period;
    }
}

void Output::stop()
{
    if (!haptic_) return;
    auto* haptic = reinterpret_cast<SDL_Haptic*>(haptic_);
    // Zero first, then stop. Stopping an effect that still holds a level has been observed to leave the
    // level applied.
    write(0.0, 0.0, 0.0);
    for (int id : { constantId_, sineId_, springId_, damperId_ }) {
        if (id >= 0) SDL_HapticStopEffect(haptic, id);
    }
    playing_ = false;
}

void Output::destroy()
{
    if (!haptic_) return;
    auto* haptic = reinterpret_cast<SDL_Haptic*>(haptic_);

    // IDEA-412. Stopping is not enough and closing is not enough: after both, the wheel stayed powered and
    // pulled to one side, and `SDL_HapticNumEffectsPlaying` still read 1. The effect must be DESTROYED.
    stop();
    for (int* id : { &constantId_, &sineId_, &springId_, &damperId_ }) {
        if (*id >= 0) {
            SDL_HapticDestroyEffect(haptic, *id);
            *id = -1;
        }
    }
    armed_ = false;
    haptic_ = nullptr;
    lastLevel_ = lastTorque_ = -1.0;
    lastPeriod_ = -1;
}

}  // namespace ncm::ffb
