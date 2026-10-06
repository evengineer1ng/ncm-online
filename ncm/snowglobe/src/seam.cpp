// NCM Snowglobe (L317 SEAM-1) -- the seam key and its config. The move itself is the game's own TeleportationFacility,
// called from NcmSnowglobe.reds; this file only says when, and by how much.
#include "seam.hpp"

#include "log.hpp"

#include <nlohmann/json.hpp>

#include <windows.h>
#include <Xinput.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace ncm::snowglobe::seam {
namespace {

struct Config {
    bool enabled = true;
    std::string key = "J";
    int vk = 'J';
    std::string button = "NONE";
    WORD mask = 0;
    float offset[3] = {0.0f, 0.0f, -2000.0f};   // SEAM-1: drop the car 2 km straight down, mid-air, and keep flying
    float minZ = 3000.0f;
    int watchFrames = 90;
};

std::mutex g_mutex;
Config g_config;
std::wstring g_path;
std::filesystem::file_time_type g_stamp{};
std::atomic<int> g_requests{0};
std::thread g_thread;
std::atomic<bool> g_running{false};

int vkOf(std::string name, int fallback)
{
    std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
    static const std::unordered_map<std::string, int> keys = {
        {"HOME", VK_HOME}, {"END", VK_END}, {"INSERT", VK_INSERT}, {"DELETE", VK_DELETE},
        {"PAGEUP", VK_PRIOR}, {"PAGEDOWN", VK_NEXT}, {"F9", VK_F9}, {"F10", VK_F10}, {"F11", VK_F11},
    };
    auto it = keys.find(name);
    if (it != keys.end()) return it->second;
    if (name.size() == 1 && std::isalnum(static_cast<unsigned char>(name[0]))) return static_cast<int>(name[0]);
    return fallback;
}

WORD buttonOf(std::string name)
{
    std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
    static const std::unordered_map<std::string, int> buttons = {
        {"DPADUP", XINPUT_GAMEPAD_DPAD_UP}, {"DPADDOWN", XINPUT_GAMEPAD_DPAD_DOWN},
        {"DPADLEFT", XINPUT_GAMEPAD_DPAD_LEFT}, {"DPADRIGHT", XINPUT_GAMEPAD_DPAD_RIGHT},
        {"BACK", XINPUT_GAMEPAD_BACK}, {"LS", XINPUT_GAMEPAD_LEFT_THUMB}, {"RS", XINPUT_GAMEPAD_RIGHT_THUMB},
    };
    auto it = buttons.find(name);
    return it != buttons.end() ? static_cast<WORD>(it->second) : 0;
}

bool focused()
{
    DWORD pid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &pid);
    return pid == GetCurrentProcessId();
}

WORD padButtons()
{
    for (DWORD i = 0; i < XUSER_MAX_COUNT; ++i) {
        XINPUT_STATE st{};
        if (XInputGetState(i, &st) == ERROR_SUCCESS) return st.Gamepad.wButtons;
    }
    return 0;
}

void reload(bool first)
{
    std::error_code ec;
    const auto stamp = std::filesystem::last_write_time(g_path, ec);
    if (ec) { if (first) SNG_WARN("config: ncm_snowglobe_config.json not found -- defaults (J, drop 2000 m, above 3000 m)"); return; }
    if (!first && stamp == g_stamp) return;
    g_stamp = stamp;
    try {
        std::ifstream in(g_path);
        const auto j = nlohmann::json::parse(in);
        std::lock_guard<std::mutex> lock(g_mutex);
        Config c = g_config;
        c.enabled = j.value("enabled", c.enabled);
        c.key = j.value("seamKey", c.key);
        c.vk = vkOf(c.key, 'J');
        c.button = j.value("seamButton", c.button);
        c.mask = buttonOf(c.button);
        if (j.contains("offset") && j["offset"].is_array() && j["offset"].size() == 3)
            for (int i = 0; i < 3; ++i) c.offset[i] = std::clamp(j["offset"][i].get<float>(), -12000.0f, 12000.0f);
        c.minZ = j.value("minZ", c.minZ);
        c.watchFrames = std::clamp(j.value("watchFrames", c.watchFrames), 10, 600);
        g_config = c;
        SNG_INFO("config: %s -- enabled=%d key=%s pad=%s offset=(%.0f, %.0f, %.0f) minZ=%.0f watch=%d frames",
                 first ? "loaded" : "reloaded", c.enabled ? 1 : 0, c.key.c_str(), c.button.c_str(), c.offset[0],
                 c.offset[1], c.offset[2], c.minZ, c.watchFrames);
    } catch (const std::exception& e) {
        SNG_ERR("config: CONFIG ERROR, not loaded, last good values kept: %s", e.what());
    }
}

void loop()
{
    reload(true);
    bool held = false;
    uint64_t nextReload = GetTickCount64() + 1000;
    while (g_running.load(std::memory_order_acquire)) {
        const uint64_t now = GetTickCount64();
        if (now >= nextReload) { reload(false); nextReload = now + 1000; }
        Config c;
        { std::lock_guard<std::mutex> lock(g_mutex); c = g_config; }
        const bool focus = c.enabled && focused();
        const bool down = focus && (((GetAsyncKeyState(c.vk) & 0x8000) != 0) || (c.mask && (padButtons() & c.mask)));
        if (down && !held) {
            g_requests.fetch_add(1, std::memory_order_acq_rel);
            SNG_INFO("seam requested: move the car by (%.0f, %.0f, %.0f)", c.offset[0], c.offset[1], c.offset[2]);
        }
        held = down;
        Sleep(5);
    }
}

}  // namespace

void start(const std::wstring& directory)
{
    g_path = directory + L"\\ncm_snowglobe_config.json";
    if (g_running.exchange(true)) return;
    g_thread = std::thread(loop);
}

void stop()
{
    if (!g_running.exchange(false)) return;
    if (g_thread.joinable()) g_thread.join();
}

int consumeRequests() { return g_requests.exchange(0, std::memory_order_acq_rel); }

float offset(int axis)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    return (axis >= 0 && axis < 3) ? g_config.offset[axis] : 0.0f;
}

float minZ() { std::lock_guard<std::mutex> lock(g_mutex); return g_config.minZ; }
int watchFrames() { std::lock_guard<std::mutex> lock(g_mutex); return g_config.watchFrames; }

}  // namespace ncm::snowglobe::seam
