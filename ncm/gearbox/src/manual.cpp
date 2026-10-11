#include "manual.hpp"

#include "clones.hpp"
#include "gearing_shm.hpp"
#include "levers_shm.hpp"
#include "log.hpp"

#include <windows.h>
#include <Xinput.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <vector>
#include <cstdio>

namespace ncm::gearbox::manual {
namespace {

std::mutex g_mutex;
std::unordered_map<uint64_t, VirtualSpec> g_specs;

int g_upVk = VK_LSHIFT, g_downVk = VK_LCONTROL;
bool g_upHeld = false, g_downHeld = false;
// the pad (owner, 2026-10-04: "A and X on an Xbox controller for shift down and up")
WORD g_padUp = XINPUT_GAMEPAD_X, g_padDown = XINPUT_GAMEPAD_A;
bool g_padUpHeld = false, g_padDownHeld = false;

uint64_t g_record = 0;
int32_t g_gear = 0;
uint64_t g_cutUntilMs = 0;
float g_rpm = 0.0f;
float g_frac = 0.0f;           // 0 idle .. 1 the gear's limiter (the HUD bar, the engine sound)
int32_t g_event = 0;
uint64_t g_shifts = 0, g_refused = 0;
uint64_t g_lastTickMs = 0;
bool g_engineAudio = true;
std::string g_audioScale = "band";   // band (0.3.0 default) | curve | blend | rpm (idle .. shift rpm) | limiter | fraction | off
// ---- THE BAND (0.3.0, owner: "still sounds like a tape skipping over" -- two writers on veh_engine_rpm, ours and the
// game's, every frame): stop writing the sound at all. Instead each shift repoints the clone's ONE native gear's
// `.maxSpeed` to the selected gear's limiter, so the game's own engine sweeps its own rpm -- and its own sound -- idle
// at rest to redline at that gear's limit. `.minSpeed` stays 0 (a floor the engine pushes toward). The game still never
// shifts; the driver moves the band. Other modes put the full band back.
float g_bandAppliedMps = -1.0f;   // the long gear's ceiling we last wrote (-1 = untouched / restored)
float g_bandAppliedLo = 0.0f, g_bandAppliedHi = 0.0f;
// 0.3.1 (owner on 0.3.0: "middle gears though all sound the same ... it just plays the same pitch until you shift"):
// the 0.3.0 trace showed the game's rpm parked near 4,200 in gears 3-6, because with the band starting at 0 km/h a
// middle gear only ever drives its top quarter. Each shift now also sets the gear's rpm window so that the speed you
// LAND at after the upshift (the previous gear's limiter) maps to `landingRpm` and this gear's limiter to
// `redlineRpm`: minEngineRPM = landing - (redline - landing) * f0 / (1 - f0), f0 = previous limiter / this limiter.
// For a close box that minimum goes far below zero; `minRpmFloor` clamps it if the game dislikes negatives.
float g_landingRpm = 2600.0f, g_redlineRpm = 5300.0f, g_minRpmFloor = -30000.0f;
uint64_t g_bandGear = 0;          // the record whose slices were last written (0 = none)
int g_bandFails = 0;
int g_slices = 7;                  // 0.4.0: native slices per selected gear (`manual.band.slices`, 1..7)
int g_bandSlicesApplied = 0;
float g_audioRpm = 0.0f;           // the engine note's rpm this frame (scale rpm)
float g_audioIdle = 800.0f, g_audioTop = 4500.0f;
int g_cycleVk = VK_PRIOR;          // PAGEUP: cycle the engine-sound scale live (0.2.6 experiment)
bool g_cycleHeld = false;
uint64_t g_lastTraceMs = 0;
float g_lastWritten = -1.0f;      // what engineAudioValue() last handed the script
float g_dashSpeed = -1.0f;        // the vehicle blackboard's SpeedValue -- what the car's own dash shows (trace only)

// ---- THE BLEND (0.2.7, owner 2026-10-04): "whatever you did with pgup produced engine sounds ... lets just make it
// composable into a general rpm formula" -- quietest at the bottom of a gear, loudest at the top, every layer always
// audible: a crescendo. `veh_engine_rpm` takes ONE value a frame, and the game writes its own every frame too (0.2.6
// trace: its throttle-flare rpm, never ours), so what the owner heard per preset was already a mix. The blend makes that
// mix deliberate: each frame writes ONE layer -- or, for `off`, nothing, so the game's own value plays -- in
// proportions that slide along the layers (quietest first) as the gear runs from its floor to its limiter. Error
// diffusion, not dice: the same revs always produce the same pattern.
std::vector<std::string> g_blendLayers = {"fraction", "off", "rpm", "limiter"};
float g_blendFloor = 0.12f;       // every layer's minimum weight, so all of them are heard across the whole ramp
float g_blendAcc[8] = {};
int g_blendLast = -1;

// ---- THE CURVE (0.2.8, owner on the blend: "right idea ... but its mixed weirdly, clearly kinda chopped, need harmonic
// or melodic"): the blend hopped each frame between values thousands of rpm apart. The curve is ONE continuous value:
// lo .. hi across each gear, shaped by gamma (>1 lingers low and climbs hard near the limiter -- the crescendo), pulled
// `follow` of the way toward the game's own rpm (which it writes every frame anyway, so the two writers stop fighting),
// and slewed with a `smoothMs` time constant so an upshift falls like revs instead of cutting. All live-tunable: the
// config file is re-read while the game runs (`manual.curve`).
float g_curveLo = 1500.0f, g_curveHi = 5300.0f, g_curveGamma = 1.6f, g_follow = 0.3f, g_smoothMs = 120.0f;
float g_gameRpm = 0.0f;           // the vehicle blackboard's RPMValue last frame (the game's own; we no longer write it)
float g_smoothed = -1.0f;
std::string g_configError;        // 0.2.9: the last reload's parse error ("" = the file loaded); shown on the HUD
uint64_t g_smoothAtMs = 0;
std::string g_audio;

HANDLE g_mapping = nullptr;
ncm::gearbox_levers::Block* g_block = nullptr;

uint64_t nowMs() { return GetTickCount64(); }

// ---- STACKED GEARBOXES (owner, 2026-10-08; doc 50 R4) ------------------------------------------------------------
// The Machine's driveline paths arrive from the server through NCM Carrier (gearing_shm.hpp), written relative to the
// car's own box: `A*m` each of the car's gears times m, `T*m` its top gear times m (core engineering.gearing). A gear
// with ratio factor m keeps the car gear's force-speed trade: its ceiling divides by m, its share multiplies by m (and
// by the path's efficiency) -- capped at 1, because Carrier's levers only take drive away. Path 0 is the car's box plus
// any inline boxes; each side box is its own path, engaged by the driver's bound control. Stale = the car's box alone.
struct StackEntry { bool all = true; float m = 1.0f; int group = 0; };
struct StackPath {
    std::string when = "any", rangeWhen = "any", label;
    int shiftMs = 0, rangeMs = 0;
    float efficiency = 1.0f;
    std::vector<StackEntry> entries;
};
HANDLE g_gearingMap = nullptr;
const ncm::gearing_shm::Block* g_gearing = nullptr;
uint64_t g_gearingTryMs = 0;
uint32_t g_textSeq = 0;
bool g_selectKnown = false;
uint32_t g_selectSeq = 0;
std::vector<StackPath> g_paths;     // empty = no stacked boxes
bool g_stackLive = false;
int g_path = 0;
std::vector<int> g_groups;          // the active ladder's range group per gear (parallel to the effective gears)

int whenRank(const std::string& w) { return w == "stationary" ? 2 : (w == "neutral" ? 1 : 0); }

std::vector<std::string> split(const std::string& s, char c)
{
    std::vector<std::string> out;
    size_t at = 0;
    for (;;) {
        const size_t k = s.find(c, at);
        out.push_back(s.substr(at, k == std::string::npos ? std::string::npos : k - at));
        if (k == std::string::npos) break;
        at = k + 1;
    }
    return out;
}

/// engineering.gearing wire text -> paths. Anything malformed refuses the whole text (the car's own box drives).
bool parseStack(const std::string& text, std::vector<StackPath>& out)
{
    out.clear();
    if (text.empty()) return true;
    const auto paths = split(text, ';');
    if (paths.empty() || paths[0] != "v1") return false;
    for (size_t i = 1; i < paths.size() && out.size() < 4; ++i) {
        const auto parts = split(paths[i], '|');
        const auto head = split(parts[0], ',');
        if (head.size() < 7 || head[0] != "P") return false;
        StackPath p;
        p.when = head[1];
        p.shiftMs = std::atoi(head[2].c_str());
        p.rangeWhen = head[3];
        p.rangeMs = std::atoi(head[4].c_str());
        p.efficiency = std::clamp(static_cast<float>(std::atof(head[5].c_str())), 0.0f, 1.0f);
        p.label = head[6];
        for (size_t k = 1; k < parts.size() && p.entries.size() < 32; ++k) {
            const std::string& e = parts[k];   // A*2.4@1
            const size_t star = e.find('*'), at = e.find('@');
            if (e.size() < 4 || star != 1 || at == std::string::npos || at < star) return false;
            StackEntry x;
            x.all = e[0] == 'A';
            if (!x.all && e[0] != 'T') return false;
            x.m = static_cast<float>(std::atof(e.substr(star + 1, at - star - 1).c_str()));
            x.group = std::atoi(e.substr(at + 1).c_str());
            if (!(x.m > 0.05f && x.m < 20.0f)) return false;
            p.entries.push_back(x);
        }
        if (p.entries.empty()) return false;
        out.push_back(std::move(p));
    }
    return true;
}

/// Read the relayed block (once a second until NCM Carrier has created it). Returns true while stacked boxes are live.
bool pollStack(uint64_t now)
{
    if (!g_gearing) {
        if (now - g_gearingTryMs < 1000) return false;
        g_gearingTryMs = now;
        wchar_t name[96];
        ncm::gearing_shm::name(name, 96, GetCurrentProcessId());
        HANDLE h = OpenFileMappingW(FILE_MAP_READ, FALSE, name);
        if (!h) return false;
        void* view = MapViewOfFile(h, FILE_MAP_READ, 0, 0, sizeof(ncm::gearing_shm::Block));
        if (!view) { CloseHandle(h); return false; }
        const auto* b = static_cast<const ncm::gearing_shm::Block*>(view);
        if (b->magic != ncm::gearing_shm::kMagic || b->version != ncm::gearing_shm::kVersion) {
            GBX_WARN("stack: NCM Carrier's gearing block has the wrong magic/version; stacked gearboxes off");
            UnmapViewOfFile(view); CloseHandle(h); g_gearingTryMs = now + 60000; return false;
        }
        g_gearingMap = h;
        g_gearing = b;
        GBX_INFO("stack: reading stacked-gearbox paths relayed by NCM Carrier");
    }
    const uint64_t at = g_gearing->stampMs;
    const bool fresh = at != 0 && now >= at && now - at <= ncm::gearing_shm::kStaleMs;
    if (fresh && g_gearing->textSeq != g_textSeq) {
        char copy[ncm::gearing_shm::kTextBytes];
        uint32_t len = 0, seq = 0;
        for (int tries = 0; tries < 3; ++tries) {
            seq = g_gearing->seq;
            len = std::min<uint32_t>(static_cast<uint32_t>(g_gearing->textLen), ncm::gearing_shm::kTextBytes - 1);
            std::memcpy(copy, g_gearing->text, len);
            if (seq == g_gearing->seq && (seq % 2) == 0) break;
        }
        copy[len] = 0;
        g_textSeq = g_gearing->textSeq;
        std::vector<StackPath> parsed;
        if (parseStack(copy, parsed)) {
            g_paths = std::move(parsed);
            if (g_path >= static_cast<int>(g_paths.size())) g_path = 0;
            std::string desc;
            for (size_t i = 0; i < g_paths.size(); ++i) {
                char b[160];
                std::snprintf(b, sizeof b, "%s[%zu] %s: %zu stage(s), engage %s%s", desc.empty() ? "" : " | ", i, g_paths[i].label.c_str(),
                              g_paths[i].entries.size(), g_paths[i].when.c_str(), g_paths[i].rangeWhen != "any" ? (", range " + g_paths[i].rangeWhen).c_str() : "");
                desc += b;
            }
            GBX_INFO("stack: %s", g_paths.empty() ? "no stacked boxes (the car's own box)" : desc.c_str());
        } else {
            g_paths.clear();
            GBX_WARN("stack: could not read the paths (%s); the car's own box drives", copy);
        }
    }
    if (fresh != g_stackLive) {
        g_stackLive = fresh;
        if (!fresh) { g_path = 0; GBX_INFO("stack: no word from NCM Carrier for %llu ms; the car's own box drives", static_cast<unsigned long long>(ncm::gearing_shm::kStaleMs)); }
    }
    return g_stackLive && !g_paths.empty();
}

/// The effective box this frame: the car's spec, or the active path laddered from it (sorted by ceiling, duplicates
/// within one path dropped -- never across paths).
VirtualSpec effective(const VirtualSpec& spec, bool stacked)
{
    g_groups.assign(spec.gears.size(), 0);
    if (!stacked || spec.gears.empty() || g_path < 0 || g_path >= static_cast<int>(g_paths.size())) return spec;
    const StackPath& p = g_paths[static_cast<size_t>(g_path)];
    struct G { VirtualGear vg; int group; };
    std::vector<G> ladder;
    auto add = [&](const VirtualGear& base, float m, int group) {
        VirtualGear vg;
        vg.ceilingMps = base.ceilingMps / m;
        vg.share = std::min(1.0f, base.share * m * p.efficiency);
        ladder.push_back({vg, group});
    };
    for (const auto& e : p.entries) {
        if (e.all) for (const auto& g : spec.gears) add(g, e.m, e.group);
        else add(spec.gears.back(), e.m, e.group);
    }
    std::stable_sort(ladder.begin(), ladder.end(), [](const G& a, const G& b) { return a.vg.ceilingMps < b.vg.ceilingMps; });
    VirtualSpec out = spec;
    out.gears.clear();
    g_groups.clear();
    for (const auto& g : ladder) {
        if (!out.gears.empty() && std::fabs(g.vg.ceilingMps - out.gears.back().ceilingMps) <= out.gears.back().ceilingMps * 0.005f) continue;
        if (out.gears.size() >= 32) break;
        out.gears.push_back(g.vg);
        g_groups.push_back(g.group);
    }
    out.shiftMs = std::max(spec.shiftMs, p.shiftMs);
    return out;
}

int vkOf(std::string name, int fallback)
{
    std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
    static const std::unordered_map<std::string, int> keys = {
        {"LSHIFT", VK_LSHIFT}, {"RSHIFT", VK_RSHIFT}, {"LCTRL", VK_LCONTROL}, {"LCONTROL", VK_LCONTROL},
        {"RCTRL", VK_RCONTROL}, {"RCONTROL", VK_RCONTROL}, {"LALT", VK_LMENU}, {"RALT", VK_RMENU},
        {"UP", VK_UP}, {"DOWN", VK_DOWN}, {"PAGEUP", VK_PRIOR}, {"PAGEDOWN", VK_NEXT}, {"TAB", VK_TAB},
        {"CAPSLOCK", VK_CAPITAL}, {"MOUSE4", VK_XBUTTON1}, {"MOUSE5", VK_XBUTTON2},
    };
    auto it = keys.find(name);
    if (it != keys.end()) return it->second;
    if (name.size() == 1 && std::isalnum(static_cast<unsigned char>(name[0]))) return static_cast<int>(name[0]);
    return fallback;
}

/// Only this game window's keys: with two games on one PC each shifts only its own car.
bool focused()
{
    DWORD pid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &pid);
    return pid == GetCurrentProcessId();
}

WORD buttonOf(std::string name, WORD fallback)
{
    std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
    static const std::unordered_map<std::string, int> buttons = {
        {"A", XINPUT_GAMEPAD_A}, {"B", XINPUT_GAMEPAD_B}, {"X", XINPUT_GAMEPAD_X}, {"Y", XINPUT_GAMEPAD_Y},
        {"LB", XINPUT_GAMEPAD_LEFT_SHOULDER}, {"RB", XINPUT_GAMEPAD_RIGHT_SHOULDER},
        {"LS", XINPUT_GAMEPAD_LEFT_THUMB}, {"RS", XINPUT_GAMEPAD_RIGHT_THUMB},
        {"DPADUP", XINPUT_GAMEPAD_DPAD_UP}, {"DPADDOWN", XINPUT_GAMEPAD_DPAD_DOWN},
        {"DPADLEFT", XINPUT_GAMEPAD_DPAD_LEFT}, {"DPADRIGHT", XINPUT_GAMEPAD_DPAD_RIGHT},
        {"BACK", XINPUT_GAMEPAD_BACK}, {"START", XINPUT_GAMEPAD_START}, {"NONE", 0},
    };
    auto it = buttons.find(name);
    return it != buttons.end() ? static_cast<WORD>(it->second) : fallback;
}

/// The first connected pad's buttons (0 when none, or when this window does not have focus).
WORD padButtons()
{
    if (!focused()) return 0;
    for (DWORD i = 0; i < XUSER_MAX_COUNT; ++i) {
        XINPUT_STATE st{};
        if (XInputGetState(i, &st) == ERROR_SUCCESS) return st.Gamepad.wButtons;
    }
    return 0;
}

bool padPressed(WORD buttons, WORD mask, bool& held)
{
    const bool down = mask != 0 && (buttons & mask) != 0;
    const bool edge = down && !held;
    held = down;
    return edge;
}

bool pressed(int vk, bool& held)
{
    const bool down = focused() && (GetAsyncKeyState(vk) & 0x8000) != 0;
    const bool edge = down && !held;
    held = down;
    return edge;
}

void publish(float drive, float ceiling)
{
    if (!g_block) {
        wchar_t name[96];
        ncm::gearbox_levers::name(name, 96, GetCurrentProcessId());
        g_mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, sizeof(ncm::gearbox_levers::Block), name);
        if (!g_mapping) { static bool warned = false; if (!warned) { warned = true; GBX_ERR("manual: could not create the Carrier lever block"); } return; }
        g_block = static_cast<ncm::gearbox_levers::Block*>(MapViewOfFile(g_mapping, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(ncm::gearbox_levers::Block)));
        if (!g_block) { CloseHandle(g_mapping); g_mapping = nullptr; return; }
        g_block->magic = ncm::gearbox_levers::kMagic;
        g_block->version = ncm::gearbox_levers::kVersion;
        g_block->stampMs = 0;
        GBX_INFO("manual: publishing gear levers for NCM Carrier");
    }
    g_block->driveMul = std::clamp(drive, 0.0f, 1.0f);
    g_block->ceilingMps = ceiling;
    g_block->gear = g_gear;
    g_block->seq = g_block->seq + 1;
    g_block->stampMs = nowMs();
}

}  // namespace

namespace {
/// The model's torque multiplier at road speed `mps`: its first forward gear reaching it (the automatic's gear there).
float modelTorqueAt(const VirtualSpec& spec, float mps)
{
    for (size_t i = 0; i < spec.modelTopMps.size() && i < spec.modelTorque.size(); ++i)
        if (spec.modelTopMps[i] >= mps) return spec.modelTorque[i];
    return spec.modelTorque.empty() ? 1.0f : spec.modelTorque.back();
}

/// 0.4.0, THE SLICES: the selected gear's band 0..`mps`, rpm `lo`..`hi`, cut across the clone's seven native gears
/// once (no write when it is already there). Every slice starts at 0 km/h on the same rpm line and ends at its own top,
/// so the game's own engine moves up through them without a jump in the revs; each takes the model's torque at its top.
/// Slices past `g_slices` sit just above the limiter, where Carrier's ceiling never lets the car go.
void applyBand(const VirtualSpec& spec, uint64_t record, float mps, float lo, float hi, const char* why)
{
    if (spec.slices.size() != static_cast<size_t>(ncm::gearbox::kSlices) || !(mps > 0.5f)) return;
    if (g_bandGear == record && g_bandSlicesApplied == g_slices && std::fabs(g_bandAppliedMps - mps) < 0.01f
        && std::fabs(g_bandAppliedLo - lo) < 0.5f && std::fabs(g_bandAppliedHi - hi) < 0.5f) return;
    const int n = std::clamp(g_slices, 1, ncm::gearbox::kSlices);
    bool ok = true;
    char tops[160] = "";
    for (int k = 0; k < ncm::gearbox::kSlices; ++k) {
        float top, rpmTop;
        if (k < n) {
            top = mps * static_cast<float>(k + 1) / static_cast<float>(n);
            rpmTop = lo + (hi - lo) * static_cast<float>(k + 1) / static_cast<float>(n);
        } else {   // unused: just past the limiter, the same line continued
            top = mps * (1.0f + 0.01f * static_cast<float>(k - n + 1));
            rpmTop = lo + (hi - lo) * top / mps;
        }
        ok = ncm::gearbox::retuneSlice(spec.slices[static_cast<size_t>(k)], 0.0f, top, lo, rpmTop, modelTorqueAt(spec, top)) && ok;
        if (k < n) {
            const size_t used = std::strlen(tops);
            std::snprintf(tops + used, sizeof tops - used, "%s%.0f", k ? "/" : "", top * 3.6f);
        }
    }
    if (ok) { g_bandGear = record; g_bandSlicesApplied = g_slices; g_bandAppliedMps = mps; g_bandAppliedLo = lo; g_bandAppliedHi = hi; }
    else if (++g_bandFails <= 5) GBX_WARN("band: could not re-slice the native gears (%s)", why);
    GBX_INFO("band: %s -> %d native slices to %s km/h, rpm %.0f..%.0f%s", why, n, tops, lo, hi, ok ? "" : " FAILED");
}

/// The rpm window for gear index `idx` (0-based) of `spec`: landing at the previous limiter, redline at this one.
void bandWindow(const VirtualSpec& spec, size_t idx, float& lo, float& hi)
{
    hi = g_redlineRpm;
    if (idx == 0 || idx >= spec.gears.size()) { lo = spec.idleRpm; return; }   // first gear (and N/R) start from idle
    const float f0 = spec.gears[idx - 1].ceilingMps / spec.gears[idx].ceilingMps;
    if (!(f0 > 0.0f && f0 < 0.999f)) { lo = spec.idleRpm; return; }
    lo = std::max(g_minRpmFloor, g_landingRpm - (g_redlineRpm - g_landingRpm) * f0 / (1.0f - f0));
}
}  // namespace

void registerSpec(uint64_t record, VirtualSpec spec)
{
    std::lock_guard<std::mutex> _(g_mutex);
    g_specs[record] = std::move(spec);
}

void configure(const std::string& upKey, const std::string& downKey, const std::string& padUp, const std::string& padDown)
{
    g_upVk = vkOf(upKey, VK_LSHIFT);
    g_downVk = vkOf(downKey, VK_LCONTROL);
    g_padUp = buttonOf(padUp, XINPUT_GAMEPAD_X);
    g_padDown = buttonOf(padDown, XINPUT_GAMEPAD_A);
    GBX_INFO("manual: shift up %s / pad %s, shift down %s / pad %s (this window only)", upKey.empty() ? "LSHIFT" : upKey.c_str(),
             padUp.empty() ? "X" : padUp.c_str(), downKey.empty() ? "LCTRL" : downKey.c_str(), padDown.empty() ? "A" : padDown.c_str());
}

int32_t tick(uint64_t record, float speedMps, int32_t nativeHudGear)
{
    std::lock_guard<std::mutex> _(g_mutex);
    g_event = 0;
    auto it = g_specs.find(record);
    if (it == g_specs.end()) { g_record = 0; return -2; }
    const uint64_t nowStack = nowMs();
    const bool stacked = pollStack(nowStack);
    if (record != g_record) g_path = 0;
    // an engage press (the driver's bound control on a side box): that path, or -- pressed for the path already
    // driving -- back to the car's own box. The stricter `when` of the two paths decides whether it may happen now.
    if (g_gearing) {
        const uint32_t sel = g_gearing->selectSeq;
        if (!g_selectKnown) { g_selectKnown = true; g_selectSeq = sel; }
        else if (sel != g_selectSeq) {
            g_selectSeq = sel;
            const int asked = g_gearing->selectPath;
            const int target = (asked == g_path) ? 0 : asked;
            if (stacked && target >= 0 && target < static_cast<int>(g_paths.size()) && target != g_path) {
                const std::string& rule = whenRank(g_paths[g_path].when) >= whenRank(g_paths[target].when) ? g_paths[g_path].when : g_paths[target].when;
                const float speedNow = std::fabs(speedMps);
                const bool allowed = rule == "stationary" ? speedNow < 1.0f : (rule == "neutral" ? g_gear == 0 : true);
                if (!allowed) {
                    ++g_refused;
                    GBX_INFO("stack: engage %s refused (%s first) at %.0f km/h, gear %d", g_paths[target].label.c_str(),
                             rule == "stationary" ? "stop" : "neutral", speedNow * 3.6f, g_gear);
                } else {
                    const int from = g_path;
                    g_path = target;
                    const VirtualSpec next = effective(it->second, true);
                    if (g_gear > 0) {   // land in the lowest gear that does not over-rev at this speed
                        int land = static_cast<int>(next.gears.size());
                        for (size_t i = 0; i < next.gears.size(); ++i) if (next.gears[i].ceilingMps >= speedNow * 1.03f) { land = static_cast<int>(i) + 1; break; }
                        g_gear = std::max(1, land);
                        g_cutUntilMs = nowStack + static_cast<uint64_t>(std::max(0, next.shiftMs));
                        g_event = 1;
                    }
                    ++g_shifts;
                    GBX_INFO("stack: path %d (%s) -> %d (%s), %zu gears, now in %d at %.0f km/h", from, g_paths[from].label.c_str(), target,
                             g_paths[target].label.c_str(), next.gears.size(), g_gear, speedNow * 3.6f);
                }
            }
        }
    }
    const VirtualSpec spec = effective(it->second, stacked);
    const int32_t n = static_cast<int32_t>(spec.gears.size());
    if (g_gear > n) g_gear = n;
    if (record != g_record) {
        g_record = record;
        g_gear = 0;
        g_cutUntilMs = 0;
        g_audio = spec.audio;
        g_audioIdle = spec.idleRpm;
        g_audioTop = spec.audioMaxRpm > spec.idleRpm ? spec.audioMaxRpm : spec.maxRpm;
        GBX_INFO("manual: in a %s (%d-speed, top gear to %.0f km/h); starting in N; sounds %s_gear_up/_gear_down; engine audio %s (%s, %.0f-%.0f rpm)",
                 spec.spec.c_str(), n, n > 0 ? spec.gears.back().ceilingMps * 3.6f : 0.0f, spec.audio.c_str(),
                 g_engineAudio ? "ours" : "the game's", g_audioScale.c_str(), g_audioIdle, g_audioTop);
    }
    const uint64_t now = nowMs();
    g_lastTickMs = now;
    const float speed = std::fabs(speedMps);
    const WORD pad = padButtons();
    const bool wantUp = pressed(g_upVk, g_upHeld) | padPressed(pad, g_padUp, g_padUpHeld);
    const bool wantDown = pressed(g_downVk, g_downHeld) | padPressed(pad, g_padDown, g_padDownHeld);
    if (pressed(g_cycleVk, g_cycleHeld)) {
        static const char* kModes[] = {"band", "curve", "blend", "rpm", "limiter", "fraction", "off"};
        size_t next = 0;
        for (size_t i = 0; i < 7; ++i) if (g_audioScale == kModes[i]) { next = (i + 1) % 7; break; }
        g_audioScale = kModes[next];
        GBX_INFO("audio: engine-sound scale -> %s (at %.0f km/h, gear %d)", g_audioScale.c_str(), speed * 3.6f, g_gear);
    }
    // the selector: R (-1) - N (0) - 1..n. R only from N at a standstill, as a real box (owner QA 2026-10-04: reverse
    // "has multiple gears and doesnt get refused in drive gear")
    constexpr float kStill = 1.0f;   // m/s
    // a range box's own procedure: moving between ranges (a change of group in the ladder) follows `rangeWhen`, and
    // takes the range box's own time
    const StackPath* path = (stacked && g_path < static_cast<int>(g_paths.size())) ? &g_paths[static_cast<size_t>(g_path)] : nullptr;
    auto rangeBlocked = [&](int32_t from, int32_t to) -> bool {
        if (!path || from < 1 || to < 1 || from > n || to > n || g_groups.size() != static_cast<size_t>(n)) return false;
        if (g_groups[static_cast<size_t>(from - 1)] == g_groups[static_cast<size_t>(to - 1)]) return false;
        if (path->rangeWhen == "stationary" && speed >= kStill) return true;
        if (path->rangeWhen == "neutral") return true;   // a sequential step never passes through N
        return false;
    };
    auto rangeMs = [&](int32_t from, int32_t to) -> int {
        if (!path || from < 1 || to < 1 || g_groups.size() != static_cast<size_t>(n)) return 0;
        return g_groups[static_cast<size_t>(from - 1)] != g_groups[static_cast<size_t>(to - 1)] ? path->rangeMs : 0;
    };
    if (wantUp && g_gear < n && rangeBlocked(g_gear, g_gear + 1)) {
        ++g_refused;
        GBX_INFO("stack: range change refused at %.0f km/h (%s)", speed * 3.6f, path->rangeWhen == "neutral" ? "neutral first" : "stop first");
    } else if (wantUp && g_gear < n) {
        ++g_gear;
        g_cutUntilMs = g_gear >= 1 ? now + static_cast<uint64_t>(std::max({0, spec.shiftMs, rangeMs(g_gear - 1, g_gear)})) : 0;
        g_event = g_gear >= 1 ? 1 : 0; ++g_shifts;
    }
    if (wantDown && g_gear == 0) {
        if (speed < kStill) { g_gear = -1; ++g_shifts; }
        else {
            ++g_refused;
            static uint64_t lastLog = 0;
            if (now - lastLog > 1000) { lastLog = now; GBX_INFO("manual: reverse refused at %.0f km/h (stop first)", speed * 3.6f); }
        }
    } else if (wantDown && g_gear > 0) {
        const int32_t target = g_gear - 1;
        if (target >= 1 && speed > spec.gears[static_cast<size_t>(target - 1)].ceilingMps * 1.03f) {
            ++g_refused;
            static uint64_t lastLog = 0;
            if (now - lastLog > 1000) { lastLog = now; GBX_INFO("manual: downshift to %d refused at %.0f km/h (over-rev)", target, speed * 3.6f); }
        } else if (rangeBlocked(g_gear, target)) {
            ++g_refused;
            GBX_INFO("stack: range change refused at %.0f km/h (%s)", speed * 3.6f, path->rangeWhen == "neutral" ? "neutral first" : "stop first");
        } else {
            g_cutUntilMs = now + static_cast<uint64_t>(std::max({0, spec.shiftMs * 2 / 3, rangeMs(g_gear, target)}));
            g_gear = target;
            g_event = -1; ++g_shifts;
        }
    }
    // which way the game is driving: backwards once the car rolls back. (The HUD gear read by the script is our own
    // write from the last frame, so it cannot tell us the native box's intent; the road speed's sign can.)
    (void)nativeHudGear;
    const bool backwards = speedMps < -0.3f;
    if (g_gear == -1) {
        // R: the game's own reverse drives; nothing pushes forward
        publish(speedMps <= 0.3f ? 1.0f : 0.0f, 0.0f);   // reverse drives; rolling forward gets nothing
        g_frac = std::clamp(speed / 8.0f, 0.0f, 1.0f);   // ~29 km/h of reverse fills the bar
    } else if (g_gear == 0) {
        // N: nothing drives either way; S still brakes (brakes are not drive)
        publish(0.0f, 0.0f);
        g_frac = 0.0f;
    } else {
        const VirtualGear& vg = spec.gears[static_cast<size_t>(g_gear - 1)];
        const bool cut = now < g_cutUntilMs;
        // 0.4.0: with the slices live the native gears already carry the model's torque at each speed -- the old share
        // (this gear's model torque against the strongest) would count the taller gears' weakness twice. A stacked
        // path still loses its own efficiency.
        const bool sliced = g_engineAudio && g_audioScale == "band" && g_bandGear == record;
        const float share = sliced ? (path ? std::clamp(path->efficiency, 0.0f, 1.0f) : 1.0f) : vg.share;
        // a forward gear never reverses the car: S brakes to a stop and holds
        publish((cut || backwards) ? 0.0f : share, vg.ceilingMps);
        g_frac = vg.ceilingMps > 0.0f ? std::clamp(speed / vg.ceilingMps, 0.0f, 1.05f) : 0.0f;
    }
    if (g_engineAudio && g_audioScale == "band") {
        // N and R voice first gear's band (the engine idles; a blip in N climbs like first); 1..n their own limiter
        const size_t idx = g_gear >= 1 ? static_cast<size_t>(g_gear - 1) : 0;
        if (idx < spec.gears.size()) {
            float lo = 0.0f, hi = 0.0f;
            bandWindow(spec, idx, lo, hi);
            applyBand(spec, record, spec.gears[idx].ceilingMps, lo, hi, g_gear >= 1 ? "gear" : "N/R");
        }
    } else if (g_bandGear == record && g_bandAppliedMps >= 0.0f) {
        applyBand(spec, record, spec.longTopMps, spec.idleRpm, spec.maxRpm, "full band (mode not band)");
        g_bandGear = 0;
    }
    g_rpm = spec.idleRpm + std::min(g_frac, 1.0f) * (spec.maxRpm - spec.idleRpm);
    g_audioRpm = g_audioIdle + std::min(g_frac, 1.0f) * (g_audioTop - g_audioIdle);
    return g_gear;
}

float rpm() { return g_rpm; }
float rpmFraction() { return g_frac; }
std::string audioName() { return g_record ? g_audio : std::string(); }
bool engineAudio() { return g_engineAudio; }
void setEngineAudio(bool on) { g_engineAudio = on; }
void setEngineAudioScale(const std::string& scale) { g_audioScale = scale.empty() ? std::string("band") : scale; }

namespace {
float layerValue(const std::string& layer)
{
    if (layer == "off") return -1.0f;
    if (layer == "limiter") return g_rpm;
    if (layer == "fraction") return std::min(g_frac, 1.0f);
    return g_audioRpm;   // rpm
}

/// The layers' weights at gear progress x (0 = the gear's floor, 1 = its limiter): a tent around each layer's place
/// on the ramp (quietest at 0, loudest at 1) on top of the floor, normalised.
void blendWeights(float x, float* w, size_t n)
{
    float sum = 0.0f;
    for (size_t i = 0; i < n; ++i) {
        const float centre = n > 1 ? static_cast<float>(i) / static_cast<float>(n - 1) : 0.0f;
        const float tent = std::max(0.0f, 1.0f - std::fabs(x - centre) * static_cast<float>(n > 1 ? n - 1 : 1));
        w[i] = g_blendFloor + tent;
        sum += w[i];
    }
    for (size_t i = 0; i < n; ++i) w[i] = sum > 0.0f ? w[i] / sum : 0.0f;
}
}  // namespace

float engineAudioValue()
{
    float v = -1.0f;
    if (g_audioScale == "band") { g_lastWritten = -1.0f; return -1.0f; }   // the game is the only writer
    if (g_engineAudio && g_audioScale == "curve") {
        const float x = std::clamp(g_frac, 0.0f, 1.0f);
        float target = g_curveLo + (g_curveHi - g_curveLo) * std::pow(x, g_curveGamma);
        if (g_follow > 0.0f && g_gameRpm > 1.0f) target = (1.0f - g_follow) * target + g_follow * g_gameRpm;
        const uint64_t now = nowMs();
        if (g_smoothed < 0.0f || g_smoothMs <= 0.0f || now - g_smoothAtMs > 1000) g_smoothed = target;
        else {
            const float dt = static_cast<float>(now - g_smoothAtMs);
            g_smoothed += (1.0f - std::exp(-dt / g_smoothMs)) * (target - g_smoothed);
        }
        g_smoothAtMs = now;
        v = g_smoothed;
        g_lastWritten = v;
        return v;
    }
    if (g_engineAudio && g_audioScale == "blend") {
        const size_t n = std::min<size_t>(g_blendLayers.size(), 8);
        float w[8] = {};
        blendWeights(std::clamp(g_frac, 0.0f, 1.0f), w, n);
        size_t pick = 0;
        for (size_t i = 0; i < n; ++i) { g_blendAcc[i] += w[i]; if (g_blendAcc[i] > g_blendAcc[pick]) pick = i; }
        g_blendAcc[pick] -= 1.0f;
        g_blendLast = static_cast<int>(pick);
        v = n ? layerValue(g_blendLayers[pick]) : -1.0f;
    } else if (g_engineAudio && g_audioScale != "off") {
        v = layerValue(g_audioScale);
    }
    g_lastWritten = v;
    return v;
}

void setBlend(const std::vector<std::string>& layers, float floor)
{
    std::vector<std::string> ok;
    for (const auto& l : layers) if (l == "off" || l == "rpm" || l == "limiter" || l == "fraction") ok.push_back(l);
    if (!ok.empty() && ok.size() <= 8) g_blendLayers = ok;
    g_blendFloor = std::clamp(floor, 0.0f, 2.0f);
    std::string names;
    for (const auto& l : g_blendLayers) names += (names.empty() ? "" : " < ") + l;
    GBX_INFO("audio: blend layers %s (quietest first), floor %.2f", names.c_str(), g_blendFloor);
}

void noteDashSpeed(float value) { g_dashSpeed = value; }

void setBand(float landingRpm, float redlineRpm, float minRpmFloor)
{
    g_redlineRpm = std::clamp(redlineRpm, 1000.0f, 20000.0f);
    g_landingRpm = std::clamp(landingRpm, 0.0f, g_redlineRpm - 100.0f);
    g_minRpmFloor = std::min(minRpmFloor, g_landingRpm);
    GBX_INFO("audio: band landing %.0f rpm, redline %.0f rpm, min floor %.0f", g_landingRpm, g_redlineRpm, g_minRpmFloor);
}

void setSlices(int slices)
{
    g_slices = std::clamp(slices, 1, ncm::gearbox::kSlices);
    GBX_INFO("audio: band sliced over %d native gear(s)", g_slices);
}

void setCurve(float lo, float hi, float gamma, float follow, float smoothMs)
{
    g_curveLo = std::max(0.0f, lo);
    g_curveHi = std::max(g_curveLo, hi);
    g_curveGamma = std::clamp(gamma, 0.2f, 5.0f);
    g_follow = std::clamp(follow, 0.0f, 1.0f);
    g_smoothMs = std::clamp(smoothMs, 0.0f, 2000.0f);
    GBX_INFO("audio: curve lo %.0f hi %.0f gamma %.2f follow %.2f smooth %.0f ms", g_curveLo, g_curveHi, g_curveGamma, g_follow, g_smoothMs);
}

void setAudioCycleKey(const std::string& name) { g_cycleVk = vkOf(name, VK_PRIOR); }

std::string audioMode() { return g_engineAudio ? g_audioScale : std::string("off"); }

void setConfigError(const std::string& error) { g_configError = error; }

// 0.2.9 (owner: "been trying all kinds of nonsense values in config, no sound change" -- the log showed follow 1.00 on
// every load after 20:47, which switches the curve off, then a file that no longer parsed): say on screen what is live.
std::string audioDetail()
{
    if (!g_configError.empty()) return "CONFIG ERROR - not loaded, last good values kept";
    if (g_audioScale == "band") {
        char b[96];
        if (g_bandAppliedMps >= 0.0f) std::snprintf(b, sizeof b, "%d slices to %.0f km/h, rpm %.0f..%.0f (land %.0f red %.0f)", g_bandSlicesApplied, g_bandAppliedMps * 3.6f, g_bandAppliedLo, g_bandAppliedHi, g_landingRpm, g_redlineRpm);
        else std::snprintf(b, sizeof b, "game voice: band not applied");
        return b;
    }
    if (g_audioScale != "curve") return "";
    char buf[96];
    if (g_follow >= 0.99f)
        std::snprintf(buf, sizeof buf, "lo %.0f hi %.0f g %.1f  FOLLOW 100%%: curve off", g_curveLo, g_curveHi, g_curveGamma);
    else
        std::snprintf(buf, sizeof buf, "lo %.0f hi %.0f g %.1f follow %.2f", g_curveLo, g_curveHi, g_curveGamma, g_follow);
    return buf;
}

void trace(float blackboardRpm, float speedMps)
{
    g_gameRpm = blackboardRpm;
    if (!g_record) return;
    const uint64_t now = nowMs();
    if (now - g_lastTraceMs < 1000) return;
    g_lastTraceMs = now;
    std::string mix;
    if (g_audioScale == "blend") {
        const size_t n = std::min<size_t>(g_blendLayers.size(), 8);
        float w[8] = {};
        blendWeights(std::clamp(g_frac, 0.0f, 1.0f), w, n);
        char buf[48];
        for (size_t i = 0; i < n; ++i) { std::snprintf(buf, sizeof buf, " %s %.0f%%", g_blendLayers[i].c_str(), w[i] * 100.0f); mix += buf; }
    }
    GBX_INFO("trace: %5.1f km/h (dash SpeedValue %.1f) gear %d frac %.2f | sound %s wrote %.2f%s | game rpm %.0f (our virtual %.0f)",
             std::fabs(speedMps) * 3.6f, g_dashSpeed, g_gear, g_frac, g_audioScale.c_str(), g_lastWritten, mix.c_str(), blackboardRpm, g_rpm);
}

int32_t displayGear(int32_t native)
{
    return (g_record && nowMs() - g_lastTickMs < 300) ? g_gear : native;
}

float displayRpm(float native)
{
    return (g_record && nowMs() - g_lastTickMs < 300) ? g_rpm : native;
}
int32_t shiftEvent() { return g_event; }

void leave()
{
    std::lock_guard<std::mutex> _(g_mutex);
    if (g_record && g_bandAppliedMps >= 0.0f) {
        auto it = g_specs.find(g_record);
        if (it != g_specs.end()) applyBand(it->second, g_record, it->second.longTopMps, it->second.idleRpm, it->second.maxRpm, "left the car: full band");
        g_bandGear = 0;
    }
    if (g_block) g_block->stampMs = 0;
    if (g_record) GBX_INFO("manual: out of the car after %llu shift(s), %llu refused", static_cast<unsigned long long>(g_shifts),
                           static_cast<unsigned long long>(g_refused));
    g_record = 0;
}

std::string status()
{
    return "manual specs=" + std::to_string(g_specs.size()) + " gear=" + std::to_string(g_gear) + " shifts=" + std::to_string(g_shifts) +
           " stack=" + (g_stackLive ? std::to_string(g_paths.size()) + " path(s), on " + std::to_string(g_path) : std::string("off"));
}

}  // namespace ncm::gearbox::manual
