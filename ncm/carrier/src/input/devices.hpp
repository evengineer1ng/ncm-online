// NCM Carrier -- wheel, pedals and the haptic device, through SDL.
//
// WHAT CHANGED BY MOVING INSIDE THE GAME. The companion had to present a virtual Xbox 360 pad through
// ViGEmBus, because nothing inside Cyberpunk could read a wheel and the only way in was to impersonate a
// controller. This plugin writes the final vehicle command directly, so **the virtual pad is gone** --
// and with it ViGEmBus, HidHide, the driver install dialog, and the whole bypass table in Report 34
// section 7 (Report 36 section 6.2 predicted exactly this).
//
// ROLES ARE DETECTED BY SHAPE, NOT BY NAME (`wheel-profiles/default.json._detection`), because names are
// inconsistent across drivers and firmware and a name-matched rig breaks when someone updates G HUB:
//
//   steering   an axis that rests near centre and travels both ways
//   pedals     axes that rest at one END of travel
//   rim        many buttons and no usable axes
//
// And the finding that cost an evening (`IDEA-408`): **a pedal at rest reads -32768, not 0.** Treated as
// raw, a released brake pedal is a fully applied one.
#pragma once

#include "ffb/safety.hpp"

#include <cstdint>
#include <string>
#include <vector>

struct _SDL_Joystick;
struct _SDL_Haptic;

namespace ncm::input {

enum class Role { Unknown, Steering, Pedals, Rim };

struct Axis {
    int index = 0;
    int rest = 0;           // where it sits untouched -- centre for a wheel, one end for a pedal
    bool bipolar = false;   // travels both ways from rest
};

struct Device {
    int sdlIndex = 0;
    std::string name;
    Role role = Role::Unknown;
    std::vector<Axis> axes;
    int buttons = 0;
    _SDL_Joystick* joystick = nullptr;
};

/// The player's current control inputs, normalised. Absent means absent: a rig with no clutch reports no
/// clutch rather than a clutch at zero (`IDEA-361`, applied to input).
struct Controls {
    bool hasSteering = false; double steering = 0.0;   // -1 .. 1
    bool hasThrottle = false; double throttle = 0.0;   //  0 .. 1
    bool hasBrake = false;    double brake = 0.0;      //  0 .. 1
};

class Devices {
public:
    ~Devices();

    bool open();
    void close();
    void poll();

    const Controls& controls() const { return controls_; }
    bool present() const { return !devices_.empty(); }

    ffb::DeviceClass deviceClass() const { return class_; }
    const std::string& wheelName() const { return wheelName_; }
    _SDL_Haptic* haptic() const { return haptic_; }

    /// What the NCM panel draws. Never invented -- an absent device is reported absent, because "no wheel
    /// detected" and "a wheel we could not identify" are different problems for a player to solve.
    std::string describe() const;

private:
    void classifyAll();
    bool openHaptic();

    std::vector<Device> devices_;
    Controls controls_;
    _SDL_Haptic* haptic_ = nullptr;
    ffb::DeviceClass class_ = ffb::DeviceClass::Unknown;
    std::string wheelName_;
    bool sdlOwned_ = false;
};

}  // namespace ncm::input
