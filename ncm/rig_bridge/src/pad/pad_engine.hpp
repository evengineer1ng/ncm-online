#pragma once

// NCM Rig Bridge -- the gamepad mapping engine: a C++ port of JoyMoco's `MappingEngine`, `StagedGesture`,
// `ThresholdGesture` and `MacroRunner` (owner's JoyMoco repository, read-only), plus two things JoyMoco
// does not have: every variant and mapping is filtered by CONTEXT (driving / on foot / both), and a
// condition may name a raw device (the ESP32 rim, a wheel base) as well as a Joy-Con hand.
//
// **Pure.** No SDL, no DirectInput, no XInput, no clock of its own: it is handed a snapshot of every
// source and a timestamp and returns the virtual pad. That is what lets `tests/pad_tests.cpp` hold its
// behaviour without hardware -- the same property JoyMoco's own test suite relies on.

#include "pad_model.hpp"

#include <nlohmann/json.hpp>

#include <cstdint>
#include <deque>
#include <map>
#include <optional>
#include <queue>
#include <string>
#include <utility>
#include <vector>

namespace ncm::rig::pad {
using json = nlohmann::json;

/// A variant asked for a rumble effect when it fired (JoyMoco `feedback_effect` / `feedback_side`).
struct Feedback {
    std::string effect;
    std::string side;
};

/// One time-stamped snapshot, the unit a recording is made of.
struct Frame {
    int64_t tNs = 0;
    Samples samples;
};

class Engine {
public:
    Engine() = default;
    explicit Engine(json profile) { setProfile(std::move(profile)); }

    void setProfile(json profile);
    const json& profile() const { return profile_; }

    /// Advance one tick. `driving` is the context filter's input: true while the player is mounted.
    VirtualPad process(const Samples& raw, int64_t nowNs, bool driving, std::vector<Feedback>* feedback = nullptr);

    /// Everything neutral, every hold dropped, every macro cancelled. The invariant JoyMoco's emergency
    /// reset owns: no output survives a disconnect, a profile change or a shutdown.
    void reset();

    /// Variants that are holding their output right now, or fired within the last 400 ms -- the panel lights
    /// these rows so a tester can see WHICH variant their press or swing matched.
    std::vector<std::string> activeVariants(int64_t nowNs) const;
    bool gyroSteeringOn() const { return steeringOn_; }
    const Samples& filteredSamples() const { return samples_; }

private:
    struct State {
        std::set<std::string> buttons;
        std::pair<float, float> leftStick{0.0f, 0.0f}, rightStick{0.0f, 0.0f};
        float leftTrigger = 0.0f, rightTrigger = 0.0f;
        void reset() { *this = State{}; }
    };
    struct Staged {
        json def;
        size_t stage = 0;
        int64_t stageSinceNs = 0;
        int64_t cooldownUntilNs = 0;
        std::map<std::string, std::set<std::string>> previous;
    };
    struct Threshold {
        json def;
        bool active = false;
        int64_t lastFireNs = 0;
    };
    struct Step {
        int64_t dueNs;
        uint64_t order;
        uint64_t run;
        json action;
        bool operator>(const Step& o) const { return dueNs != o.dueNs ? dueNs > o.dueNs : order > o.order; }
    };
    struct Pose { bool held = false; float centerH = 0.0f, centerV = 0.0f; };

    bool contextAllows(const json& def, bool driving) const;
    Sample calibrate(const std::string& source, const Sample& raw);
    std::optional<std::string> fireStaged(Staged& g, int64_t now, float* magnitude);
    bool fireThreshold(Threshold& g, int64_t now, float* magnitude);
    void startMacro(const json& macro, int64_t now, float power);
    void tickMacros(int64_t now);
    std::set<std::string> protectedControls() const;
    void applyHeld(const json& def, bool active);
    void direct(const json& mapping, const std::string& source, const Sample& sample);
    void updateSteeringToggle(const std::string& source, const Sample& sample);
    float steeringValue(const Sample& sample);
    json macroFor(const json& def) const;
    VirtualPad toPad() const;

    json profile_ = json::object();
    Samples samples_;
    std::map<std::string, Sample> filterPrev_;
    std::vector<Staged> staged_;
    std::vector<Threshold> thresholds_;
    std::vector<std::pair<std::string, json>> held_;       // insertion order = last-write-wins order
    std::vector<Step> macroQueue_;                           // a min-heap on (due, order); iterable, unlike priority_queue
    std::set<uint64_t> cancelled_;
    uint64_t runIds_ = 0, stepOrder_ = 0;
    State state_;
    std::map<std::string, Pose> poses_;
    std::map<std::string, int64_t> lastFired_;
    bool steeringOn_ = false;
    std::optional<float> steeringCenter_;
    float steeringOutput_ = 0.0f;
    std::optional<int64_t> steeringHoldStartNs_;
    bool steeringToggleFired_ = false;
    bool steeringApplied_ = false;
    bool lastDriving_ = false;
};

// ---- recording ---------------------------------------------------------------------------------------
//
// Ports of JoyMoco's `XboxInputSurface.complete` and `MotionRecorderDialog._analyze`: a capture window of
// frames becomes one variant definition. They throw `std::runtime_error` with a player-readable reason on a
// take that cannot be used, exactly where JoyMoco shows "Rejected: ...".

/// Button-only: the FIRST new press on any source becomes a held variant (`hold_until_release`).
json recordButtonVariant(const std::vector<Frame>& frames, const std::string& target, const std::string& context,
                         const std::vector<std::string>& existingNames);

/// Button(s) and/or motion: JoyMoco's full recorded-variant analysis.
json recordMotionVariant(const std::vector<Frame>& frames, const std::string& target, const std::string& context,
                         const std::vector<std::string>& existingNames);

/// JoyMoco `_output_steps`: what a TAP of `target` presses and releases.
json outputSteps(const std::string& target);

/// Human summary of a variant's source, for the panel ("Evenracing 1.0.0 button 9 · hold").
std::string describeVariant(const json& variant);

}  // namespace ncm::rig::pad
