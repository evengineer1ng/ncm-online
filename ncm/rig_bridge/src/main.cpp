#include "bridge.hpp"
#include "config.hpp"
#include "direct_input.hpp"
#include "log.hpp"
#include "rtti.hpp"
#include "vehicle_hook.hpp"

#include <RED4ext/RED4ext.hpp>

#include <windows.h>

#include <memory>

namespace {
HMODULE module = nullptr;
RED4ext::v1::PluginHandle pluginHandle{};
const RED4ext::v1::Sdk* pluginSdk = nullptr;
std::unique_ptr<ncm::rig::DirectInputRig> rig;
std::unique_ptr<ncm::rig::Bridge> bridge;
ncm::rig::Config config;

std::wstring directoryOf(HMODULE value)
{
    wchar_t path[MAX_PATH]{};
    if (!GetModuleFileNameW(value, path, MAX_PATH)) return L".";
    std::wstring full(path);
    const auto slash = full.find_last_of(L'\\');
    return slash == std::wstring::npos ? L"." : full.substr(0, slash);
}

template <typename Function>
void stage(const char* name, Function&& function)
{
    try { function(); }
    catch (const std::exception& e) { RIG_ERR("%s failed: %s; remaining stages continue", name, e.what()); }
    catch (...) { RIG_ERR("%s failed unexpectedly; remaining stages continue", name); }
}

bool runningEnter(RED4ext::CGameApplication*)
{
    const auto directory = directoryOf(module);
    stage("config", [&] { config = ncm::rig::Config::load(directory); });
    stage("DirectInput", [&] {
        rig = std::make_unique<ncm::rig::DirectInputRig>(config);
        if (!rig->start()) RIG_WARN("DirectInput provider did not start; bridge diagnostics remain available");
    });
    stage("loopback bridge", [&] {
        if (!rig) return;
        bridge = std::make_unique<ncm::rig::Bridge>(config.port, *rig, directory);
        bridge->start();
    });
    stage("vehicle detour", [&] { ncm::rig::vehicle::install(pluginHandle, pluginSdk, config.inputEnabled); });
    RIG_INFO("NCM Rig Bridge %s started: provider=DirectInput hook=%s", NCM_RIG_BRIDGE_VERSION,
             ncm::rig::vehicle::installed() ? "installed" : "absent");
    return true;
}

bool runningExit(RED4ext::CGameApplication*)
{
    stage("vehicle detour teardown", [&] { ncm::rig::vehicle::remove(pluginHandle, pluginSdk); });
    stage("bridge teardown", [&] { if (bridge) bridge->stop(); bridge.reset(); });
    stage("DirectInput teardown", [&] { if (rig) rig->stop(); rig.reset(); });
    RIG_INFO("NCM Rig Bridge stopped cleanly");
    return true;
}
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* info)
{
    info->name = L"NCM Rig Bridge";
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
        pluginHandle = handle;
        pluginSdk = sdk;
        ncm::rig::log::init(directoryOf(module));
        ncm::rig::rtti::registerNatives();
        RED4ext::v1::GameState state{.OnEnter=&runningEnter,.OnUpdate=nullptr,.OnExit=&runningExit};
        if (!sdk || !sdk->gameStates || !sdk->gameStates->Add(handle, RED4ext::EGameStateType::Running, &state))
            RIG_ERR("could not register Running-state lifecycle; plugin remains inert");
    } else if (reason == RED4ext::v1::EMainReason::Unload) {
        RIG_INFO("RED4ext unload reached after Running-state teardown");
    }
    return true;
}

