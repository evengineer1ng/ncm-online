#include "xinput_hook.hpp"

#include "../log.hpp"

#include <windows.h>
#include <Xinput.h>

#include <algorithm>
#include <atomic>
#include <mutex>
#include <string>
#include <vector>

namespace ncm::rig::pad::xinput {
namespace {
using GetStateFn = DWORD(WINAPI*)(DWORD, XINPUT_STATE*);
using SetStateFn = DWORD(WINAPI*)(DWORD, XINPUT_VIBRATION*);
using GetCapsFn = DWORD(WINAPI*)(DWORD, DWORD, XINPUT_CAPABILITIES*);

std::mutex mutex;
VirtualPad current;
std::atomic<unsigned> userIndex{0};
std::atomic<uint32_t> packets{0};
std::atomic<bool> everActive{false};     // report a pad-less slot connected only once the virtual pad has spoken
std::atomic<bool> physicalSeen{false};
std::atomic<uint64_t> reads{0}, merges{0}, rumbleEvents{0};
std::function<void(float, float)> rumbleSink;
std::vector<std::string> hookedNames;

// One slot per hooked function: an original pointer and a detour that knows which original is its own.
// Three modules times four functions is the most there can be.
constexpr int kMax = 4;
GetStateFn getOriginal[kMax]{}, getExOriginal[kMax]{};
SetStateFn setOriginal[kMax]{};
GetCapsFn capsOriginal[kMax]{};
void* hookedTargets[kMax * 4]{};
int hookedCount = 0;

DWORD mergeInto(DWORD result, DWORD user, XINPUT_STATE* state)
{
    ++reads;
    if (!state || user != userIndex.load()) return result;
    VirtualPad v;
    { std::lock_guard lock(mutex); v = current; }
    if (result == ERROR_SUCCESS) {
        physicalSeen = true;
        if (v.idle()) return result;
        Gamepad p{state->Gamepad.wButtons, state->Gamepad.bLeftTrigger, state->Gamepad.bRightTrigger,
                  state->Gamepad.sThumbLX, state->Gamepad.sThumbLY, state->Gamepad.sThumbRX, state->Gamepad.sThumbRY};
        const Gamepad m = merge(p, v);
        state->Gamepad = {m.buttons, m.lt, m.rt, m.lx, m.ly, m.rx, m.ry};
        state->dwPacketNumber += packets.load();
        ++merges;
        return result;
    }
    if (result == ERROR_DEVICE_NOT_CONNECTED && everActive.load()) {
        // No physical pad in the slot: the virtual pad IS the pad.
        const Gamepad m = merge(Gamepad{}, v);
        state->dwPacketNumber = packets.load();
        state->Gamepad = {m.buttons, m.lt, m.rt, m.lx, m.ly, m.rx, m.ry};
        ++merges;
        return ERROR_SUCCESS;
    }
    return result;
}

template <int N> DWORD WINAPI getStateDetour(DWORD user, XINPUT_STATE* state)
{
    return mergeInto(getOriginal[N] ? getOriginal[N](user, state) : ERROR_DEVICE_NOT_CONNECTED, user, state);
}
template <int N> DWORD WINAPI getStateExDetour(DWORD user, XINPUT_STATE* state)
{
    return mergeInto(getExOriginal[N] ? getExOriginal[N](user, state) : ERROR_DEVICE_NOT_CONNECTED, user, state);
}
template <int N> DWORD WINAPI setStateDetour(DWORD user, XINPUT_VIBRATION* vibration)
{
    if (vibration && user == userIndex.load()) {
        ++rumbleEvents;
        std::function<void(float, float)> sink;
        { std::lock_guard lock(mutex); sink = rumbleSink; }
        if (sink) sink(vibration->wLeftMotorSpeed / 65535.0f, vibration->wRightMotorSpeed / 65535.0f);
    }
    return setOriginal[N] ? setOriginal[N](user, vibration) : ERROR_DEVICE_NOT_CONNECTED;
}
template <int N> DWORD WINAPI capsDetour(DWORD user, DWORD flags, XINPUT_CAPABILITIES* caps)
{
    const DWORD result = capsOriginal[N] ? capsOriginal[N](user, flags, caps) : ERROR_DEVICE_NOT_CONNECTED;
    if (result == ERROR_DEVICE_NOT_CONNECTED && caps && user == userIndex.load() && everActive.load()) {
        ZeroMemory(caps, sizeof(*caps));
        caps->Type = XINPUT_DEVTYPE_GAMEPAD;
        caps->SubType = XINPUT_DEVSUBTYPE_GAMEPAD;
        caps->Gamepad.wButtons = 0xF3FF;
        caps->Gamepad.bLeftTrigger = caps->Gamepad.bRightTrigger = 0xFF;
        caps->Gamepad.sThumbLX = caps->Gamepad.sThumbLY = caps->Gamepad.sThumbRX = caps->Gamepad.sThumbRY = static_cast<SHORT>(0xFFC0);
        caps->Vibration.wLeftMotorSpeed = caps->Vibration.wRightMotorSpeed = 0xFFFF;
        return ERROR_SUCCESS;
    }
    return result;
}

using AnyFn = void*;
AnyFn getDetours[kMax] = {reinterpret_cast<AnyFn>(&getStateDetour<0>), reinterpret_cast<AnyFn>(&getStateDetour<1>),
                          reinterpret_cast<AnyFn>(&getStateDetour<2>), reinterpret_cast<AnyFn>(&getStateDetour<3>)};
AnyFn getExDetours[kMax] = {reinterpret_cast<AnyFn>(&getStateExDetour<0>), reinterpret_cast<AnyFn>(&getStateExDetour<1>),
                            reinterpret_cast<AnyFn>(&getStateExDetour<2>), reinterpret_cast<AnyFn>(&getStateExDetour<3>)};
AnyFn setDetours[kMax] = {reinterpret_cast<AnyFn>(&setStateDetour<0>), reinterpret_cast<AnyFn>(&setStateDetour<1>),
                          reinterpret_cast<AnyFn>(&setStateDetour<2>), reinterpret_cast<AnyFn>(&setStateDetour<3>)};
AnyFn capsDetours[kMax] = {reinterpret_cast<AnyFn>(&capsDetour<0>), reinterpret_cast<AnyFn>(&capsDetour<1>),
                           reinterpret_cast<AnyFn>(&capsDetour<2>), reinterpret_cast<AnyFn>(&capsDetour<3>)};

bool alreadyHooked(void* target)
{
    for (int i = 0; i < hookedCount; ++i) if (hookedTargets[i] == target) return true;
    return false;
}
}  // namespace

bool install(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk)
{
    if (!sdk || !sdk->hooking || !sdk->hooking->Attach) { RIG_ERR("XInput hook: RED4ext hooking API unavailable"); return false; }
    int slot = 0;
    for (const wchar_t* name : {L"xinput1_4.dll", L"xinput1_3.dll", L"xinput9_1_0.dll"}) {
        if (slot >= kMax) break;
        HMODULE module = GetModuleHandleW(name);
        if (!module) module = LoadLibraryW(name);   // the game resolves these at run time; load so we are first
        if (!module) continue;
        auto attach = [&](void* target, void* detour, void** original) {
            if (!target || alreadyHooked(target)) return false;
            if (!sdk->hooking->Attach(handle, target, detour, original)) return false;
            hookedTargets[hookedCount++] = target;
            return true;
        };
        int ok = 0;
        ok += attach(reinterpret_cast<void*>(GetProcAddress(module, "XInputGetState")), getDetours[slot],
                     reinterpret_cast<void**>(&getOriginal[slot]));
        ok += attach(reinterpret_cast<void*>(GetProcAddress(module, MAKEINTRESOURCEA(100))), getExDetours[slot],
                     reinterpret_cast<void**>(&getExOriginal[slot]));
        ok += attach(reinterpret_cast<void*>(GetProcAddress(module, "XInputSetState")), setDetours[slot],
                     reinterpret_cast<void**>(&setOriginal[slot]));
        ok += attach(reinterpret_cast<void*>(GetProcAddress(module, "XInputGetCapabilities")), capsDetours[slot],
                     reinterpret_cast<void**>(&capsOriginal[slot]));
        char narrow[64]{};
        WideCharToMultiByte(CP_UTF8, 0, name, -1, narrow, sizeof(narrow), nullptr, nullptr);
        RIG_INFO("XInput hook: %s -> %d function(s) attached", narrow, ok);
        if (ok) hookedNames.push_back(std::string(narrow) + ":" + std::to_string(ok));
        ++slot;
    }
    if (hookedCount == 0) RIG_WARN("XInput hook: nothing attached -- the gamepad layer cannot reach the game");
    return hookedCount > 0;
}

void remove(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk)
{
    { std::lock_guard lock(mutex); current.reset(); rumbleSink = nullptr; }
    if (sdk && sdk->hooking && sdk->hooking->Detach)
        for (int i = 0; i < hookedCount; ++i) sdk->hooking->Detach(handle, hookedTargets[i]);
    hookedCount = 0;
}

void setUserIndex(unsigned index) { userIndex = index > 3 ? 0 : index; }

void publish(const VirtualPad& pad)
{
    std::lock_guard lock(mutex);
    if (!(pad == current)) {
        current = pad;
        ++packets;
        if (!pad.idle()) everActive = true;
    }
}

void setRumbleSink(std::function<void(float, float)> sink) { std::lock_guard lock(mutex); rumbleSink = std::move(sink); }

void rumblePhysical(float large, float small)
{
    const unsigned user = userIndex.load();
    XINPUT_VIBRATION v{static_cast<WORD>(std::clamp(large, 0.0f, 1.0f) * 65535), static_cast<WORD>(std::clamp(small, 0.0f, 1.0f) * 65535)};
    for (int i = 0; i < kMax; ++i) if (setOriginal[i]) { setOriginal[i](user, &v); return; }
}

nlohmann::json status()
{
    VirtualPad v;
    { std::lock_guard lock(mutex); v = current; }
    return {{"hooked", hookedCount}, {"modules", hookedNames}, {"user", userIndex.load()}, {"reads", reads.load()},
            {"merges", merges.load()}, {"physicalPad", physicalSeen.load()}, {"virtualActive", everActive.load()},
            {"gameRumble", rumbleEvents.load()}, {"buttons", v.buttons}, {"lx", v.lx}, {"ly", v.ly}, {"rx", v.rx},
            {"ry", v.ry}, {"lt", v.lt}, {"rt", v.rt}};
}

}  // namespace ncm::rig::pad::xinput
