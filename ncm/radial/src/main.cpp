#include "bridge.hpp"
#include "log.hpp"
#include "rtti.hpp"

#include <RED4ext/RED4ext.hpp>

#include <windows.h>

#include <memory>

namespace {
HMODULE module = nullptr;
std::unique_ptr<ncm::radial::Bridge> bridge;

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
    try {
        bridge = std::make_unique<ncm::radial::Bridge>();
        bridge->start();
    } catch (const std::exception& e) {
        RADIAL_ERR("bridge failed to start: %s; the wheel stays closed", e.what());
    }
    RADIAL_INFO("NCM Radial %s started", NCM_RADIAL_VERSION);
    return true;
}

bool runningExit(RED4ext::CGameApplication*)
{
    try { if (bridge) bridge->stop(); bridge.reset(); } catch (...) {}
    RADIAL_INFO("NCM Radial stopped cleanly");
    return true;
}
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* info)
{
    info->name = L"NCM Radial";
    info->author = L"Night City Motorsports";
    info->version = RED4EXT_V1_SEMVER(0, 1, 0);
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
        ncm::radial::log::init(directoryOf(module));
        ncm::radial::rtti::registerNatives();
        RED4ext::v1::GameState state{.OnEnter = &runningEnter, .OnUpdate = nullptr, .OnExit = &runningExit};
        if (!sdk || !sdk->gameStates || !sdk->gameStates->Add(handle, RED4ext::EGameStateType::Running, &state))
            RADIAL_ERR("could not register Running-state lifecycle; plugin remains inert");
    }
    return true;
}
