// NCM Host -- the RED4ext plugin that runs NIGHT CITY MOTORSPORTS 3.0's simulation in single player (L338, KB-385).
//
// CET's Lua sandbox has no coroutines, no load and no setfenv, so the NCM resources (written for OPEN//77's Lua 5.4
// VMs, ~600 CreateThread/Wait threads) cannot run inside it. This plugin embeds Lua 5.4 + SQLite and runs the NCM
// Host (ncm/host/*.lua, unchanged) and the resources in it. CET keeps the deck, the HUD line and the game bindings, and
// talks to this plugin through ONE native: NcmHost_Call(cmd: String, payload: String) -> String (JSON in, JSON out),
// on the game's script thread. Nothing here touches the game itself.
#include "vm.hpp"

#include <RED4ext/RED4ext.hpp>

#include <windows.h>

#include <cstdio>
#include <share.h>
#include <ctime>
#include <memory>
#include <mutex>
#include <string>

namespace {
HMODULE g_module = nullptr;
std::string g_root;
std::unique_ptr<ncm::host::Vm> g_vm;
std::string g_startError;
std::mutex g_logMutex;
FILE* g_logFile = nullptr;

std::string narrow(const std::wstring& w)
{
    if (w.empty()) return {};
    const int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
    std::string s(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), s.data(), n, nullptr, nullptr);
    return s;
}

std::string pluginDir()
{
    wchar_t path[MAX_PATH]{};
    if (!GetModuleFileNameW(g_module, path, MAX_PATH)) return ".";
    std::wstring full(path);
    const auto slash = full.find_last_of(L'\\');
    std::string dir = narrow(slash == std::wstring::npos ? L"." : full.substr(0, slash));
    for (auto& c : dir) if (c == '\\') c = '/';
    return dir;
}

void writeLog(const char* level, const char* message)
{
    std::lock_guard<std::mutex> lock(g_logMutex);
    if (!g_logFile) return;
    const std::time_t t = std::time(nullptr);
    std::tm tm{};
    localtime_s(&tm, &t);
    char stamp[32];
    std::strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tm);
    std::fprintf(g_logFile, "[%s] [%s] %s\n", stamp, level, message);
    std::fflush(g_logFile);
}

using Flags = RED4ext::CBaseFunction::Flags;

// NcmHost_Call(cmd, payload) -> String
void hostCall(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    RED4ext::CString cmd, payload;
    RED4ext::GetParameter(stack, &cmd);
    RED4ext::GetParameter(stack, &payload);
    stack->code++;
    std::string result;
    if (!g_vm) {
        g_vm = std::make_unique<ncm::host::Vm>();
        std::string err;
        if (!g_vm->start(g_root, err)) {
            g_startError = err;
            writeLog("error", ("host failed to start: " + err).c_str());
        }
    }
    if (!g_vm->running()) {
        result = "{\"ok\":false,\"error\":\"NCM Host could not start -- see red4ext/plugins/ncm_host/ncm_host.log\"}";
    } else {
        result = g_vm->call(cmd.c_str(), payload.c_str());
    }
    if (out) *out = RED4ext::CString(result.c_str());
}

// NcmHost_Ready() -> Bool: the plugin is loaded (CET checks this before anything else)
void hostReady(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    stack->code++;
    if (out) *out = true;
}

void registerTypes() {}
void postRegister()
{
    auto* system = RED4ext::CRTTISystem::Get();
    auto add = [system](const char* name, RED4ext::ScriptingFunction_t<void*> callback, const char* result,
                        std::initializer_list<std::pair<const char*, const char*>> parameters) {
        auto* fn = RED4ext::CGlobalFunction::Create(name, name, callback);
        fn->flags = Flags{.isNative = true, .isStatic = true};
        if (result && *result) fn->SetReturnType(result);
        for (const auto& [type, param] : parameters) fn->AddParam(type, param);
        system->RegisterFunction(fn);
    };
    using F = RED4ext::ScriptingFunction_t<void*>;
    add("NcmHost_Call", reinterpret_cast<F>(&hostCall), "String", {{"String", "cmd"}, {"String", "payload"}});
    add("NcmHost_Ready", reinterpret_cast<F>(&hostReady), "Bool", {});
    writeLog("info", "natives registered: NcmHost_Call, NcmHost_Ready");
}

bool runningExit(RED4ext::CGameApplication*)
{
    try {
        if (g_vm && g_vm->running()) g_vm->call("shutdown", "{}");
        g_vm.reset();
    } catch (...) {}
    writeLog("info", "NCM Host stopped");
    return true;
}
}  // namespace

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* info)
{
    info->name = L"NCM Host";
    info->author = L"Night City Motorsports";
    info->version = RED4EXT_V1_SEMVER(3, 0, 0);
    info->runtime = RED4EXT_V1_RUNTIME_VERSION_LATEST;
    info->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports() { return RED4EXT_API_VERSION_1; }

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle handle, RED4ext::v1::EMainReason reason,
                                        const RED4ext::v1::Sdk* sdk)
{
    if (reason == RED4ext::v1::EMainReason::Load) {
        g_module = static_cast<HMODULE>(handle);
        g_root = pluginDir();
        const std::string logPath = g_root + "/ncm_host.log";
        // shared for reading: the log is the first thing anyone opens while the game is still running
        g_logFile = _fsopen(logPath.c_str(), "w", _SH_DENYWR);
        ncm::host::setLogger(&writeLog);
        writeLog("info", ("NCM Host " NCM_HOST_VERSION " loaded at " + g_root).c_str());
        if (auto* system = RED4ext::CRTTISystem::Get()) {
            system->AddRegisterCallback(registerTypes);
            system->AddPostRegisterCallback(postRegister);
        } else {
            writeLog("error", "RTTI unavailable: no natives, NCM Host inert");
        }
        RED4ext::v1::GameState state{.OnEnter = nullptr, .OnUpdate = nullptr, .OnExit = &runningExit};
        if (sdk && sdk->gameStates) sdk->gameStates->Add(handle, RED4ext::EGameStateType::Running, &state);
    } else if (reason == RED4ext::v1::EMainReason::Unload) {
        if (g_logFile) { std::fclose(g_logFile); g_logFile = nullptr; }
    }
    return true;
}
