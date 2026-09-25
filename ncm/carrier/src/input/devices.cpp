#include "input/devices.hpp"

#include "log.hpp"

#include <SDL.h>
#include <SDL_haptic.h>
#include <SDL_joystick.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>

namespace ncm::ffb {

DeviceClass classify(const std::string& deviceName)
{
    std::string lowered;
    lowered.reserve(deviceName.size());
    for (char c : deviceName) lowered.push_back(static_cast<char>(::tolower(static_cast<unsigned char>(c))));

    auto has = [&](const char* needle) { return lowered.find(needle) != std::string::npos; };

    // Direct drive first: it is the class that gets hurt by a wrong guess, so it wins every tie.
    if (has("moza") || has("simucube") || has("simagic") || has("fanatec dd") || has("podium") ||
        has("csl dd") || has("vrs ") || has("asetek") || has("cammus"))
        return DeviceClass::DirectDrive;

    if (has("g29") || has("g920") || has("g923") || has("g27") || has("g25") || has("driving force"))
        return DeviceClass::Gear;

    if (has("t128") || has("t150") || has("t248") || has("t300") || has("t500") || has("tmx") ||
        has("thrustmaster") || has("csl elite") || has("clubsport"))
        return DeviceClass::Belt;

    return DeviceClass::Unknown;
}

}  // namespace ncm::ffb

namespace ncm::input {
namespace {

constexpr int kAxisMax = 32767;
constexpr int kRestTolerance = 6000;   // generous: a centred wheel is rarely at exactly 0

double normaliseBipolar(int raw)
{
    return std::clamp(static_cast<double>(raw) / kAxisMax, -1.0, 1.0);
}

/// A pedal rests at one END of travel, usually -32768. Map that end to 0 and the far end to 1, which is the
/// fix for `IDEA-408`: read raw, a released pedal looks fully pressed.
double normalisePedal(int raw, int rest)
{
    const double span = (rest < 0) ? (2.0 * kAxisMax) : -(2.0 * kAxisMax);
    if (span == 0.0) return 0.0;
    return std::clamp((static_cast<double>(raw) - rest) / span, 0.0, 1.0);
}

}  // namespace

Devices::~Devices() { close(); }

bool Devices::open()
{
    // The game may already have initialised SDL. Initialising a subsystem twice is safe and reference
    // counted; initialising SDL itself when the host owns it is not.
    if (SDL_WasInit(SDL_INIT_JOYSTICK) == 0) {
        if (SDL_InitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC) != 0) {
            NCM_ERR("SDL joystick/haptic unavailable: %s", SDL_GetError());
            return false;
        }
        sdlOwned_ = true;
    }
    SDL_JoystickEventState(SDL_IGNORE);  // we poll; events would fight the game's own pump

    const int count = SDL_NumJoysticks();
    for (int i = 0; i < count; ++i) {
        SDL_Joystick* js = SDL_JoystickOpen(i);
        if (!js) continue;

        Device device;
        device.sdlIndex = i;
        device.name = SDL_JoystickName(js) ? SDL_JoystickName(js) : "unknown";
        device.joystick = reinterpret_cast<_SDL_Joystick*>(js);
        device.buttons = SDL_JoystickNumButtons(js);

        const int axes = SDL_JoystickNumAxes(js);
        SDL_JoystickUpdate();
        for (int a = 0; a < axes; ++a) {
            Axis axis;
            axis.index = a;
            axis.rest = SDL_JoystickGetAxis(js, a);
            axis.bipolar = std::abs(axis.rest) < kRestTolerance;
            device.axes.push_back(axis);
        }
        devices_.push_back(std::move(device));
        NCM_INFO("device %d: \"%s\" (%d axes, %d buttons)", i, devices_.back().name.c_str(), axes,
                 devices_.back().buttons);
    }

    classifyAll();
    openHaptic();
    return !devices_.empty();
}

void Devices::classifyAll()
{
    for (auto& device : devices_) {
        int bipolar = 0, unipolar = 0;
        for (const auto& axis : device.axes) (axis.bipolar ? bipolar : unipolar) += 1;

        if (bipolar >= 1 && device.axes.size() >= 3) {
            // A wheel base usually presents the steering axis plus its own pedal inputs.
            device.role = Role::Steering;
            wheelName_ = device.name;
            class_ = ffb::classify(device.name);
        } else if (bipolar == 1) {
            device.role = Role::Steering;
            wheelName_ = device.name;
            class_ = ffb::classify(device.name);
        } else if (unipolar >= 2) {
            device.role = Role::Pedals;
        } else if (device.buttons > 8 && device.axes.empty()) {
            device.role = Role::Rim;
        }
    }
    if (!wheelName_.empty())
        NCM_INFO("wheel \"%s\" classified as %s (ceiling %.2f)", wheelName_.c_str(),
                 ffb::nameOf(class_), ffb::ceilingFor(class_));
}

bool Devices::openHaptic()
{
    // **Opening a haptic index is not the test -- creating an effect is** (`IDEA-407`). The owner's wheel
    // enumerates three times and the middle index opens while being able to produce nothing. So probe.
    const int count = SDL_NumHaptics();
    for (int i = 0; i < count; ++i) {
        SDL_Haptic* haptic = SDL_HapticOpen(i);
        if (!haptic) continue;
        const unsigned int features = SDL_HapticQuery(haptic);
        if ((features & SDL_HAPTIC_CONSTANT) || (features & SDL_HAPTIC_SINE)) {
            haptic_ = reinterpret_cast<_SDL_Haptic*>(haptic);
            NCM_INFO("haptic device %d opened (%s), %d effect slot(s)", i,
                     SDL_HapticName(i) ? SDL_HapticName(i) : "unnamed", SDL_HapticNumEffects(haptic));
            return true;
        }
        SDL_HapticClose(haptic);
    }
    NCM_WARN("no haptic device could produce an effect -- force feedback is unavailable");
    return false;
}

void Devices::poll()
{
    SDL_JoystickUpdate();
    Controls next;

    for (const auto& device : devices_) {
        auto* js = reinterpret_cast<SDL_Joystick*>(device.joystick);
        if (!js) continue;

        for (const auto& axis : device.axes) {
            const int raw = SDL_JoystickGetAxis(js, axis.index);
            if (axis.bipolar && device.role == Role::Steering && !next.hasSteering) {
                next.steering = normaliseBipolar(raw);
                next.hasSteering = true;
            } else if (!axis.bipolar) {
                const double value = normalisePedal(raw, axis.rest);
                // Convention across every rig seen so far: the first unipolar axis is throttle, the second
                // brake. A rig that disagrees is what the panel's rebinding is for.
                if (!next.hasThrottle) { next.throttle = value; next.hasThrottle = true; }
                else if (!next.hasBrake) { next.brake = value; next.hasBrake = true; }
            }
        }
    }
    controls_ = next;
}

std::string Devices::describe() const
{
    if (devices_.empty()) return "none";
    std::string out = wheelName_.empty() ? "unclassified" : wheelName_;
    out += " [";
    out += ffb::nameOf(class_);
    out += haptic_ ? ", haptic" : ", no haptic";
    out += "]";
    return out;
}

void Devices::close()
{
    if (haptic_) {
        SDL_HapticClose(reinterpret_cast<SDL_Haptic*>(haptic_));
        haptic_ = nullptr;
    }
    for (auto& device : devices_) {
        if (device.joystick) SDL_JoystickClose(reinterpret_cast<SDL_Joystick*>(device.joystick));
        device.joystick = nullptr;
    }
    devices_.clear();
    if (sdlOwned_) {
        SDL_QuitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC);
        sdlOwned_ = false;
    }
}

}  // namespace ncm::input
