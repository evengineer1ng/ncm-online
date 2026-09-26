#include "config.hpp"

#include "log.hpp"

#include <nlohmann/json.hpp>

#include <fstream>

namespace ncm {

Config Config::load(const std::wstring& directory)
{
    Config config;
    // `L"\ncm_carrier.json"` is a NEWLINE followed by `cm_carrier.json`, not a separator followed by a
    // filename. That is KB-133 exactly, in a second place: the log path was fixed for 0.1.1 and this one
    // was not, so every session since has silently run on defaults because the file could never be found.
    const std::wstring path = directory + L"\\ncm_carrier.json";
    std::ifstream in(path);
    if (!in) return config;  // absent is the ordinary case, not an error

    try {
        nlohmann::json j;
        in >> j;
        config.port = j.value("port", config.port);
        config.enableHook = j.value("enableHook", config.enableHook);
        config.enableFfb = j.value("enableFfb", config.enableFfb);
        config.enablePhysicsProbe = j.value("enablePhysicsProbe", config.enablePhysicsProbe);
        NCM_INFO("config: port %u, hook %s, ffb %s, physics probe %s", config.port,
                 config.enableHook ? "on" : "off", config.enableFfb ? "on" : "off",
                 config.enablePhysicsProbe ? "on" : "off");
    } catch (const std::exception& e) {
        NCM_WARN("config unreadable (%s) -- using defaults", e.what());
        return Config{};
    }
    return config;
}

}  // namespace ncm
