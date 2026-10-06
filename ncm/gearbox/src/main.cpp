// NCM Gearbox (L306) -- NCM's own manual transmission.
//   phase 0 (S1): build the manual clones and log the evidence.
//   phase 3a (S2): find where the engine keeps the gear -- an RTTI census, a read-only correlation on the player's car
//   while they drive (r6/scripts/ncm_gearbox), and a hold experiment that is OFF until ncm_gearbox_config.json names
//   a field. The manual itself (input, clutch, neutral, HUD) is built on what this finds.
#include "clones.hpp"
#include "discover.hpp"
#include "log.hpp"
#include "natives.hpp"
#include "stepper.hpp"

#include <RED4ext/RED4ext.hpp>

#include <windows.h>

namespace {
HMODULE module = nullptr;
void* g_handle = nullptr;
const void* g_sdk = nullptr;
std::wstring directory;

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
        const auto specs = ncm::gearbox::loadSpecs(directory + L"\\ncm_gearbox_specs.json");
        std::string lastBase;
        size_t built = 0;
        for (const auto& clone : specs.clones) {
            if (clone.base != lastBase) { ncm::gearbox::dumpModel(clone.base); lastBase = clone.base; }
            if (ncm::gearbox::buildClone(clone, specs.reverseFirst, specs.gearHeadroom)) ++built;
        }
        GBX_INFO("NCM Gearbox %s: %zu of %zu manual clone(s) built", NCM_GEARBOX_VERSION, built, specs.clones.size());
    } catch (const std::exception& e) {
        GBX_ERR("clone build threw: %s -- manuals drive as their model this session", e.what());
    }
    // the S2 instrument (census, physics-step hook) only when the config asks for it; the manual needs neither
    if (ncm::gearbox::discover::instrumenting()) {
        try { ncm::gearbox::discover::census(); } catch (...) { GBX_ERR("census threw; observation continues without it"); }
    }
    return true;
}

bool runningExit(RED4ext::CGameApplication*) { return true; }
}  // namespace

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* info)
{
    info->name = L"NCM Gearbox";
    info->author = L"Night City Motorsports";
    info->version = RED4EXT_V1_SEMVER(0, 2, 4);
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
        g_handle = handle;
        g_sdk = sdk;
        directory = directoryOf(module);
        ncm::gearbox::log::init(directory);
        ncm::gearbox::discover::loadConfig(directory + L"\\ncm_gearbox_config.json");
        ncm::gearbox::natives::registerNatives();
        RED4ext::v1::GameState state{.OnEnter = &runningEnter, .OnUpdate = nullptr, .OnExit = &runningExit};
        if (!sdk || !sdk->gameStates || !sdk->gameStates->Add(handle, RED4ext::EGameStateType::Running, &state))
            GBX_ERR("could not register Running-state lifecycle; plugin remains inert");
    }
    return true;
}
