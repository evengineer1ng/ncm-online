#include "config.hpp"
#include "log.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <fstream>
#include <ostream>

namespace ncm::rig {
namespace {
void readAxis(const nlohmann::json& root, const char* name, AxisBinding& out)
{
    if (!root.contains(name) || !root[name].is_object()) return;
    const auto& j = root[name];
    out.deviceKey = j.value("device", out.deviceKey);
    out.deviceGuid = j.value("deviceGuid", out.deviceGuid);
    out.deviceName = j.value("deviceName", out.deviceName);
    out.axis = j.value("axis", out.axis);
    out.invert = j.value("invert", out.invert);
    out.minimum = j.value("minimum", out.minimum);
    out.maximum = j.value("maximum", out.maximum);
    out.deadzone = std::clamp(j.value("deadzone", out.deadzone), 0.0f, 0.95f);
}
}

namespace {
nlohmann::json axisJson(const AxisBinding& b)
{
    return {{"device", b.deviceKey}, {"axis", b.axis}, {"invert", b.invert},
            {"minimum", b.minimum}, {"maximum", b.maximum}, {"deadzone", b.deadzone}};
}
}

bool Config::save(const std::wstring& directory) const
{
    nlohmann::json j;
    j["port"] = port;
    j["inputEnabled"] = inputEnabled;
    j["steeringGamma"] = steeringGamma;
    j["steerDegrees"] = steerDegrees;
    j["wheelRangeDegrees"] = wheelRangeDegrees;
    j["axes"] = {{"steering", axisJson(steering)}, {"throttle", axisJson(throttle)},
                 {"brake", axisJson(brake)}, {"clutch", axisJson(clutch)}};
    j["buttons"] = nlohmann::json::array();
    for (const auto& b : buttons)
        j["buttons"].push_back({{"device", b.deviceKey}, {"button", b.button},
                                {"virtualKey", b.virtualKey}, {"vehicleOnly", b.vehicleOnly}});
    j["ffb"] = {{"device", ffbDeviceKey}, {"enabled", ffbEnabled}, {"armed", ffbArmed},
                {"deviceClass", feel::nameOf(deviceClass)}, {"strength", ffbStrength},
                {"spring", tune.spring}, {"damper", tune.damper}, {"texture", tune.texture},
                {"engine", tune.engine}, {"road", tune.road}, {"watchdogMs", ffbWatchdogMs}};

    // Written beside the DLL, next to the log, so a rig's configuration travels with the plugin.
    const std::wstring path = directory + L"\\ncm_rig_bridge.user.json";
    std::ofstream stream(path, std::ios::trunc);
    if (!stream) { RIG_WARN("could not write %ls -- bindings will not survive a restart", path.c_str()); return false; }
    stream << j.dump(2) << "\n";
    RIG_INFO("bindings saved to ncm_rig_bridge.user.json");
    return true;
}

namespace {
/// Applies one file's contents over `out`. Missing file is not an error: the shipped defaults stand.
bool applyFile(const std::wstring& path, Config& out);
}

/// **Two files, and the split matters.** `ncm_rig_bridge.json` ships inside the package, so the launcher
/// re-projects it over the top on every join -- anything written there is erased the next time the player
/// starts the game. Bindings chosen in the panel therefore go to `ncm_rig_bridge.user.json`, which is not
/// in the package and survives. Shipped file first, user file over it.
Config Config::load(const std::wstring& directory)
{
    Config out;
    applyFile(directory + L"\\ncm_rig_bridge.json", out);
    if (applyFile(directory + L"\\ncm_rig_bridge.user.json", out))
        RIG_INFO("user bindings applied over the shipped defaults");
    RIG_INFO("config: port=%u input=%s ffb=%s/%s class=%s strength=%.3f ceiling=%.3f buttons=%zu",
             out.port, out.inputEnabled ? "on" : "off", out.ffbEnabled ? "on" : "off",
             out.ffbArmed ? "armed" : "disarmed", feel::nameOf(out.deviceClass), out.ffbStrength,
             feel::ceilingFor(out.deviceClass), out.buttons.size());
    return out;
}

namespace {
bool applyFile(const std::wstring& path, Config& out)
{
    std::ifstream stream(path);
    if (!stream) return false;
    try {
        nlohmann::json j;
        stream >> j;
        out.port = j.value("port", out.port);
        out.inputEnabled = j.value("inputEnabled", out.inputEnabled);
        out.steeringGamma = std::clamp(j.value("steeringGamma", out.steeringGamma), 0.2f, 2.0f);
        out.steerDegrees = std::clamp(j.value("steerDegrees", out.steerDegrees), 5.0f, 540.0f);
        out.wheelRangeDegrees = std::clamp(j.value("wheelRangeDegrees", out.wheelRangeDegrees), 90.0f, 1440.0f);
        if (j.contains("axes")) {
            readAxis(j["axes"], "steering", out.steering);
            readAxis(j["axes"], "throttle", out.throttle);
            readAxis(j["axes"], "brake", out.brake);
            readAxis(j["axes"], "clutch", out.clutch);
        }
        if (j.contains("ffb") && j["ffb"].is_object()) {
            const auto& f = j["ffb"];
            out.ffbDeviceKey = f.value("device", out.ffbDeviceKey);
            out.ffbDeviceGuid = f.value("deviceGuid", out.ffbDeviceGuid);
            out.ffbDeviceName = f.value("deviceName", out.ffbDeviceName);
            out.ffbEnabled = f.value("enabled", out.ffbEnabled);
            out.ffbArmed = f.value("armed", out.ffbArmed);
            // The class is read FIRST: it decides the ceiling that `strength` is then clamped against, so
            // reading them the other way round would clamp against a stale ladder.
            // Overlay semantics: a key the file omits keeps whatever the previous file set, rather than
            // snapping back to a default. Defaulting to "unknown" here would silently drop the shipped
            // class every time a user file left it out.
            out.deviceClass = feel::classFrom(f.value("deviceClass", std::string(feel::nameOf(out.deviceClass))));
            out.ffbStrength = std::clamp(f.value("strength", out.ffbStrength),
                                         0.0f, feel::ceilingFor(out.deviceClass));
            out.tune.spring = std::clamp(f.value("spring", out.tune.spring), 0.0f, 1.0f);
            out.tune.damper = std::clamp(f.value("damper", out.tune.damper), 0.0f, 1.0f);
            out.tune.texture = std::clamp(f.value("texture", out.tune.texture), 0.0f, 1.0f);
            out.tune.engine = std::clamp(f.value("engine", out.tune.engine), 0.0f, 1.0f);
            out.tune.road = std::clamp(f.value("road", out.tune.road), 0.0f, 1.0f);
            out.ffbWatchdogMs = std::clamp(f.value("watchdogMs", out.ffbWatchdogMs), 100u, 1000u);
        }
        if (j.contains("buttons") && j["buttons"].is_array()) {
            for (const auto& b : j["buttons"]) {
                ButtonBinding bind;
                bind.deviceKey = b.value("device", "");
                bind.deviceGuid = b.value("deviceGuid", "");
                bind.deviceName = b.value("deviceName", "");
                bind.button = b.value("button", 0u);
                bind.virtualKey = static_cast<uint16_t>(b.value("virtualKey", 0u));
                bind.vehicleOnly = b.value("vehicleOnly", true);
                if (bind.button < 128 && bind.virtualKey != 0) out.buttons.push_back(bind);
            }
        }
    } catch (const std::exception& e) {
        RIG_ERR("%ls is invalid (%s); it was ignored rather than half-applied", path.c_str(), e.what());
        return false;
    }
    return true;
}
}
}

