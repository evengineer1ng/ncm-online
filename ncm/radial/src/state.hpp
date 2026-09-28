#pragma once

// The wheel's state, as Lua last described it. Written by the bridge thread, read by redscript on the game
// thread, so every access goes through one mutex and every read returns a copy.
//
// Two rules make this safe to leave running for a whole session:
//   * **A dropped socket closes the wheel** (`disconnect`). Lua owns the wheel; if Lua is gone, a wheel that
//     stays on screen is a wheel nobody can close.
//   * **A stale frame closes the wheel** (`frame` with a clock). Lua sends a frame every tick while the wheel is
//     up. If none arrives for `kStaleMs`, the resource has stalled or stopped, and the same reasoning applies.

#include <array>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>

namespace ncm::radial {

constexpr int kSlots = 8;
constexpr int64_t kStaleMs = 1500;

struct Slot {
    int state = 0;            // 0 open (no action), 1 live, 2 greyed
    std::string label;
    std::string key;
    std::string detail;
};

class State {
public:
    using Clock = std::chrono::steady_clock;

    // One message from Lua. Returns false, and changes nothing, for anything it does not understand.
    bool apply(const std::string& message, Clock::time_point now = Clock::now());
    void disconnect();

    // "open|selected|pointerDegrees|layoutRevision"
    std::string frame(Clock::time_point now = Clock::now());
    // "revision|title|hint" then kSlots x "state|label|key|detail"
    std::string layout();

    void reportHost(const std::string& host, int drawn);
    std::string health();

private:
    std::mutex mutex_;
    std::array<Slot, kSlots> slots_{};
    std::string title_ = "NCM";
    std::string hint_;
    int revision_ = 0;
    bool open_ = false;
    int selected_ = -1;
    float pointer_ = -1.0f;
    Clock::time_point lastFrame_{};
    std::string host_ = "none";
    int drawn_ = 0;
    bool staleClosed_ = false;
};

State& state();

// Exposed for tests: strips the field separator and control characters, and bounds the length.
std::string clean(const std::string& text, size_t limit);
}
