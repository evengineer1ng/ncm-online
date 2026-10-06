// NCM Snowglobe (L317) -- the doorway above Night City. 0.0.1 is SEAM-1 only: can the game move the occupied car in
// mid-air and keep its velocity and its driver? A dev key asks; NcmSnowglobe.reds moves the car with the game's own
// TeleportationFacility and measures before and after. Dev only.
#include "log.hpp"
#include "seam.hpp"

#include <RED4ext/RED4ext.hpp>

#include <windows.h>

namespace ncm::snowglobe::natives { void registerNatives(); }

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
    info->name = L"NCM Snowglobe";
    info->author = L"Night City Motorsports";
    info->version = RED4EXT_V1_SEMVER(0, 0, 5);
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
        ncm::snowglobe::log::init(directory);
        SNG_INFO("NCM Snowglobe %s: SEAM-1 -- press the seam key in a car above minZ", NCM_SNOWGLOBE_VERSION);
        ncm::snowglobe::natives::registerNatives();
        ncm::snowglobe::seam::start(directory);
    } else if (reason == RED4ext::v1::EMainReason::Unload) {
        ncm::snowglobe::seam::stop();
    }
    return true;
}
