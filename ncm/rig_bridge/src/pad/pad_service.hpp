#pragma once

// NCM Rig Bridge -- the gamepad layer's orchestrator: sources in (SDL3 + DirectInput), the JoyMoco engine in
// the middle, XInput out; recording, calibration, rumble presets, profiles on disk, and the local HTTP API the
// F6 DEVICES > GAMEPAD panel talks to.
//
// **Why a separate HTTP API instead of the existing bridge socket.** The Rig Bridge's snapshot reaches the
// panel through bridge.html -> Lua -> `page:send`, and `page:send` silently drops large messages (`KB-63`).
// A gamepad profile with dozens of recorded variants would cross that line with no error anywhere. The panel
// therefore fetches gamepad state straight from this loopback listener, guarded to this game's process tree.

#include "pad_engine.hpp"
#include "sdl_input.hpp"

#include <nlohmann/json.hpp>

#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace ncm::rig {
class DirectInputRig;
}

namespace ncm::rig::pad {

class PadService {
public:
    PadService(std::wstring directory, DirectInputRig& rig, uint16_t apiPort);
    ~PadService();

    void start();
    void stop();

    uint16_t apiPort() const { return apiPort_.load(); }
    nlohmann::json state();
    nlohmann::json command(const nlohmann::json& cmd);

private:
    struct RumbleStep { std::vector<std::string> hands; float level; uint32_t durationMs, gapMs; };
    enum class Phase { Idle, Countdown, Capture };
    enum class Mode { Button, Motion, Calibrate };

    void tickLoop();
    void rumbleLoop();
    void apiLoop();
    void serve(uintptr_t socket);

    bool loadProfile(const std::string& name, std::string* error);
    bool saveProfile(const std::string& name, std::string* error);
    std::vector<std::string> profileNames() const;
    std::wstring profilePath(const std::string& name) const;
    void applyProfileLocked();
    void finishRecordingLocked(int64_t now);

    void playEffect(const std::string& effectId, const std::string& side);
    std::vector<std::string> handsFor(const std::string& side) const;

    std::wstring directory_;
    DirectInputRig& rig_;
    SdlInput sdl_;
    std::atomic<uint16_t> apiPort_;
    std::atomic<bool> running_{false};
    std::thread tick_, rumble_, api_;
    std::atomic<uintptr_t> listener_{0};

    std::mutex mutex_;                // engine, profile, recording, live view
    Engine engine_;
    nlohmann::json profile_ = nlohmann::json::object();
    std::string profileName_ = "default";
    bool dirty_ = false;
    Samples live_;
    VirtualPad pad_;
    bool driving_ = false;
    int64_t nowNs_ = 0;

    Phase phase_ = Phase::Idle;
    Mode mode_ = Mode::Button;
    std::string recordTarget_, recordContext_ = "both";
    int64_t phaseStartNs_ = 0;
    std::vector<Frame> frames_;
    std::string recordResult_;
    bool recordOk_ = false;

    std::mutex rumbleMutex_;
    std::condition_variable rumbleWake_;
    std::deque<RumbleStep> rumbleQueue_;
    float lastGameLarge_ = -1.0f, lastGameSmall_ = -1.0f;
};

}  // namespace ncm::rig::pad
