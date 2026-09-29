#include "ffb_output.hpp"

#include "feel.hpp"

#include <algorithm>
#include <climits>
#include <cstdio>
#include <vector>

namespace ncm::rig {
namespace {

const char* const kVibeNames[kVibes] = {"slip", "road", "engine", "impact"};

uint32_t restingPeriod(int index)
{
    if (index == static_cast<int>(Vibe::Engine)) return feel::enginePeriodMicros(0.0f);
    if (index == static_cast<int>(Vibe::Impact)) return feel::impactPeriodMicros();
    return feel::textureCarrierPeriodMicros();
}

std::string hex(HRESULT hr)
{
    char buffer[16]{};
    std::snprintf(buffer, sizeof(buffer), "0x%08lX", static_cast<unsigned long>(hr));
    return buffer;
}

LONG units(float fraction) { return static_cast<LONG>(std::clamp(fraction, -1.0f, 1.0f) * DI_FFNOMINALMAX); }

struct AxisProbe {
    std::vector<DWORD> actuators;   // every force-actuated axis, in the device's own order
};

BOOL CALLBACK enumerateAxis(const DIDEVICEOBJECTINSTANCEW* value, void* context)
{
    auto* probe = static_cast<AxisProbe*>(context);
    if ((value->dwType & DIDFT_AXIS) != 0 && (value->dwFlags & DIDOI_FFACTUATOR) != 0 &&
        value->dwOfs != static_cast<DWORD>(-1))
        probe->actuators.push_back(value->dwOfs);
    return DIENUM_CONTINUE;
}

bool isAcquisitionLoss(HRESULT hr)
{
    return hr == DIERR_INPUTLOST || hr == DIERR_NOTACQUIRED || hr == DIERR_NOTEXCLUSIVEACQUIRED ||
           hr == DIERR_NOTDOWNLOADED;
}
}  // namespace

// A message-only window, created once and never destroyed while the process lives. Exclusive DirectInput
// access is tied to a window; borrowing the game's meant the first splash/console window it found, and
// when that window went away the acquisition -- and every effect with it -- went too. SDL does the same.
HWND FfbOutput::helperWindow()
{
    static HWND window = [] {
        WNDCLASSEXW cls{};
        cls.cbSize = sizeof(cls);
        cls.lpfnWndProc = DefWindowProcW;
        cls.hInstance = GetModuleHandleW(nullptr);
        cls.lpszClassName = L"NcmRigBridgeFfb";
        RegisterClassExW(&cls);
        return CreateWindowExW(0, cls.lpszClassName, L"NCM Rig Bridge FFB", 0, 0, 0, 0, 0, HWND_MESSAGE,
                               nullptr, cls.hInstance, nullptr);
    }();
    return window;
}

void FfbOutput::note(bool warn, const std::string& line)
{
    if (log_) log_(warn, line);
}

bool FfbOutput::open(IDirectInput8W* api, const GUID& instance, const std::string& name)
{
    if (device_ && IsEqualGUID(instance, instance_)) return isOpen();
    close();
    instance_ = instance;
    name_ = name;
    failures_ = 0;

    auto fail = [&](const char* step, HRESULT hr) {
        status_ = std::string("FAILED at ") + step + " " + hex(hr);
        note(true, "FFB " + name_ + ": " + status_);
        close();
        status_ = std::string("FAILED at ") + step + " " + hex(hr);   // close() resets it
        return false;
    };

    HRESULT hr = api->CreateDevice(instance, &device_, nullptr);
    if (FAILED(hr)) { device_ = nullptr; return fail("CreateDevice", hr); }
    hr = device_->SetDataFormat(&c_dfDIJoystick2);
    if (FAILED(hr)) return fail("SetDataFormat", hr);

    HWND window = helperWindow();
    if (!window) return fail("helper window", HRESULT_FROM_WIN32(GetLastError()));
    hr = device_->SetCooperativeLevel(window, DISCL_EXCLUSIVE | DISCL_BACKGROUND);
    if (FAILED(hr)) return fail("SetCooperativeLevel(exclusive)", hr);

    // Properties BEFORE acquire: several drivers refuse DIPROP_AUTOCENTER on an acquired device
    // (the owner's G29 answered 0x800700AA, "busy", when this ran after). Neither is fatal.
    DIPROPDWORD property{};
    property.diph.dwSize = sizeof(property);
    property.diph.dwHeaderSize = sizeof(property.diph);
    property.diph.dwHow = DIPH_DEVICE;
    property.dwData = DIPROPAUTOCENTER_OFF;
    const HRESULT autocenter = device_->SetProperty(DIPROP_AUTOCENTER, &property.diph);
    property.dwData = DI_FFNOMINALMAX;
    const HRESULT gain = device_->SetProperty(DIPROP_FFGAIN, &property.diph);

    hr = device_->Acquire();
    if (FAILED(hr)) return fail("Acquire(exclusive) -- another program may own the wheel", hr);
    const HRESULT reset = device_->SendForceFeedbackCommand(DISFFC_RESET);
    const HRESULT actuators = device_->SendForceFeedbackCommand(DISFFC_SETACTUATORSON);

    // **Which axis.** X whenever the device lists X as force-actuated -- that is every wheel we have
    // seen, and "the first actuator" picked Y on the owner's G29 and silently failed every CreateEffect.
    // A base that does not actuate X gets its own first actuator. And if creation fails on the chosen
    // axis, X is tried before giving up.
    AxisProbe probe;
    device_->EnumObjects(enumerateAxis, &probe, DIDFT_AXIS);
    const bool actuatesX = std::find(probe.actuators.begin(), probe.actuators.end(),
                                     static_cast<DWORD>(DIJOFS_X)) != probe.actuators.end();
    DWORD axis = actuatesX || probe.actuators.empty() ? static_cast<DWORD>(DIJOFS_X) : probe.actuators.front();
    if (!createAll(axis) && axis != static_cast<DWORD>(DIJOFS_X)) {
        releaseEffects();
        axis = DIJOFS_X;
        createAll(axis);
    }
    axis_ = axis;

    char line[256]{};
    std::snprintf(line, sizeof(line),
                  "FFB %s: axis=%s (%zu actuator axes) autocenter=%s gain=%s reset=%s actuators=%s "
                  "spring=%s damper=%s constant=%s slip=%s road=%s engine=%s impact=%s",
                  name_.c_str(), axisName(), probe.actuators.size(), hex(autocenter).c_str(),
                  hex(gain).c_str(), hex(reset).c_str(), hex(actuators).c_str(), spring_ ? "yes" : "NO",
                  damper_ ? "yes" : "NO", constant_ ? "yes" : "NO", vibes_[0].effect ? "yes" : "NO",
                  vibes_[1].effect ? "yes" : "NO", vibes_[2].effect ? "yes" : "NO", vibes_[3].effect ? "yes" : "NO");
    note(!constant_, line);
    if (!constant_) return false;

    char ready[96]{};
    std::snprintf(ready, sizeof(ready), "OK - %d/7 effects on axis %s", effects(), axisName());
    status_ = ready;
    return true;
}

bool FfbOutput::createAll(DWORD axis)
{
    DWORD axes[1] = {axis};
    // A one-axis Cartesian direction of {1}: the vector points along the axis and the SIGNED magnitude
    // chooses the way. Zero here is a zero-length vector -- force with nowhere to go.
    LONG direction[1] = {1};
    DIEFFECT effect{};
    effect.dwSize = sizeof(effect);
    effect.dwFlags = DIEFF_CARTESIAN | DIEFF_OBJECTOFFSETS;
    effect.dwDuration = INFINITE;
    effect.dwSamplePeriod = 0;
    effect.dwGain = DI_FFNOMINALMAX;
    effect.dwTriggerButton = DIEB_NOTRIGGER;
    effect.dwTriggerRepeatInterval = 0;
    effect.cAxes = 1;
    effect.rgdwAxes = axes;
    effect.rglDirection = direction;
    effect.lpEnvelope = nullptr;
    effect.dwStartDelay = 0;

    auto make = [&](const GUID& type, IDirectInputEffect** out, const char* what) {
        const HRESULT hr = device_->CreateEffect(type, &effect, out, nullptr);
        if (FAILED(hr)) {
            *out = nullptr;
            note(true, std::string("FFB CreateEffect(") + what + ") " + hex(hr));
            status_ = std::string("FAILED at CreateEffect(") + what + ") " + hex(hr);
            return;
        }
        // Start ONCE, at zero. From here on only type-specific parameters change.
        const HRESULT started = (*out)->Start(1, 0);
        if (FAILED(started)) note(true, std::string("FFB Start(") + what + ") " + hex(started));
    };

    DICONDITION condition{};   // zero coefficients: present, playing, and inert until set
    effect.cbTypeSpecificParams = sizeof(condition);
    effect.lpvTypeSpecificParams = &condition;
    make(GUID_Spring, &spring_, "spring");
    make(GUID_Damper, &damper_, "damper");

    DICONSTANTFORCE force{};
    effect.cbTypeSpecificParams = sizeof(force);
    effect.lpvTypeSpecificParams = &force;
    make(GUID_ConstantForce, &constant_, "constant");

    // One SINE per vibration slider. SLIP and ROAD sit on the fixed 125 Hz carrier; ENGINE starts at the
    // idle period and follows revs. Separate effects, so a period change on one never restarts another.
    DIPERIODIC periodic{};
    effect.cbTypeSpecificParams = sizeof(periodic);
    effect.lpvTypeSpecificParams = &periodic;
    for (int i = 0; i < kVibes; ++i) {
        periodic.dwPeriod = restingPeriod(i);
        make(GUID_Sine, &vibes_[i].effect, kVibeNames[i]);
        vibes_[i].sent = 0;
        vibes_[i].period = periodic.dwPeriod;
    }

    sentConstant_ = sentSpring_ = sentDamper_ = 0;
    return constant_ != nullptr;
}

void FfbOutput::releaseEffects()
{
    for (IDirectInputEffect** e : {&vibes_[0].effect, &vibes_[1].effect, &vibes_[2].effect, &vibes_[3].effect,
                                   &constant_, &spring_, &damper_}) {
        if (!*e) continue;
        (*e)->Stop();
        (*e)->Unload();
        (*e)->Release();
        *e = nullptr;
    }
}

void FfbOutput::close()
{
    if (device_) {
        zero();
        // Release, never merely stop: a DirectInput effect can outlive the process that made it, and a
        // wheel left pulling to one side after the game exits is the worst failure here.
        releaseEffects();
        device_->SendForceFeedbackCommand(DISFFC_RESET);
        device_->Unacquire();
        device_->Release();
        device_ = nullptr;
    }
    status_ = "not opened";
    sentConstant_ = sentSpring_ = sentDamper_ = LONG_MIN;
    for (auto& v : vibes_) { v.sent = LONG_MIN; v.period = 0; }
}

bool FfbOutput::write(IDirectInputEffect* effect, DIEFFECT& params, const char* what)
{
    ++writes_;
    HRESULT hr = effect->SetParameters(&params, DIEP_TYPESPECIFICPARAMS);
    if (isAcquisitionLoss(hr) && device_) {
        // Lost exclusive access (another program grabbed the wheel, a driver reset). Take it back and
        // restart this effect -- acquisition loss stops effects, and a stopped effect at a new magnitude
        // is still silence.
        device_->Acquire();
        hr = effect->SetParameters(&params, DIEP_TYPESPECIFICPARAMS | DIEP_START);
    }
    if (SUCCEEDED(hr)) {
        if (failures_ != 0 && hr == DI_OK) status_ = "OK - recovered";
        return true;
    }
    ++failures_;
    if (hr != lastFailure_ || failures_ % 1000 == 1) {
        // Say WHO, not just what: exclusive access lost means another program or plugin is driving this
        // wheel's force feedback (SimHub, a vendor tool, another mod), and only one owner can.
        status_ = isAcquisitionLoss(hr)
            ? std::string("LOST - another program or plugin took the wheel's force feedback (") + hex(hr) + ")"
            : std::string("FAILING: ") + what + " update " + hex(hr);
        note(true, "FFB " + status_);
    }
    lastFailure_ = hr;
    return false;
}

void FfbOutput::setConditions(float spring, float damper)
{
    if (!device_) return;
    auto apply = [&](IDirectInputEffect* effect, float coefficient, LONG& sent, const char* what) {
        if (!effect) return;
        const LONG value = units(std::clamp(coefficient, 0.0f, 1.0f));
        if (value == sent) return;
        DICONDITION condition{};
        condition.lPositiveCoefficient = value;
        condition.lNegativeCoefficient = value;
        condition.dwPositiveSaturation = DI_FFNOMINALMAX;
        condition.dwNegativeSaturation = DI_FFNOMINALMAX;
        DIEFFECT params{};
        params.dwSize = sizeof(params);
        params.cbTypeSpecificParams = sizeof(condition);
        params.lpvTypeSpecificParams = &condition;
        if (write(effect, params, what)) sent = value;
    };
    apply(spring_, spring, sentSpring_, "spring");
    apply(damper_, damper, sentDamper_, "damper");
}

void FfbOutput::setConstant(float value)
{
    if (!constant_) return;
    const LONG level = units(value);
    if (std::abs(level - sentConstant_) < 20) return;   // 0.2% of full scale
    DICONSTANTFORCE force{level};
    DIEFFECT params{};
    params.dwSize = sizeof(params);
    params.cbTypeSpecificParams = sizeof(force);
    params.lpvTypeSpecificParams = &force;
    if (write(constant_, params, "constant")) sentConstant_ = level;
}

void FfbOutput::setVibration(Vibe which, float magnitude, uint32_t periodMicros)
{
    Periodic& v = vibes_[static_cast<int>(which)];
    if (!v.effect) return;
    const LONG level = units(std::clamp(magnitude, 0.0f, 1.0f));
    const auto now = std::chrono::steady_clock::now();
    // The period is what a driver may restart the wave for, so it moves at most ten times a second: even
    // at 12 Hz that leaves a whole cycle between restarts. Magnitude alone may move at 50 Hz -- if a driver
    // restarts even for that, 20 ms is still two and a half 125 Hz cycles, felt rather than pinned at zero.
    DWORD period = v.period ? v.period : periodMicros;
    if (periodMicros != v.period && now - v.lastPeriod >= std::chrono::milliseconds(100)) period = periodMicros;
    const bool periodMoves = period != v.period;
    if (!periodMoves && std::abs(level - v.sent) < 20) return;
    if (!periodMoves && level != 0 && now - v.last < std::chrono::milliseconds(20)) return;
    v.last = now;
    DIPERIODIC periodic{};
    periodic.dwMagnitude = static_cast<DWORD>(level);
    periodic.dwPeriod = period;
    DIEFFECT params{};
    params.dwSize = sizeof(params);
    params.cbTypeSpecificParams = sizeof(periodic);
    params.lpvTypeSpecificParams = &periodic;
    if (write(v.effect, params, kVibeNames[static_cast<int>(which)])) {
        v.sent = level;
        if (periodMoves) { v.period = period; v.lastPeriod = now; }
    }
}

void FfbOutput::zero()
{
    setConstant(0.0f);
    for (int i = 0; i < kVibes; ++i) {
        vibes_[i].last = {};
        setVibration(static_cast<Vibe>(i), 0.0f, vibes_[i].period ? vibes_[i].period : restingPeriod(i));
    }
    setConditions(0.0f, 0.0f);
}

int FfbOutput::effects() const
{
    int n = (spring_ ? 1 : 0) + (damper_ ? 1 : 0) + (constant_ ? 1 : 0);
    for (const auto& v : vibes_) n += v.effect ? 1 : 0;
    return n;
}

const char* FfbOutput::axisName() const
{
    const DWORD a = axis_;
    if (a == static_cast<DWORD>(DIJOFS_X)) return "X";
    if (a == static_cast<DWORD>(DIJOFS_Y)) return "Y";
    if (a == static_cast<DWORD>(DIJOFS_Z)) return "Z";
    if (a == static_cast<DWORD>(DIJOFS_RX)) return "RX";
    if (a == static_cast<DWORD>(DIJOFS_RY)) return "RY";
    if (a == static_cast<DWORD>(DIJOFS_RZ)) return "RZ";
    return "other";
}

}  // namespace ncm::rig
