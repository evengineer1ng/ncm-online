#pragma once

// NCM Rig Bridge -- the GAMEPAD layer's data model.
//
// A C++ port of JoyMoco's model (`src/joymoco/model.py` in the owner's JoyMoco repository, read-only). The
// profile format is JoyMoco's profile v1 so a profile can move between the two, with three additions that
// are Rig Bridge's own and are documented in `GAMEPAD_PROFILE.md` beside this plugin:
//
//   * a condition's `controller` may be a DEVICE KEY (`joystick:<name or serial>`, `di:<VID:PID>`) as well
//     as a JoyMoco hand (`left`, `right`, `primary`, `left_leg`, `right_leg`, `controller`), and a raw
//     device's buttons are named `b<index>` (0-based) and its hats `hat<n>_up|right|down|left`;
//   * every variant and mapping carries `context`: `both` (default), `driving` or `on_foot`;
//   * `xinput.user_index` names which XInput slot the virtual pad merges into.

#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace ncm::rig::pad {

struct Vec3 {
    float x = 0.0f, y = 0.0f, z = 0.0f;
    float axis(const std::string& name) const { return name == "y" ? y : name == "z" ? z : x; }
    Vec3 minus(const Vec3& o) const { return {x - o.x, y - o.y, z - o.z}; }
};

/// One source's state at one instant. For a JoyMoco hand every field is meaningful; a raw device fills
/// `buttons` (as `b<n>` / `hat<n>_<dir>`) and `axes` (normalised -1..1) and leaves the motion fields zero.
struct Sample {
    bool connected = true;
    int64_t tNs = 0;
    std::set<std::string> buttons;
    float stickX = 0.0f, stickY = 0.0f, stick2X = 0.0f, stick2Y = 0.0f;
    float triggerLeft = 0.0f, triggerRight = 0.0f;
    Vec3 gyro;           // degrees / second
    Vec3 accel;          // g
    Vec3 orientation;    // degrees
    std::vector<float> axes;
    bool motion = false; // has gyro/accel (a Joy-Con, DualSense, Switch Pro ...)

    /// JoyMoco's `getattr(sample, field).axis(axis)`, for the named fields a condition may read.
    float field(const std::string& name, const std::string& axis) const;
    bool held(const std::string& button) const { return buttons.count(button) != 0; }
};

/// Keyed by source: a JoyMoco hand name, or a device key.
using Samples = std::map<std::string, Sample>;

/// What the game is sent, in XInput's own vocabulary so the hook can merge it without translation.
struct VirtualPad {
    uint16_t buttons = 0;
    float lx = 0.0f, ly = 0.0f, rx = 0.0f, ry = 0.0f;   // -1..1, +y is up
    float lt = 0.0f, rt = 0.0f;                          // 0..1
    void reset() { *this = VirtualPad{}; }
    bool idle() const { return buttons == 0 && lx == 0 && ly == 0 && rx == 0 && ry == 0 && lt == 0 && rt == 0; }
    bool operator==(const VirtualPad&) const = default;
};

// XInput button bits. `home` is the Guide button, visible only through XInputGetStateEx.
constexpr uint16_t kDpadUp = 0x0001, kDpadDown = 0x0002, kDpadLeft = 0x0004, kDpadRight = 0x0008;
constexpr uint16_t kStart = 0x0010, kBack = 0x0020, kLs = 0x0040, kRs = 0x0080;
constexpr uint16_t kLb = 0x0100, kRb = 0x0200, kHome = 0x0400;
constexpr uint16_t kA = 0x1000, kB = 0x2000, kX = 0x4000, kY = 0x8000;

/// The gamepad button names JoyMoco uses, and their XInput bits. 0 = not a button.
uint16_t buttonBit(const std::string& name);
const std::vector<std::string>& buttonNames();

/// Every output a variant may target, in panel order: buttons, triggers, then held stick directions.
const std::vector<std::string>& targetNames();

/// JoyMoco hands. Anything else in a condition's `controller` is a device key.
bool isHand(const std::string& source);
bool isMotionHand(const std::string& source);

}  // namespace ncm::rig::pad
