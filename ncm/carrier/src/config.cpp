#include "config.hpp"

#include "log.hpp"

#include <nlohmann/json.hpp>

#include <fstream>

namespace ncm {

Config Config::load(const std::wstring& directory)
{
    Config config;
    const std::wstring path = directory + L"\ncm_carrier.json";
    std::ifstream in(path);
    if (!in) return config;  // absent is the ordinary case, not an error

    try {
        nlohmann::json j;
        in >> j;
        config.port = j.value("port", config.port);
        config.enableHook = j.value("enableHook", config.enableHook);
        config.enableFfb = j.value("enableFfb", config.enableFfb);
        NCM_INFO("config: port %u, hook %s, ffb %s", config.port,
                 config.enableHook ? "on" : "off", config.enableFfb ? "on" : "off");
    } catch (const std::exception& e) {
        NCM_WARN("config unreadable (%s) -- using defaults", e.what());
        return Config{};
    }
    return config;
}

}  // namespace ncm
