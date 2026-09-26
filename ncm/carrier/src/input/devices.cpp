#include "input/devices.hpp"

#include "input/hid_scan.hpp"
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

/// How long to let SDL's detector find hardware before calling a zero a zero. Detection on Windows is
/// asynchronous, so reading `SDL_NumJoysticks()` on the line after init can legitimately return 0 on a
/// machine with four controllers plugged in.
constexpr int kDetectWaitMs = 2000;
constexpr int kDetectStepMs = 100;

/// Wait, briefly, for SDL to report any device at all. Returns the final count.
int Devices::waitForDevices(const char* strategy)
{
    for (int waited = 0; waited <= kDetectWaitMs; waited += kDetectStepMs) {
        SDL_JoystickUpdate();  // events are ignored, so detection has to be pumped by hand
        const int count = SDL_NumJoysticks();
        if (count > 0) {
            NCM_INFO("SDL [%s]: %d joystick(s) after %d ms", strategy, count, waited);
            return count;
        }
        if (waited < kDetectWaitMs) SDL_Delay(kDetectStepMs);
    }
    NCM_WARN("SDL [%s]: still 0 joystick(s) after %d ms (last error: %s)", strategy, kDetectWaitMs,
             SDL_GetError() && *SDL_GetError() ? SDL_GetError() : "none");
    return 0;
}

bool Devices::open()
{
    // WHAT WENT WRONG ON 2026-09-25, AND WHY THE ANSWER IS A HINT AND NOT A DEVICE QUIRK.
    //
    // The carrier reported `devices none` on a machine with FOUR working controllers -- a Logitech G29
    // wheelbase, Thrustmaster pedals, a custom ESP32 rim over Bluetooth, and an Xbox pad -- all healthy in
    // Windows. Four vendors, three transports, zero seen. No per-device explanation survives that; only
    // something that blinds the whole subsystem does.
    //
    // `SDL_HINT_JOYSTICK_THREAD` is documented as controlling "whether a separate thread should be used
    // for handling joystick DETECTION and raw input messages on Windows", and it defaults to off -- which
    // means detection rides on the message pump of whatever thread called init. We init from RED4ext's
    // Running `OnEnter`, a game-engine state callback, and nothing promises that thread dispatches window
    // messages to SDL's message-only window. Turning the hint on gives SDL its own pump and removes the
    // dependency on the host's entirely.
    //
    // Ask Windows first, underneath DirectInput, so we know what SDL OUGHT to find before we judge what
    // it did find. This is also where the exclusive-acquisition theory gets tested; see `hid_scan.hpp`.
    const int expected = hid::logGameControllers();

    // Hints must be set BEFORE the subsystem starts, so they go first.
    SDL_SetHint(SDL_HINT_JOYSTICK_THREAD, "1");
    // The game owns the foreground window, not us; without this SDL can decline to report devices it does
    // not believe we are entitled to read.
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");

    SDL_version linked;
    SDL_GetVersion(&linked);
    const uint32_t wasInit = SDL_WasInit(SDL_INIT_JOYSTICK);
    NCM_INFO("SDL %u.%u.%u linked; joystick subsystem was %s before we touched it",
             linked.major, linked.minor, linked.patch, wasInit ? "already up" : "down");

    // **Joystick and haptic are initialised SEPARATELY, on purpose.** They used to be one call, so a
    // machine whose haptic layer refused took the joysticks down with it and the carrier reported no
    // hardware at all. A rig with no force feedback is still a rig we can read.
    if (wasInit == 0) {
        if (SDL_InitSubSystem(SDL_INIT_JOYSTICK) != 0) {
            NCM_ERR("SDL joystick subsystem unavailable: %s -- no input this session", SDL_GetError());
            return false;
        }
        sdlOwned_ = true;
    }
    if (SDL_InitSubSystem(SDL_INIT_HAPTIC) != 0) {
        NCM_WARN("SDL haptic subsystem unavailable: %s -- reading devices anyway", SDL_GetError());
    }

    SDL_JoystickEventState(SDL_IGNORE);  // we poll; events would fight the game's own pump

    int count = waitForDevices("default");

    // Second strategy, and it is a DIAGNOSTIC as much as a fallback. RAWINPUT is SDL's default Windows
    // backend; if turning it off finds hardware that leaving it on could not, the log says so plainly and
    // the next build can stop guessing.
    //
    // **THE TRIGGER USED TO BE `count == 0`, AND THAT WAS THE BUG.** On 2026-09-25 SDL found the Xbox pad
    // instantly and stopped, so the alternate backend was never tried on a rig that was missing three
    // devices. "Found something" is not "found everything". Windows' own HID count is the yardstick now:
    // if SDL is short of it, try the other backend before settling.
    if (count < expected && sdlOwned_) {
        NCM_WARN("retrying enumeration with SDL_JOYSTICK_RAWINPUT disabled");
        SDL_QuitSubSystem(SDL_INIT_JOYSTICK);
        SDL_SetHint(SDL_HINT_JOYSTICK_RAWINPUT, "0");
        if (SDL_InitSubSystem(SDL_INIT_JOYSTICK) != 0) {
            NCM_ERR("re-init without RAWINPUT failed: %s", SDL_GetError());
            return false;
        }
        SDL_JoystickEventState(SDL_IGNORE);
        count = waitForDevices("no-rawinput");
    }

    if (expected > 0 && count < expected) {
        NCM_WARN("SDL sees %d of the %d game controller(s) Windows reports. The missing ones are not "
                 "broken; something else in this process has them. See the HID read-handle results above.",
                 count, expected);
    }

    if (count == 0) {
        NCM_ERR("SDL reports no joystick of any kind. Windows device manager is the place to check next; "
                "if hardware IS present this is a carrier defect, not a player problem.");
        openHaptic();
        return false;
    }

    for (int i = 0; i < count; ++i) {
        // Named BEFORE opening, so a device we cannot open is still identified in the log rather than
        // vanishing. "A device we failed to read" and "no device" are different problems.
        const char* indexName = SDL_JoystickNameForIndex(i);
        char guid[64] = {};
        SDL_JoystickGetGUIDString(SDL_JoystickGetDeviceGUID(i), guid, sizeof(guid));

        SDL_Joystick* js = SDL_JoystickOpen(i);
        if (!js) {
            NCM_WARN("device %d \"%s\" [%s] could not be opened: %s", i,
                     indexName ? indexName : "unnamed", guid, SDL_GetError());
            continue;
        }

        Device device;
        device.sdlIndex = i;
        device.name = SDL_JoystickName(js) ? SDL_JoystickName(js) : (indexName ? indexName : "unknown");
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
        NCM_INFO("device %d: \"%s\" [%s] (%d axes, %d buttons, %d hat(s))", i,
                 devices_.back().name.c_str(), guid, axes, devices_.back().buttons,
                 SDL_JoystickNumHats(js));
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
    NCM_INFO("SDL reports %d haptic device(s)", count);
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
