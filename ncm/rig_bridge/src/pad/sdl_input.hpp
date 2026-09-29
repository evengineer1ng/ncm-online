#pragma once

// NCM Rig Bridge -- SDL3 input: Joy-Cons, DualShock/DualSense, Switch Pro (as JoyMoco HANDS, with gyro and
// accelerometer), plus every plain joystick SDL can see (the ESP32 rim, a wheel base, pedals) as
// `joystick:<serial or name>`.
//
// A port of JoyMoco's `SdlJoyConService` (owner's JoyMoco repository, read-only). SDL3 is loaded at run time
// from beside this DLL and bound by `GetProcAddress`, exactly as JoyMoco binds it through ctypes, so there
// is no import-time dependency: a missing SDL3.dll disables motion input and says so, and nothing else.
//
// **Why SDL at all, when DirectInput already reads the wheel.** Two reasons, both measured: DirectInput
// cannot read a Joy-Con's IMU, and the owner's Evenracing rim (E502:BBAB) is never offered to DirectInput
// inside the game process while an out-of-process DirectInput scan finds it -- JoyMoco reads it through
// SDL3 as `joystick:Evenracing 1.0.0`, and the default profile's rim bindings use that key.
//
// **Threading.** Every SDL call happens on this class's own thread, which is also the thread that called
// `SDL_Init` and pumps its events. Callers read snapshots and queue rumble; they never touch SDL.

#include "pad_model.hpp"

#include <nlohmann/json.hpp>

#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace ncm::rig::pad {

class SdlInput {
public:
    using Log = std::function<void(bool warn, const std::string& line)>;

    SdlInput(std::wstring dllPath, Log log) : dllPath_(std::move(dllPath)), log_(std::move(log)) {}
    ~SdlInput() { stop(); }

    void start();
    void stop();

    /// JoyMoco `assignments`: hand -> "auto" | "none" | a controller serial/MAC.
    void setAssignments(const nlohmann::json& assignments);

    Samples snapshot() const;
    /// What SDL can see, for the panel: key, name, kind, assigned hand, motion, battery.
    nlohmann::json devices() const;
    /// Queue a rumble. `hand` is a JoyMoco hand; levels 0..1.
    void rumble(const std::string& hand, float low, float high, uint32_t durationMs);

    bool available() const { return available_.load(); }
    std::string status() const;

private:
    struct Impl;
    void run();

    std::wstring dllPath_;
    Log log_;
    std::thread thread_;
    std::atomic<bool> running_{false};
    std::atomic<bool> available_{false};
    Impl* impl_ = nullptr;
    mutable std::mutex mutex_;
    Samples samples_;
    nlohmann::json devices_ = nlohmann::json::array();
    nlohmann::json assignments_ = nlohmann::json::object();
    bool assignmentsChanged_ = false;
    struct Rumble { std::string hand; float low, high; uint32_t ms; };
    std::vector<Rumble> rumbles_;
    std::string status_ = "not started";
};

}  // namespace ncm::rig::pad
