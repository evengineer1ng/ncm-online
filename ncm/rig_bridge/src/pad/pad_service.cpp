#include "pad_service.hpp"

#include "xinput_hook.hpp"
#include "../direct_input.hpp"
#include "../log.hpp"
#include "../net_guard.hpp"
#include "../state.hpp"

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace ncm::rig::pad {
namespace {
using json = nlohmann::json;
namespace fs = std::filesystem;

constexpr int64_t kMs = 1'000'000;
constexpr int64_t kMotionCountdownMs = 3000, kMotionCaptureMs = 4000;     // JoyMoco's fixed recording windows
constexpr int64_t kButtonWindowMs = 8000;
constexpr int64_t kCalibrateCountdownMs = 3000, kCalibrateCaptureMs = 2000;

int64_t steadyNs()
{
    return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

std::string utf8(const std::wstring& w)
{
    if (w.empty()) return {};
    const int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
    std::string out(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), out.data(), n, nullptr, nullptr);
    return out;
}

std::wstring wide(const std::string& s)
{
    if (s.empty()) return {};
    const int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0);
    std::wstring out(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), out.data(), n);
    return out;
}

/// A profile name is also a file name: keep it to what every filesystem and every eye can read.
std::string sanitize(std::string name)
{
    std::string out;
    for (char c : name) if (std::isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_' || c == ' ') out.push_back(c);
    while (!out.empty() && out.back() == ' ') out.pop_back();
    return out.substr(0, 48);
}

std::string lower(std::string s) { for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c))); return s; }

bool sendAll(SOCKET s, const std::string& data)
{
    size_t done = 0;
    while (done < data.size()) {
        const int sent = send(s, data.data() + done, static_cast<int>(data.size() - done), 0);
        if (sent <= 0) return false;
        done += static_cast<size_t>(sent);
    }
    return true;
}
}  // namespace

PadService::PadService(std::wstring directory, DirectInputRig& rig, uint16_t apiPort)
    : directory_(std::move(directory)), rig_(rig),
      sdl_(directory_ + L"\\SDL3.dll", [](bool warn, const std::string& line) {
          if (warn) RIG_WARN("%s", line.c_str()); else RIG_INFO("%s", line.c_str());
      }),
      apiPort_(apiPort) {}

PadService::~PadService() { stop(); }

// ============================================================================ profiles
std::wstring PadService::profilePath(const std::string& name) const
{
    return directory_ + L"\\profiles\\" + wide(sanitize(name)) + L".json";
}

std::vector<std::string> PadService::profileNames() const
{
    std::vector<std::string> names;
    std::error_code ec;
    for (const auto& entry : fs::directory_iterator(fs::path(directory_) / L"profiles", ec)) {
        if (!entry.is_regular_file() || entry.path().extension() != L".json") continue;
        names.push_back(utf8(entry.path().stem().wstring()));
    }
    std::sort(names.begin(), names.end());
    return names;
}

bool PadService::loadProfile(const std::string& name, std::string* error)
{
    std::ifstream in(profilePath(name), std::ios::binary);
    if (!in) { if (error) *error = "no profile named '" + name + "'"; return false; }
    json loaded;
    try {
        std::stringstream ss;
        ss << in.rdbuf();
        std::string text = ss.str();
        if (text.size() >= 3 && static_cast<unsigned char>(text[0]) == 0xEF) text.erase(0, 3);   // BOM, as JoyMoco's files may carry
        loaded = json::parse(text);
    } catch (const std::exception& e) {
        if (error) *error = std::string("could not read profile: ") + e.what();
        return false;
    }
    if (!loaded.is_object() || !loaded.contains("gestures")) { if (error) *error = "not a gamepad profile"; return false; }
    profile_ = std::move(loaded);
    profileName_ = sanitize(name);
    dirty_ = false;
    applyProfileLocked();
    std::ofstream(directory_ + L"\\profiles\\active.txt", std::ios::trunc) << profileName_;
    RIG_INFO("gamepad profile '%s' loaded: %zu variant(s)", profileName_.c_str(), profile_["gestures"].size());
    return true;
}

bool PadService::saveProfile(const std::string& requested, std::string* error)
{
    const std::string name = sanitize(requested.empty() ? profileName_ : requested);
    if (name.empty()) { if (error) *error = "give the profile a name"; return false; }
    profile_["name"] = name;
    const std::wstring path = profilePath(name), temp = path + L".tmp";
    {
        std::ofstream out(temp, std::ios::binary | std::ios::trunc);
        if (!out) { if (error) *error = "could not write the profile file"; return false; }
        out << profile_.dump(2) << "\n";
    }
    if (!MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING)) {
        if (error) *error = "could not replace the profile file";
        return false;
    }
    profileName_ = name;
    dirty_ = false;
    std::ofstream(directory_ + L"\\profiles\\active.txt", std::ios::trunc) << profileName_;
    RIG_INFO("gamepad profile '%s' saved", profileName_.c_str());
    return true;
}

void PadService::applyProfileLocked()
{
    engine_.setProfile(profile_);
    sdl_.setAssignments(profile_.value("assignments", json::object()));
    xinput::setUserIndex(profile_.value("xinput", json::object()).value("user_index", 0u));
}

// ============================================================================ lifecycle
void PadService::start()
{
    if (running_.exchange(true)) return;
    std::error_code ec;
    fs::create_directories(fs::path(directory_) / L"profiles", ec);
    // First run: the shipped default becomes the player's own `default.json`, so an update that re-projects
    // `_shipped/` can never overwrite what they saved.
    const fs::path shipped = fs::path(directory_) / L"profiles" / L"_shipped" / L"default.json";
    const fs::path mine = fs::path(directory_) / L"profiles" / L"default.json";
    if (!fs::exists(mine, ec) && fs::exists(shipped, ec)) fs::copy_file(shipped, mine, ec);
    std::string active = "default";
    if (std::ifstream in(directory_ + L"\\profiles\\active.txt"); in) std::getline(in, active);
    {
        std::lock_guard lock(mutex_);
        std::string error;
        if (!loadProfile(active, &error) && !loadProfile("default", &error))
            RIG_WARN("gamepad: no profile could be loaded (%s); the layer runs empty", error.c_str());
    }
    xinput::setRumbleSink([this](float large, float small) {
        std::lock_guard lock(mutex_);
        const json rumble = profile_.value("rumble", json::object());
        if (!rumble.value("enabled", true) || !rumble.value("game_generated", true)) return;
        if (large == lastGameLarge_ && small == lastGameSmall_) return;
        lastGameLarge_ = large;
        lastGameSmall_ = small;
        // JoyMoco `game_rumble`: the large motor on the left hand, the small on the right, as 120 ms slices.
        std::lock_guard rl(rumbleMutex_);
        if (rumbleQueue_.size() < 64) {
            rumbleQueue_.push_back({{"left"}, large, 120, 0});
            rumbleQueue_.push_back({{"right"}, small, 120, 0});
            rumbleWake_.notify_one();
        }
    });
    sdl_.start();
    tick_ = std::thread([this] { tickLoop(); });
    rumble_ = std::thread([this] { rumbleLoop(); });
    api_ = std::thread([this] { apiLoop(); });
}

void PadService::stop()
{
    if (!running_.exchange(false)) return;
    xinput::setRumbleSink(nullptr);
    if (auto s = listener_.exchange(0)) closesocket(static_cast<SOCKET>(s));
    rumbleWake_.notify_all();
    if (tick_.joinable()) tick_.join();
    if (rumble_.joinable()) rumble_.join();
    if (api_.joinable()) api_.join();
    xinput::publish(VirtualPad{});
    sdl_.stop();
}

// ============================================================================ the tick
void PadService::tickLoop()
{
    while (running_.load()) {
        Samples samples = sdl_.snapshot();
        rig_.rawSamples(samples);
        const bool driving = ncm::rig::state().playerVehicle() != nullptr;
        const int64_t now = steadyNs();
        std::vector<Feedback> feedback;
        VirtualPad pad;
        bool recording = false;
        {
            std::lock_guard lock(mutex_);
            pad = engine_.process(samples, now, driving, &feedback);
            live_ = samples;
            pad_ = pad;
            driving_ = driving;
            nowNs_ = now;
            if (phase_ == Phase::Countdown) {
                const int64_t wait = mode_ == Mode::Motion ? kMotionCountdownMs : kCalibrateCountdownMs;
                if (now - phaseStartNs_ >= wait * kMs) { phase_ = Phase::Capture; phaseStartNs_ = now; frames_.clear(); }
            } else if (phase_ == Phase::Capture) {
                frames_.push_back({now, samples});
                const int64_t window = mode_ == Mode::Motion ? kMotionCaptureMs
                                     : mode_ == Mode::Calibrate ? kCalibrateCaptureMs : kButtonWindowMs;
                bool done = now - phaseStartNs_ >= window * kMs;
                // A button take ends on the first press rather than waiting out the window.
                if (!done && mode_ == Mode::Button) {
                    try { recordButtonVariant(frames_, recordTarget_, recordContext_, {}); done = true; } catch (...) {}
                }
                if (done) finishRecordingLocked(now);
            }
            recording = phase_ != Phase::Idle;
        }
        // While recording, the variant being recorded must not ALSO press things in the game.
        xinput::publish(recording ? VirtualPad{} : pad);
        for (const auto& f : feedback) playEffect(f.effect, f.side);
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
}

void PadService::finishRecordingLocked(int64_t)
{
    phase_ = Phase::Idle;
    std::vector<std::string> names;
    for (const auto& g : profile_.value("gestures", json::array()))
        if (g.value("xbox_target", "") == recordTarget_) names.push_back(g.value("variant_name", ""));
    try {
        if (mode_ == Mode::Calibrate) {
            // JoyMoco calibration: two seconds held still -> per-hand gyro bias and neutral orientation. Taken
            // from RAW samples, since the engine applies these very values to what it reads.
            std::map<std::string, std::pair<int, std::array<double, 6>>> sums;
            for (const auto& f : frames_)
                for (const auto& [src, s] : f.samples) {
                    if (!s.motion || !isMotionHand(src)) continue;
                    auto& [n, a] = sums[src];
                    ++n;
                    a[0] += s.gyro.x; a[1] += s.gyro.y; a[2] += s.gyro.z;
                    a[3] += s.orientation.x; a[4] += s.orientation.y; a[5] += s.orientation.z;
                }
            if (sums.empty()) throw std::runtime_error("no motion controller was connected");
            json cal = profile_.value("calibration", json::object());
            for (const auto& [src, entry] : sums) {
                const auto& [n, a] = entry;
                cal[src] = {{"gyro_bias", {{"x", a[0] / n}, {"y", a[1] / n}, {"z", a[2] / n}}},
                            {"neutral_orientation", {{"x", a[3] / n}, {"y", a[4] / n}, {"z", a[5] / n}}}};
            }
            profile_["calibration"] = cal;
            recordResult_ = "Calibrated " + std::to_string(sums.size()) + " controller(s). Save the profile to keep it.";
        } else {
            json variant = mode_ == Mode::Button ? recordButtonVariant(frames_, recordTarget_, recordContext_, names)
                                                 : recordMotionVariant(frames_, recordTarget_, recordContext_, names);
            if (variant.contains("macro")) {
                const std::string id = variant["macro"];
                json& macros = profile_["macros"];
                if (!macros.is_array()) macros = json::array();
                macros.erase(std::remove_if(macros.begin(), macros.end(), [&](const json& m) { return m.value("id", "") == id; }), macros.end());
                macros.push_back({{"id", id}, {"steps", outputSteps(recordTarget_)}});
            }
            recordResult_ = "Added '" + variant.value("variant_name", std::string("variant")) + "': " + describeVariant(variant);
            profile_["gestures"].push_back(std::move(variant));
        }
        recordOk_ = true;
        dirty_ = true;
        applyProfileLocked();
    } catch (const std::exception& e) {
        recordOk_ = false;
        recordResult_ = std::string("Rejected: ") + e.what();
    }
    RIG_INFO("gamepad recording %s: %s", recordOk_ ? "ok" : "rejected", recordResult_.c_str());
    frames_.clear();
}

// ============================================================================ rumble
std::vector<std::string> PadService::handsFor(const std::string& side) const
{
    std::vector<std::string> hands;
    std::stringstream ss(side);
    std::string token;
    while (std::getline(ss, token, '+')) {
        token.erase(std::remove(token.begin(), token.end(), ' '), token.end());
        std::vector<std::string> add;
        if (token == "both") add = {"left", "right"};
        else if (token == "left" || token == "right" || token == "primary" || token == "left_leg" ||
                 token == "right_leg" || token == "controller") add = {token};
        for (const auto& h : add) if (std::find(hands.begin(), hands.end(), h) == hands.end()) hands.push_back(h);
    }
    return hands;
}

void PadService::playEffect(const std::string& effectId, const std::string& sideOverride)
{
    json effect;
    {
        std::lock_guard lock(mutex_);
        const json rumble = profile_.value("rumble", json::object());
        if (!rumble.value("enabled", true)) return;
        for (const auto& e : profile_.value("rumble_effects", json::array()))
            if (e.value("id", "") == effectId) effect = e;
    }
    if (effect.is_null()) return;
    // JoyMoco `play_effect`: shaped effects play their own steps; simple ones repeat a pulse.
    const std::string side = sideOverride.empty() ? effect.value("side", std::string("both")) : sideOverride;
    std::vector<RumbleStep> steps;
    if (effect.contains("steps") && effect["steps"].is_array()) {
        for (const auto& s : effect["steps"])
            steps.push_back({handsFor(s.value("side", side)), std::clamp(s.value("intensity", 0.4f), 0.0f, 1.0f),
                             static_cast<uint32_t>(std::max(10, s.value("duration_ms", 40))),
                             static_cast<uint32_t>(std::max(0, s.value("gap_ms", 0)))});
    } else {
        const int pulses = std::clamp(effect.value("pulses", 1), 1, 32);
        for (int i = 0; i < pulses; ++i)
            steps.push_back({handsFor(side), std::clamp(effect.value("intensity", 0.4f), 0.0f, 1.0f),
                             static_cast<uint32_t>(std::max(10, effect.value("duration_ms", 45))),
                             static_cast<uint32_t>(i < pulses - 1 ? std::max(0, effect.value("gap_ms", 35)) : 0)});
    }
    std::lock_guard rl(rumbleMutex_);
    for (auto& s : steps) if (rumbleQueue_.size() < 64) rumbleQueue_.push_back(std::move(s));
    rumbleWake_.notify_one();
}

void PadService::rumbleLoop()
{
    while (running_.load()) {
        RumbleStep step;
        {
            std::unique_lock lock(rumbleMutex_);
            rumbleWake_.wait_for(lock, std::chrono::milliseconds(200), [&] { return !rumbleQueue_.empty() || !running_.load(); });
            if (!running_.load()) break;
            if (rumbleQueue_.empty()) continue;
            step = std::move(rumbleQueue_.front());
            rumbleQueue_.pop_front();
        }
        float scale = 1.0f;
        { std::lock_guard lock(mutex_); scale = std::clamp(profile_.value("rumble", json::object()).value("scale", 1.0f), 0.0f, 1.0f); }
        const float level = step.level * scale;
        for (const auto& hand : step.hands) {
            if (hand == "controller") xinput::rumblePhysical(level, level);
            else sdl_.rumble(hand, level, level, step.durationMs);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(step.durationMs + step.gapMs));
        for (const auto& hand : step.hands) if (hand == "controller") xinput::rumblePhysical(0, 0);
    }
}

// ============================================================================ state and commands
json PadService::state()
{
    std::lock_guard lock(mutex_);
    json variants = json::array();
    const auto active = engine_.activeVariants(nowNs_);
    for (const auto& g : profile_.value("gestures", json::array())) {
        const std::string id = g.value("id", "");
        variants.push_back({{"id", id}, {"target", g.value("xbox_target", "")}, {"name", g.value("variant_name", "")},
                            {"summary", describeVariant(g)}, {"context", g.value("context", std::string("both"))},
                            {"effect", g.value("feedback_effect", "")}, {"side", g.value("feedback_side", std::string("both"))},
                            {"enabled", g.value("enabled", true)}, {"motion", g.value("capture_motion", false)},
                            {"active", std::find(active.begin(), active.end(), id) != active.end()}});
    }
    json effects = json::array();
    for (const auto& e : profile_.value("rumble_effects", json::array())) effects.push_back(e.value("id", ""));
    json sources = json::object();
    for (const auto& [src, s] : live_) {
        json one = {{"buttons", std::vector<std::string>(s.buttons.begin(), s.buttons.end())}, {"motion", s.motion}};
        if (s.motion) one["gyro"] = {s.gyro.x, s.gyro.y, s.gyro.z};
        sources[src] = one;
    }
    std::vector<std::string> pressed;
    for (const auto& b : buttonNames()) if (pad_.buttons & buttonBit(b)) pressed.push_back(b);
    const char* phase = phase_ == Phase::Idle ? "idle" : phase_ == Phase::Countdown ? "countdown" : "capture";
    int64_t remaining = 0;
    if (phase_ != Phase::Idle) {
        const int64_t window = phase_ == Phase::Countdown
            ? (mode_ == Mode::Motion ? kMotionCountdownMs : kCalibrateCountdownMs)
            : (mode_ == Mode::Motion ? kMotionCaptureMs : mode_ == Mode::Calibrate ? kCalibrateCaptureMs : kButtonWindowMs);
        remaining = std::max<int64_t>(0, window - (nowNs_ - phaseStartNs_) / kMs);
    }
    return {{"profile", {{"name", profileName_}, {"dirty", dirty_}}}, {"profiles", profileNames()},
            {"targets", targetNames()}, {"variants", variants}, {"effects", effects},
            {"mappings", profile_.value("mappings", json::array())},
            {"steering", profile_.value("gyro_steering", json::object())}, {"steeringOn", engine_.gyroSteeringOn()},
            {"rumble", profile_.value("rumble", json::object())},
            {"assignments", profile_.value("assignments", json::object())},
            {"sources", sources}, {"sdlDevices", sdl_.devices()}, {"sdl", sdl_.status()},
            {"pad", {{"buttons", pressed}, {"lx", pad_.lx}, {"ly", pad_.ly}, {"rx", pad_.rx}, {"ry", pad_.ry},
                     {"lt", pad_.lt}, {"rt", pad_.rt}}},
            {"driving", driving_}, {"xinput", xinput::status()},
            {"recording", {{"phase", phase}, {"target", recordTarget_},
                           {"mode", mode_ == Mode::Button ? "button" : mode_ == Mode::Motion ? "motion" : "calibrate"},
                           {"remainingMs", remaining}, {"result", recordResult_}, {"ok", recordOk_}}}};
}

json PadService::command(const json& cmd)
{
    const std::string op = cmd.value("op", "");
    std::string error;
    bool ok = true;
    std::string effectToPlay, effectSide;
    {
        std::lock_guard lock(mutex_);
        auto findVariant = [&](const std::string& id) -> json* {
            for (auto& g : profile_["gestures"]) if (g.value("id", "") == id) return &g;
            return nullptr;
        };
        if (op == "record" || op == "calibrate") {
            if (phase_ != Phase::Idle) { ok = false; error = "a recording is already running"; }
            else {
                mode_ = op == "calibrate" ? Mode::Calibrate : cmd.value("mode", std::string("button")) == "motion" ? Mode::Motion : Mode::Button;
                recordTarget_ = cmd.value("target", "");
                recordContext_ = cmd.value("context", std::string("both"));
                if (mode_ != Mode::Calibrate && std::find(targetNames().begin(), targetNames().end(), recordTarget_) == targetNames().end()) {
                    ok = false; error = "unknown gamepad target '" + recordTarget_ + "'";
                } else {
                    // A button take starts listening at once; motion and calibration count down first, as JoyMoco does.
                    phase_ = mode_ == Mode::Button ? Phase::Capture : Phase::Countdown;
                    phaseStartNs_ = nowNs_;
                    frames_.clear();
                    recordResult_.clear();
                }
            }
        } else if (op == "cancel") {
            phase_ = Phase::Idle;
            frames_.clear();
            recordResult_ = "Cancelled.";
            recordOk_ = false;
        } else if (op == "variant") {
            json* v = findVariant(cmd.value("id", ""));
            if (!v) { ok = false; error = "no such variant"; }
            else {
                const json set = cmd.value("set", json::object());
                for (const char* key : {"context", "feedback_effect", "feedback_side", "variant_name", "enabled", "cooldown_ms"})
                    if (set.contains(key)) (*v)[key] = set[key];
                dirty_ = true;
                applyProfileLocked();
            }
        } else if (op == "delete") {
            json& g = profile_["gestures"];
            const auto before = g.size();
            const std::string id = cmd.value("id", "");
            g.erase(std::remove_if(g.begin(), g.end(), [&](const json& x) { return x.value("id", "") == id; }), g.end());
            if (g.size() == before) { ok = false; error = "no such variant"; }
            else { dirty_ = true; applyProfileLocked(); }
        } else if (op == "steering") {
            json s = profile_.value("gyro_steering", json::object());
            for (const auto& [k, val] : cmd.value("set", json::object()).items()) s[k] = val;
            profile_["gyro_steering"] = s;
            dirty_ = true;
            applyProfileLocked();
        } else if (op == "mapping") {
            json& m = profile_["mappings"];
            if (!m.is_array()) m = json::array();
            const std::string id = cmd.value("id", "");
            bool found = false;
            for (auto& x : m) if (x.value("id", "") == id) {
                const json set = cmd.value("set", json::object());
                for (const auto& [k, val] : set.items()) {
                    if (k == "source" || k == "output") for (const auto& [k2, v2] : val.items()) x[k][k2] = v2;
                    else x[k] = val;
                }
                found = true;
            }
            if (!found) { ok = false; error = "no such mapping"; } else { dirty_ = true; applyProfileLocked(); }
        } else if (op == "rumble") {
            json r = profile_.value("rumble", json::object());
            for (const auto& [k, val] : cmd.value("set", json::object()).items()) r[k] = val;
            profile_["rumble"] = r;
            dirty_ = true;
        } else if (op == "assign") {
            json a = profile_.value("assignments", json::object());
            a[cmd.value("hand", "")] = cmd.value("key", std::string("auto"));
            profile_["assignments"] = a;
            dirty_ = true;
            applyProfileLocked();
        } else if (op == "test") {
            effectToPlay = cmd.value("effect", "");
            effectSide = cmd.value("side", "");
        } else if (op == "save") {
            ok = saveProfile(cmd.value("name", ""), &error);
        } else if (op == "load") {
            ok = loadProfile(cmd.value("name", ""), &error);
        } else if (op == "new") {
            const std::string name = sanitize(cmd.value("name", ""));
            if (name.empty()) { ok = false; error = "give the profile a name"; }
            else {
                // A new scheme starts from the current one's effects and assignments but no variants.
                json fresh = profile_;
                fresh["name"] = name;
                fresh["gestures"] = json::array();
                fresh["macros"] = json::array();
                profile_ = fresh;
                profileName_ = name;
                dirty_ = true;
                applyProfileLocked();
            }
        } else if (op == "reset") {
            engine_.reset();
        } else if (op != "state") {
            ok = false;
            error = "unknown op '" + op + "'";
        }
    }
    if (!effectToPlay.empty()) playEffect(effectToPlay, effectSide);
    json out = {{"ok", ok}};
    if (!ok) out["error"] = error;
    out["state"] = state();
    return out;
}

// ============================================================================ the loopback API
void PadService::apiLoop()
{
    WSADATA data{};
    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) { RIG_ERR("gamepad API: Winsock unavailable"); return; }
    SOCKET listener = INVALID_SOCKET;
    const uint16_t base = apiPort_.load();
    for (uint16_t candidate = base; candidate < base + 4; ++candidate) {
        SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if (s == INVALID_SOCKET) continue;
        BOOL exclusive = TRUE;
        setsockopt(s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, reinterpret_cast<const char*>(&exclusive), sizeof(exclusive));
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_port = htons(candidate);
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
        if (bind(s, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != SOCKET_ERROR && listen(s, 8) != SOCKET_ERROR) {
            listener = s;
            apiPort_ = candidate;
            break;
        }
        closesocket(s);
    }
    if (listener == INVALID_SOCKET) { RIG_ERR("gamepad API: no free port from %u", base); WSACleanup(); return; }
    listener_ = static_cast<uintptr_t>(listener);
    ncm::rig::state().setPadApiPort(apiPort_.load());
    RIG_INFO("gamepad API listening on http://127.0.0.1:%u/pad/state", apiPort_.load());
    while (running_.load()) {
        SOCKET client = accept(listener, nullptr, nullptr);
        if (client == INVALID_SOCKET) break;
        const uint32_t peer = peerPid(client);
        if (!sameProcessTree(peer, GetCurrentProcessId())) {
            RIG_WARN("gamepad API refused pid=%u outside this game's process tree", peer);
            closesocket(client);
            continue;
        }
        DWORD timeout = 2000;
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
        serve(static_cast<uintptr_t>(client));
        closesocket(client);
    }
    listener_ = 0;
    WSACleanup();
}

void PadService::serve(uintptr_t value)
{
    SOCKET s = static_cast<SOCKET>(value);
    std::string request;
    char buffer[8192];
    size_t headerEnd = std::string::npos;
    while (headerEnd == std::string::npos && request.size() < 65536) {
        const int got = recv(s, buffer, sizeof(buffer), 0);
        if (got <= 0) return;
        request.append(buffer, static_cast<size_t>(got));
        headerEnd = request.find("\r\n\r\n");
    }
    if (headerEnd == std::string::npos) return;
    const std::string head = lower(request.substr(0, headerEnd));
    size_t contentLength = 0;
    if (auto at = head.find("content-length:"); at != std::string::npos) contentLength = std::strtoul(head.c_str() + at + 15, nullptr, 10);
    std::string body = request.substr(headerEnd + 4);
    while (body.size() < contentLength && body.size() < (1u << 20)) {
        const int got = recv(s, buffer, sizeof(buffer), 0);
        if (got <= 0) break;
        body.append(buffer, static_cast<size_t>(got));
    }
    const std::string cors = "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
                             "Access-Control-Allow-Headers: Content-Type\r\nCache-Control: no-store\r\n";
    auto respond = [&](int code, const char* reason, const std::string& payload) {
        sendAll(s, "HTTP/1.1 " + std::to_string(code) + " " + reason + "\r\n" + cors +
                   "Content-Type: application/json; charset=utf-8\r\nContent-Length: " + std::to_string(payload.size()) +
                   "\r\nConnection: close\r\n\r\n" + payload);
    };
    if (head.rfind("options ", 0) == 0) { respond(204, "No Content", ""); return; }
    if (head.rfind("get /pad/state", 0) == 0) { respond(200, "OK", state().dump()); return; }
    if (head.rfind("post /pad/cmd", 0) == 0) {
        json cmd;
        try { cmd = json::parse(body); } catch (...) { respond(400, "Bad Request", R"({"ok":false,"error":"body is not JSON"})"); return; }
        respond(200, "OK", command(cmd).dump());
        return;
    }
    respond(404, "Not Found", R"({"ok":false,"error":"unknown route"})");
}

}  // namespace ncm::rig::pad
