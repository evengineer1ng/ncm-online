#include "bridge.hpp"
#include "log.hpp"
#include "rtti.hpp"
#include "road_loader.hpp"

#include <RED4ext/RED4ext.hpp>

#include <windows.h>

#include <memory>
#include <chrono>

namespace {
HMODULE module = nullptr;
std::unique_ptr<ncm::pace::Bridge> bridge;
bool trafficProbeEnabled = false;
bool trafficProbeDone = false;
bool trafficProbeUpdateSeen = false;
std::chrono::steady_clock::time_point trafficProbeNext;

std::wstring directoryOf(HMODULE value)
{
    wchar_t path[MAX_PATH]{};
    if (!GetModuleFileNameW(value, path, MAX_PATH)) return L".";
    std::wstring full(path);
    const auto slash = full.find_last_of(L'\\');
    return slash == std::wstring::npos ? L"." : full.substr(0, slash);
}

bool runningEnter(RED4ext::CGameApplication*)
{
    trafficProbeEnabled = GetFileAttributesW((directoryOf(module) + L"\\probe_traffic.flag").c_str()) != INVALID_FILE_ATTRIBUTES;
    trafficProbeDone = false;
    trafficProbeUpdateSeen = false;
    trafficProbeNext = std::chrono::steady_clock::now();
    try {
        bridge = std::make_unique<ncm::pace::Bridge>();
        bridge->start();
    } catch (const std::exception& e) {
        PACE_ERR("bridge failed to start: %s; live races fall back to platform AI", e.what());
    }
    PACE_INFO("NCM Pace %s started", NCM_PACE_VERSION);
    PACE_INFO("traffic-resource probe enabled=%d", trafficProbeEnabled ? 1 : 0);
    try { ncm::pace::rtti::dumpSignatures(); } catch (...) { PACE_ERR("rtti dump failed"); }
    if (trafficProbeEnabled) {
        try { trafficProbeDone = ncm::pace::rtti::probeTrafficResources(); }
        catch (...) { PACE_ERR("traffic-resource initial probe failed"); }
    }
    return true;
}

bool runningUpdate(RED4ext::CGameApplication*)
{
    try { ncm::pace::pollRoadGraph(); } catch (...) { PACE_ERR("road graph load failed"); }
    if (!trafficProbeUpdateSeen) { PACE_INFO("traffic-resource Running update called"); trafficProbeUpdateSeen = true; }
    if (!trafficProbeEnabled || trafficProbeDone || std::chrono::steady_clock::now() < trafficProbeNext) return false;
    trafficProbeNext = std::chrono::steady_clock::now() + std::chrono::seconds(20);
    try { trafficProbeDone = ncm::pace::rtti::probeTrafficResources(); }
    catch (...) { PACE_ERR("traffic-resource probe failed"); trafficProbeDone = true; }
    return false;
}

bool runningExit(RED4ext::CGameApplication*)
{
    try { if (bridge) bridge->stop(); bridge.reset(); } catch (...) {}
    PACE_INFO("NCM Pace stopped cleanly");
    return true;
}
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* info)
{
    info->name = L"NCM Pace";
    info->author = L"Night City Motorsports";
    info->version = RED4EXT_V1_SEMVER(0, 7, 0);
    info->runtime = RED4EXT_V1_RUNTIME_VERSION_LATEST;
    info->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports() { return RED4EXT_API_VERSION_1; }

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle handle,
                                        RED4ext::v1::EMainReason reason,
                                        const RED4ext::v1::Sdk* sdk)
{
    if (reason == RED4ext::v1::EMainReason::Load) {
        module = static_cast<HMODULE>(handle);
        ncm::pace::log::init(directoryOf(module));
        ncm::pace::rtti::registerNatives();
        RED4ext::v1::GameState state{.OnEnter = &runningEnter, .OnUpdate = &runningUpdate, .OnExit = &runningExit};
        if (!sdk || !sdk->gameStates || !sdk->gameStates->Add(handle, RED4ext::EGameStateType::Running, &state))
            PACE_ERR("could not register Running-state lifecycle; plugin remains inert");
    }
    return true;
}
