#pragma once

// NCM Scanner state. Two flows cross here, in opposite directions, and neither blocks the other:
//
//   * DOWN (Lua -> redscript): what the reticle should say -- a state, the scan progress, a title and a detail.
//     Written by the bridge thread from each Lua `frame`, read by redscript on the game thread each tick.
//   * UP (redscript -> Lua): what the player is looking at while vision is on. Written by redscript through a
//     native on each tick, read by the bridge thread and returned as the reply to every Lua message.
//
// One mutex, and every read returns a copy. Two rules keep a dead feed from lying on screen:
//   * a dropped socket clears the reticle text (the green render and the bare reticle stay: they are the
//     player's own key, not Lua's);
//   * a stale feed (no Lua frame for kStaleMs) does the same.

#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace ncm::vision {

constexpr int64_t kStaleMs = 1500;
constexpr uint64_t kRecordMask = 0xFFFFFFFFFFull;   // CRC32 + length; the TweakDB offset bits are not identity

// Reticle states. The numbers are the wire; redscript switches on them.
enum class Reticle : int {
    Bare = 0,         // vision on, nothing to say (no feed, or not aimed at anything)
    Searching = 1,    // aimed at nothing useful
    Unknown = 2,      // an NCM machine this Driver has not identified
    Known = 3,        // an NCM machine this Driver already knows
    Scanning = 4,     // lock in progress
    Identified = 5,   // a scan just revealed it
    Refused = 6,      // no NCM record, out of range, too soon...
};

struct Target {
    bool active = false;     // vision is on
    uint64_t entity = 0;     // EntityID hash of the look-at object, 0 for none
    uint64_t record = 0;     // TweakDBID (masked) when the object is a vehicle, else 0
    int kind = 0;            // 0 none, 1 vehicle, 2 anything else
    float distance = -1.0f;
    float x = 0.0f, y = 0.0f, z = 0.0f;   // the object's world position; the server finds network cars by it
    uint32_t seq = 0;
};

// The quickhack list and the info panel beside the reticle (0.3.0). They arrive with each Lua frame; an empty
// list or an empty info title hides that panel.
struct HackRow {
    int state = 0;           // 0 ready, 1 unavailable, 2 slotting, 3 uploading, 4 cooling, 5 incoming
    std::string label;
    std::string right;       // free text: upload time, "COOLING 12s", "DRIVEN ONLY"...
};
struct InfoRow {
    std::string key;
    std::string value;
};
constexpr size_t kMaxHackRows = 12;
constexpr size_t kMaxInfoRows = 6;

class State {
public:
    using Clock = std::chrono::steady_clock;

    // One message from Lua. Returns false, and changes nothing, for anything it does not understand.
    bool apply(const std::string& message, Clock::time_point now = Clock::now());
    void disconnect();

    // "revision|state|progress|title|detail"; an empty text field is sent as "~".
    std::string reticle(Clock::time_point now = Clock::now());
    // "revision|selected|rows|infoTitle|infoSub|info": rows are "state`label`right" joined by '^', info rows are
    // "key`value" joined by '^'; selected is -1 for none; an empty field is "~". Redscript reads it right after
    // reticle() on the same tick, so the stale rule has already run.
    std::string panel();

    // Called by redscript through a native, on the game thread.
    void report(bool active, uint64_t entity, uint64_t record, int kind, float distance,
                float x = 0.0f, float y = 0.0f, float z = 0.0f);
    // The reply to every Lua message: {"vision":{...}}. The record travels as its KEY only; the server maps it
    // back to a catalogue record, so the catalogue never crosses the wire (L193).
    std::string targetJson();

    std::string health();

private:
    void clearPanel();   // caller holds mutex_
    std::mutex mutex_;
    int revision_ = 0;
    int state_ = 0;
    float progress_ = 0.0f;
    std::string title_;
    std::string detail_;
    int selected_ = -1;
    std::vector<HackRow> hacks_;
    std::string infoTitle_;
    std::string infoSub_;
    std::vector<InfoRow> info_;
    Clock::time_point lastFrame_{};
    bool haveFrame_ = false;
    bool staleCleared_ = false;
    Target target_{};
};

State& state();

// Exposed for tests.
std::string clean(const std::string& text, size_t limit);
uint32_t crc32(std::string_view text);
uint64_t recordKey(std::string_view name);
}
