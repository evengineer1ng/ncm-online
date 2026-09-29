#include "sdl_input.hpp"

#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <map>
#include <set>

namespace ncm::rig::pad {
namespace {
using json = nlohmann::json;

// SDL3's C ABI, declared by hand exactly as JoyMoco declares it through ctypes. `bool` is C99 bool.
using SDL_JoystickID = uint32_t;
struct SdlApi {
    bool (*Init)(uint32_t);
    void (*Quit)();
    const char* (*GetError)();
    bool (*SetHint)(const char*, const char*);
    void (*PumpEvents)();
    void (*UpdateGamepads)();
    void (*UpdateJoysticks)();
    SDL_JoystickID* (*GetGamepads)(int*);
    SDL_JoystickID* (*GetJoysticks)(int*);
    bool (*IsGamepad)(SDL_JoystickID);
    int (*GetGamepadTypeForID)(SDL_JoystickID);
    const char* (*GetGamepadNameForID)(SDL_JoystickID);
    int (*GetGamepadPlayerIndexForID)(SDL_JoystickID);
    void* (*OpenGamepad)(SDL_JoystickID);
    const char* (*GetGamepadSerial)(void*);
    void (*CloseGamepad)(void*);
    bool (*GamepadConnected)(void*);
    int16_t (*GetGamepadAxis)(void*, int);
    bool (*GetGamepadButton)(void*, int);
    bool (*GamepadHasSensor)(void*, int);
    bool (*SetGamepadSensorEnabled)(void*, int, bool);
    bool (*GetGamepadSensorData)(void*, int, float*, int);
    bool (*RumbleGamepad)(void*, uint16_t, uint16_t, uint32_t);
    int (*GetGamepadPowerInfo)(void*, int*);
    int (*GetNumGamepadTouchpads)(void*);
    bool (*GetGamepadTouchpadFinger)(void*, int, int, bool*, float*, float*, float*);
    const char* (*GetJoystickNameForID)(SDL_JoystickID);
    uint16_t (*GetJoystickVendorForID)(SDL_JoystickID);
    uint16_t (*GetJoystickProductForID)(SDL_JoystickID);
    int (*GetJoystickTypeForID)(SDL_JoystickID);
    void* (*OpenJoystick)(SDL_JoystickID);
    const char* (*GetJoystickSerial)(void*);
    void (*CloseJoystick)(void*);
    bool (*JoystickConnected)(void*);
    int (*GetNumJoystickAxes)(void*);
    int (*GetNumJoystickButtons)(void*);
    int (*GetNumJoystickHats)(void*);
    int16_t (*GetJoystickAxis)(void*, int);
    bool (*GetJoystickButton)(void*, int);
    uint8_t (*GetJoystickHat)(void*, int);
    void (*Free)(void*);
};

constexpr uint32_t kInitJoystick = 0x00000200, kInitGamepad = 0x00002000;
constexpr int kSensorAccel = 1, kSensorGyro = 2;
constexpr int kTypeXbox360 = 2, kTypeXboxOne = 3, kTypePs4 = 5, kTypePs5 = 6, kTypeSwitchPro = 7;
constexpr int kTypeJoyConLeft = 8, kTypeJoyConRight = 9;
// SDL_JoystickType values for the kinds of device DirectInput and force feedback own (KB-209).
constexpr int kJoystickWheel = 2, kJoystickFlightStick = 4, kJoystickThrottle = 9;
constexpr int kAxisLeftX = 0, kAxisLeftY = 1, kAxisRightX = 2, kAxisRightY = 3, kAxisLeftTrigger = 4, kAxisRightTrigger = 5;

// JoyMoco's three button tables, by SDL gamepad button index.
const std::map<int, const char*> kJoyConButtons = {
    {0, "b"}, {1, "a"}, {2, "y"}, {3, "x"}, {4, "minus"}, {5, "home"}, {6, "plus"}, {7, "ls"}, {8, "rs"},
    {9, "shoulder"}, {10, "shoulder"}, {11, "dpad_up"}, {12, "dpad_down"}, {13, "dpad_left"}, {14, "dpad_right"},
    {15, "capture"}, {16, "sr"}, {17, "sl"}, {18, "sl"}, {19, "sr"}};
const std::map<int, const char*> kGamepadButtons = {
    {0, "a"}, {1, "b"}, {2, "x"}, {3, "y"}, {4, "back"}, {5, "home"}, {6, "start"}, {7, "ls"}, {8, "rs"},
    {9, "lb"}, {10, "rb"}, {11, "dpad_up"}, {12, "dpad_down"}, {13, "dpad_left"}, {14, "dpad_right"}};
const std::map<int, const char*> kPrimaryButtons = {
    {0, "b"}, {1, "a"}, {2, "y"}, {3, "x"}, {4, "minus"}, {5, "home"}, {6, "plus"}, {7, "ls"}, {8, "rs"},
    {9, "lb"}, {10, "rb"}, {11, "dpad_up"}, {12, "dpad_down"}, {13, "dpad_left"}, {14, "dpad_right"},
    {15, "capture"}, {20, "capture"}};

float axis(int16_t raw) { return std::clamp(raw / (raw >= 0 ? 32767.0f : 32768.0f), -1.0f, 1.0f); }

std::string narrow(const char* s) { return s ? std::string(s) : std::string(); }

std::string vidPid(uint16_t vid, uint16_t pid)
{
    char buf[16];
    snprintf(buf, sizeof(buf), "%04X:%04X", vid, pid);
    return buf;
}

// `SDL_JOYSTICK_IGNORE_DEVICES`: "0xVVVV/0xPPPP,...". Nintendo and Sony are left out even when DirectInput
// lists them, because they are the motion hands and only SDL can read their IMU; Microsoft because an Xbox
// pad is only ever opened to read its serial. Everything else DirectInput owns, SDL never enumerates.
std::string ignoreHint(const std::set<std::string>& owned)
{
    std::string out;
    for (const auto& key : owned) {
        if (key.size() < 9 || key[4] != ':') continue;
        const std::string vid = key.substr(0, 4);
        if (vid == "057E" || vid == "054C" || vid == "045E") continue;
        if (!out.empty()) out += ',';
        out += "0x" + vid + "/0x" + key.substr(5, 4);
    }
    return out;
}

int64_t nowNs()
{
    return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}
}  // namespace

struct SdlInput::Impl {
    HMODULE module = nullptr;
    SdlApi api{};
    struct Pad { void* handle; SDL_JoystickID id; std::string key, name; int type; std::string hand; };
    struct Stick { void* handle; SDL_JoystickID id; std::string key, name; int axes, buttons, hats; };
    std::vector<Pad> pads;
    std::vector<Stick> sticks;
    std::map<std::string, Vec3> orientation;
    std::map<std::string, int64_t> lastNs;

    template <typename T> bool bind(T& fn, const char* name)
    {
        fn = reinterpret_cast<T>(GetProcAddress(module, name));
        return fn != nullptr;
    }
    bool load(const std::wstring& path, std::string* missing)
    {
        module = LoadLibraryExW(path.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
        if (!module) { *missing = "SDL3.dll not loadable"; return false; }
        const std::pair<void**, const char*> table[] = {
            {reinterpret_cast<void**>(&api.Init), "SDL_Init"}, {reinterpret_cast<void**>(&api.Quit), "SDL_Quit"},
            {reinterpret_cast<void**>(&api.GetError), "SDL_GetError"}, {reinterpret_cast<void**>(&api.SetHint), "SDL_SetHint"},
            {reinterpret_cast<void**>(&api.PumpEvents), "SDL_PumpEvents"},
            {reinterpret_cast<void**>(&api.UpdateGamepads), "SDL_UpdateGamepads"},
            {reinterpret_cast<void**>(&api.UpdateJoysticks), "SDL_UpdateJoysticks"},
            {reinterpret_cast<void**>(&api.GetGamepads), "SDL_GetGamepads"},
            {reinterpret_cast<void**>(&api.GetJoysticks), "SDL_GetJoysticks"},
            {reinterpret_cast<void**>(&api.IsGamepad), "SDL_IsGamepad"},
            {reinterpret_cast<void**>(&api.GetGamepadTypeForID), "SDL_GetGamepadTypeForID"},
            {reinterpret_cast<void**>(&api.GetGamepadNameForID), "SDL_GetGamepadNameForID"},
            {reinterpret_cast<void**>(&api.GetGamepadPlayerIndexForID), "SDL_GetGamepadPlayerIndexForID"},
            {reinterpret_cast<void**>(&api.OpenGamepad), "SDL_OpenGamepad"},
            {reinterpret_cast<void**>(&api.GetGamepadSerial), "SDL_GetGamepadSerial"},
            {reinterpret_cast<void**>(&api.CloseGamepad), "SDL_CloseGamepad"},
            {reinterpret_cast<void**>(&api.GamepadConnected), "SDL_GamepadConnected"},
            {reinterpret_cast<void**>(&api.GetGamepadAxis), "SDL_GetGamepadAxis"},
            {reinterpret_cast<void**>(&api.GetGamepadButton), "SDL_GetGamepadButton"},
            {reinterpret_cast<void**>(&api.GamepadHasSensor), "SDL_GamepadHasSensor"},
            {reinterpret_cast<void**>(&api.SetGamepadSensorEnabled), "SDL_SetGamepadSensorEnabled"},
            {reinterpret_cast<void**>(&api.GetGamepadSensorData), "SDL_GetGamepadSensorData"},
            {reinterpret_cast<void**>(&api.RumbleGamepad), "SDL_RumbleGamepad"},
            {reinterpret_cast<void**>(&api.GetGamepadPowerInfo), "SDL_GetGamepadPowerInfo"},
            {reinterpret_cast<void**>(&api.GetNumGamepadTouchpads), "SDL_GetNumGamepadTouchpads"},
            {reinterpret_cast<void**>(&api.GetGamepadTouchpadFinger), "SDL_GetGamepadTouchpadFinger"},
            {reinterpret_cast<void**>(&api.GetJoystickNameForID), "SDL_GetJoystickNameForID"},
            {reinterpret_cast<void**>(&api.GetJoystickVendorForID), "SDL_GetJoystickVendorForID"},
            {reinterpret_cast<void**>(&api.GetJoystickProductForID), "SDL_GetJoystickProductForID"},
            {reinterpret_cast<void**>(&api.GetJoystickTypeForID), "SDL_GetJoystickTypeForID"},
            {reinterpret_cast<void**>(&api.OpenJoystick), "SDL_OpenJoystick"},
            {reinterpret_cast<void**>(&api.GetJoystickSerial), "SDL_GetJoystickSerial"},
            {reinterpret_cast<void**>(&api.CloseJoystick), "SDL_CloseJoystick"},
            {reinterpret_cast<void**>(&api.JoystickConnected), "SDL_JoystickConnected"},
            {reinterpret_cast<void**>(&api.GetNumJoystickAxes), "SDL_GetNumJoystickAxes"},
            {reinterpret_cast<void**>(&api.GetNumJoystickButtons), "SDL_GetNumJoystickButtons"},
            {reinterpret_cast<void**>(&api.GetNumJoystickHats), "SDL_GetNumJoystickHats"},
            {reinterpret_cast<void**>(&api.GetJoystickAxis), "SDL_GetJoystickAxis"},
            {reinterpret_cast<void**>(&api.GetJoystickButton), "SDL_GetJoystickButton"},
            {reinterpret_cast<void**>(&api.GetJoystickHat), "SDL_GetJoystickHat"},
            {reinterpret_cast<void**>(&api.Free), "SDL_free"}};
        for (const auto& [slot, name] : table) {
            *slot = reinterpret_cast<void*>(GetProcAddress(module, name));
            if (!*slot) { *missing = name; return false; }
        }
        return true;
    }
};

void SdlInput::start()
{
    if (running_.exchange(true)) return;
    thread_ = std::thread([this] { run(); });
}

void SdlInput::stop()
{
    if (!running_.exchange(false)) return;
    if (thread_.joinable()) thread_.join();
}

void SdlInput::setOwnedElsewhere(std::set<std::string> vidPids)
{
    std::lock_guard lock(mutex_);
    if (vidPids == ownedElsewhere_) return;
    ownedElsewhere_ = std::move(vidPids);
    ownedChanged_ = true;
}

void SdlInput::setAssignments(const json& assignments)
{
    std::lock_guard lock(mutex_);
    assignments_ = assignments.is_object() ? assignments : json::object();
    assignmentsChanged_ = true;
}

Samples SdlInput::snapshot() const { std::lock_guard lock(mutex_); return samples_; }
json SdlInput::devices() const { std::lock_guard lock(mutex_); return devices_; }
std::string SdlInput::status() const { std::lock_guard lock(mutex_); return status_; }

void SdlInput::rumble(const std::string& hand, float low, float high, uint32_t durationMs)
{
    std::lock_guard lock(mutex_);
    if (rumbles_.size() < 64) rumbles_.push_back({hand, low, high, durationMs});
}

void SdlInput::run()
{
    Impl impl;
    impl_ = &impl;
    std::string missing;
    auto setStatus = [this](const std::string& s) { std::lock_guard lock(mutex_); status_ = s; };
    if (!impl.load(dllPath_, &missing)) {
        setStatus("unavailable: " + missing);
        if (log_) log_(true, "SDL3 motion input unavailable (" + missing + "): Joy-Cons and SDL-only devices are off");
        impl_ = nullptr;
        return;
    }
    auto& sdl = impl.api;
    // JoyMoco's hints, plus a joystick thread: nothing guarantees this thread's window messages are
    // dispatched anywhere but here, so SDL gets its own detection thread (the Carrier learned this, KB-140).
    sdl.SetHint("SDL_JOYSTICK_ENHANCED_REPORTS", "1");
    sdl.SetHint("SDL_JOYSTICK_HIDAPI_COMBINE_JOY_CONS", "0");
    sdl.SetHint("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1");
    sdl.SetHint("SDL_JOYSTICK_THREAD", "1");
    // KB-209. SDL 3.4 ships a HIDAPI driver for Logitech wheels that sends the wheel its own commands on
    // open; with it running, ARM killed the G29's force feedback until a replug. Force feedback belongs to
    // DirectInput (ffb_output), so that driver is off and every device DirectInput reads is hidden from SDL.
    sdl.SetHint("SDL_JOYSTICK_HIDAPI_LG4FF", "0");
    std::set<std::string> owned;
    { std::lock_guard lock(mutex_); owned = ownedElsewhere_; ownedChanged_ = false; }
    sdl.SetHint("SDL_JOYSTICK_IGNORE_DEVICES", ignoreHint(owned).c_str());
    if (!sdl.Init(kInitGamepad | kInitJoystick)) {
        const std::string why = narrow(sdl.GetError());
        setStatus("SDL_Init failed: " + why);
        if (log_) log_(true, "SDL3 init failed: " + why);
        FreeLibrary(impl.module);
        impl_ = nullptr;
        return;
    }
    available_ = true;
    setStatus("running");
    if (log_) log_(false, "SDL3 motion input started");

    auto discover = [&](const json& assignments) {
        // ---- gamepads: hands -------------------------------------------------------------------------
        int count = 0;
        SDL_JoystickID* ids = sdl.GetGamepads(&count);
        struct Entry { SDL_JoystickID id; int type; std::string serial, name; int player; };
        std::vector<Entry> entries;
        for (int i = 0; ids && i < count; ++i) {
            const int type = sdl.GetGamepadTypeForID(ids[i]);
            if (type != kTypeXbox360 && type != kTypeXboxOne && type != kTypePs4 && type != kTypePs5 &&
                type != kTypeSwitchPro && type != kTypeJoyConLeft && type != kTypeJoyConRight) continue;
            std::string serial;
            if (void* probe = sdl.OpenGamepad(ids[i])) { serial = narrow(sdl.GetGamepadSerial(probe)); sdl.CloseGamepad(probe); }
            if (serial.empty()) serial = "sdl-" + std::to_string(ids[i]);
            std::string name = narrow(sdl.GetGamepadNameForID(ids[i]));
            if (name.empty()) name = "Motion controller";
            entries.push_back({ids[i], type, serial, name, sdl.GetGamepadPlayerIndexForID(ids[i])});
        }
        if (ids) sdl.Free(ids);

        auto assigned = [&](const char* hand) { return assignments.is_object() ? assignments.value(hand, std::string("auto")) : std::string("auto"); };
        std::map<SDL_JoystickID, std::string> desired;
        std::set<std::string> blocked, taken;
        for (const char* hand : {"left", "right", "primary", "left_leg", "right_leg", "controller"}) {
            const std::string a = assigned(hand);
            if (a == "none") blocked.insert(hand);
            else if (a != "auto")
                for (const auto& e : entries) if (e.serial == a) { desired[e.id] = hand; taken.insert(hand); }
        }
        auto available = [&](const std::string& h) { return !blocked.count(h) && !taken.count(h); };
        auto give = [&](SDL_JoystickID id, const std::string& h) { desired[id] = h; taken.insert(h); };
        std::vector<Entry> generic;
        for (const auto& e : entries) {
            if (desired.count(e.id)) continue;
            // A second same-handedness Joy-Con is worn on that leg, keeping the first-seen one the hand-held one.
            if (e.type == kTypeJoyConLeft) { if (available("left")) give(e.id, "left"); else if (available("left_leg")) give(e.id, "left_leg"); }
            else if (e.type == kTypeJoyConRight) { if (available("right")) give(e.id, "right"); else if (available("right_leg")) give(e.id, "right_leg"); }
            // An Xbox pad reaches the game natively over XInput; it is only ever a hand if assigned by serial.
            else if (e.type == kTypePs4 || e.type == kTypePs5 || e.type == kTypeSwitchPro) generic.push_back(e);
        }
        std::sort(generic.begin(), generic.end(), [](const Entry& a, const Entry& b) {
            return (a.player >= 0 ? a.player : 99) < (b.player >= 0 ? b.player : 99);
        });
        if (generic.size() == 1 && desired.empty() && available("primary")) give(generic[0].id, "primary");
        else for (const auto& e : generic) {
            if (available("left")) give(e.id, "left");
            else if (available("right")) give(e.id, "right");
        }

        // Close pads whose assignment changed or that vanished; open the new ones with sensors on.
        for (auto it = impl.pads.begin(); it != impl.pads.end();) {
            auto d = desired.find(it->id);
            if (d != desired.end() && d->second == it->hand && sdl.GamepadConnected(it->handle)) { desired.erase(d); ++it; continue; }
            sdl.CloseGamepad(it->handle);
            it = impl.pads.erase(it);
        }
        for (const auto& [id, hand] : desired) {
            void* pad = sdl.OpenGamepad(id);
            if (!pad) continue;
            const Entry* e = nullptr;
            for (const auto& x : entries) if (x.id == id) e = &x;
            for (int sensor : {kSensorAccel, kSensorGyro})
                if (sdl.GamepadHasSensor(pad, sensor)) sdl.SetGamepadSensorEnabled(pad, sensor, true);
            impl.pads.push_back({pad, id, e ? e->serial : "", e ? e->name : "", e ? e->type : 0, hand});
            if (log_) log_(false, "SDL3 " + std::string(e ? e->name : "pad") + " [" + (e ? e->serial : "") + "] -> " + hand);
        }

        // ---- raw joysticks (not gamepads): the rim, a wheel base, pedals ------------------------------
        int jcount = 0;
        SDL_JoystickID* jids = sdl.GetJoysticks(&jcount);
        std::set<SDL_JoystickID> seen;
        for (int i = 0; jids && i < jcount; ++i) {
            if (sdl.IsGamepad(jids[i])) continue;
            // Belt and braces for the hint above (KB-209): a wheel base, pedals or a flight stick is
            // DirectInput's, and so is anything DirectInput already lists. Never opened, not even to read.
            const int jtype = sdl.GetJoystickTypeForID(jids[i]);
            if (jtype == kJoystickWheel || jtype == kJoystickThrottle || jtype == kJoystickFlightStick) continue;
            if (owned.count(vidPid(sdl.GetJoystickVendorForID(jids[i]), sdl.GetJoystickProductForID(jids[i])))) continue;
            seen.insert(jids[i]);
            if (std::any_of(impl.sticks.begin(), impl.sticks.end(), [&](const auto& s) { return s.id == jids[i]; })) continue;
            void* js = sdl.OpenJoystick(jids[i]);
            if (!js) continue;
            std::string name = narrow(sdl.GetJoystickNameForID(jids[i]));
            if (name.empty()) name = "Raw joystick";
            const std::string serial = narrow(sdl.GetJoystickSerial(js));
            const std::string key = "joystick:" + (serial.empty() ? name : serial);
            impl.sticks.push_back({js, jids[i], key, name, sdl.GetNumJoystickAxes(js), sdl.GetNumJoystickButtons(js),
                                   sdl.GetNumJoystickHats(js)});
            if (log_) log_(false, "SDL3 joystick " + key + " (" + std::to_string(impl.sticks.back().buttons) + " buttons)");
        }
        if (jids) sdl.Free(jids);
        for (auto it = impl.sticks.begin(); it != impl.sticks.end();) {
            if (seen.count(it->id) && sdl.JoystickConnected(it->handle)) { ++it; continue; }
            sdl.CloseJoystick(it->handle);
            it = impl.sticks.erase(it);
        }
    };

    auto readPad = [&](const Impl::Pad& p) {
        Sample s;
        s.tNs = nowNs();
        s.motion = sdl.GamepadHasSensor(p.handle, kSensorGyro);
        float data[3]{};
        if (sdl.GetGamepadSensorData(p.handle, kSensorAccel, data, 3)) s.accel = {data[0] / 9.80665f, data[1] / 9.80665f, data[2] / 9.80665f};
        if (sdl.GetGamepadSensorData(p.handle, kSensorGyro, data, 3)) {
            constexpr float kDeg = 57.2957795f;
            s.gyro = {data[0] * kDeg, data[1] * kDeg, data[2] * kDeg};
        }
        // JoyMoco's complementary filter: integrate gyro, pull pitch/roll toward the accelerometer at 2%.
        const int64_t last = impl.lastNs[p.hand];
        const float dt = last ? std::clamp((s.tNs - last) / 1e9f, 0.0f, 0.05f) : 0.0f;
        Vec3 o = impl.orientation[p.hand];
        o = {o.x + s.gyro.x * dt, o.y + s.gyro.y * dt, o.z + s.gyro.z * dt};
        const float a = std::fabs(s.accel.x) + std::fabs(s.accel.y) + std::fabs(s.accel.z);
        if (a > 0.1f) {
            const float pitch = std::atan2(s.accel.y, std::sqrt(s.accel.x * s.accel.x + s.accel.z * s.accel.z)) * 57.2957795f;
            const float roll = std::atan2(-s.accel.x, s.accel.z) * 57.2957795f;
            o = {o.x * 0.98f + pitch * 0.02f, o.y * 0.98f + roll * 0.02f, o.z};
        }
        impl.orientation[p.hand] = o;
        impl.lastNs[p.hand] = s.tNs;
        s.orientation = o;
        const auto& table = p.hand == "controller" ? kGamepadButtons : p.hand == "primary" ? kPrimaryButtons : kJoyConButtons;
        for (const auto& [index, name] : table) if (sdl.GetGamepadButton(p.handle, index)) s.buttons.insert(name);
        s.triggerLeft = axis(sdl.GetGamepadAxis(p.handle, kAxisLeftTrigger));
        s.triggerRight = axis(sdl.GetGamepadAxis(p.handle, kAxisRightTrigger));
        // A Joy-Con's ZL/ZR are digital; a DS4-shaped bridge reports them as a full-travel trigger.
        if (s.triggerLeft > 0.5f) s.buttons.insert("zl");
        if (s.triggerRight > 0.5f) s.buttons.insert("zr");
        if (sdl.GetNumGamepadTouchpads(p.handle) > 0) {
            bool down = false; float x = 0, y = 0, pressure = 0;
            if (sdl.GetGamepadTouchpadFinger(p.handle, 0, 0, &down, &x, &y, &pressure) && down) s.buttons.insert(x < 0.5f ? "sl" : "sr");
        }
        s.stickX = axis(sdl.GetGamepadAxis(p.handle, kAxisLeftX));
        s.stickY = -axis(sdl.GetGamepadAxis(p.handle, kAxisLeftY));
        s.stick2X = axis(sdl.GetGamepadAxis(p.handle, kAxisRightX));
        s.stick2Y = -axis(sdl.GetGamepadAxis(p.handle, kAxisRightY));
        return s;
    };

    auto readStick = [&](const Impl::Stick& j) {
        Sample s;
        s.tNs = nowNs();
        for (int i = 0; i < j.buttons; ++i) if (sdl.GetJoystickButton(j.handle, i)) s.buttons.insert("b" + std::to_string(i));
        for (int i = 0; i < j.hats; ++i) {
            const uint8_t hat = sdl.GetJoystickHat(j.handle, i);
            const std::string p = "hat" + std::to_string(i) + "_";
            if (hat & 1) s.buttons.insert(p + "up");
            if (hat & 2) s.buttons.insert(p + "right");
            if (hat & 4) s.buttons.insert(p + "down");
            if (hat & 8) s.buttons.insert(p + "left");
        }
        for (int i = 0; i < j.axes; ++i) s.axes.push_back(axis(sdl.GetJoystickAxis(j.handle, i)));
        return s;
    };

    json assignments;
    { std::lock_guard lock(mutex_); assignments = assignments_; assignmentsChanged_ = false; }
    discover(assignments);
    auto lastDiscover = std::chrono::steady_clock::now();
    while (running_.load()) {
        sdl.PumpEvents();
        sdl.UpdateGamepads();
        sdl.UpdateJoysticks();
        bool rediscover = std::chrono::steady_clock::now() - lastDiscover > std::chrono::seconds(1);
        std::vector<Rumble> rumbles;
        {
            std::lock_guard lock(mutex_);
            if (assignmentsChanged_) { assignments = assignments_; assignmentsChanged_ = false; rediscover = true; }
            if (ownedChanged_) { owned = ownedElsewhere_; ownedChanged_ = false; rediscover = true; }
            rumbles.swap(rumbles_);
        }
        if (rediscover) {
            sdl.SetHint("SDL_JOYSTICK_IGNORE_DEVICES", ignoreHint(owned).c_str());
            // A device DirectInput has since claimed is released here rather than kept open.
            for (auto it = impl.sticks.begin(); it != impl.sticks.end();) {
                if (!owned.count(vidPid(sdl.GetJoystickVendorForID(it->id), sdl.GetJoystickProductForID(it->id)))) { ++it; continue; }
                if (log_) log_(false, "SDL3 released " + it->key + ": DirectInput owns it");
                sdl.CloseJoystick(it->handle);
                it = impl.sticks.erase(it);
            }
            discover(assignments);
            lastDiscover = std::chrono::steady_clock::now();
        }
        for (const auto& r : rumbles)
            for (const auto& p : impl.pads)
                if (p.hand == r.hand)
                    sdl.RumbleGamepad(p.handle, static_cast<uint16_t>(std::clamp(r.low, 0.0f, 1.0f) * 65535),
                                      static_cast<uint16_t>(std::clamp(r.high, 0.0f, 1.0f) * 65535), r.ms);

        Samples next;
        json devices = json::array();
        for (const auto& p : impl.pads) {
            if (!sdl.GamepadConnected(p.handle)) continue;
            next[p.hand] = readPad(p);
            int battery = -1;
            sdl.GetGamepadPowerInfo(p.handle, &battery);
            devices.push_back({{"key", p.key}, {"name", p.name}, {"hand", p.hand}, {"kind", "gamepad"},
                               {"motion", next[p.hand].motion}, {"battery", battery}});
        }
        for (const auto& j : impl.sticks) {
            if (!sdl.JoystickConnected(j.handle)) continue;
            next[j.key] = readStick(j);
            devices.push_back({{"key", j.key}, {"name", j.name}, {"kind", "joystick"}, {"buttons", j.buttons},
                               {"axes", j.axes}, {"hats", j.hats}});
        }
        {
            std::lock_guard lock(mutex_);
            samples_ = std::move(next);
            devices_ = std::move(devices);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));   // ~200 Hz, JoyMoco's poll rate
    }

    for (auto& p : impl.pads) { sdl.RumbleGamepad(p.handle, 0, 0, 0); sdl.CloseGamepad(p.handle); }
    for (auto& j : impl.sticks) sdl.CloseJoystick(j.handle);
    sdl.Quit();
    FreeLibrary(impl.module);
    available_ = false;
    impl_ = nullptr;
    std::lock_guard lock(mutex_);
    samples_.clear();
    status_ = "stopped";
}

}  // namespace ncm::rig::pad
