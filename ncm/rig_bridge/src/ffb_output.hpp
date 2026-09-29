#pragma once

// NCM Rig Bridge -- force-feedback OUTPUT, and nothing else.
//
// Force output used to live inside the input provider: it shared the polling handle, borrowed whichever
// visible window the game process happened to own, and was torn down by every device rescan. Each of
// those couplings could silence the wheel on its own, and together they made "no force" a hunt.
//
// This module owns the whole output path and follows the sequence SDL's DirectInput haptic backend uses --
// the only recipe that has ever moved the owner's wheel (tools/ncm-wheel.py drove it through SDL):
//
//   own device instance -> own message-only window -> EXCLUSIVE|BACKGROUND -> acquire -> reset ->
//   actuators on -> create four effects on ONE force axis -> start each ONCE -> thereafter only update
//   type-specific parameters. "Silent" is magnitude zero, never Stop(), so nothing ever needs restarting.
//
// Every DirectInput call records its HRESULT into `status()`, which the panel shows. A tester reporting
// "no force" hands over the failing call and its code in one screenshot -- nobody runs a console tool.

#include <dinput.h>
#include <windows.h>

#include <chrono>
#include <cstdint>
#include <functional>
#include <string>

namespace ncm::rig {

/// The three vibration sliders, each on its own effect so each can be felt and measured alone.
enum class Vibe { Slip = 0, Road = 1, Engine = 2, Impact = 3 };
constexpr int kVibes = 4;

class FfbOutput {
public:
    /// `warn` = true for a failure worth a WARN line. The module never decides where logs go.
    using Log = std::function<void(bool warn, const std::string& line)>;

    explicit FfbOutput(Log log = {}) : log_(std::move(log)) {}
    ~FfbOutput() { close(); }
    FfbOutput(const FfbOutput&) = delete;
    FfbOutput& operator=(const FfbOutput&) = delete;

    /// Open `instance` for output. Returns true when at least the constant effect exists -- without it
    /// there is no steering weight and the output is not usable. Safe to call repeatedly.
    bool open(IDirectInput8W* api, const GUID& instance, const std::string& name);
    void close();

    bool isOpen() const { return device_ != nullptr && constant_ != nullptr; }
    const GUID& instance() const { return instance_; }

    /// Condition coefficients, 0..1 of the device's own maximum. Standing stiffness: call on change only.
    void setConditions(float spring, float damper);
    /// Signed steering torque, -1..1 of device maximum. Cheap to call every tick; unchanged values are
    /// not re-sent.
    void setConstant(float value);
    /// One vibration channel, 0..1 of device maximum. SLIP and ROAD pass the fixed carrier period; ENGINE
    /// passes a rev-following one, rewritten at most every 100 ms. Each channel is its own effect, so one
    /// channel's period change can never restart another.
    void setVibration(Vibe which, float magnitude, uint32_t periodMicros);
    /// Everything to zero. The effects keep PLAYING at zero, so the next write is felt immediately.
    void zero();

    // ---- self-report -------------------------------------------------------------------------------
    bool ok() const { return isOpen() && failures_ == 0; }
    int effects() const;                    // how many of the seven exist
    const char* axisName() const;
    const std::string& status() const { return status_; }   // one line, human-readable, carries HRESULTs
    uint64_t writes() const { return writes_; }
    uint64_t failures() const { return failures_; }

private:
    bool write(IDirectInputEffect* effect, DIEFFECT& params, const char* what);
    bool createAll(DWORD axis);
    void releaseEffects();
    void note(bool warn, const std::string& line);
    static HWND helperWindow();

    Log log_;
    GUID instance_{};
    std::string name_;
    IDirectInputDevice8W* device_ = nullptr;
    IDirectInputEffect* spring_ = nullptr;
    IDirectInputEffect* damper_ = nullptr;
    IDirectInputEffect* constant_ = nullptr;
    struct Periodic {
        IDirectInputEffect* effect = nullptr;
        LONG sent = LONG_MIN;
        DWORD period = 0;
        std::chrono::steady_clock::time_point last{};
        std::chrono::steady_clock::time_point lastPeriod{};
    };
    Periodic vibes_[kVibes];
    DWORD axis_ = DIJOFS_X;

    // What the device was last TOLD. A value within one DirectInput unit-step is not re-sent.
    LONG sentConstant_ = LONG_MIN;
    LONG sentSpring_ = LONG_MIN;
    LONG sentDamper_ = LONG_MIN;

    std::string status_ = "not opened";
    uint64_t writes_ = 0;
    uint64_t failures_ = 0;
    HRESULT lastFailure_ = S_OK;
};

}  // namespace ncm::rig
