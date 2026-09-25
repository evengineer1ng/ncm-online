// NCM Carrier -- the feel model.
//
// **NCM emits what the car is DOING, never how hard to push** (`IDEA-396`). Everything below turns measured
// vehicle state into one intensity and one self-aligning torque. The weights are the ones the companion
// arrived at over several testers' sessions and they are carried across unchanged, because a port that
// also retunes cannot be debugged: nobody could tell whether it feels different because it moved or
// because it changed.
//
// The rung is the shared unit (`L133`). A tester on a T128 and a tester on a G29 can both say "two rungs
// more" and mean the same thing, which no percentage ever achieved.
//
// KB-106 TRAVELS WITH IT. `kRoadScale = 1.0` means **not yet measured**. The observation counters below are
// what closes it: drive once, read the peaks, set the scale. A native carrier is a better desk for that
// measurement -- it is not a reason to postpone it.
#pragma once

#include "bridge/server.hpp"
#include "ffb/output.hpp"
#include "ffb/safety.hpp"

#include <chrono>
#include <map>
#include <memory>
#include <string>

namespace ncm::input { class Devices; }

namespace ncm::ffb {

// Raw suspension units -> 0..1. 1.0 reproduces the previous behaviour exactly rather than inventing a
// correction. If a hard kerb strike peaks at 0.04, this becomes 25.
constexpr double kRoadScale = 1.0;

struct Tune {
    double spring = 0.55;
    double damper = 0.35;
    double texture = 0.60;
    double engine = 0.45;
    double road = 1.00;
};

/// What a channel actually reached, so `kRoadScale` can be set from evidence instead of taste.
struct Observation {
    double max = 0.0;
    long frames = 0;
    bool live = false;
};

class Mixer {
public:
    explicit Mixer(input::Devices* devices);
    ~Mixer();

    void feed(const bridge::Frame& frame);
    void silence();
    void shutdown();

    void setRung(int index);
    int rungIndex() const { return rungIndex_; }
    double rung() const { return rung_; }

    Tune& tune() { return tune_; }
    const std::map<std::string, Observation>& observations() const { return observed_; }

    /// What the NCM panel draws for the CARRIER tab.
    std::string describe() const;

private:
    void observe(const char* channel, double value, bool live);
    void emit();

    input::Devices* devices_ = nullptr;
    std::unique_ptr<Output> out_;

    Tune tune_;
    double level_ = 0.0;
    double torque_ = 0.0;
    double engineRatio_ = 0.0;
    double rung_ = kFloor;
    int rungIndex_ = 0;

    std::map<std::string, Observation> observed_;
    std::chrono::steady_clock::time_point last_;
    bool started_ = false;
};

}  // namespace ncm::ffb
