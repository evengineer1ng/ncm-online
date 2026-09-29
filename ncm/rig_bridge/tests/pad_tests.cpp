// NCM Rig Bridge -- gamepad engine tests. The engine is pure, so every behaviour here is asserted without
// hardware: a Sample is built by hand, time is a number, and the virtual pad is read back.

#include "pad/pad_engine.hpp"
#include "pad/xinput_merge.hpp"

#include <cmath>
#include <cstdio>
#include <string>

using namespace ncm::rig::pad;

namespace {
int failures = 0;
void check(const char* name, bool ok)
{
    if (!ok) { std::printf("FAIL %s\n", name); ++failures; }
}
constexpr int64_t kMs = 1'000'000;

const std::string kRim = "joystick:Evenracing 1.0.0";

Sample rim(std::initializer_list<const char*> buttons)
{
    Sample s;
    for (const char* b : buttons) s.buttons.insert(b);
    return s;
}

Sample motion(float gx, float gy, float gz, std::initializer_list<const char*> buttons = {})
{
    Sample s;
    s.motion = true;
    s.gyro = {gx, gy, gz};
    s.accel = {0, 0, 1};
    for (const char* b : buttons) s.buttons.insert(b);
    return s;
}

json rimVariant(const char* target, const char* button, const char* context = "both")
{
    return {{"id", std::string("rim-") + target}, {"type", "staged"}, {"enabled", true}, {"cooldown_ms", 0},
            {"xbox_target", target}, {"context", context}, {"feedback_effect", "soft-click"}, {"feedback_side", "both"},
            {"stages", json::array({{{"name", "press"}, {"conditions", json::array({{{"controller", kRim}, {"button_pressed", button}}})}}})},
            {"hold_until_release", {{"controller", kRim}, {"button", button}}}};
}
}  // namespace

int main()
{
    // ---- a rim button held is the gamepad button held, and released with it ---------------------------
    {
        Engine e(json{{"gestures", json::array({rimVariant("b", "b8")})}, {"filtering", {{"alpha", 1.0}}}});
        Samples s{{kRim, rim({})}};
        check("idle rim sends nothing", e.process(s, 0, false).buttons == 0);
        s[kRim] = rim({"b8"});
        std::vector<Feedback> fb;
        check("rim b8 press -> B", e.process(s, 10 * kMs, false, &fb).buttons == kB);
        check("the variant's rumble preset fires once", fb.size() == 1 && fb[0].effect == "soft-click");
        check("held rim b8 keeps B down", e.process(s, 500 * kMs, false).buttons == kB);
        s[kRim] = rim({});
        check("release rim b8 releases B", e.process(s, 510 * kMs, false).buttons == 0);
    }

    // ---- variants are additive: two sources, one output -------------------------------------------------
    {
        json joyconY = {{"id", "jc-b"}, {"type", "staged"}, {"cooldown_ms", 0}, {"xbox_target", "b"},
                        {"stages", json::array({{{"conditions", json::array({{{"controller", "right"}, {"button_pressed", "y"}}})}}})},
                        {"hold_until_release", {{"controller", "right"}, {"button", "y"}}}};
        Engine e(json{{"gestures", json::array({rimVariant("b", "b8"), joyconY})}});
        Samples s{{kRim, rim({})}, {"right", motion(0, 0, 0)}};
        e.process(s, 0, false);
        s["right"] = motion(0, 0, 0, {"y"});
        check("Joy-Con Y also drives B", e.process(s, 10 * kMs, false).buttons == kB);
        s["right"] = motion(0, 0, 0);
        s[kRim] = rim({"b8"});
        check("and the rim still does", e.process(s, 20 * kMs, false).buttons == kB);
    }

    // ---- context: a driving-only variant is inert on foot, and is dropped when you dismount ------------
    {
        Engine e(json{{"gestures", json::array({rimVariant("a", "b1", "driving")})}});
        Samples s{{kRim, rim({})}};
        e.process(s, 0, false);
        s[kRim] = rim({"b1"});
        check("driving-only variant is silent on foot", e.process(s, 10 * kMs, false).buttons == 0);
        s[kRim] = rim({});
        e.process(s, 20 * kMs, true);
        s[kRim] = rim({"b1"});
        check("driving-only variant fires in a car", e.process(s, 30 * kMs, true).buttons == kA);
        check("dismounting drops its hold", e.process(s, 40 * kMs, false).buttons == 0);
    }

    // ---- press SR, then swing: the staged motion variant taps its target -------------------------------
    {
        json swing = {{"id", "swing-b"}, {"type", "staged"}, {"cooldown_ms", 250}, {"xbox_target", "b"},
                      {"feedback_effect", "strong-thump"}, {"feedback_side", "right"},
                      {"stages", json::array({
                          {{"name", "press sr"}, {"conditions", json::array({{{"controller", "right"}, {"button_pressed", "sr"}}})}},
                          {{"name", "recorded motion"}, {"timeout_ms", 1000},
                           {"conditions", json::array({{{"controller", "right"}, {"field", "gyro_dps"}, {"axis", "y"}, {"min", 300}}})}}})}};
        Engine e(json{{"gestures", json::array({swing})}, {"filtering", {{"alpha", 1.0}}}});
        Samples s{{"right", motion(0, 0, 0)}};
        e.process(s, 0, false);
        s["right"] = motion(0, 0, 0, {"sr"});
        check("the press alone does nothing", e.process(s, 10 * kMs, false).buttons == 0);
        s["right"] = motion(0, 50, 0, {"sr"});
        check("a gentle move does nothing", e.process(s, 20 * kMs, false).buttons == 0);
        s["right"] = motion(0, 420, 0, {"sr"});
        std::vector<Feedback> fb;
        check("the swing taps B", e.process(s, 30 * kMs, false, &fb).buttons == kB);
        check("with its preset on its side", fb.size() == 1 && fb[0].side == "right");
        s["right"] = motion(0, 0, 0, {"sr"});
        check("the tap releases after ~100 ms", e.process(s, 140 * kMs, false).buttons == 0);
        s["right"] = motion(0, 420, 0);
        e.process(s, 600 * kMs, false);
        check("a swing without SR held does not fire", e.process(s, 610 * kMs, false).buttons == 0);
    }

    // ---- a swing too long after the press times out ----------------------------------------------------
    {
        json swing = {{"id", "t"}, {"type", "staged"}, {"cooldown_ms", 0}, {"xbox_target", "x"},
                      {"hold_until_release", nullptr},
                      {"stages", json::array({
                          {{"conditions", json::array({{{"controller", "right"}, {"button_pressed", "a"}}, })}},
                          {{"timeout_ms", 200}, {"conditions", json::array({{{"controller", "left"}, {"field", "gyro_dps"}, {"axis", "x"}, {"min", 200}}})}}})}};
        Engine e(json{{"gestures", json::array({swing})}, {"filtering", {{"alpha", 1.0}}}});
        Samples s{{"right", motion(0, 0, 0)}, {"left", motion(0, 0, 0)}};
        e.process(s, 0, false);
        s["right"] = motion(0, 0, 0, {"a"});
        e.process(s, 10 * kMs, false);
        s["right"] = motion(0, 0, 0);
        e.process(s, 20 * kMs, false);
        s["left"] = motion(300, 0, 0);
        e.process(s, 400 * kMs, false);
        check("a late swing after the stage timeout does not fire", e.process(s, 410 * kMs, false).buttons == 0);
    }

    // ---- recording: first new press becomes a held variant; a button already down does not count ------
    {
        std::vector<Frame> frames;
        frames.push_back({0, {{kRim, rim({"b3"})}, {"right", motion(0, 0, 0)}}});
        frames.push_back({10 * kMs, {{kRim, rim({"b3"})}, {"right", motion(0, 0, 0)}}});
        frames.push_back({20 * kMs, {{kRim, rim({"b3", "b9"})}, {"right", motion(0, 0, 0)}}});
        const json v = recordButtonVariant(frames, "ls", "on_foot", {});
        check("records the NEW press, not the held one", v["stages"][0]["conditions"][0]["button_pressed"] == "b9");
        check("as a hold on that source", v["hold_until_release"]["controller"] == kRim);
        check("carrying the chosen context", v["context"] == "on_foot");
        Engine e(json{{"gestures", json::array({v})}});
        Samples s{{kRim, rim({})}};
        e.process(s, 0, false);
        s[kRim] = rim({"b9"});
        check("the recorded variant works", e.process(s, 10 * kMs, false).buttons == kLs);
    }

    // ---- recording: a press-then-swing take becomes a two-stage motion variant -------------------------
    {
        std::vector<Frame> frames;
        int64_t t = 0;
        for (int i = 0; i < 60; ++i, t += 5 * kMs) frames.push_back({t, {{"right", motion(1, -2, 1)}}});
        for (int i = 0; i < 10; ++i, t += 5 * kMs) frames.push_back({t, {{"right", motion(1, -2, 1, {"sr"})}}});
        for (int i = 0; i < 20; ++i, t += 5 * kMs) {
            const float y = 500.0f * std::sin(3.14159f * i / 19.0f);
            frames.push_back({t, {{"right", motion(5, y, 3, {"sr"})}}});
        }
        for (int i = 0; i < 30; ++i, t += 5 * kMs) frames.push_back({t, {{"right", motion(0, 0, 0, {"sr"})}}});
        const json v = recordMotionVariant(frames, "b", "both", {});
        check("two stages: press, then motion", v["stages"].size() == 2);
        check("stage one is the SR press", v["stages"][0]["conditions"][0]["button_pressed"] == "sr");
        const json& m = v["stages"][1]["conditions"][0];
        check("the dominant axis is picked", m["axis"] == "y" && m.contains("min"));
        check("threshold is ~55% of the peak", m["min"].get<float>() > 200.0f && m["min"].get<float>() < 320.0f);
        check("SR must still be held during the swing", m.contains("buttons_held"));
    }

    // ---- a take with no motion is rejected with a reason -----------------------------------------------
    {
        std::vector<Frame> frames;
        for (int i = 0; i < 80; ++i) frames.push_back({i * 5 * kMs, {{"right", motion(1, 1, 1, i > 40 ? std::initializer_list<const char*>{"a"} : std::initializer_list<const char*>{})}}});
        bool threw = false;
        try { recordMotionVariant(frames, "a", "both", {}); } catch (const std::exception&) { threw = true; }
        check("a take that never moves is refused, not saved", threw);
    }

    // ---- Joy-Con stick passthrough honours rotation and deadzone ---------------------------------------
    {
        json m = {{"id", "ls"}, {"source", {{"type", "stick"}, {"controller", "left"}, {"rotation", "clockwise"}, {"deadzone", 0.1}}},
                  {"output", {{"control", "left_stick"}}}};
        Engine e(json{{"mappings", json::array({m})}});
        Sample left = motion(0, 0, 0);
        left.stickX = 0.0f; left.stickY = 1.0f;
        const VirtualPad p = e.process({{"left", left}}, 0, false);
        check("a sideways Joy-Con's up is the pad's right", p.lx > 0.99f && std::fabs(p.ly) < 0.01f);
    }

    // ---- gyro steering: hold to toggle, then tilt drives left X in a car only --------------------------
    {
        json cfg = {{"enabled", true}, {"controller", "right"}, {"toggle_button", "capture"}, {"hold_ms", 100},
                    {"axis", "z"}, {"full_lock_deg", 45.0}, {"deadzone_deg", 0.0}, {"response_curve", 1.0}, {"smoothing", 0.0},
                    {"context", "driving"}};
        Engine e(json{{"gyro_steering", cfg}, {"filtering", {{"alpha", 1.0}}}});
        Sample r = motion(0, 0, 0, {"capture"});
        r.tNs = 0;
        e.process({{"right", r}}, 0, true);
        r.tNs = 150 * kMs;
        e.process({{"right", r}}, 150 * kMs, true);
        check("holding capture toggles steering on", e.gyroSteeringOn());
        Sample tilt = motion(0, 0, 0);
        tilt.orientation.z = 22.5f;
        const VirtualPad p = e.process({{"right", tilt}}, 200 * kMs, true);
        check("half lock tilt is half left-X", std::fabs(p.lx - 0.5f) < 0.02f);
        check("steering is silent on foot", std::fabs(e.process({{"right", tilt}}, 210 * kMs, false).lx) < 0.001f);
    }

    // ---- the XInput merge: buttons OR, the further-deflected stick or trigger wins ----------------------
    {
        using ncm::rig::pad::xinput::Gamepad;
        VirtualPad v;
        v.buttons = kB;
        v.lx = 0.5f;
        v.rt = 1.0f;
        const Gamepad physical{kA, 40, 0, -30000, 100, 0, 0};
        const Gamepad m = ncm::rig::pad::xinput::merge(physical, v);
        check("buttons are ORed", m.buttons == (kA | kB));
        check("a harder physical stick keeps its value", m.lx == -30000);
        check("a resting physical stick yields to the virtual one", merge(Gamepad{0, 0, 0, 100, 0, 0, 0}, v).lx > 16000);
        check("triggers take the larger", m.lt == 40 && m.rt == 255);
        check("an idle virtual pad changes nothing", merge(physical, VirtualPad{}).lx == -30000 && merge(physical, VirtualPad{}).buttons == kA);
    }

    // ---- JoyMoco tap output steps -------------------------------------------------------------------------
    check("a button tap presses and releases after 100 ms", outputSteps("a").size() == 2 && outputSteps("a")[1]["delay_ms"] == 100);
    check("a stick direction taps the stick", outputSteps("right_stick_down")[0]["y"] == -1.0);

    if (failures == 0) std::printf("NCM Rig Bridge pad tests passed\n");
    return failures == 0 ? 0 : 1;
}
