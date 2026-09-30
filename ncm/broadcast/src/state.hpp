#pragma once

// NCM Broadcast state (L235). Pure C++: no RED4ext, so the tests run without the game.
//
// The `ncm_broadcast` resource feeds two things over loopback, and redscript draws them natively in the HUD (no
// WebUI page is drawn; the only surface is the hidden transport page, in the resource's own budget of eight):
//
//   * labels -- a name over each race car that is not a player: {"cmd":"labels","ttl":3,"items":[{"entity":"<hash>",
//               "title":"Derek Smith","sub":"Kabuki Wolves","chip":"P1","accent":0}]}. The whole set is replaced
//               each time; it goes dark by itself `ttl` seconds after the last refresh, so a feed that stops (a race
//               that ended, a resource that died) never leaves names hanging in the air.
//   * tower  -- the opt-in timing tower: {"cmd":"tower","ttl":5,"title":..,"sub":..,"rows":[{"pos":"1","name":..,
//               "gap":"+0.8s","flag":"me"}]}. An empty row list hides it.
//   * view   -- calibration the server can change without a rebuild: {"cmd":"view","range":250,"scale":1,
//               "projX":1920,"projY":1080,"lift":1.9,"towerX":60,"towerY":330}.
//
// Every string redscript reads is '|'-separated, so '|' and line breaks are scrubbed from text on the way in.

#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace ncm::broadcast {

constexpr size_t kMaxLabels = 32;
constexpr size_t kMaxRows = 24;

struct Label {
    uint64_t entity = 0;
    std::string title, sub, chip;
    int accent = 0;                 // 0 field, 1 leader, 2 finished, 3 out
};

struct Row {
    std::string pos, name, gap, flag;   // flag: "", "me", "phys", "fin", "out"
};

struct View {
    double range = 250, scale = 1, projX = 1920, projY = 1080, lift = 1.9, towerX = 60, towerY = 330;
};

class State {
public:
    using Clock = std::chrono::steady_clock;

    bool apply(const std::string& json, Clock::time_point now = Clock::now());
    void disconnect();

    int labelCount(Clock::time_point now = Clock::now());
    uint64_t labelEntity(int index);
    std::string labelText(int index);              // "title|sub|chip|accent"
    std::string tower(Clock::time_point now = Clock::now());    // "rev|visible|title|sub|rows"
    std::string towerRow(int index);               // "pos|name|gap|flag"
    std::string view();                            // "rev|range|scale|projX|projY|lift|towerX|towerY"
    std::string health();
    std::vector<std::string> outbox();

private:
    std::mutex mutex_;
    std::vector<Label> labels_;
    Clock::time_point labelsUntil_{};
    int towerRev_ = 0;
    std::string towerTitle_, towerSub_;
    std::vector<Row> rows_;
    Clock::time_point towerUntil_{};
    int viewRev_ = 0;
    View view_;
    uint64_t messages_ = 0;
    std::vector<std::string> out_;
};

State& state();
uint64_t parseHash(const std::string& text);
std::string clean(std::string text, size_t max);
}
