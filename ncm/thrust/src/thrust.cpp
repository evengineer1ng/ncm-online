// NCM Thrust (L316 F0) -- one key, one burn, one lever. The physics is NCM Carrier's; this file only decides when.
#include "thrust.hpp"

#include "log.hpp"
#include "thrust_levers.hpp"

#include <nlohmann/json.hpp>

#include <windows.h>
#include <Xinput.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>
#include <unordered_map>

namespace ncm::thrust {
namespace {

struct Config {
    bool enabled = true;
    std::string fireKey = "H";
    int fireVk = 'H';
    std::string fireButton = "Y";   // owner, 2026-10-04: vertical action from the car is TRIANGLE on a pad (XInput Y)
    WORD fireMask = XINPUT_GAMEPAD_Y;
    float twr = 2.0f;
    uint32_t burnMs = 143;     // r = 2 for 143 ms: peak vz 1.40 m/s, apex 0.20 m (doc 51 §F0)
    bool holdMode = false;
};

Config g_config;
std::wstring g_configPath;
std::filesystem::file_time_type g_configStamp{};

HANDLE g_mapping = nullptr;
ncm::thrust_levers::Block* g_block = nullptr;

std::thread g_thread;
std::atomic<bool> g_running{false};

uint64_t nowMs() { return GetTickCount64(); }

int vkOf(std::string name, int fallback)
{
    std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
    static const std::unordered_map<std::string, int> keys = {
        {"LSHIFT", VK_LSHIFT}, {"RSHIFT", VK_RSHIFT}, {"LCTRL", VK_LCONTROL}, {"RCTRL", VK_RCONTROL},
        {"LALT", VK_LMENU}, {"RALT", VK_RMENU}, {"SPACE", VK_SPACE}, {"HOME", VK_HOME}, {"END", VK_END},
        {"INSERT", VK_INSERT}, {"DELETE", VK_DELETE}, {"MOUSE4", VK_XBUTTON1}, {"MOUSE5", VK_XBUTTON2},
    };
    auto it = keys.find(name);
    if (it != keys.end()) return it->second;
    if (name.size() == 1 && std::isalnum(static_cast<unsigned char>(name[0]))) return static_cast<int>(name[0]);
    return fallback;
}

WORD buttonOf(std::string name, WORD fallback)
{
    std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
    static const std::unordered_map<std::string, int> buttons = {
        {"A", XINPUT_GAMEPAD_A}, {"B", XINPUT_GAMEPAD_B}, {"X", XINPUT_GAMEPAD_X}, {"Y", XINPUT_GAMEPAD_Y},
        {"TRIANGLE", XINPUT_GAMEPAD_Y}, {"SQUARE", XINPUT_GAMEPAD_X}, {"CROSS", XINPUT_GAMEPAD_A}, {"CIRCLE", XINPUT_GAMEPAD_B},
        {"LB", XINPUT_GAMEPAD_LEFT_SHOULDER}, {"RB", XINPUT_GAMEPAD_RIGHT_SHOULDER},
        {"LS", XINPUT_GAMEPAD_LEFT_THUMB}, {"RS", XINPUT_GAMEPAD_RIGHT_THUMB},
        {"DPADUP", XINPUT_GAMEPAD_DPAD_UP}, {"DPADDOWN", XINPUT_GAMEPAD_DPAD_DOWN},
        {"DPADLEFT", XINPUT_GAMEPAD_DPAD_LEFT}, {"DPADRIGHT", XINPUT_GAMEPAD_DPAD_RIGHT}, {"NONE", 0},
    };
    auto it = buttons.find(name);
    return it != buttons.end() ? static_cast<WORD>(it->second) : fallback;
}

/// The first connected pad's buttons (0 when none). Callers check focus first.
WORD padButtons()
{
    for (DWORD i = 0; i < XUSER_MAX_COUNT; ++i) {
        XINPUT_STATE st{};
        if (XInputGetState(i, &st) == ERROR_SUCCESS) return st.Gamepad.wButtons;
    }
    return 0;
}

/// Only this game window's keys: with two games on one PC each pushes only its own car.
bool focused()
{
    DWORD pid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &pid);
    return pid == GetCurrentProcessId();
}

/// Re-read the config when it changes on disk. A file that does not parse keeps the last good values, and says so.
void reloadIfChanged(bool first)
{
    std::error_code ec;
    const auto stamp = std::filesystem::last_write_time(g_configPath, ec);
    if (ec) { if (first) THR_WARN("config: ncm_thrust_config.json not found -- defaults (H, r=2.00, 143 ms)"); return; }
    if (!first && stamp == g_configStamp) return;
    g_configStamp = stamp;
    try {
        std::ifstream in(g_configPath);
        const auto j = nlohmann::json::parse(in);
        Config c = g_config;
        c.enabled = j.value("enabled", c.enabled);
        c.fireKey = j.value("fireKey", c.fireKey);
        c.fireVk = vkOf(c.fireKey, 'H');
        c.fireButton = j.value("fireButton", c.fireButton);
        c.fireMask = buttonOf(c.fireButton, XINPUT_GAMEPAD_Y);
        c.twr = std::clamp(j.value("twr", c.twr), 0.0f, ncm::thrust_levers::kMaxTwr);
        c.burnMs = std::min<uint32_t>(j.value("burnMs", c.burnMs), ncm::thrust_levers::kMaxBurnMs);
        c.holdMode = j.value("holdMode", c.holdMode);
        g_config = c;
        THR_INFO("config: %s -- enabled=%d key=%s pad=%s twr=%.2f burn=%u ms hold=%d", first ? "loaded" : "reloaded",
                 c.enabled ? 1 : 0, c.fireKey.c_str(), c.fireButton.c_str(), c.twr, c.burnMs, c.holdMode ? 1 : 0);
    } catch (const std::exception& e) {
        THR_ERR("config: CONFIG ERROR, not loaded, last good values kept: %s", e.what());
    }
}

bool openBlock()
{
    if (g_block) return true;
    wchar_t name[96];
    ncm::thrust_levers::name(name, 96, GetCurrentProcessId());
    g_mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, sizeof(ncm::thrust_levers::Block), name);
    if (!g_mapping) { THR_ERR("could not create the Carrier lever block"); return false; }
    g_block = static_cast<ncm::thrust_levers::Block*>(MapViewOfFile(g_mapping, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(ncm::thrust_levers::Block)));
    if (!g_block) { CloseHandle(g_mapping); g_mapping = nullptr; THR_ERR("could not map the Carrier lever block"); return false; }
    g_block->stampMs = 0;
    g_block->burnSeq = 0;
    g_block->holding = 0;
    g_block->magic = ncm::thrust_levers::kMagic;
    g_block->version = ncm::thrust_levers::kVersion;
    THR_INFO("publishing the lift lever for NCM Carrier");
    return true;
}

void loop()
{
    reloadIfChanged(true);
    if (!openBlock()) return;
    bool held = false;
    uint32_t burns = 0;
    uint64_t nextReload = nowMs() + 1000;
    while (g_running.load(std::memory_order_acquire)) {
        const uint64_t now = nowMs();
        if (now >= nextReload) { reloadIfChanged(false); nextReload = now + 1000; }
        const Config c = g_config;
        if (c.enabled) {
            const bool focus = focused();
            const bool key = focus && (GetAsyncKeyState(c.fireVk) & 0x8000) != 0;
            const bool pad = focus && c.fireMask != 0 && (padButtons() & c.fireMask) != 0;
            const bool down = key || pad;
            const bool edge = down && !held;
            held = down;
            g_block->twr = c.twr;
            g_block->burnMs = c.burnMs;
            g_block->holding = (c.holdMode && down) ? 1u : 0u;
            if (edge && !c.holdMode) {
                g_block->burnSeq = g_block->burnSeq + 1;
                THR_INFO("burn #%u requested (%s): twr=%.2f for %u ms", ++burns, pad ? "pad" : "key", c.twr, c.burnMs);
            } else if (edge) {
                THR_INFO("hold: burning at twr=%.2f while %s / pad %s is held", c.twr, c.fireKey.c_str(), c.fireButton.c_str());
            }
            g_block->seq = g_block->seq + 1;
            g_block->stampMs = now;   // last, so Carrier never sees a fresh stamp over half-written values
        }
        Sleep(5);
    }
}

}  // namespace

void start(const std::wstring& directory)
{
    g_configPath = directory + L"\\ncm_thrust_config.json";
    if (g_running.exchange(true)) return;
    g_thread = std::thread(loop);
}

void stop()
{
    if (!g_running.exchange(false)) return;
    if (g_thread.joinable()) g_thread.join();
    if (g_block) { g_block->stampMs = 0; UnmapViewOfFile(g_block); g_block = nullptr; }
    if (g_mapping) { CloseHandle(g_mapping); g_mapping = nullptr; }
}

}  // namespace ncm::thrust
