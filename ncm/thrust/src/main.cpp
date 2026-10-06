// NCM Thrust (L316 F0) -- the first rung of the flight ladder: one physical part that produces force.
// Press the fire key in a seated NCM car and NCM Carrier lifts it by a thrust-to-weight ratio for one burn. Dev only.
#include "log.hpp"
#include "thrust.hpp"

#include <RED4ext/RED4ext.hpp>

#include <windows.h>

namespace {
std::wstring directoryOf(HMODULE value)
{
    wchar_t path[MAX_PATH]{};
    if (!GetModuleFileNameW(value, path, MAX_PATH)) return L".";
    std::wstring full(path);
    const auto slash = full.find_last_of(L'\\');
    return slash == std::wstring::npos ? L"." : full.substr(0, slash);
}
}  // namespace

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* info)
{
    info->name = L"NCM Thrust";
    info->author = L"Night City Motorsports";
    info->version = RED4EXT_V1_SEMVER(0, 0, 2);
    info->runtime = RED4EXT_V1_RUNTIME_VERSION_LATEST;
    info->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports() { return RED4EXT_API_VERSION_1; }

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle handle,
                                        RED4ext::v1::EMainReason reason,
                                        const RED4ext::v1::Sdk*)
{
    if (reason == RED4ext::v1::EMainReason::Load) {
        const auto directory = directoryOf(static_cast<HMODULE>(handle));
        ncm::thrust::log::init(directory);
        THR_INFO("NCM Thrust %s: the lift lever needs NCM Carrier 0.1.33+ and a seated NCM car", NCM_THRUST_VERSION);
        ncm::thrust::start(directory);
    } else if (reason == RED4ext::v1::EMainReason::Unload) {
        ncm::thrust::stop();
    }
    return true;
}
