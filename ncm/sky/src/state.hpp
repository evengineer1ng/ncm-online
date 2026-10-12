#pragma once

// NCM Sky state (KB-430). Two flows cross here, in opposite directions, and neither blocks the other:
//
//   * DOWN (Lua -> redscript): the SCENE -- each body NCM wants drawn, by id: its kind (which template), its
//     appearance, its world position and its full orientation (a unit quaternion i, j, k, r; redscript turns it into the
//     game's own EulerAngles with Quaternion.ToEulerAngles, so no Euler convention is guessed here). Written by the bridge
//     thread from each Lua `scene`, read by redscript on the game thread each tick.
//   * UP (redscript -> Lua): what redscript did with each body (spawned, moved, refused, gone) and the entity it
//     made. Written by redscript through a native, read by the bridge thread as the reply to every Lua message.
//
// One mutex, and every read returns a copy. A dead feed must never leave anything in the sky:
//   * a dropped socket empties the scene;
//   * a stale feed (no Lua scene for kStaleMs) does the same.

#include <chrono>
#include <cstdint>
#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace ncm::sky {

constexpr int64_t kStaleMs = 3000;
constexpr size_t kMaxBodies = 64;

struct Body {
    std::string id;          // Lua's name for it ("earth", "moon", ...): [a-z0-9_], at most 24 characters
    int kind = 0;            // which template (redscript's table); 0 is never valid
    std::string appearance;  // [a-z0-9_], may be empty
    double x = 0, y = 0, z = 0;
    double qi = 0, qj = 0, qk = 0, qr = 1;  // unit quaternion (REDengine Quaternion fields)
};

struct Report {
    int state = 0;           // 1 spawned, 2 moved, 3 refused, 4 despawned
    uint64_t entity = 0;
    std::string why;
};

class State {
public:
    using Clock = std::chrono::steady_clock;

    // One message from Lua. Returns false, and changes nothing, for anything it does not understand.
    bool apply(const std::string& message, Clock::time_point now = Clock::now());
    void disconnect();

    // "revision|body^body^..."; a body is "id`kind`appearance`x`y`z`qi`qj`qk`qr" (an empty appearance is "~").
    // The revision changes whenever the scene does, so redscript does nothing on a tick where it has not.
    std::string scene(Clock::time_point now = Clock::now());

    // Called by redscript through a native, on the game thread.
    void report(const std::string& id, int state, uint64_t entity, const std::string& why);
    // The reply to every Lua message: {"sky":{"rev":n,"bodies":{"earth":{"state":1,"entity":"...","why":""}}}}.
    std::string statusJson();
    std::string health();

private:
    std::mutex mutex_;
    int revision_ = 0;
    std::vector<Body> bodies_;
    std::map<std::string, Report> reports_;
    Clock::time_point lastScene_{};
    bool haveScene_ = false;
    bool staleCleared_ = false;
};

State& state();

// Exposed for tests.
bool validId(const std::string& id);
}
