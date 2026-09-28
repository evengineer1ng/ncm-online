#include "direct_input.hpp"

#include "feel.hpp"
#include "log.hpp"
#include "mapping.hpp"
#include "state.hpp"

#include <dinput.h>
#include <windows.h>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cctype>
#include <mutex>
#include <vector>

namespace ncm::rig {
namespace {
using Clock = std::chrono::steady_clock;

std::string utf8(const wchar_t* value)
{
    if (!value) return {};
    const int count = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
    if (count <= 1) return {};
    std::string out(static_cast<size_t>(count), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value, -1, out.data(), count, nullptr, nullptr);
    out.pop_back();
    return out;
}

std::string guidText(const GUID& guid)
{
    wchar_t buffer[64]{};
    StringFromGUID2(guid, buffer, static_cast<int>(std::size(buffer)));
    return utf8(buffer);
}

bool containsInsensitive(const std::string& text, const std::string& needle)
{
    if (needle.empty()) return true;
    return std::search(text.begin(), text.end(), needle.begin(), needle.end(), [](char a, char b) {
        return std::tolower(static_cast<unsigned char>(a)) == std::tolower(static_cast<unsigned char>(b));
    }) != text.end();
}

HWND gameWindow()
{
    struct Search { DWORD pid; HWND result; } search{GetCurrentProcessId(), nullptr};
    EnumWindows([](HWND window, LPARAM value) -> BOOL {
        auto* s = reinterpret_cast<Search*>(value);
        DWORD pid = 0;
        GetWindowThreadProcessId(window, &pid);
        if (pid == s->pid && IsWindowVisible(window)) { s->result = window; return FALSE; }
        return TRUE;
    }, reinterpret_cast<LPARAM>(&search));
    return search.result ? search.result : GetDesktopWindow();
}

LONG axisValue(const DIJOYSTATE2& s, const std::string& name)
{
    if (name == "x") return s.lX;
    if (name == "y") return s.lY;
    if (name == "z") return s.lZ;
    if (name == "rx") return s.lRx;
    if (name == "ry") return s.lRy;
    if (name == "rz") return s.lRz;
    if (name == "slider0") return s.rglSlider[0];
    if (name == "slider1") return s.rglSlider[1];
    return 32767;
}

void sendKey(uint16_t key, bool down)
{
    INPUT input{};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = key;
    input.ki.dwFlags = down ? 0 : KEYEVENTF_KEYUP;
    SendInput(1, &input, sizeof(input));
}
}

struct DirectInputRig::Impl {
    struct Device {
        GUID instance{};
        GUID product{};
        std::string guid;        // instance -- CHANGES between sessions, never persist it
        std::string key;         // "VID:PID" (+ "#n" for identical twins) -- stable, persist this
        std::string name;
        bool ffb = false;
        bool virtualDevice = false;
        bool wheel = false;      // DI8DEVTYPE_DRIVING -- the device says it is a wheel
        bool gamepad = false;    // DI8DEVTYPE_GAMEPAD -- must never be auto-bound as steering
        IDirectInputDevice8W* handle = nullptr;
        DIJOYSTATE2 state{};
        bool current = false;
    };

    explicit Impl(Config value) : config(std::move(value)) {}
    ~Impl() { shutdown(); }

    Config config;
    IDirectInput8W* api = nullptr;
    std::vector<Device> devices;
    std::atomic<bool> running{false};
    std::thread thread;
    mutable std::mutex mutex;
    std::atomic<bool> ffbEnabled{true};
    std::atomic<bool> ffbArmed{false};
    std::atomic<float> ffbStrength{feel::kFloor};
    std::atomic<float> springStrength{0.55f};
    std::atomic<float> damperStrength{0.35f};
    std::atomic<float> textureTune{0.60f};
    std::atomic<float> engineTune{0.45f};
    std::atomic<float> roadTune{1.00f};
    std::atomic<float> pulse{0.0f};
    std::atomic<int64_t> pulseUntilMs{0};
    IDirectInputEffect* spring = nullptr;
    IDirectInputEffect* damper = nullptr;
    IDirectInputEffect* constant = nullptr;
    IDirectInputEffect* sine = nullptr;
    Device* ffbDevice = nullptr;
    bool warnedNoFfb = false;
    bool effectsRunning_ = false;   // spring/damper are STOPPED; they need restarting, not just updating
    uint32_t offered = 0;   // how many DirectInput handed us before any were rejected
    uint64_t sequence = 0;
    std::vector<bool> priorButtons;

    // Slewed outputs. These persist between ticks on purpose: an unreadable frame HOLDS the last force
    // rather than dropping it to zero, which would read as the wheel dying every time a packet was late.
    float level_ = 0.0f;
    float torque_ = 0.0f;
    float revs_ = 0.0f;
    Clock::time_point lastTick_{};
    uint32_t lastPeriod_ = 0;
    // What the device was last TOLD, so an unchanged value is never re-sent. -1 means "unknown: send".
    float sentSine_ = -1.0f;
    float sentConstant_ = -2.0f;
    bool quiet_ = false;           // stopEffects already ran; repeating it every tick only floods the driver

    // What each channel actually reached this session, so the road scale can be set from evidence rather
    // than taste. Printed once at teardown -- a channel that peaked near zero was never felt.
    struct Peak { float max = 0.0f; uint64_t frames = 0; };
    Peak peakTexture, peakTorque, peakRoad, peakSlip, peakCollision;
    static void observe(Peak& p, float v) { const float a = std::fabs(v); if (a > p.max) p.max = a; ++p.frames; }

    static BOOL CALLBACK enumerateCallback(const DIDEVICEINSTANCEW* value, void* context)
    {
        auto* self = static_cast<Impl*>(context);
        ++self->offered;
        Device d;
        d.instance = value->guidInstance;
        d.product = value->guidProduct;
        d.guid = guidText(value->guidInstance);
        d.name = utf8(value->tszProductName);
        char key[32]{};
        std::snprintf(key, sizeof(key), "%04X:%04X",
                      static_cast<unsigned>(value->guidProduct.Data1 & 0xFFFFu),
                      static_cast<unsigned>((value->guidProduct.Data1 >> 16) & 0xFFFFu));
        d.key = key;
        // Two identical devices (a pair of matching pedal sets) share a VID:PID, so the second gets a
        // suffix. Order comes from enumeration, which is stable for as long as both stay plugged in.
        int twins = 0;
        for (const auto& other : self->devices) if (other.key.rfind(d.key, 0) == 0) ++twins;
        if (twins > 0) d.key += "#" + std::to_string(twins + 1);
        d.virtualDevice = containsInsensitive(d.name, "vjoy") || containsInsensitive(d.name, "vigem") ||
                          containsInsensitive(d.name, "virtual");
        const DWORD kind = value->dwDevType & 0xFF;
        d.wheel = kind == DI8DEVTYPE_DRIVING;
        d.gamepad = kind == DI8DEVTYPE_GAMEPAD;
        // **Every rejection is logged.** These two failures used to `return DIENUM_CONTINUE` silently, so a
        // device DirectInput DID offer -- but which could not be opened, because something else in this
        // process already holds it -- was indistinguishable in the log from a device that was never
        // attached at all. "Why can it not see my pedals" has to be answerable from the log.
        const HRESULT created = self->api->CreateDevice(d.instance, &d.handle, nullptr);
        if (FAILED(created)) {
            RIG_WARN("device %s | %s | OFFERED but CreateDevice failed: 0x%08lX", d.key.c_str(),
                     d.name.c_str(), created);
            return DIENUM_CONTINUE;
        }
        const HRESULT formatted = d.handle->SetDataFormat(&c_dfDIJoystick2);
        if (FAILED(formatted)) {
            RIG_WARN("device %s | %s | OFFERED but SetDataFormat failed: 0x%08lX", d.key.c_str(),
                     d.name.c_str(), formatted);
            d.handle->Release();
            return DIENUM_CONTINUE;
        }
        DIDEVCAPS caps{};
        caps.dwSize = sizeof(caps);
        if (SUCCEEDED(d.handle->GetCapabilities(&caps))) d.ffb = (caps.dwFlags & DIDC_FORCEFEEDBACK) != 0;
        DIPROPRANGE range{};
        range.diph.dwSize = sizeof(range);
        range.diph.dwHeaderSize = sizeof(range.diph);
        range.diph.dwHow = DIPH_DEVICE;
        range.lMin = 0;
        range.lMax = 65535;
        d.handle->SetProperty(DIPROP_RANGE, &range.diph);
        const HRESULT coop = d.handle->SetCooperativeLevel(gameWindow(), DISCL_NONEXCLUSIVE | DISCL_BACKGROUND);
        const HRESULT acquired = d.handle->Acquire();
        if (FAILED(coop) || FAILED(acquired))
            RIG_WARN("device %s | %s | opened but coop=0x%08lX acquire=0x%08lX -- it may be held by "
                     "another process or plugin", d.key.c_str(), d.name.c_str(), coop, acquired);
        RIG_INFO("device %s | %s | type=%s ffb=%s virtual=%s", d.key.c_str(), d.name.c_str(),
                 d.wheel ? "wheel" : (d.gamepad ? "gamepad" : "other"),
                 d.ffb ? "yes" : "no", d.virtualDevice ? "yes" : "no");
        self->devices.push_back(std::move(d));
        return DIENUM_CONTINUE;
    }

    bool initialize()
    {
        const HRESULT result = DirectInput8Create(GetModuleHandleW(nullptr), DIRECTINPUT_VERSION,
                                                   IID_IDirectInput8W, reinterpret_cast<void**>(&api), nullptr);
        if (FAILED(result)) { RIG_ERR("DirectInput8Create failed: 0x%08lX", result); return false; }
        offered = 0;
        api->EnumDevices(DI8DEVCLASS_GAMECTRL, enumerateCallback, this, DIEDFL_ATTACHEDONLY);
        RIG_INFO("DirectInput offered %u device(s); %zu usable", offered, devices.size());
        if (devices.empty()) RIG_WARN("no DirectInput game controllers found");
        // If this process sees fewer than a standalone enumeration does, something in-process is holding
        // them -- run ncm_rig_devices.exe beside the game and compare the two lists.
        selectFfbDevice();
        priorButtons.assign(config.buttons.size(), false);
        return true;
    }

    enum class Role { Steering, Pedal, Button, Ffb };

    /// **An explicit binding that does not match resolves to NOTHING.** The old fallback ended in
    /// "return the first non-virtual device", which meant a pedal binding whose device was absent quietly
    /// resolved to whatever was first in the list -- an Xbox pad -- and then reported the rig as complete,
    /// which stopped the rescan that would have found the real pedals when they arrived. A role that
    /// cannot be filled must stay empty and say so.
    Device* select(const std::string& key, const std::string& guid, const std::string& name, Role role)
    {
        if (!key.empty()) {
            for (auto& d : devices) if (d.key == key) return &d;
            // A key with no twin suffix should still match the first of a pair.
            for (auto& d : devices) if (d.key.rfind(key + "#", 0) == 0) return &d;
        }
        if (!guid.empty())
            for (auto& d : devices) if (containsInsensitive(d.guid, guid)) return &d;
        if (!name.empty())
            for (auto& d : devices) if (containsInsensitive(d.name, name)) return &d;

        if (!key.empty() || !guid.empty() || !name.empty()) return nullptr;   // asked for; not here.

        // Nothing was configured. Adopt only what a device says about ITSELF.
        if (role == Role::Steering || role == Role::Ffb) {
            for (auto& d : devices) if (d.wheel && !d.virtualDevice) return &d;
            for (auto& d : devices) if (d.ffb && !d.virtualDevice) return &d;
            return nullptr;
        }
        // A pedal set and a gamepad are indistinguishable by enumeration, so a pedal is NEVER adopted on
        // a guess -- binding one wrong means the throttle is held down by a controller sitting on a desk.
        return nullptr;
    }

    Device* bindingDevice(const AxisBinding& b, Role role)
    {
        return select(b.deviceKey, b.deviceGuid, b.deviceName, role);
    }

    /// Every role that CAN be filled, is. This drives the rescan, so it must not be satisfiable by a
    /// device that merely happens to be plugged in.
    /// Counting is not opening. A full rebuild releases and re-acquires every endpoint, which drops the
    /// live force-feedback effects -- doing that on a timer would make the wheel stutter every two
    /// seconds. Enumeration on its own disturbs nothing, so the cheap count decides whether the
    /// expensive rebuild is warranted.
    static BOOL CALLBACK countCallback(const DIDEVICEINSTANCEW*, void* context)
    {
        ++*static_cast<uint32_t*>(context);
        return DIENUM_CONTINUE;
    }

    bool deviceSetChanged()
    {
        uint32_t now = 0;
        api->EnumDevices(DI8DEVCLASS_GAMECTRL, countCallback, &now, DIEDFL_ATTACHEDONLY);
        return now != offered;
    }

    bool rigComplete()
    {
        if (!bindingDevice(config.steering, Role::Steering)) return false;
        for (const auto* b : {&config.throttle, &config.brake, &config.clutch}) {
            const bool wanted = !b->deviceKey.empty() || !b->deviceGuid.empty() || !b->deviceName.empty();
            if (wanted && !bindingDevice(*b, Role::Pedal)) return false;
        }
        if (!config.ffbDeviceKey.empty() && !ffbDevice) return false;
        for (const auto& b : config.buttons)
            if (!b.deviceKey.empty() && !select(b.deviceKey, b.deviceGuid, "", Role::Button)) return false;
        return true;
    }

    void selectFfbDevice()
    {
        ffbDevice = select(config.ffbDeviceKey, config.ffbDeviceGuid, config.ffbDeviceName, Role::Ffb);
        if (!ffbDevice || !ffbDevice->ffb) {
            ffbDevice = nullptr;
            if (!warnedNoFfb) { warnedNoFfb = true; RIG_WARN("no force-feedback DirectInput device selected"); }
            return;
        }
        warnedNoFfb = false;
        ffbDevice->handle->Unacquire();
        const HRESULT coop = ffbDevice->handle->SetCooperativeLevel(gameWindow(), DISCL_EXCLUSIVE | DISCL_BACKGROUND);
        const HRESULT acquired = SUCCEEDED(coop) ? ffbDevice->handle->Acquire() : coop;
        if (FAILED(acquired)) {
            RIG_WARN("FFB device %s could not acquire exclusively: 0x%08lX", ffbDevice->name.c_str(), acquired);
            ffbDevice->handle->SetCooperativeLevel(gameWindow(), DISCL_NONEXCLUSIVE | DISCL_BACKGROUND);
            ffbDevice->handle->Acquire();
            ffbDevice = nullptr;
            return;
        }
        createEffects();
    }

    void releaseDevices()
    {
        stopEffects();
        // Release, never merely stop: a DirectInput effect can outlive the process that created it, and a
        // wheel left powered and pulling to one side after the game exits is the worst failure here.
        if (sine) { sine->Release(); sine = nullptr; }
        if (constant) { constant->Release(); constant = nullptr; }
        if (spring) { spring->Release(); spring = nullptr; }
        if (damper) { damper->Release(); damper = nullptr; }
        ffbDevice = nullptr;
        for (auto& d : devices) if (d.handle) { d.handle->Unacquire(); d.handle->Release(); }
        devices.clear();
    }

    void rebuildDevices()
    {
        std::lock_guard lock(mutex);
        for (size_t i = 0; i < priorButtons.size(); ++i) if (priorButtons[i]) sendKey(config.buttons[i].virtualKey, false);
        std::fill(priorButtons.begin(), priorButtons.end(), false);
        const size_t before = devices.size();
        releaseDevices();
        offered = 0;
        api->EnumDevices(DI8DEVCLASS_GAMECTRL, enumerateCallback, this, DIEDFL_ATTACHEDONLY);
        selectFfbDevice();
        // A rescan that found the same nothing is not news, and at one line every two seconds it buries
        // the lines that are. Say it only when the set actually changed.
        if (devices.size() != before)
            RIG_INFO("device set changed: %zu -> %zu endpoint(s)", before, devices.size());
    }

    void createEffects()
    {
        DWORD axes[1] = {DIJOFS_X};
        LONG direction[1] = {0};
        DIEFFECT effect{};
        effect.dwSize = sizeof(effect);
        effect.dwFlags = DIEFF_CARTESIAN | DIEFF_OBJECTOFFSETS;
        effect.dwDuration = INFINITE;
        effect.dwGain = DI_FFNOMINALMAX;
        effect.dwTriggerButton = DIEB_NOTRIGGER;
        effect.cAxes = 1;
        effect.rgdwAxes = axes;
        effect.rglDirection = direction;
        DICONDITION condition{};
        effect.cbTypeSpecificParams = sizeof(condition);
        effect.lpvTypeSpecificParams = &condition;
        if (FAILED(ffbDevice->handle->CreateEffect(GUID_Spring, &effect, &spring, nullptr))) spring = nullptr;
        if (FAILED(ffbDevice->handle->CreateEffect(GUID_Damper, &effect, &damper, nullptr))) damper = nullptr;
        DICONSTANTFORCE force{};
        effect.cbTypeSpecificParams = sizeof(force);
        effect.lpvTypeSpecificParams = &force;
        if (FAILED(ffbDevice->handle->CreateEffect(GUID_ConstantForce, &effect, &constant, nullptr))) constant = nullptr;

        // **The texture carrier.** 125 Hz is not arbitrary: the companion's first attempt at 25 Hz felt
        // like a rumble pack, and 125 Hz is the difference between "a motor is running" and "the tyres are
        // letting go". The period is re-modulated per tick from engine revs; this is only the seed.
        DIPERIODIC periodic{};
        periodic.dwMagnitude = 0;
        periodic.lOffset = 0;
        periodic.dwPhase = 0;
        periodic.dwPeriod = feel::enginePeriodMicros(0.0f);
        effect.cbTypeSpecificParams = sizeof(periodic);
        effect.lpvTypeSpecificParams = &periodic;
        if (FAILED(ffbDevice->handle->CreateEffect(GUID_Sine, &effect, &sine, nullptr))) sine = nullptr;

        RIG_INFO("FFB output %s: spring=%s damper=%s constant=%s sine=%s", ffbDevice->name.c_str(),
                 spring ? "yes" : "no", damper ? "yes" : "no", constant ? "yes" : "no", sine ? "yes" : "no");
        applyConditions();
        if (!sine) RIG_WARN("no SINE effect: road texture and slip cannot be felt on this device");
        if (!constant) RIG_WARN("no CONSTANT effect: self-aligning torque and collision jolts are unavailable");
    }

    void stopEffects()
    {
        if (quiet_) return;
        // Zero the magnitudes FIRST, then stop. Stopping an effect that still holds a level has been
        // observed to leave that level applied on the device.
        sentSine_ = -1.0f; sentConstant_ = -2.0f;   // force the zero writes through
        writeConstant(0.0f);
        writeSine(0.0f, lastPeriod_ ? lastPeriod_ : feel::enginePeriodMicros(0.0f));
        if (sine) sine->Stop();
        if (constant) constant->Stop();
        if (spring) spring->Stop();
        if (damper) damper->Stop();
        level_ = 0.0f;
        torque_ = 0.0f;
        effectsRunning_ = false;
        quiet_ = true;
    }

    /// Start the two DYNAMIC effects exactly once per run. They are then only ever UPDATED in place.
    void startDynamic()
    {
        sentSine_ = -1.0f; sentConstant_ = -2.0f;
        writeSine(0.0f, lastPeriod_ ? lastPeriod_ : feel::enginePeriodMicros(0.0f));
        writeConstant(0.0f);
        if (sine) sine->Start(1, 0);
        if (constant) constant->Start(1, 0);
    }

    /// **Update in place; never restart.** `DIEP_START` on a playing effect RESTARTS it, and a restarted
    /// sine begins again at phase 0. The port sent it on every 250 Hz tick, so a 21-83 ms engine wave was
    /// reset every 4 ms and never got past the first sliver of its cycle -- the telemetry peaked at 1.0
    /// while the rim felt nothing. The companion always did it this way: run once, then
    /// `SDL_HapticUpdateEffect` only when the value moved by 0.005 or more.
    static HRESULT updateInPlace(IDirectInputEffect* effect, DIEFFECT& params)
    {
        HRESULT hr = effect->SetParameters(&params, DIEP_TYPESPECIFICPARAMS | DIEP_NORESTART);
        // Some drivers cannot change a periodic's PERIOD while it plays. Only then, restart -- and the
        // period is quantised below, so this happens on a rev change, not on every tick.
        if (hr == DIERR_EFFECTPLAYING) hr = effect->SetParameters(&params, DIEP_TYPESPECIFICPARAMS | DIEP_START);
        return hr;
    }

    static void conditionEffect(IDirectInputEffect* effect, float coefficient)
    {
        if (!effect) return;
        const LONG value = static_cast<LONG>(std::clamp(coefficient, 0.0f, 1.0f) * 10000.0f);
        DICONDITION condition{};
        condition.lPositiveCoefficient = value;
        condition.lNegativeCoefficient = value;
        condition.dwPositiveSaturation = 10000;
        condition.dwNegativeSaturation = 10000;
        DIEFFECT params{};
        params.dwSize = sizeof(params);
        params.cbTypeSpecificParams = sizeof(condition);
        params.lpvTypeSpecificParams = &condition;
        effect->SetParameters(&params, DIEP_TYPESPECIFICPARAMS | DIEP_START);
    }

    /// Spring and damper are STIFFNESS, and stiffness is a standing property of the wheel -- it is set
    /// when a slider moves, never per frame. Rewriting a condition effect at 250 Hz makes it fight the
    /// driver's own hands instead of resisting them.
    void applyConditions()
    {
        if (!ffbDevice) return;
        const bool live = ffbEnabled.load() && ffbArmed.load();
        const float rung = ffbStrength.load();
        const float ceiling = feel::ceilingFor(config.deviceClass);
        const float scale = ceiling > 0.0f ? std::clamp(rung / ceiling, 0.0f, 1.0f) : 0.0f;
        conditionEffect(spring, live ? springStrength.load() * scale : 0.0f);
        conditionEffect(damper, live ? damperStrength.load() * scale : 0.0f);
    }

    void writeConstant(float signedMagnitude)
    {
        if (!constant) return;
        const float value = std::clamp(signedMagnitude, -1.0f, 1.0f);
        if (std::fabs(value - sentConstant_) < 0.002f) return;
        sentConstant_ = value;
        DICONSTANTFORCE force{static_cast<LONG>(value * 10000.0f)};
        DIEFFECT params{};
        params.dwSize = sizeof(params);
        params.cbTypeSpecificParams = sizeof(force);
        params.lpvTypeSpecificParams = &force;
        updateInPlace(constant, params);
    }

    void writeSine(float magnitude, uint32_t periodMicros)
    {
        if (!sine) return;
        const float value = std::clamp(magnitude, 0.0f, 1.0f);
        // Quantise the engine period to 1 ms so rising revs step the hum instead of rewriting it per tick.
        periodMicros = std::max<uint32_t>(1000, (periodMicros + 500) / 1000 * 1000);
        if (std::fabs(value - sentSine_) < 0.002f && periodMicros == lastPeriod_) return;
        sentSine_ = value;
        DIPERIODIC periodic{};
        periodic.dwMagnitude = static_cast<DWORD>(value * 10000.0f);
        periodic.lOffset = 0;
        periodic.dwPhase = 0;
        periodic.dwPeriod = periodMicros;
        DIEFFECT params{};
        params.dwSize = sizeof(params);
        params.cbTypeSpecificParams = sizeof(periodic);
        params.lpvTypeSpecificParams = &periodic;
        updateInPlace(sine, params);
        lastPeriod_ = periodMicros;
    }

    /// The single point where a level becomes force. Nothing else in this class touches the device, so
    /// "is force being applied?" has exactly one answer to check.
    void updateEffects()
    {
        const auto now = Clock::now();
        const float dt = lastTick_.time_since_epoch().count() == 0
            ? 0.004f
            : std::chrono::duration<float>(now - lastTick_).count();
        lastTick_ = now;

        if (!ffbDevice || !ffbEnabled.load() || !ffbArmed.load()) { stopEffects(); return; }
        // **Spring and damper must be RESTARTED, not merely left configured.** `stopEffects` stops all
        // four -- correct, because a stale telemetry feed must not keep pushing -- but the condition
        // effects were only ever (re)started from `applyConditions`, which runs when a slider moves. So
        // the first dismount or dropped frame killed centring for the rest of the session and the wheel
        // went light and stayed light. Anything that stops them owes them a start.
        if (!effectsRunning_) { applyConditions(); startDynamic(); effectsRunning_ = true; quiet_ = false; }

        const auto nowMs = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
        const bool testing = nowMs < pulseUntilMs.load();
        const auto frame = state().feedback();

        // The watchdog. Telemetry that has gone stale is NOT a car sitting still -- it is a car we can no
        // longer see, and holding the last frame would keep pushing at the wheel of a car that may have
        // stopped, crashed or been left behind entirely.
        const bool current = frame.updated.time_since_epoch().count() != 0 &&
            std::chrono::duration_cast<std::chrono::milliseconds>(now - frame.updated).count() <= config.ffbWatchdogMs;
        if ((!frame.inVehicle || !current) && !testing) { stopEffects(); return; }

        const feel::DeviceClass cls = config.deviceClass;
        const float rung = ffbStrength.load();

        feel::Tune tune;
        tune.spring = springStrength.load();
        tune.damper = damperStrength.load();
        tune.texture = textureTune.load();
        tune.engine = engineTune.load();
        tune.road = roadTune.load();

        // A TEST PULSE is a deliberate, bounded jolt at the current rung -- it must not also spin up the
        // road and engine channels, or "does force reach this device at all?" stops being answerable.
        if (testing) {
            level_ = feel::slew(level_, 0.0f, dt);
            torque_ = feel::slew(torque_, pulse.load(), dt);
            writeSine(feel::clampToClass(cls, level_), feel::enginePeriodMicros(0.0f));
            writeConstant(feel::clampToClass(cls, torque_));
            return;
        }

        const auto mixed = feel::mix(frame.telemetry, tune);
        if (mixed.readable) {
            level_ = feel::slew(level_, mixed.intensity * rung, dt);
            torque_ = feel::slew(torque_, mixed.torque * rung, dt);
            if (frame.telemetry.hasEngine) revs_ = std::clamp(frame.telemetry.engine, 0.0f, 1.0f);
            observe(peakTexture, mixed.intensity);
            observe(peakTorque, mixed.torque);
            if (frame.telemetry.hasSuspLong) observe(peakRoad, frame.telemetry.suspLong);
            if (frame.telemetry.hasSuspLat) observe(peakRoad, frame.telemetry.suspLat);
            if (frame.telemetry.hasSlipTotal) observe(peakSlip, frame.telemetry.slipTotal);
        }
        // else: HOLD. An unreadable frame is not a zero frame.

        // The jolt rides ON TOP of the self-aligning torque rather than replacing it, because a real
        // impact does not suspend the castor -- it arrives through it.
        const float jolt = state().collisionAt(now);
        if (jolt != 0.0f) observe(peakCollision, jolt);

        writeSine(feel::clampToClass(cls, level_), feel::enginePeriodMicros(revs_));
        writeConstant(feel::clampToClass(cls, torque_ + jolt * rung));
    }

    /// Printed once at teardown, where it cannot be missed. A channel whose peak sits near zero was
    /// inaudible for the whole session, and that is a tuning fact no amount of reasoning replaces.
    void reportPeaks()
    {
        if (peakTexture.frames == 0) return;
        auto say = [](const char* name, const Peak& p) {
            RIG_INFO("measured %s: peak %.5f over %llu frame(s)%s", name, p.max,
                     static_cast<unsigned long long>(p.frames),
                     p.max < 0.05f ? "  <-- too small to feel" : "");
        };
        say("texture(mix)", peakTexture);
        say("torque(align)", peakTorque);
        say("road(susp)", peakRoad);
        say("slip", peakSlip);
        say("collision", peakCollision);
    }

    bool poll(Device& d)
    {
        HRESULT hr = d.handle->Poll();
        if (FAILED(hr)) { d.handle->Acquire(); hr = d.handle->Poll(); }
        d.current = SUCCEEDED(hr) && SUCCEEDED(d.handle->GetDeviceState(sizeof(d.state), &d.state));
        return d.current;
    }

    void dispatchButtons()
    {
        for (size_t i = 0; i < config.buttons.size(); ++i) {
            const auto& bind = config.buttons[i];
            auto* device = select(bind.deviceKey, bind.deviceGuid, bind.deviceName, Role::Button);
            const bool down = device && device->current && (device->state.rgbButtons[bind.button] & 0x80) != 0 &&
                              (!bind.vehicleOnly || state().playerVehicle() != nullptr);
            if (down != priorButtons[i]) { sendKey(bind.virtualKey, down); priorButtons[i] = down; }
        }
    }

    void run()
    {
        RIG_INFO("input pump started at 250 Hz");
        // **Rescan while anything is still missing, not while the bound device is silent.** Keying the
        // rescan off "the selected steering device is not responding" meant that once ANY device was
        // bound the search stopped -- so hardware powered on after the game was never found. A rig is a
        // set of devices that arrive at different times; keep looking until the set is complete.
        uint32_t ticksSinceScan = 0;
        constexpr uint32_t kRescanTicks = 500;       // ~2 s at 250 Hz
        bool announcedComplete = false;
        while (running.load(std::memory_order_acquire)) {
            bool wheelCurrent = false;
            {
                std::lock_guard lock(mutex);
                bool any = false;
                for (auto& d : devices) any = poll(d) || any;
                auto* wheel = bindingDevice(config.steering, Role::Steering);
                auto* throttle = bindingDevice(config.throttle, Role::Pedal);
                auto* brake = bindingDevice(config.brake, Role::Pedal);
                auto* clutch = bindingDevice(config.clutch, Role::Pedal);
                InputFrame frame;
                frame.connected = any && wheel && wheel->current;
                wheelCurrent = frame.connected;
                frame.sequence = ++sequence;
                if (frame.connected) {
                    frame.steering = mapAxis(static_cast<uint32_t>(axisValue(wheel->state, config.steering.axis)), config.steering, true, config.steerScale());
                    frame.steering = std::copysign(std::pow(std::fabs(frame.steering), config.steeringGamma), frame.steering);
                    if (throttle && throttle->current) frame.throttle = mapAxis(static_cast<uint32_t>(axisValue(throttle->state, config.throttle.axis)), config.throttle, false);
                    if (brake && brake->current) frame.brake = mapAxis(static_cast<uint32_t>(axisValue(brake->state, config.brake.axis)), config.brake, false);
                    if (clutch && clutch->current) frame.clutch = mapAxis(static_cast<uint32_t>(axisValue(clutch->state, config.clutch.axis)), config.clutch, false);
                }
                state().publishInput(frame);
                dispatchButtons();
                updateEffects();
            }
            (void)wheelCurrent;
            bool complete;
            { std::lock_guard lock(mutex); complete = rigComplete(); }
            if (complete != announcedComplete) {
                announcedComplete = complete;
                RIG_INFO("rig %s", complete ? "COMPLETE -- every expected endpoint is bound"
                                            : "incomplete -- still scanning for missing endpoint(s)");
            }
            // **Rescan on hardware arriving, not on the rig looking unfinished.** Keying this to
            // `complete` meant that a rig with nothing bound yet counted as finished and stopped looking,
            // so pedals plugged in after launch were never picked up -- the same stall as before, one
            // door along. What matters is whether the device set moved.
            if (++ticksSinceScan >= kRescanTicks) {
                ticksSinceScan = 0;
                bool changed;
                { std::lock_guard lock(mutex); changed = deviceSetChanged(); }
                if (changed || !complete) rebuildDevices();
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(4));
        }
        for (size_t i = 0; i < priorButtons.size(); ++i) if (priorButtons[i]) sendKey(config.buttons[i].virtualKey, false);
        stopEffects();
        reportPeaks();
        RIG_INFO("input pump stopped");
    }

    void shutdown()
    {
        running.store(false);
        if (thread.joinable()) thread.join();
        releaseDevices();
        if (api) { api->Release(); api = nullptr; }
    }

    std::string json() const
    {
        std::lock_guard lock(mutex);
        nlohmann::json root{{"provider", "directinput"}, {"ffb", ffbDevice != nullptr},
                            {"ffbArmed", ffbArmed.load()}, {"devices", nlohmann::json::array()}};
        static const char* kAxisNames[8] = {"x","y","z","rx","ry","rz","slider0","slider1"};
        for (const auto& d : devices) {
            // Live, normalised axis values. Without these a dropdown is a guessing game: nothing tells
            // you which of a pedal set's three axes is the brake except watching one move.
            nlohmann::json axes = nlohmann::json::object();
            const LONG raw[8] = {d.state.lX, d.state.lY, d.state.lZ, d.state.lRx, d.state.lRy, d.state.lRz,
                                 d.state.rglSlider[0], d.state.rglSlider[1]};
            for (int a = 0; a < 8; ++a)
                axes[kAxisNames[a]] = std::clamp(static_cast<float>(raw[a]) / 65535.0f, 0.0f, 1.0f);
            root["devices"].push_back({{"id", d.key}, {"name", d.name}, {"guid", d.guid},
                {"wheel", d.wheel}, {"gamepad", d.gamepad}, {"ffb", d.ffb},
                {"live", d.current}, {"axes", axes}});
        }
        auto* self = const_cast<Impl*>(this);
        auto roleOf = [&](const AxisBinding& b, Role role) -> nlohmann::json {
            auto* d = self->select(b.deviceKey, b.deviceGuid, b.deviceName, role);
            const bool wanted = !b.deviceKey.empty() || !b.deviceGuid.empty() || !b.deviceName.empty();
            return {{"device", d ? d->key : std::string()}, {"name", d ? d->name : std::string()},
                    {"axis", b.axis}, {"invert", b.invert}, {"deadzone", b.deadzone},
                    {"bound", d != nullptr},
                    // "configured but absent" is a different problem from "never configured", and the
                    // panel must be able to say which.
                    {"missing", wanted && d == nullptr}};
        };
        root["roles"] = {{"steering", roleOf(config.steering, Role::Steering)},
                         {"throttle", roleOf(config.throttle, Role::Pedal)},
                         {"brake", roleOf(config.brake, Role::Pedal)},
                         {"clutch", roleOf(config.clutch, Role::Pedal)},
                         {"ffb", {{"device", ffbDevice ? ffbDevice->key : std::string()},
                                  {"name", ffbDevice ? ffbDevice->name : std::string()},
                                  {"bound", ffbDevice != nullptr}}}};
        return root.dump();
    }
};

DirectInputRig::DirectInputRig(Config config) : impl_(std::make_unique<Impl>(std::move(config)))
{
    impl_->ffbEnabled.store(impl_->config.ffbEnabled);
    impl_->ffbArmed.store(impl_->config.ffbArmed);
    impl_->ffbStrength.store(std::clamp(impl_->config.ffbStrength, 0.0f,
                                        feel::ceilingFor(impl_->config.deviceClass)));
    impl_->springStrength.store(impl_->config.tune.spring);
    impl_->damperStrength.store(impl_->config.tune.damper);
    impl_->textureTune.store(impl_->config.tune.texture);
    impl_->engineTune.store(impl_->config.tune.engine);
    impl_->roadTune.store(impl_->config.tune.road);
}
DirectInputRig::~DirectInputRig() = default;
bool DirectInputRig::start()
{
    if (!impl_->initialize()) return false;
    impl_->running.store(true);
    impl_->thread = std::thread([this] { impl_->run(); });
    return true;
}
void DirectInputRig::stop() { impl_->shutdown(); }
void DirectInputRig::setFfbEnabled(bool value) { impl_->ffbEnabled.store(value); impl_->applyConditions(); }
void DirectInputRig::setFfbArmed(bool value) { impl_->ffbArmed.store(value); impl_->applyConditions(); RIG_INFO("FFB %s", value ? "ARMED" : "DISARMED"); }
void DirectInputRig::setFfbStrength(float value)
{
    // The ONE place a rung becomes real. Everything upstream -- panel, config, defaults -- passes through
    // here, so the class ceiling cannot be routed around.
    impl_->ffbStrength.store(std::clamp(value, 0.0f, feel::ceilingFor(impl_->config.deviceClass)));
    impl_->applyConditions();
}
void DirectInputRig::setFfbSpring(float value) { impl_->springStrength.store(std::clamp(value, 0.0f, 1.0f)); impl_->applyConditions(); }
void DirectInputRig::setFfbDamper(float value) { impl_->damperStrength.store(std::clamp(value, 0.0f, 1.0f)); impl_->applyConditions(); }
void DirectInputRig::setFfbTexture(float value) { impl_->textureTune.store(std::clamp(value, 0.0f, 1.0f)); }
void DirectInputRig::setFfbEngine(float value) { impl_->engineTune.store(std::clamp(value, 0.0f, 1.0f)); }
void DirectInputRig::setFfbRoad(float value) { impl_->roadTune.store(std::clamp(value, 0.0f, 1.0f)); }
float DirectInputRig::ffbTexture() const { return impl_->textureTune.load(); }
float DirectInputRig::ffbEngine() const { return impl_->engineTune.load(); }
float DirectInputRig::ffbRoad() const { return impl_->roadTune.load(); }
feel::DeviceClass DirectInputRig::deviceClass() const { return impl_->config.deviceClass; }

void DirectInputRig::setSteerDegrees(float degrees)
{
    impl_->config.steerDegrees = std::clamp(degrees, 5.0f, 540.0f);
    RIG_INFO("steering range %.0f deg/side (scale %.2fx of a %.0f deg wheel)", impl_->config.steerDegrees,
             impl_->config.steerScale(), impl_->config.wheelRangeDegrees);
}

void DirectInputRig::setDeviceClass(const std::string& name)
{
    const auto next = feel::classFrom(name);
    const float before = feel::ceilingFor(impl_->config.deviceClass);
    const float fraction = before > 0.0f ? impl_->ffbStrength.load() / before : 0.0f;
    impl_->config.deviceClass = next;
    // Hold the SETTING, not the magnitude. Someone at 50% who corrects the class from `unknown` to
    // `gear` means "half strength on a gear wheel", not "keep the tiny number the safer cap allowed".
    setFfbStrength(std::clamp(fraction, 0.0f, 1.0f) * feel::ceilingFor(next));
    RIG_INFO("device class %s -> %s (ceiling %.3f)", name.c_str(), feel::nameOf(next),
             feel::ceilingFor(next));
}
void DirectInputRig::testPulse(float value) { impl_->pulse.store(std::clamp(value, -0.5f, 0.5f)); impl_->pulseUntilMs.store(std::chrono::duration_cast<std::chrono::milliseconds>((Clock::now() + std::chrono::milliseconds(180)).time_since_epoch()).count()); }
std::string DirectInputRig::deviceJson() const { return impl_->json(); }

bool DirectInputRig::bind(const std::string& role, const std::string& device, const std::string& axis,
                          bool invert, float deadzone)
{
    AxisBinding* target = nullptr;
    if (role == "steering") target = &impl_->config.steering;
    else if (role == "throttle") target = &impl_->config.throttle;
    else if (role == "brake") target = &impl_->config.brake;
    else if (role == "clutch") target = &impl_->config.clutch;
    else if (role == "ffb") {
        std::lock_guard lock(impl_->mutex);
        impl_->config.ffbDeviceKey = device;
        impl_->config.ffbDeviceGuid.clear();
        impl_->config.ffbDeviceName.clear();
        impl_->selectFfbDevice();
        RIG_INFO("bound ffb -> %s", device.empty() ? "(none)" : device.c_str());
        return true;
    }
    if (!target) { RIG_WARN("bind: unknown role '%s'", role.c_str()); return false; }

    std::lock_guard lock(impl_->mutex);
    target->deviceKey = device;
    // A fresh choice supersedes whatever legacy instance-guid or name match was there; leaving them would
    // let a stale match win over the device the driver just picked.
    target->deviceGuid.clear();
    target->deviceName.clear();
    if (!axis.empty()) target->axis = axis;
    target->invert = invert;
    if (deadzone >= 0.0f) target->deadzone = std::clamp(deadzone, 0.0f, 0.95f);
    RIG_INFO("bound %s -> %s axis %s%s", role.c_str(), device.empty() ? "(none)" : device.c_str(),
             target->axis.c_str(), target->invert ? " inverted" : "");
    return true;
}

void DirectInputRig::persist(const std::wstring& directory) const { impl_->config.save(directory); }
const Config& DirectInputRig::config() const { return impl_->config; }
bool DirectInputRig::hasFfb() const { return impl_->ffbDevice != nullptr; }
bool DirectInputRig::ffbArmed() const { return impl_->ffbArmed.load(); }
float DirectInputRig::ffbStrength() const { return impl_->ffbStrength.load(); }
float DirectInputRig::ffbSpring() const { return impl_->springStrength.load(); }
float DirectInputRig::ffbDamper() const { return impl_->damperStrength.load(); }
}
