#pragma once

#include "feel.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace ncm::rig {

struct AxisBinding {
    // **The stable key is VID:PID**, e.g. "044F:B371". DirectInput INSTANCE guids change between
    // sessions -- the same G29 enumerated as {A8C4D180-...-8008-...} and then {A702FD40-...-8006-...} --
    // so a config written against an instance guid silently stops matching and the role falls through to
    // whatever else is plugged in. VID:PID also means a binding is meaningful on somebody else's machine.
    std::string deviceKey;
    std::string deviceGuid;   // legacy/instance, still matched for older configs
    std::string deviceName;
    std::string axis;
    bool invert = false;
    float minimum = 0.0f;
    float maximum = 1.0f;
    float deadzone = 0.0f;
};

struct ButtonBinding {
    std::string deviceKey;
    std::string deviceGuid;
    std::string deviceName;
    uint32_t button = 0;
    uint16_t virtualKey = 0;
    bool vehicleOnly = true;
};

struct Config {
    uint16_t port = 38520;
    bool inputEnabled = true;
    // The companion's `steer_curve` default. Above 1.0 softens the centre; the 0.5 this shipped with was
    // the inverse curve and made the wheel roughly twice as twitchy off-centre as the rig is driven with.
    float steeringGamma = 1.3f;

    // **How much of the wheel's physical travel is full lock.** Without this the plugin mapped the wheel's
    // ENTIRE range to full lock, so a 900-degree G29 needed 450 degrees of rotation to reach it and the car
    // barely left centre however hard it was turned. `scale = (wheelRange / 2) / steerDegrees`, exactly as
    // the companion computes it: 900 and 45 give 10x.
    float steerDegrees = 45.0f;
    float wheelRangeDegrees = 900.0f;
    float steerScale() const { return (wheelRangeDegrees / 2.0f) / (steerDegrees < 5.0f ? 5.0f : steerDegrees); }
    // **Nothing is bound out of the box except by shape.** A wheel announces itself as a driving device
    // and is adopted automatically; a pedal set cannot be told from a gamepad by enumeration alone, so it
    // is never guessed -- the panel binds it. An unbound role contributes nothing rather than defaulting.
    AxisBinding steering{"", "", "", "x", false, 0.0f, 1.0f, 0.015f};
    AxisBinding throttle{"", "", "", "x", false, 0.0f, 1.0f, 0.02f};
    AxisBinding brake{"", "", "", "z", false, 0.0f, 1.0f, 0.02f};
    AxisBinding clutch{"", "", "", "y", false, 0.0f, 1.0f, 0.02f};
    std::vector<ButtonBinding> buttons;

    std::string ffbDeviceKey;
    std::string ffbDeviceGuid;
    std::string ffbDeviceName;
    bool ffbEnabled = true;
    bool ffbArmed = false;

    // **The class is a safety declaration, not a label.** It picks the ceiling from the measured ladder in
    // `feel.hpp`, and an unrecognised value is `unknown` -- the LOWEST ceiling of the four, because a device
    // we could not identify is assumed to be the most powerful thing it could be.
    // `Unknown` now also means AUTO: the bound wheel's recognised class is used when there is one.
    feel::DeviceClass deviceClass = feel::DeviceClass::Unknown;
    // **Strength is the SLIDER, 0..1 of the ceiling -- never a device magnitude.** The ceiling depends on
    // which wheel is attached (and, for direct drive, its torque), which is not known when the file is
    // read. Storing the magnitude clamped it against a guess before the wheel had been seen.
    float ffbFraction = 0.5f;
    float ratedNm = 0.0f;   // the driver's own base torque; 0 = use the recognised value
    feel::Tune tune{};
    uint32_t ffbWatchdogMs = 250;

    static Config load(const std::wstring& directory);
    /// Writes the bindings back so a choice made in the panel survives a restart. Best-effort: a rig that
    /// cannot save its configuration must still drive.
    bool save(const std::wstring& directory) const;
};
}
