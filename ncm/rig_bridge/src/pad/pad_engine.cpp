#include "pad_engine.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <functional>
#include <stdexcept>

namespace ncm::rig::pad {
namespace {

double num(const json& j, const char* key, double fallback)
{
    if (!j.is_object()) return fallback;
    auto it = j.find(key);
    if (it == j.end() || it->is_null()) return fallback;
    if (it->is_number()) return it->get<double>();
    if (it->is_boolean()) return it->get<bool>() ? 1.0 : 0.0;
    if (it->is_string()) { try { return std::stod(it->get<std::string>()); } catch (...) {} }
    return fallback;
}

std::string str(const json& j, const char* key, const std::string& fallback = {})
{
    if (!j.is_object()) return fallback;
    auto it = j.find(key);
    return (it != j.end() && it->is_string()) ? it->get<std::string>() : fallback;
}

bool flag(const json& j, const char* key, bool fallback)
{
    if (!j.is_object()) return fallback;
    auto it = j.find(key);
    return (it != j.end() && it->is_boolean()) ? it->get<bool>() : fallback;
}

/// A condition's `controller` names a hand or a device key; `gamepad:*`-style wildcards take the first match.
const Sample* resolve(const Samples& samples, const std::string& key, std::string* actual = nullptr)
{
    auto it = samples.find(key);
    if (it != samples.end()) { if (actual) *actual = it->first; return &it->second; }
    if (key.size() > 1 && key.back() == '*') {
        const std::string prefix = key.substr(0, key.size() - 1);
        for (const auto& [k, s] : samples)
            if (k.rfind(prefix, 0) == 0) { if (actual) *actual = k; return &s; }
    }
    return nullptr;
}

bool gateOpen(const json& gate, const Samples& samples)
{
    const Sample* s = resolve(samples, str(gate, "controller"));
    if (!s) return false;
    if (gate.contains("button")) return s->held(str(gate, "button"));
    const float value = s->field(str(gate, "field", "trigger_right"), str(gate, "axis", "x"));
    if (gate.contains("min") && value < num(gate, "min", 0)) return false;
    if (gate.contains("max") && value > num(gate, "max", 0)) return false;
    return true;
}

bool holdOpen(const json& hold, const Samples& samples)
{
    if (hold.is_array()) {
        if (hold.empty()) return false;
        for (const auto& g : hold) if (!gateOpen(g, samples)) return false;
        return true;
    }
    return hold.is_object() && gateOpen(hold, samples);
}

/// JoyMoco `_implicit_hold`: a recorded "press X, then swing" means X must still be down for the swing to
/// count -- unless a later stage is itself another press (a multi-tap combo).
json implicitHold(const json& stages)
{
    for (size_t i = 1; i < stages.size(); ++i)
        for (const auto& c : stages[i].value("conditions", json::array()))
            if (c.contains("button_pressed")) return nullptr;
    json gates = json::array();
    if (!stages.empty())
        for (const auto& c : stages[0].value("conditions", json::array()))
            if (c.contains("button_pressed"))
                gates.push_back({{"controller", str(c, "controller")}, {"button", str(c, "button_pressed")}});
    return gates.empty() ? json(nullptr) : gates;
}

float clamp1(float v) { return std::max(-1.0f, std::min(1.0f, v)); }
float clamp01(float v) { return std::max(0.0f, std::min(1.0f, v)); }

constexpr float kDiag = 0.70710678f, kUpX = 0.93969f, kUpY = 0.34202f;
std::pair<float, float> poseVector(const std::string& n)
{
    if (n == "left") return {-1.0f, 0.0f};
    if (n == "right") return {1.0f, 0.0f};
    if (n == "down") return {0.0f, -1.0f};
    if (n == "up_left") return {-kUpX, kUpY};
    if (n == "up_right") return {kUpX, kUpY};
    if (n == "down_left") return {-kDiag, -kDiag};
    if (n == "down_right") return {kDiag, -kDiag};
    return {0.0f, 0.0f};
}
bool stickHoldVector(const std::string& d, std::pair<float, float>* out)
{
    static const std::map<std::string, std::pair<float, float>> v = {
        {"up", {0.0f, 1.0f}}, {"down", {0.0f, -1.0f}}, {"left", {-1.0f, 0.0f}}, {"right", {1.0f, 0.0f}},
        {"up_left", {-kDiag, kDiag}}, {"up_right", {kDiag, kDiag}},
        {"down_left", {-kDiag, -kDiag}}, {"down_right", {kDiag, -kDiag}}};
    auto it = v.find(d);
    if (it == v.end()) return false;
    *out = it->second;
    return true;
}

// JoyMoco `PRIMARY_BUTTON_MAP`: a single DS4/DS5/Switch Pro stream passes through to the virtual pad.
const std::vector<std::pair<std::string, std::string>>& primaryButtonMap()
{
    static const std::vector<std::pair<std::string, std::string>> m = {
        {"a", "a"}, {"b", "b"}, {"x", "x"}, {"y", "y"}, {"lb", "lb"}, {"rb", "rb"}, {"minus", "back"},
        {"plus", "start"}, {"home", "home"}, {"ls", "ls"}, {"rs", "rs"}, {"dpad_up", "dpad_up"},
        {"dpad_down", "dpad_down"}, {"dpad_left", "dpad_left"}, {"dpad_right", "dpad_right"}};
    return m;
}

std::optional<std::string> heldControl(const std::string& target)
{
    if (target == "left_trigger" || target == "right_trigger") return target;
    if (target.rfind("left_stick_", 0) == 0) return std::string("left_stick");
    if (target.rfind("right_stick_", 0) == 0) return std::string("right_stick");
    return std::nullopt;
}

std::pair<float, float> stickValue(float x, float y, const json& source)
{
    const std::string rotation = str(source, "rotation", "normal");
    if (rotation == "clockwise") { const float t = x; x = y; y = -t; }
    else if (rotation == "counterclockwise") { const float t = x; x = -y; y = t; }
    else if (rotation == "180") { x = -x; y = -y; }
    const float deadzone = std::clamp(static_cast<float>(num(source, "deadzone", 0.10)), 0.0f, 0.95f);
    const float magnitude = std::min(1.0f, std::hypot(x, y));
    if (magnitude <= deadzone) return {0.0f, 0.0f};
    // Radial rescaling removes centre drift without turning the remaining travel into a digital threshold.
    const float factor = ((magnitude - deadzone) / (1.0f - deadzone)) / magnitude;
    return {clamp1(x * factor), clamp1(y * factor)};
}

int64_t epochMs()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}
}  // namespace

// ============================================================================ model helpers
float Sample::field(const std::string& name, const std::string& axis) const
{
    if (name == "gyro_dps") return gyro.axis(axis);
    if (name == "acceleration_g") return accel.axis(axis);
    if (name == "orientation_deg") return orientation.axis(axis);
    if (name == "stick_x") return stickX;
    if (name == "stick_y") return stickY;
    if (name == "stick2_x") return stick2X;
    if (name == "stick2_y") return stick2Y;
    if (name == "trigger_left") return triggerLeft;
    if (name == "trigger_right") return triggerRight;
    if (name.rfind("axis", 0) == 0) {
        try {
            const size_t i = std::stoul(name.substr(4));
            return i < axes.size() ? axes[i] : 0.0f;
        } catch (...) { return 0.0f; }
    }
    return 0.0f;
}

uint16_t buttonBit(const std::string& n)
{
    static const std::map<std::string, uint16_t> bits = {
        {"a", kA}, {"b", kB}, {"x", kX}, {"y", kY}, {"lb", kLb}, {"rb", kRb}, {"back", kBack},
        {"start", kStart}, {"home", kHome}, {"ls", kLs}, {"rs", kRs}, {"dpad_up", kDpadUp},
        {"dpad_down", kDpadDown}, {"dpad_left", kDpadLeft}, {"dpad_right", kDpadRight}};
    auto it = bits.find(n);
    return it == bits.end() ? 0 : it->second;
}

const std::vector<std::string>& buttonNames()
{
    static const std::vector<std::string> n = {"a", "b", "x", "y", "lb", "rb", "back", "start", "home", "ls", "rs",
                                               "dpad_up", "dpad_down", "dpad_left", "dpad_right"};
    return n;
}

const std::vector<std::string>& targetNames()
{
    static const std::vector<std::string> n = [] {
        std::vector<std::string> v = buttonNames();
        v.insert(v.end(), {"left_trigger", "right_trigger",
                           "left_stick_up", "left_stick_down", "left_stick_left", "left_stick_right",
                           "right_stick_up", "right_stick_down", "right_stick_left", "right_stick_right"});
        return v;
    }();
    return n;
}

bool isHand(const std::string& s)
{
    return s == "left" || s == "right" || s == "primary" || s == "left_leg" || s == "right_leg" || s == "controller";
}
bool isMotionHand(const std::string& s) { return isHand(s) && s != "controller"; }

// ============================================================================ engine
void Engine::setProfile(json profile)
{
    reset();
    profile_ = profile.is_object() ? std::move(profile) : json::object();
    staged_.clear();
    thresholds_.clear();
    for (const auto& def : profile_.value("gestures", json::array())) {
        if (!flag(def, "enabled", true)) continue;
        if (str(def, "type") == "staged") staged_.push_back(Staged{def});
        else thresholds_.push_back(Threshold{def});
    }
    filterPrev_.clear();
}

void Engine::reset()
{
    held_.clear();
    macroQueue_.clear();
    cancelled_.clear();
    state_.reset();
    poses_.clear();
    steeringOn_ = false;
    steeringCenter_.reset();
    steeringOutput_ = 0.0f;
    steeringHoldStartNs_.reset();
    steeringToggleFired_ = false;
    for (auto& g : staged_) { g.stage = 0; g.previous.clear(); }
    for (auto& g : thresholds_) g.active = false;
}

bool Engine::contextAllows(const json& def, bool driving) const
{
    const std::string c = str(def, "context", "both");
    if (c == "driving") return driving;
    if (c == "on_foot") return !driving;
    return true;
}

Sample Engine::calibrate(const std::string& source, const Sample& raw)
{
    if (!raw.motion) return raw;
    Sample s = raw;
    const json cal = profile_.value("calibration", json::object()).value(source, json::object());
    const json bias = cal.value("gyro_bias", json::object()), neutral = cal.value("neutral_orientation", json::object());
    s.gyro = s.gyro.minus({static_cast<float>(num(bias, "x", 0)), static_cast<float>(num(bias, "y", 0)),
                           static_cast<float>(num(bias, "z", 0))});
    s.orientation = s.orientation.minus({static_cast<float>(num(neutral, "x", 0)),
                                         static_cast<float>(num(neutral, "y", 0)),
                                         static_cast<float>(num(neutral, "z", 0))});
    // JoyMoco `SensorFilterPipeline`: alpha * current + (1 - alpha) * previous, on the motion fields only.
    const float alpha = static_cast<float>(num(profile_.value("filtering", json::object()), "alpha", 0.42));
    auto it = filterPrev_.find(source);
    if (it != filterPrev_.end()) {
        auto blend = [alpha](const Vec3& c, const Vec3& o) {
            return Vec3{c.x * alpha + o.x * (1 - alpha), c.y * alpha + o.y * (1 - alpha), c.z * alpha + o.z * (1 - alpha)};
        };
        s.gyro = blend(s.gyro, it->second.gyro);
        s.accel = blend(s.accel, it->second.accel);
        s.orientation = blend(s.orientation, it->second.orientation);
    }
    filterPrev_[source] = s;
    return s;
}

std::optional<std::string> Engine::fireStaged(Staged& g, int64_t now, float* magnitude)
{
    const json& stages = g.def["stages"];
    if (!stages.is_array() || stages.empty()) return std::nullopt;
    json hold = g.def.value("hold_until_release", json(nullptr));
    if (hold.is_null()) hold = implicitHold(stages);
    const bool hasHold = !hold.is_null();
    if (hasHold && g.stage != 0 && !holdOpen(hold, samples_)) g.stage = 0;
    if (now < g.cooldownUntilNs) return std::nullopt;
    const json& stage = stages[g.stage];
    const int64_t timeoutNs = static_cast<int64_t>(num(stage, "timeout_ms", 0) * 1'000'000.0);
    if (g.stage && timeoutNs && now - g.stageSinceNs > timeoutNs) { g.stage = 0; return std::nullopt; }

    std::map<std::string, std::set<std::string>> pressed;
    for (const auto& [src, s] : samples_) {
        const auto& before = g.previous[src];
        for (const auto& b : s.buttons) if (!before.count(b)) pressed[src].insert(b);
        g.previous[src] = s.buttons;
    }

    for (const auto& c : stage.value("conditions", json::array())) {
        std::string actual;
        const Sample* s = resolve(samples_, str(c, "controller"), &actual);
        if (!s) return std::nullopt;
        if (c.contains("button_pressed")) {
            if (!pressed[actual].count(str(c, "button_pressed"))) return std::nullopt;
            continue;
        }
        for (const auto& b : c.value("buttons_held", json::array()))
            if (b.is_string() && !s->held(b.get<std::string>())) return std::nullopt;
        const float value = s->field(str(c, "field", "gyro_dps"), str(c, "axis", "x"));
        if (c.contains("min") && value < num(c, "min", 0)) return std::nullopt;
        if (c.contains("max") && value > num(c, "max", 0)) return std::nullopt;
    }

    ++g.stage;
    g.stageSinceNs = now;
    if (g.stage < stages.size()) return std::nullopt;
    // While the gate is still held, skip straight back to the motion stage: stage 0 is an edge that never
    // repeats while the button stays down, so a hold-mode gesture could otherwise fire only once per hold.
    g.stage = (hasHold && stages.size() > 1 && holdOpen(hold, samples_)) ? stages.size() - 1 : 0;
    g.cooldownUntilNs = now + static_cast<int64_t>(num(g.def, "cooldown_ms", 250) * 1'000'000.0);

    float power = 1.0f;
    std::vector<float> magnitudes;
    for (const auto& c : stage.value("conditions", json::array())) {
        if (!c.contains("power_peak")) continue;
        const Sample* s = resolve(samples_, str(c, "controller"));
        if (!s) continue;
        const float value = std::fabs(s->field(str(c, "field", "gyro_dps"), str(c, "axis", "x")));
        const float floor = static_cast<float>(num(c, "power_floor", 0)), peak = static_cast<float>(num(c, "power_peak", 0));
        magnitudes.push_back(peak - floor != 0 ? clamp01((value - floor) / (peak - floor)) : 0.0f);
    }
    if (!magnitudes.empty()) power = *std::max_element(magnitudes.begin(), magnitudes.end());
    if (magnitude) *magnitude = power;
    return str(g.def, "id");
}

bool Engine::fireThreshold(Threshold& g, int64_t now, float* magnitude)
{
    const Sample* s = resolve(samples_, str(g.def, "controller"));
    if (!s) return false;
    const float value = s->field(str(g.def, "source", "gyro_dps"), str(g.def, "axis", "x"));
    const float threshold = static_cast<float>(num(g.def, "threshold", 100.0));
    const float hysteresis = static_cast<float>(num(g.def, "hysteresis", 15.0));
    const bool passed = threshold >= 0 ? value >= threshold : value <= threshold;
    const bool released = threshold >= 0 ? value < threshold - hysteresis : value > threshold + hysteresis;
    if (released) g.active = false;
    const bool cooldownReady = now - g.lastFireNs >= static_cast<int64_t>(num(g.def, "cooldown_ms", 250) * 1'000'000.0);
    bool required = true;
    for (const auto& b : g.def.value("required_buttons", json::array()))
        if (b.is_string() && !s->held(b.get<std::string>())) required = false;
    if (!(passed && !g.active && required && cooldownReady)) return false;
    g.active = true;
    g.lastFireNs = now;
    float power = 1.0f;
    if (g.def.contains("power_peak")) {
        const float floor = static_cast<float>(num(g.def, "power_floor", 0)), peak = static_cast<float>(num(g.def, "power_peak", 0));
        power = peak - floor != 0 ? clamp01((std::fabs(value) - floor) / (peak - floor)) : 0.0f;
    }
    if (magnitude) *magnitude = power;
    return true;
}

json Engine::macroFor(const json& def) const
{
    const std::string id = str(def, "macro");
    for (const auto& m : profile_.value("macros", json::array()))
        if (str(m, "id") == id && !id.empty()) return m;
    // A variant with no macro of its own taps its target -- the same steps JoyMoco's recorder would write.
    const std::string target = str(def, "xbox_target");
    return target.empty() ? json(nullptr) : json{{"id", "implicit"}, {"steps", outputSteps(target)}};
}

void Engine::startMacro(const json& macro, int64_t now, float power)
{
    const uint64_t run = ++runIds_;
    int64_t due = now;
    for (const auto& action : macro.value("steps", json::array())) {
        double delay = num(action, "delay_ms", 0);
        if (action.contains("power_delay_ms")) {
            const json& p = action["power_delay_ms"];
            delay = num(p, "min", 0) + (num(p, "max", 0) - num(p, "min", 0)) * clamp01(power);
        }
        due += static_cast<int64_t>(delay * 1'000'000.0);
        macroQueue_.push_back(Step{due, ++stepOrder_, run, action});
        std::push_heap(macroQueue_.begin(), macroQueue_.end(), std::greater<Step>());
    }
}

void Engine::tickMacros(int64_t now)
{
    while (!macroQueue_.empty() && macroQueue_.front().dueNs <= now) {
        std::pop_heap(macroQueue_.begin(), macroQueue_.end(), std::greater<Step>());
        Step step = std::move(macroQueue_.back());
        macroQueue_.pop_back();
        if (cancelled_.count(step.run)) continue;
        const json& a = step.action;
        const std::string kind = str(a, "type");
        if (kind == "button_press") state_.buttons.insert(str(a, "button"));
        else if (kind == "button_release") state_.buttons.erase(str(a, "button"));
        else if (kind == "left_stick") state_.leftStick = {static_cast<float>(num(a, "x", 0)), static_cast<float>(num(a, "y", 0))};
        else if (kind == "right_stick") state_.rightStick = {static_cast<float>(num(a, "x", 0)), static_cast<float>(num(a, "y", 0))};
        else if (kind == "left_trigger") state_.leftTrigger = static_cast<float>(num(a, "value", 0));
        else if (kind == "right_trigger") state_.rightTrigger = static_cast<float>(num(a, "value", 0));
        else if (kind == "reset") state_.reset();
    }
}

std::set<std::string> Engine::protectedControls() const
{
    // A macro still mid-flight owns the continuous control it names until it finishes (a shot's pulse
    // has its snap-back-to-neutral queued ~100 ms out), so a held sweep cannot overwrite it.
    std::set<std::string> out;
    for (const auto& s : macroQueue_) {
        if (cancelled_.count(s.run)) continue;
        const std::string kind = str(s.action, "type");
        if (kind == "left_stick" || kind == "right_stick" || kind == "left_trigger" || kind == "right_trigger")
            out.insert(kind);
    }
    return out;
}

void Engine::applyHeld(const json& def, bool active)
{
    const std::string target = str(def, "xbox_target");
    auto setButton = [&](const std::string& b) { if (active) state_.buttons.insert(b); else state_.buttons.erase(b); };
    if (buttonBit(target)) { setButton(target); return; }
    if (target == "left_trigger") { state_.leftTrigger = active ? 1.0f : 0.0f; return; }
    if (target == "right_trigger") { state_.rightTrigger = active ? 1.0f : 0.0f; return; }
    if (target.size() > 5 && target.compare(target.size() - 5, 5, "_hold") == 0) {
        const std::string b = target.substr(0, target.size() - 5);
        if (b == "a" || b == "b" || b == "x" || b == "y") setButton(b);
        return;
    }
    const auto us = target.find('_');
    if (us != std::string::npos && target.find('_', us + 1) == std::string::npos) {
        const std::string p0 = target.substr(0, us), p1 = target.substr(us + 1);
        const std::set<std::string> first = {"lt", "rt", "lb", "rb"}, second = {"a", "b", "x", "y", "lt", "rt"};
        if (first.count(p0) && second.count(p1)) {
            for (const auto& part : {p0, p1}) {
                if (part == "lt") state_.leftTrigger = active ? 1.0f : 0.0f;
                else if (part == "rt") state_.rightTrigger = active ? 1.0f : 0.0f;
                else setButton(part);
            }
            return;
        }
    }
    for (const char* stick : {"left", "right"}) {
        const std::string prefix = std::string(stick) + "_stick_";
        if (target.rfind(prefix, 0) != 0) continue;
        std::pair<float, float> v;
        if (!stickHoldVector(target.substr(prefix.size()), &v)) return;
        (std::string(stick) == "left" ? state_.leftStick : state_.rightStick) = active ? v : std::pair<float, float>{0.0f, 0.0f};
        return;
    }
}

void Engine::direct(const json& mapping, const std::string& source, const Sample& sample)
{
    if (!flag(mapping, "enabled", true) || str(mapping, "layer", "default") != "default") return;
    const json& src = mapping["source"];
    if (str(src, "controller") != source) return;
    const json& target = mapping["output"];
    const std::string type = str(src, "type");
    const std::string control = str(target, "control");
    auto stickRef = [&](const std::string& c) -> std::pair<float, float>* {
        return c == "left_stick" ? &state_.leftStick : c == "right_stick" ? &state_.rightStick : nullptr;
    };
    if (type == "stick") {
        // "auto" (Rig Bridge's own): take whichever stick pair is deflected. How SDL reports a SOLO Joy-Con's
        // stick depends on its orientation hints -- JoyMoco's own profiles read it from both pairs over time.
        const std::string which = str(src, "stick", "left");
        const bool second = which == "right" ||
            (which == "auto" && std::hypot(sample.stick2X, sample.stick2Y) > std::hypot(sample.stickX, sample.stickY));
        const auto v = stickValue(second ? sample.stick2X : sample.stickX, second ? sample.stick2Y : sample.stickY, src);
        if (auto* s = stickRef(control)) *s = v;
    } else if (type == "button") {
        const std::string out = str(target, "button");
        if (sample.held(str(src, "button"))) state_.buttons.insert(out); else state_.buttons.erase(out);
    } else if (type == "gyro_analog") {
        if (src.contains("gate") && !gateOpen(src["gate"], samples_)) return;
        const float raw = sample.field(str(src, "field", "gyro_dps"), str(src, "axis", "x"));
        if (control == "left_trigger" || control == "right_trigger") {
            const float base = static_cast<float>(num(src, "base", 0)), ceiling = static_cast<float>(num(src, "max", 1));
            float magnitude;
            if (src.contains("peak")) {
                const float floor = static_cast<float>(num(src, "floor", 0)), peak = static_cast<float>(num(src, "peak", 0));
                magnitude = peak - floor != 0 ? clamp01((std::fabs(raw) - floor) / (peak - floor)) : 0.0f;
            } else {
                magnitude = clamp01(std::fabs(static_cast<float>(num(src, "scale", 0.005)) * raw));
            }
            (control == "left_trigger" ? state_.leftTrigger : state_.rightTrigger) = clamp01(base + (ceiling - base) * magnitude);
        } else if (auto* s = stickRef(control)) {
            const float v = clamp1(static_cast<float>(num(src, "scale", 0.005)) * raw);
            (str(target, "axis", "x") == "x" ? s->first : s->second) = v;
        }
    } else if (type == "pose_stick") {
        Pose& pose = poses_[str(mapping, "id")];
        auto* stick = stickRef(control);
        if (!stick) return;
        if (!(src.contains("gate") && gateOpen(src["gate"], samples_))) {
            if (pose.held) { pose.held = false; *stick = {0.0f, 0.0f}; }   // disengage exactly once, then stay silent
            return;
        }
        const json axes = src.value("axes", json::array({"x", "y"}));
        const std::string field = str(src, "field", "orientation_deg");
        float h = sample.field(field, axes.size() > 0 ? axes[0].get<std::string>() : "x");
        float v = sample.field(field, axes.size() > 1 ? axes[1].get<std::string>() : "y");
        if (src.contains("anchor")) {
            if (const Sample* a = resolve(samples_, str(src["anchor"], "controller"))) {
                const std::string af = str(src["anchor"], "field", field);
                h -= a->field(af, axes.size() > 0 ? axes[0].get<std::string>() : "x");
                v -= a->field(af, axes.size() > 1 ? axes[1].get<std::string>() : "y");
            }
        }
        if (!pose.held) { pose.held = true; pose.centerH = h; pose.centerV = v; }
        const float dh = h - pose.centerH, dv = v - pose.centerV;
        const float bias = std::max(0.1f, static_cast<float>(num(src, "neutral_bias", 1.0)));
        std::string best = "neutral";
        float bestDistance = std::hypot(dh, dv) / bias;
        for (const auto& [name, p] : src.value("poses", json::object()).items()) {
            if (!p.is_array() || p.size() < 2) continue;
            const float d = std::hypot(dh - p[0].get<float>(), dv - p[1].get<float>());
            if (d < bestDistance) { bestDistance = d; best = name; }
        }
        auto value = best == "neutral" ? std::pair<float, float>{0.0f, 0.0f} : poseVector(best);
        const std::string rotation = str(src, "rotation", "normal");
        if (rotation == "clockwise") value = {value.second, -value.first};
        else if (rotation == "counterclockwise") value = {-value.second, value.first};
        else if (rotation == "180") value = {-value.first, -value.second};
        *stick = value;
    }
}

void Engine::updateSteeringToggle(const std::string& source, const Sample& sample)
{
    const json cfg = profile_.value("gyro_steering", json::object());
    if (!flag(cfg, "enabled", false) || source != str(cfg, "controller", "primary")) return;
    const std::string hotkey = str(cfg, "toggle_button", "capture");
    if (!sample.held(hotkey)) { steeringHoldStartNs_.reset(); steeringToggleFired_ = false; return; }
    if (!steeringHoldStartNs_) { steeringHoldStartNs_ = sample.tNs; return; }
    const int64_t holdNs = std::max<int64_t>(100, static_cast<int64_t>(num(cfg, "hold_ms", 500))) * 1'000'000;
    if (steeringToggleFired_ || sample.tNs - *steeringHoldStartNs_ < holdNs) return;
    steeringToggleFired_ = true;
    steeringOn_ = !steeringOn_;
    steeringOutput_ = 0.0f;
    if (steeringOn_) steeringCenter_ = sample.orientation.axis(str(cfg, "axis", "z"));
    else steeringCenter_.reset();
}

float Engine::steeringValue(const Sample& sample)
{
    const json cfg = profile_.value("gyro_steering", json::object());
    const float current = sample.orientation.axis(str(cfg, "axis", "z"));
    if (!steeringCenter_) steeringCenter_ = current;
    float delta = current - *steeringCenter_;
    if (flag(cfg, "invert", false)) delta = -delta;
    const float fullLock = std::max(1.0f, static_cast<float>(num(cfg, "full_lock_deg", 45.0)));
    const float deadzone = std::clamp(static_cast<float>(num(cfg, "deadzone_deg", 3.0)), 0.0f, fullLock - 0.01f);
    const float magnitude = std::fabs(delta);
    const float normalized = magnitude <= deadzone ? 0.0f : std::min(1.0f, (magnitude - deadzone) / (fullLock - deadzone));
    const float curve = std::max(0.1f, static_cast<float>(num(cfg, "response_curve", 1.35)));
    const float target = normalized != 0.0f ? std::copysign(std::pow(normalized, curve), delta) : 0.0f;
    const float smoothing = std::clamp(static_cast<float>(num(cfg, "smoothing", 0.25)), 0.0f, 0.95f);
    steeringOutput_ = steeringOutput_ * smoothing + target * (1.0f - smoothing);
    return clamp1(steeringOutput_);
}

VirtualPad Engine::process(const Samples& raw, int64_t now, bool driving, std::vector<Feedback>* feedback)
{
    // A context flip (mounting or dismounting) drops every hold whose variant no longer applies, so a
    // button held for on-foot can never stay pressed into the car.
    if (driving != lastDriving_) {
        lastDriving_ = driving;
        for (auto it = held_.begin(); it != held_.end();) {
            if (!contextAllows(it->second, driving)) { applyHeld(it->second, false); it = held_.erase(it); }
            else ++it;
        }
        for (auto& g : staged_) if (!contextAllows(g.def, driving)) g.stage = 0;
    }

    samples_.clear();
    for (const auto& [source, s] : raw)
        if (s.connected) samples_[source] = calibrate(source, s);

    const json steering = profile_.value("gyro_steering", json::object());
    const std::string steeringHand = str(steering, "controller", "primary");
    if (auto it = samples_.find(steeringHand); it != samples_.end()) updateSteeringToggle(it->first, it->second);

    for (auto it = held_.begin(); it != held_.end();) {
        if (!holdOpen(it->second.value("hold_until_release", json(nullptr)), samples_)) {
            applyHeld(it->second, false);
            it = held_.erase(it);
        } else ++it;
    }

    const json mappings = profile_.value("mappings", json::array());
    for (const auto& m : mappings) {
        if (str(m["source"], "type") != "button" || !contextAllows(m, driving)) continue;
        const std::string src = str(m["source"], "controller");
        if (auto it = samples_.find(src); it != samples_.end()) direct(m, src, it->second);
    }

    const Sample* primary = resolve(samples_, "primary");
    if (primary) {
        std::set<std::string> consumed;
        if (flag(steering, "enabled", false) && steeringHand == "primary") {
            consumed.insert(str(steering, "toggle_button", "capture"));
            if (primary->held("capture")) consumed.insert("minus");
        }
        for (const auto& [from, to] : primaryButtonMap()) {
            if (primary->held(from) && !consumed.count(from)) state_.buttons.insert(to); else state_.buttons.erase(to);
        }
    }

    const bool mapperFeedback = flag(profile_.value("rumble", json::object()), "mapper_feedback", true);
    auto fired = [&](const json& def, float power) {
        const std::string id = str(def, "id");
        lastFired_[id] = now;
        if (feedback && mapperFeedback && !str(def, "feedback_effect").empty())
            feedback->push_back({str(def, "feedback_effect"), str(def, "feedback_side", "both")});
        const json hold = def.value("hold_until_release", json(nullptr));
        if (!hold.is_null() && holdOpen(hold, samples_)) {
            held_.erase(std::remove_if(held_.begin(), held_.end(), [&](const auto& h) { return h.first == id; }), held_.end());
            held_.emplace_back(id, def);
            applyHeld(def, true);
        } else if (const json macro = macroFor(def); !macro.is_null()) {
            startMacro(macro, now, power);
        }
    };
    for (auto& g : staged_) {
        if (!contextAllows(g.def, driving)) continue;
        float power = 1.0f;
        if (fireStaged(g, now, &power)) fired(g.def, power);
    }
    for (auto& g : thresholds_) {
        if (!contextAllows(g.def, driving)) continue;
        float power = 1.0f;
        if (fireThreshold(g, now, &power)) fired(g.def, power);
    }

    tickMacros(now);
    const auto owned = protectedControls();
    for (const auto& [id, def] : held_) {
        const auto control = heldControl(str(def, "xbox_target"));
        if (control && owned.count(*control)) continue;
        applyHeld(def, true);
    }
    if (primary) {
        if (!owned.count("left_stick")) state_.leftStick = {primary->stickX, primary->stickY};
        if (!owned.count("right_stick")) state_.rightStick = {primary->stick2X, primary->stick2Y};
        if (!owned.count("left_trigger")) state_.leftTrigger = primary->triggerLeft;
        if (!owned.count("right_trigger")) state_.rightTrigger = primary->triggerRight;
    }
    for (const auto& m : mappings) {
        const std::string type = str(m["source"], "type");
        if (type != "stick" && type != "gyro_analog" && type != "pose_stick") continue;
        if (!contextAllows(m, driving) || owned.count(str(m["output"], "control"))) continue;
        const std::string src = str(m["source"], "controller");
        if (auto it = samples_.find(src); it != samples_.end()) direct(m, src, it->second);
    }
    // Steering writes left-X only while it applies; the tick it stops (toggled off, dismounted, hand
    // lost) it hands left-X back at zero ONCE -- state persists between ticks, so a last tilt would
    // otherwise stay latched on the stick.
    bool steered = false;
    if (steeringOn_ && contextAllows(steering, driving) && !owned.count("left_stick")) {
        if (auto it = samples_.find(steeringHand); it != samples_.end()) {
            state_.leftStick.first = steeringValue(it->second);
            steered = true;
        }
    }
    if (steeringApplied_ && !steered && !owned.count("left_stick")) state_.leftStick.first = 0.0f;
    steeringApplied_ = steered;
    return toPad();
}

VirtualPad Engine::toPad() const
{
    VirtualPad p;
    for (const auto& b : state_.buttons) p.buttons |= buttonBit(b);
    p.lx = clamp1(state_.leftStick.first);
    p.ly = clamp1(state_.leftStick.second);
    p.rx = clamp1(state_.rightStick.first);
    p.ry = clamp1(state_.rightStick.second);
    p.lt = clamp01(state_.leftTrigger);
    p.rt = clamp01(state_.rightTrigger);
    return p;
}

std::vector<std::string> Engine::activeVariants(int64_t nowNs) const
{
    std::vector<std::string> out;
    for (const auto& [id, def] : held_) out.push_back(id);
    for (const auto& [id, at] : lastFired_)
        if (nowNs - at < 400'000'000 && std::find(out.begin(), out.end(), id) == out.end()) out.push_back(id);
    return out;
}

// ============================================================================ recording
namespace {
struct Flat { std::string source; const Sample* sample; int64_t tNs; };

std::vector<Flat> flatten(const std::vector<Frame>& frames)
{
    std::vector<Flat> out;
    for (const auto& f : frames)
        for (const auto& [src, s] : f.samples)
            if (s.connected) out.push_back({src, &s, f.tNs});
    return out;
}

float median(std::vector<float> v)
{
    if (v.empty()) return 0.0f;
    std::sort(v.begin(), v.end());
    const size_t n = v.size();
    return n % 2 ? v[n / 2] : 0.5f * (v[n / 2 - 1] + v[n / 2]);
}

float round2(float v) { return std::round(v * 100.0f) / 100.0f; }

std::string sourceLabel(const std::string& s)
{
    if (s == "left") return "Left";
    if (s == "right") return "Right";
    if (s == "primary") return "Primary";
    if (s == "left_leg") return "Left leg";
    if (s == "right_leg") return "Right leg";
    if (s == "controller") return "Controller";
    const auto colon = s.find(':');
    return colon == std::string::npos ? s : s.substr(colon + 1);
}

std::string buttonLabel(const std::string& b)
{
    if (b.size() > 1 && b[0] == 'b' && std::all_of(b.begin() + 1, b.end(), ::isdigit))
        return "button " + std::to_string(std::stoi(b.substr(1)) + 1);
    return b;
}

std::string uniqueName(std::string name, const std::vector<std::string>& existing)
{
    if (std::find(existing.begin(), existing.end(), name) == existing.end()) return name;
    for (int i = 2;; ++i) {
        const std::string candidate = name + " " + std::to_string(i);
        if (std::find(existing.begin(), existing.end(), candidate) == existing.end()) return candidate;
    }
}

bool supportsHold(const std::string& target)
{
    return buttonBit(target) || target == "left_trigger" || target == "right_trigger" ||
           target.rfind("left_stick_", 0) == 0 || target.rfind("right_stick_", 0) == 0;
}

/// JoyMoco `_trim_motion_deadspace`: keep only the part of the take where something happened.
std::vector<Flat> trimMotion(const std::vector<Flat>& live, int64_t* activeMs)
{
    if (live.size() < 20) throw std::runtime_error("not enough live sensor samples");
    const int64_t baselineEnd = live.front().tNs + 250'000'000;
    std::map<std::string, std::array<float, 4>> centers;
    std::map<std::string, std::vector<const Flat*>> baseline;
    for (const auto& f : live) if (f.tNs <= baselineEnd) baseline[f.source].push_back(&f);
    for (const auto& [src, own] : baseline) {
        std::vector<float> gx, gy, gz, a;
        for (const auto* f : own) {
            gx.push_back(f->sample->gyro.x); gy.push_back(f->sample->gyro.y); gz.push_back(f->sample->gyro.z);
            const auto& ac = f->sample->accel;
            a.push_back(std::sqrt(ac.x * ac.x + ac.y * ac.y + ac.z * ac.z));
        }
        centers[src] = {median(gx), median(gy), median(gz), median(a)};
    }
    std::vector<size_t> active;
    std::map<std::string, std::set<std::string>> previous;
    for (size_t i = 0; i < live.size(); ++i) {
        const auto& f = live[i];
        const auto c = centers.count(f.source) ? centers[f.source] : std::array<float, 4>{0, 0, 0, 1};
        const auto& s = *f.sample;
        const float gyroDelta = std::max({std::fabs(s.gyro.x - c[0]), std::fabs(s.gyro.y - c[1]), std::fabs(s.gyro.z - c[2])});
        const float accel = std::sqrt(s.accel.x * s.accel.x + s.accel.y * s.accel.y + s.accel.z * s.accel.z);
        auto prev = previous.find(f.source);
        const bool edge = prev != previous.end() && prev->second != s.buttons;
        previous[f.source] = s.buttons;
        const bool moving = s.motion && (gyroDelta >= 25.0f || std::fabs(accel - c[3]) >= 0.12f);
        if (moving || edge) active.push_back(i);
    }
    if (active.empty()) throw std::runtime_error("no active motion found within the capture");
    const int64_t first = live[active.front()].tNs, last = live[active.back()].tNs;
    std::vector<Flat> trimmed;
    for (const auto& f : live) if (f.tNs >= first - 120'000'000 && f.tNs <= last + 120'000'000) trimmed.push_back(f);
    *activeMs = std::max<int64_t>(1, (last - first) / 1'000'000);
    return trimmed;
}

/// JoyMoco `_button_stages`: each new press, on any source, becomes a stage in order.
json buttonStages(const std::vector<Flat>& samples)
{
    std::map<std::string, std::set<std::string>> previous;
    json stages = json::array();
    std::optional<int64_t> lastPress;
    for (const auto& f : samples) {
        const auto& old = previous[f.source];
        std::vector<std::string> pressed;
        for (const auto& b : f.sample->buttons) if (!old.count(b)) pressed.push_back(b);
        previous[f.source] = f.sample->buttons;
        for (const auto& b : pressed) {
            json condition = {{"controller", f.source}, {"button_pressed", b}};
            json held = json::array();
            for (const auto& h : f.sample->buttons) if (h != b) held.push_back(h);
            if (!held.empty()) condition["buttons_held"] = held;
            json stage = {{"name", "press " + b}, {"conditions", json::array({condition})}};
            if (lastPress)
                stage["timeout_ms"] = std::max<int64_t>(150, static_cast<int64_t>(std::llround((f.tNs - *lastPress) / 1e6 * 1.75)));
            stages.push_back(stage);
            lastPress = f.tNs;
        }
    }
    return stages;
}

std::map<std::string, std::set<std::string>> buttonsHeldThroughout(const std::vector<Flat>& samples)
{
    std::map<std::string, std::set<std::string>> held;
    std::set<std::string> started;
    for (const auto& f : samples) {
        if (!started.count(f.source)) {
            if (f.sample->buttons.empty()) continue;
            started.insert(f.source);
            held[f.source] = f.sample->buttons;
            continue;
        }
        std::set<std::string> both;
        for (const auto& b : held[f.source]) if (f.sample->held(b)) both.insert(b);
        held[f.source] = both;
    }
    for (auto it = held.begin(); it != held.end();) it = it->second.empty() ? held.erase(it) : std::next(it);
    return held;
}

/// JoyMoco `MotionRecorderDialog._hand_condition`, for one motion source.
json handCondition(const std::vector<Flat>& samples, const std::string& hand)
{
    std::vector<const Sample*> values;
    for (const auto& f : samples) if (f.source == hand) values.push_back(f.sample);
    if (values.size() < 20) throw std::runtime_error("not enough samples from " + sourceLabel(hand));
    const size_t baselineCount = std::max<size_t>(8, values.size() / 6);
    struct Candidate { float abs, amplitude, center, noise; std::string axis; };
    std::optional<Candidate> best;
    for (const char* axis : {"x", "y", "z"}) {
        std::vector<float> series;
        for (const auto* s : values) series.push_back(s->gyro.axis(axis));
        std::vector<float> head(series.begin(), series.begin() + std::min(baselineCount, series.size()));
        const float center = median(head);
        std::vector<float> dev;
        for (float v : head) dev.push_back(std::fabs(v - center));
        const float noise = median(dev);
        float extreme = series.front();
        for (float v : series) if (std::fabs(v - center) > std::fabs(extreme - center)) extreme = v;
        const float amplitude = extreme - center;
        if (!best || std::fabs(amplitude) > best->abs) best = Candidate{std::fabs(amplitude), amplitude, center, noise, axis};
    }
    const float required = std::max(25.0f, best->noise * 6.0f);
    if (best->abs < required) {
        char why[160];
        std::snprintf(why, sizeof(why), "%s had no clear motion on gyro %s (peak %.2f deg/s; need %.2f)",
                      sourceLabel(hand).c_str(), best->axis.c_str(), best->abs, required);
        throw std::runtime_error(why);
    }
    json condition = {{"controller", hand}, {"field", "gyro_dps"}, {"axis", best->axis}};
    condition[best->amplitude > 0 ? "min" : "max"] = round2(best->center + best->amplitude * 0.55f);
    return condition;
}

json deriveOrientationHold(const std::vector<Flat>& raw, const json& conditions)
{
    if (raw.empty()) return nullptr;
    const int64_t tailStart = raw.back().tNs - 800'000'000;
    json hold = json::array();
    for (const auto& c : conditions) {
        const std::string controller = str(c, "controller"), axis = str(c, "axis", "x");
        std::vector<float> tail;
        for (const auto& f : raw) if (f.source == controller && f.tNs >= tailStart) tail.push_back(f.sample->orientation.axis(axis));
        if (tail.size() < 5) continue;
        const float settled = median(tail);
        if (std::fabs(settled) < 5.0f) continue;
        json gate = {{"controller", controller}, {"field", "orientation_deg"}, {"axis", axis}};
        gate[settled > 0 ? "min" : "max"] = round2(settled * 0.45f);
        hold.push_back(gate);
    }
    return hold.empty() ? json(nullptr) : hold;
}
}  // namespace

json outputSteps(const std::string& target)
{
    auto press = [](const std::string& b, double delay = 0) {
        json s = {{"type", "button_press"}, {"button", b}};
        if (delay) s["delay_ms"] = delay;
        return s;
    };
    auto release = [](const std::string& b, double delay) { return json{{"type", "button_release"}, {"button", b}, {"delay_ms", delay}}; };
    if (buttonBit(target)) return json::array({press(target), release(target, 100)});
    if (target == "left_trigger" || target == "right_trigger")
        return json::array({{{"type", target}, {"value", 1}}, {{"type", target}, {"value", 0}, {"delay_ms", 100}}});
    if (target.size() > 5 && target.compare(target.size() - 5, 5, "_hold") == 0) {
        const std::string b = target.substr(0, target.size() - 5);
        return json::array({press(b), release(b, 500)});
    }
    if (target.size() > 7 && target.compare(target.size() - 7, 7, "_double") == 0) {
        const std::string b = target.substr(0, target.size() - 7);
        return json::array({press(b), release(b, 55), press(b, 65), release(b, 55)});
    }
    for (const char* stick : {"left", "right"}) {
        const std::string prefix = std::string(stick) + "_stick_";
        std::pair<float, float> v;
        if (target.rfind(prefix, 0) == 0 && stickHoldVector(target.substr(prefix.size()), &v)) {
            const std::string control = std::string(stick) + "_stick";
            return json::array({{{"type", control}, {"x", v.first}, {"y", v.second}},
                                {{"type", control}, {"x", 0}, {"y", 0}, {"delay_ms", 100}}});
        }
    }
    return json::array();
}

json recordButtonVariant(const std::vector<Frame>& frames, const std::string& target, const std::string& context,
                         const std::vector<std::string>& existingNames)
{
    std::map<std::string, std::set<std::string>> previous;
    for (const auto& frame : frames) {
        for (const auto& [src, s] : frame.samples) {
            if (!s.connected) continue;
            auto prev = previous.find(src);
            // A button already down when the capture started is not a press -- only a new edge counts.
            if (prev != previous.end()) {
                for (const auto& b : s.buttons) {
                    if (prev->second.count(b)) continue;
                    const std::string name = uniqueName(sourceLabel(src) + " " + buttonLabel(b), existingNames);
                    return {{"id", "xbox-" + target + "-recording-" + std::to_string(epochMs())},
                            {"type", "staged"}, {"enabled", true}, {"cooldown_ms", 0}, {"xbox_target", target},
                            {"variant_name", name}, {"capture_motion", false}, {"context", context},
                            {"feedback_effect", ""}, {"feedback_side", "both"},
                            {"stages", json::array({{{"name", "press " + b},
                                                     {"conditions", json::array({{{"controller", src}, {"button_pressed", b}}})}}})},
                            {"hold_until_release", {{"controller", src}, {"button", b}}}};
                }
            }
            previous[src] = s.buttons;
        }
    }
    throw std::runtime_error("no button was pressed during the capture");
}

json recordMotionVariant(const std::vector<Frame>& frames, const std::string& target, const std::string& context,
                         const std::vector<std::string>& existingNames)
{
    const std::vector<Flat> raw = flatten(frames);
    int64_t activeMs = 0;
    const std::vector<Flat> samples = trimMotion(raw, &activeMs);
    json stages = buttonStages(samples);
    const bool hadButtonStage = !stages.empty();

    std::set<std::string> present;
    for (const auto& f : samples) if (f.sample->motion && isMotionHand(f.source)) present.insert(f.source);
    if (present.empty()) throw std::runtime_error("no motion-capable controller was connected during capture");
    // Opportunistic, as in JoyMoco's row recorder: a controller resting idle while another one swings
    // does not abort the take -- only if NOTHING moved is it rejected.
    json conditions = json::array();
    std::string failures;
    for (const auto& hand : present) {
        try { conditions.push_back(handCondition(samples, hand)); }
        catch (const std::exception& e) { failures += (failures.empty() ? "" : "; ") + std::string(e.what()); }
    }
    if (conditions.empty()) throw std::runtime_error(failures.empty() ? "no motion detected" : failures);
    const auto held = buttonsHeldThroughout(samples);
    for (auto& c : conditions) {
        auto it = held.find(str(c, "controller"));
        if (it != held.end()) c["buttons_held"] = json(std::vector<std::string>(it->second.begin(), it->second.end()));
    }
    json motionStage = {{"name", "recorded motion"}, {"conditions", conditions}};
    if (hadButtonStage) motionStage["timeout_ms"] = std::max<int64_t>(400, activeMs * 2);
    stages.push_back(motionStage);

    json hold = nullptr;
    if (!hadButtonStage && supportsHold(target)) hold = deriveOrientationHold(raw, conditions);

    std::string suggested;
    for (const auto& hand : present) suggested += (suggested.empty() ? "" : " + ") + sourceLabel(hand);
    json variant = {{"id", "xbox-" + target + "-recording-" + std::to_string(epochMs())},
                    {"type", "staged"}, {"enabled", true}, {"cooldown_ms", 250},
                    {"macro", "xbox-" + target + "-output"}, {"xbox_target", target},
                    {"variant_name", uniqueName(suggested + " motion", existingNames)},
                    {"capture_motion", true}, {"context", context},
                    {"feedback_effect", ""}, {"feedback_side", "both"}, {"stages", stages}};
    if (!hold.is_null()) variant["hold_until_release"] = hold;
    return variant;
}

std::string describeVariant(const json& v)
{
    std::string out;
    for (const auto& stage : v.value("stages", json::array())) {
        std::string part;
        for (const auto& c : stage.value("conditions", json::array())) {
            std::string one = sourceLabel(str(c, "controller")) + " ";
            if (c.contains("button_pressed")) one += buttonLabel(str(c, "button_pressed"));
            else {
                char buf[96];
                const bool isMin = c.contains("min");
                std::snprintf(buf, sizeof(buf), "%s %s %s %.0f", str(c, "field", "gyro_dps") == "gyro_dps" ? "swing" : str(c, "field").c_str(),
                              str(c, "axis", "x").c_str(), isMin ? ">=" : "<=", num(c, isMin ? "min" : "max", 0));
                one += buf;
            }
            part += (part.empty() ? "" : " + ") + one;
        }
        out += (out.empty() ? "" : " -> ") + part;
    }
    out += v.contains("hold_until_release") ? "  \xc2\xb7  hold" : "  \xc2\xb7  tap";
    return out;
}

}  // namespace ncm::rig::pad
