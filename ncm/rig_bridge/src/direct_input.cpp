#include "direct_input.hpp"

#include "feel.hpp"
#include "ffb_output.hpp"
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
    std::atomic<float> ffbFraction{0.5f};   // the SLIDER, 0..1 of the ceiling
    std::atomic<float> springStrength{0.55f};
    std::atomic<float> damperStrength{0.35f};
    std::atomic<float> textureTune{0.60f};
    std::atomic<float> engineTune{0.45f};
    std::atomic<float> roadTune{1.00f};
    std::atomic<float> collisionTune{0.80f};
    std::atomic<float> pulse{0.0f};
    std::atomic<int64_t> pulseUntilMs{0};
    // Output has its OWN device handle, window and lifetime (ffb_output.hpp). The polling handle in
    // `devices` is never made exclusive, and a rescan does not touch the effects.
    FfbOutput ffb{[](bool warn, const std::string& line) {
        if (warn) RIG_WARN("%s", line.c_str()); else RIG_INFO("%s", line.c_str());
    }};
    Device* ffbDevice = nullptr;          // the ENUMERATED entry, for names and keys only
    feel::Recognition wheel_;             // what that device is, by VID:PID
    bool warnedNoFfb = false;
    bool live_ = false;                   // force currently permitted (armed, in a car, fresh telemetry)
    uint32_t offered = 0;   // how many DirectInput handed us before any were rejected
    uint64_t sequence = 0;
    std::vector<bool> priorButtons;

    // Slewed outputs. These persist between ticks on purpose: an unreadable frame HOLDS the last force
    // rather than dropping it to zero, which would read as the wheel dying every time a packet was late.
    float torque_ = 0.0f;
    Clock::time_point lastTick_{};
    float slipLevel_ = 0.0f;              // slewed channel outputs, device units
    float roadLevel_ = 0.0f;
    float engineLevel_ = 0.0f;
    float revs_ = 0.0f;                   // last MEASURED rev ratio; an absent reading holds it

    // **What each slider is sending, now and at its peak, as a fraction of full FORCE.** Feedback has to be
    // a number: "SLIP peaked 80% on lock-up and felt weak" tunes a wheel; "too rumbly" does not. ROAD
    // reading 0% over a kerb proves the data is missing rather than the feel being wrong.
    struct Readout { float now = 0.0f; float peak = 0.0f; };
    Readout outSpring, outDamper, outTorque, outSlip, outRoad, outEngine, outImpact;
    static void read(Readout& r, float v) { r.now = v; if (v > r.peak) r.peak = v; }
    void resetReadouts()
    {
        for (Readout* r : {&outSpring, &outDamper, &outTorque, &outSlip, &outRoad, &outEngine, &outImpact}) *r = {};
    }

    // ---- the wheel actually attached decides the limits ---------------------------------------------
    // An explicit class in the config wins; `unknown` means AUTO and takes the recognised class.
    feel::DeviceClass effectiveClass() const
    {
        return config.deviceClass != feel::DeviceClass::Unknown ? config.deviceClass : wheel_.cls;
    }
    float effectiveNm() const { return config.ratedNm > 0.0f ? config.ratedNm : wheel_.ratedNm; }
    float ceiling() const { return feel::ceilingFor(effectiveClass(), effectiveNm()); }
    const char* torqueSource() const
    {
        if (config.ratedNm > 0.0f) return "set";
        if (wheel_.ratedNm > 0.0f) return "recognised";
        return effectiveClass() == feel::DeviceClass::DirectDrive ? "assumed" : "n/a";
    }

    // What each channel actually reached this session, so the road scale can be set from evidence rather
    // than taste. Printed once at teardown -- a channel that peaked near zero was never felt.
    struct Peak { float max = 0.0f; uint64_t frames = 0; };
    Peak peakTexture, peakTorque, peakRoad, peakSlip, peakCollision, peakEngine;
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
        Device* chosen = select(config.ffbDeviceKey, config.ffbDeviceGuid, config.ffbDeviceName, Role::Ffb);
        if (!chosen || !chosen->ffb) {
            if (ffb.isOpen() || ffbDevice) ffb.close();
            ffbDevice = nullptr;
            wheel_ = {};
            live_ = false;
            if (!warnedNoFfb) { warnedNoFfb = true; RIG_WARN("no force-feedback DirectInput device selected"); }
            return;
        }
        warnedNoFfb = false;
        const bool same = ffb.isOpen() && IsEqualGUID(ffb.instance(), chosen->instance);
        ffbDevice = chosen;
        if (same) return;                     // a rescan found the same wheel: leave its effects alone
        wheel_ = feel::recognise(chosen->key);
        live_ = false;                        // re-apply conditions on the next permitted tick
        ffb.open(api, chosen->instance, chosen->name);
        RIG_INFO("FFB wheel %s: %s class=%s%s rated=%.1f Nm (%s) ceiling=%.3f output=%s", chosen->key.c_str(),
                 wheel_.model.empty() ? "not recognised" : wheel_.model.c_str(), feel::nameOf(effectiveClass()),
                 config.deviceClass == feel::DeviceClass::Unknown ? " (auto)" : " (set)", effectiveNm(),
                 torqueSource(), ceiling(), ffb.status().c_str());
    }

    /// Input handles only. Output survives a rescan; `selectFfbDevice` closes it if the wheel is gone.
    void releaseDevices()
    {
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

    /// Spring and damper are STIFFNESS, a standing property of the wheel: set when a slider moves or force
    /// becomes permitted, never per frame. On direct drive their saturation is held to the torque budget,
    /// so a stiff spring on a 32 Nm base cannot exceed what the slider allows.
    void applyConditions()
    {
        if (!ffb.isOpen()) return;
        const bool on = live_ && ffbEnabled.load() && ffbArmed.load();
        const float fraction = std::clamp(ffbFraction.load(), 0.0f, 1.0f);
        const float saturation = effectiveClass() == feel::DeviceClass::DirectDrive ? ceiling() : 1.0f;
        ffb.setConditions(on ? springStrength.load() * fraction * saturation : 0.0f,
                          on ? damperStrength.load() * fraction * saturation : 0.0f);
        read(outSpring, on ? springStrength.load() * fraction : 0.0f);
        read(outDamper, on ? damperStrength.load() * fraction : 0.0f);
    }

    /// The single point where a level becomes force.
    void updateEffects()
    {
        const auto now = Clock::now();
        const float dt = lastTick_.time_since_epoch().count() == 0
            ? 0.004f
            : std::chrono::duration<float>(now - lastTick_).count();
        lastTick_ = now;
        if (!ffb.isOpen()) return;

        const auto nowMs = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
        const int64_t until = pulseUntilMs.load();
        const bool testing = nowMs < until;
        const auto frame = state().feedback();
        // The watchdog. Stale telemetry is a car we can no longer see, not a car sitting still.
        const bool current = frame.updated.time_since_epoch().count() != 0 &&
            std::chrono::duration_cast<std::chrono::milliseconds>(now - frame.updated).count() <= config.ffbWatchdogMs;
        // ARM gates everything, the test included (§BU8: disarmed produces no force). The test's log line
        // and the panel say "armed=NO", so an unarmed test is not mistaken for a dead wheel.
        const bool live = ffbEnabled.load() && ffbArmed.load() &&
            (testing || (frame.inVehicle && current));

        if (live != live_) {
            live_ = live;
            if (!live) {
                slipLevel_ = roadLevel_ = engineLevel_ = torque_ = 0.0f;
                ffb.zero();
                for (Readout* r : {&outTorque, &outSlip, &outRoad, &outEngine, &outImpact}) r->now = 0.0f;
            }
            applyConditions();
        }
        if (!live) return;

        const float ceiling = this->ceiling();
        const float magnitude = std::clamp(ffbFraction.load(), 0.0f, 1.0f) * ceiling;

        // **The test must be unmistakable.** It used to be a 180 ms push of the rung through the slew
        // limiter -- about half a newton-metre on a G29, which the gearbox's own friction swallows, so
        // "I pressed test and felt nothing" proved nothing. Now: 700 ms of full-ceiling vibration with a
        // left-right kick every 100 ms, independent of the slider and the car. Never past the ceiling.
        if (testing) {
            const int64_t left = until - nowMs;
            const float kick = ((left / 100) % 2 == 0) ? 1.0f : -1.0f;
            ffb.setVibration(Vibe::Slip, ceiling, feel::textureCarrierPeriodMicros());
            ffb.setVibration(Vibe::Road, 0.0f, feel::textureCarrierPeriodMicros());
            ffb.setVibration(Vibe::Engine, 0.0f, feel::enginePeriodMicros(revs_));
            ffb.setVibration(Vibe::Impact, 0.0f, feel::impactPeriodMicros());
            ffb.setConstant(kick * ceiling);
            slipLevel_ = roadLevel_ = engineLevel_ = torque_ = 0.0f;
            return;
        }

        feel::Tune tune;
        tune.spring = springStrength.load();
        tune.damper = damperStrength.load();
        tune.texture = textureTune.load();
        tune.engine = engineTune.load();
        tune.road = roadTune.load();

        const auto mixed = feel::mix(frame.telemetry, tune);
        if (mixed.readable) {
            slipLevel_ = feel::slew(slipLevel_, mixed.slip * magnitude, dt);
            roadLevel_ = feel::slew(roadLevel_, mixed.road * magnitude, dt);
            torque_ = feel::slew(torque_, mixed.torque * magnitude, dt);
            engineLevel_ = feel::slew(engineLevel_, mixed.engine * magnitude, dt);
            if (mixed.hasEngine) revs_ = mixed.revs;
            observe(peakEngine, mixed.engine);
            observe(peakTexture, mixed.slip);
            observe(peakTorque, mixed.torque);
            if (frame.telemetry.hasSuspLong) observe(peakRoad, frame.telemetry.suspLong);
            if (frame.telemetry.hasSuspLat) observe(peakRoad, frame.telemetry.suspLat);
            if (frame.telemetry.hasSlipTotal) observe(peakSlip, frame.telemetry.slipTotal);
        }
        // else: HOLD. An unreadable frame is not a zero frame.

        // A collision is a THUD from any direction plus a sideways KICK that rides ON TOP of the
        // self-aligning torque (a real impact arrives through the castor). Not slewed: an impact is sharp,
        // and the 250 ms linear decay already bounds it. Scaled by the COLLISION slider and FORCE.
        const auto hit = state().collisionAt(now);
        const float collision = std::clamp(collisionTune.load(), 0.0f, 1.0f);
        if (hit.thud != 0.0f) observe(peakCollision, hit.thud);

        // The three vibrations are separate effects that ADD on the device, so the ceiling bounds their SUM:
        // when together they would pass it, all three scale down in proportion. Tested one at a time (the
        // method in MASTER_TEST §CD), no scaling happens and each channel reads exactly what it sends.
        float slip = std::max(0.0f, slipLevel_), road = std::max(0.0f, roadLevel_);
        float engineHum = std::max(0.0f, engineLevel_);
        float impact = hit.thud * collision * magnitude;
        const float sum = slip + road + engineHum + impact;
        if (sum > ceiling && sum > 0.0f) {
            const float scale = ceiling / sum;
            slip *= scale; road *= scale; engineHum *= scale; impact *= scale;
        }
        const float torque = feel::clampToCeiling(ceiling, torque_ + hit.kick * collision * magnitude);
        ffb.setVibration(Vibe::Slip, slip, feel::textureCarrierPeriodMicros());
        ffb.setVibration(Vibe::Road, road, feel::textureCarrierPeriodMicros());
        ffb.setVibration(Vibe::Engine, engineHum, feel::enginePeriodMicros(revs_));
        ffb.setVibration(Vibe::Impact, impact, feel::impactPeriodMicros());
        ffb.setConstant(torque);

        const float per = ceiling > 0.0f ? 1.0f / ceiling : 0.0f;
        read(outSlip, slip * per);
        read(outRoad, road * per);
        read(outEngine, engineHum * per);
        read(outImpact, impact * per);
        read(outTorque, std::fabs(torque) * per);
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
        say("slip(mix)", peakTexture);
        say("torque(align)", peakTorque);
        say("road(susp)", peakRoad);
        say("slip", peakSlip);
        say("collision", peakCollision);
        say("engine", peakEngine);
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
                // NOT `|| !complete` (owner, 2026-10-13: "we def have a connectivity issue with gamepads"): a bound
                // device that is simply not plugged in (a G29 left in the config) made EVERY tick a full rebuild --
                // every game controller on the PC released and re-acquired every 2 s, and SDL opening and closing
                // the rig each time DirectInput's list went empty mid-rebuild. Arrival changes the count; the
                // count is the trigger.
                if (changed) rebuildDevices();
                // An output that failed to open (wheel owned by another program, driver mid-reset) is
                // retried here rather than staying dead for the session.
                else { std::lock_guard lock(mutex); if (ffbDevice && !ffb.isOpen()) selectFfbDevice(); }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(4));
        }
        for (size_t i = 0; i < priorButtons.size(); ++i) if (priorButtons[i]) sendKey(config.buttons[i].virtualKey, false);
        { std::lock_guard lock(mutex); ffb.zero(); }
        reportPeaks();
        RIG_INFO("input pump stopped");
    }

    void shutdown()
    {
        running.store(false);
        if (thread.joinable()) thread.join();
        releaseDevices();
        ffb.close();
        if (api) { api->Release(); api = nullptr; }
    }

    std::string json() const
    {
        std::lock_guard lock(mutex);
        nlohmann::json root{{"provider", "directinput"}, {"ffb", ffb.isOpen()},
                            {"ffbArmed", ffbArmed.load()}, {"devices", nlohmann::json::array()}};
        // **Self-report.** A tester's screenshot of the panel must say why a wheel is silent: which wheel,
        // what we think it is, the limit we derived, and the exact DirectInput call that failed.
        root["ffbOutput"] = {
            {"ok", ffb.ok()}, {"open", ffb.isOpen()},
            {"status", ffbDevice ? ffb.status() : std::string("no force-feedback wheel found")},
            {"effects", ffb.effects()}, {"axis", ffb.axisName()}, {"writes", ffb.writes()},
            {"failures", ffb.failures()}, {"model", wheel_.model}, {"recognised", !wheel_.model.empty()},
            {"class", feel::nameOf(effectiveClass())},
            {"classAuto", config.deviceClass == feel::DeviceClass::Unknown},
            {"ratedNm", effectiveNm()}, {"torqueSource", torqueSource()},
            {"ceiling", ceiling()}, {"strength", ffbFraction.load()},
            {"peakNm", effectiveNm() > 0.0f ? ffbFraction.load() * ceiling() * effectiveNm() : 0.0f},
            {"live", live_},
            // Volatile: the panel writes these in place and never rebuilds for them.
            {"channels", {
                {"spring", {{"now", outSpring.now}, {"peak", outSpring.peak}}},
                {"damper", {{"now", outDamper.now}, {"peak", outDamper.peak}}},
                {"torque", {{"now", outTorque.now}, {"peak", outTorque.peak}}},
                {"slip", {{"now", outSlip.now}, {"peak", outSlip.peak}}},
                {"road", {{"now", outRoad.now}, {"peak", outRoad.peak}}},
                {"collision", {{"now", outImpact.now}, {"peak", outImpact.peak}}},
                {"engine", {{"now", outEngine.now}, {"peak", outEngine.peak},
                            {"hz", std::round(1000000.0f / static_cast<float>(feel::enginePeriodMicros(revs_)))}}}}}};
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
    impl_->ffbFraction.store(std::clamp(impl_->config.ffbFraction, 0.0f, 1.0f));
    impl_->springStrength.store(impl_->config.tune.spring);
    impl_->damperStrength.store(impl_->config.tune.damper);
    impl_->textureTune.store(impl_->config.tune.texture);
    impl_->engineTune.store(impl_->config.tune.engine);
    impl_->roadTune.store(impl_->config.tune.road);
    impl_->collisionTune.store(impl_->config.tune.collision);
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
void DirectInputRig::setFfbEnabled(bool value) { std::lock_guard lock(impl_->mutex); impl_->config.ffbEnabled = value; impl_->ffbEnabled.store(value); impl_->applyConditions(); }
void DirectInputRig::setFfbArmed(bool value) { std::lock_guard lock(impl_->mutex); impl_->ffbArmed.store(value); impl_->applyConditions(); RIG_INFO("FFB %s", value ? "ARMED" : "DISARMED"); }
void DirectInputRig::setFfbStrength(float value)
{
    // Legacy: a MAGNITUDE (the old rung ladder), converted to the slider against the live ceiling.
    const float ceiling = ffbCeiling();
    setFfbFraction(ceiling > 0.0f ? value / ceiling : 0.0f);
}
void DirectInputRig::setFfbFraction(float value)
{
    std::lock_guard lock(impl_->mutex);
    // The ONE place the slider becomes real. It is a fraction of the ceiling, so 100% is the ceiling for
    // whatever wheel is attached -- never past it.
    const float clamped = std::clamp(value, 0.0f, 1.0f);
    impl_->config.ffbFraction = clamped;
    impl_->ffbFraction.store(clamped);
    impl_->applyConditions();
}
float DirectInputRig::ffbFraction() const { return impl_->ffbFraction.load(); }
void DirectInputRig::resetFfbPeaks()
{
    std::lock_guard lock(impl_->mutex);
    impl_->resetReadouts();
    impl_->applyConditions();   // spring/damper readouts are set on change; re-seed them
    RIG_INFO("FFB channel peaks reset");
}
float DirectInputRig::ffbCeiling() const { std::lock_guard lock(impl_->mutex); return impl_->ceiling(); }
void DirectInputRig::setRatedTorque(float nm)
{
    std::lock_guard lock(impl_->mutex);
    impl_->config.ratedNm = std::clamp(nm, 0.0f, 50.0f);
    impl_->applyConditions();
    RIG_INFO("base torque %s %.1f Nm -> ceiling %.3f", nm > 0.0f ? "set" : "auto", impl_->effectiveNm(),
             impl_->ceiling());
}
void DirectInputRig::setFfbSpring(float value) { std::lock_guard lock(impl_->mutex); const float v = std::clamp(value, 0.0f, 1.0f); impl_->config.tune.spring = v; impl_->springStrength.store(v); impl_->applyConditions(); }
void DirectInputRig::setFfbDamper(float value) { std::lock_guard lock(impl_->mutex); const float v = std::clamp(value, 0.0f, 1.0f); impl_->config.tune.damper = v; impl_->damperStrength.store(v); impl_->applyConditions(); }
void DirectInputRig::setFfbTexture(float value) { std::lock_guard lock(impl_->mutex); const float v = std::clamp(value, 0.0f, 1.0f); impl_->config.tune.texture = v; impl_->textureTune.store(v); }
void DirectInputRig::setFfbEngine(float value) { std::lock_guard lock(impl_->mutex); const float v = std::clamp(value, 0.0f, 1.0f); impl_->config.tune.engine = v; impl_->engineTune.store(v); }
void DirectInputRig::setFfbRoad(float value) { std::lock_guard lock(impl_->mutex); const float v = std::clamp(value, 0.0f, 1.0f); impl_->config.tune.road = v; impl_->roadTune.store(v); }
float DirectInputRig::ffbTexture() const { return impl_->textureTune.load(); }
float DirectInputRig::ffbEngine() const { return impl_->engineTune.load(); }
float DirectInputRig::ffbRoad() const { return impl_->roadTune.load(); }
void DirectInputRig::setFfbCollision(float value) { std::lock_guard lock(impl_->mutex); const float v = std::clamp(value, 0.0f, 1.0f); impl_->config.tune.collision = v; impl_->collisionTune.store(v); }
float DirectInputRig::ffbCollision() const { return impl_->collisionTune.load(); }
feel::DeviceClass DirectInputRig::deviceClass() const { return impl_->config.deviceClass; }

void DirectInputRig::setSteerDegrees(float degrees)
{
    std::lock_guard lock(impl_->mutex);
    impl_->config.steerDegrees = std::clamp(degrees, 5.0f, 540.0f);
    RIG_INFO("steering range %.0f deg/side (scale %.2fx of a %.0f deg wheel)", impl_->config.steerDegrees,
             impl_->config.steerScale(), impl_->config.wheelRangeDegrees);
}

void DirectInputRig::setDeviceClass(const std::string& name)
{
    std::lock_guard lock(impl_->mutex);
    // The slider is a fraction, so changing class keeps "half strength" meaning half -- nothing to rescale.
    impl_->config.deviceClass = feel::classFrom(name);
    impl_->applyConditions();
    RIG_INFO("device class %s -> %s (ceiling %.3f)", name.c_str(), feel::nameOf(impl_->effectiveClass()),
             impl_->ceiling());
}
void DirectInputRig::testPulse(float value)
{
    impl_->pulse.store(std::clamp(value, -0.5f, 0.5f));
    impl_->pulseUntilMs.store(std::chrono::duration_cast<std::chrono::milliseconds>(
        (Clock::now() + std::chrono::milliseconds(700)).time_since_epoch()).count());
    RIG_INFO("FFB test pulse: armed=%s output=%s", impl_->ffbArmed.load() ? "yes" : "NO",
             impl_->ffb.status().c_str());
}
std::string DirectInputRig::deviceJson() const { return impl_->json(); }
void DirectInputRig::rawSamples(pad::Samples& out) const
{
    std::lock_guard lock(impl_->mutex);
    const int64_t now = std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now().time_since_epoch()).count();
    for (const auto& d : impl_->devices) {
        if (!d.current) continue;
        pad::Sample s;
        s.tNs = now;
        for (int i = 0; i < 128; ++i) if (d.state.rgbButtons[i] & 0x80) s.buttons.insert("b" + std::to_string(i));
        for (int h = 0; h < 4; ++h) {
            const DWORD pov = d.state.rgdwPOV[h];
            if (LOWORD(pov) == 0xFFFF) continue;              // centred
            const std::string p = "hat" + std::to_string(h) + "_";
            const DWORD a = pov / 100;                        // degrees clockwise from up
            if (a >= 315 || a < 45) s.buttons.insert(p + "up");
            if (a >= 45 && a < 135) s.buttons.insert(p + "right");
            if (a >= 135 && a < 225) s.buttons.insert(p + "down");
            if (a >= 225 && a < 315) s.buttons.insert(p + "left");
            // A diagonal reads as both of its neighbours, as a raw SDL hat does.
            if (a > 0 && a < 90) s.buttons.insert(p + "right");
            if (a > 90 && a < 180) s.buttons.insert(p + "down");
            if (a > 180 && a < 270) s.buttons.insert(p + "left");
            if (a > 270) s.buttons.insert(p + "up");
        }
        const LONG raw[8] = {d.state.lX, d.state.lY, d.state.lZ, d.state.lRx, d.state.lRy, d.state.lRz,
                             d.state.rglSlider[0], d.state.rglSlider[1]};
        for (LONG v : raw) s.axes.push_back(std::clamp((static_cast<float>(v) - 32767.5f) / 32767.5f, -1.0f, 1.0f));
        out["di:" + d.key] = std::move(s);
    }
}

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

void DirectInputRig::persist(const std::wstring& directory) const { std::lock_guard lock(impl_->mutex); impl_->config.save(directory); }
const Config& DirectInputRig::config() const { return impl_->config; }
bool DirectInputRig::hasFfb() const { return impl_->ffb.isOpen(); }
bool DirectInputRig::ffbArmed() const { return impl_->ffbArmed.load(); }
float DirectInputRig::ffbStrength() const { return impl_->ffbFraction.load() * ffbCeiling(); }
float DirectInputRig::ffbSpring() const { return impl_->springStrength.load(); }
float DirectInputRig::ffbDamper() const { return impl_->damperStrength.load(); }
}
