#include "bridge.hpp"
#include "log.hpp"
#include "natives.hpp"
#include "player.hpp"

#include <RED4ext/RED4ext.hpp>

#include <windows.h>

#include <memory>

// NCM Radio (doc 59): Race Week Live as a station in the game's own radio list. This plugin only PLAYS: the
// `ncm_radio` resource decides the programme on the server, the station's redscript says whether the player is
// listening, and the authored, pre-rendered clips ship beside this DLL in `pack/`. It shares no code, state, port
// range or package with the Carrier, the Rig Bridge, Pace or any other NCM plugin.
namespace {
HMODULE module = nullptr;
std::unique_ptr<ncm::radio::Player> player;
std::unique_ptr<ncm::radio::Bridge> bridge;

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
        if (player && player->start()) {
            bridge = std::make_unique<ncm::radio::Bridge>(*player);
            bridge->start();
        }
    } catch (const std::exception& e) {
        RADIO_ERR("start failed: %s; the station stays silent", e.what());
    }
    RADIO_INFO("NCM Radio %s started", NCM_RADIO_VERSION);
    return true;
}

bool runningUpdate(RED4ext::CGameApplication*)
{
    try { if (player) player->update(); } catch (...) { RADIO_ERR("update failed"); }
    return false;
}

bool runningExit(RED4ext::CGameApplication*)
{
    try { if (bridge) bridge->stop(); bridge.reset(); } catch (...) {}
    RADIO_INFO("NCM Radio stopped cleanly");
    return true;
}
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* info)
{
    info->name = L"NCM Radio";
    info->author = L"Night City Motorsports";
    info->version = RED4EXT_V1_SEMVER(NCM_RADIO_MAJOR, NCM_RADIO_MINOR, NCM_RADIO_PATCH);
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
        const auto dir = directoryOf(module);
        ncm::radio::log::init(dir);
        player = std::make_unique<ncm::radio::Player>(dir + L"\\pack");
        ncm::radio::natives::attach(player.get(), dir);
        ncm::radio::natives::registerNatives();
        RED4ext::v1::GameState state{.OnEnter = &runningEnter, .OnUpdate = &runningUpdate, .OnExit = &runningExit};
        if (!sdk || !sdk->gameStates || !sdk->gameStates->Add(handle, RED4ext::EGameStateType::Running, &state))
            RADIO_ERR("could not register Running-state lifecycle; plugin remains inert");
    } else if (reason == RED4ext::v1::EMainReason::Unload) {
        bridge.reset();
        player.reset();
    }
    return true;
}
