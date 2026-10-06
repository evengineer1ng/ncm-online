#include "scan.hpp"

#include "log.hpp"

#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <set>
#include <vector>

namespace ncm::gearbox::scan {
namespace {

constexpr uint32_t kRootDefault = 0x2000;
constexpr uint32_t kRootMax = 0x4000;
constexpr uint32_t kChildSize = 0x800;
constexpr uint32_t kMaxChildren = 768;
constexpr int kDeltaMin = -3, kDeltaMax = 3;

enum Width : uint8_t { W8 = 1, W32 = 4, F32 = 0xF };

struct Cand {
    int32_t slot;        // -1 = the car object itself; else the pointer slot's offset in it
    uint32_t off;        // offset in that region
    Width width;
    int8_t delta;        // value - hudGear, fixed at seeding
    bool alive;
};

bool readSelf(uintptr_t address, void* out, size_t size)
{
    SIZE_T got = 0;
    return ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<LPCVOID>(address), out, size, &got) && got == size;
}

bool plausiblePointer(uint64_t v)
{
    return v > 0x10000 && v < 0x00007FFFFFFFFFFFull && (v & 7) == 0;
}

struct Frame {
    std::vector<uint8_t> root;
    std::vector<int32_t> slots;                 // which root slots point somewhere readable
    std::vector<uint64_t> targets;              // what they pointed at this frame
    std::vector<std::vector<uint8_t>> children; // kChildSize bytes each
};

// `only`: when not null, read just these pointer slots (the ones that still hold live candidates)
bool capture(const void* vehicle, uint32_t size, Frame& f, const std::set<int32_t>* only = nullptr)
{
    f.root.assign(size, 0);
    if (!readSelf(reinterpret_cast<uintptr_t>(vehicle), f.root.data(), size)) return false;
    f.slots.clear(); f.targets.clear(); f.children.clear();
    for (uint32_t s = 0; s + 8 <= size && f.slots.size() < kMaxChildren; s += 8) {
        uint64_t v;
        std::memcpy(&v, f.root.data() + s, 8);
        if (!plausiblePointer(v)) continue;
        if (only && !only->count(static_cast<int32_t>(s))) continue;
        std::vector<uint8_t> child(kChildSize);
        if (!readSelf(static_cast<uintptr_t>(v), child.data(), kChildSize)) continue;
        f.slots.push_back(static_cast<int32_t>(s));
        f.targets.push_back(v);
        f.children.push_back(std::move(child));
    }
    return true;
}

bool valueAt(const std::vector<uint8_t>& region, uint32_t off, Width w, double& out)
{
    if (w == W8) { if (off + 1 > region.size()) return false; out = static_cast<int8_t>(region[off]); return true; }
    if (off + 4 > region.size()) return false;
    if (w == W32) { int32_t v; std::memcpy(&v, region.data() + off, 4); out = v; return true; }
    float f; std::memcpy(&f, region.data() + off, 4);
    if (!std::isfinite(f)) return false;
    out = f;
    return true;
}

std::vector<Cand> g_cands;
bool g_trialEnabled = false;
std::vector<int32_t> g_seedSlots;
std::vector<uint64_t> g_seedTargets;
bool g_seeded = false;
int32_t g_lastHud = -999;
std::set<int32_t> g_huds;
size_t g_lastReported = static_cast<size_t>(-1);
uint64_t g_frames = 0;
uint32_t g_size = kRootDefault;

const std::vector<uint8_t>* regionFor(const Frame& f, int32_t slot, uint64_t& target)
{
    if (slot < 0) { target = 0; return &f.root; }
    for (size_t i = 0; i < f.slots.size(); ++i) if (f.slots[i] == slot) { target = f.targets[i]; return &f.children[i]; }
    return nullptr;
}

uint64_t seedTarget(int32_t slot)
{
    for (size_t i = 0; i < g_seedSlots.size(); ++i) if (g_seedSlots[i] == slot) return g_seedTargets[i];
    return 0;
}

void seed(const Frame& f, int32_t hud)
{
    g_cands.clear();
    auto seedRegion = [&](int32_t slot, const std::vector<uint8_t>& r) {
        for (uint32_t off = 0; off < r.size(); ++off) {
            for (Width w : { W8, W32, F32 }) {
                if (w != W8 && (off & 3)) continue;
                double v;
                if (!valueAt(r, off, w, v)) continue;
                if (w == F32 && v != std::floor(v)) continue;
                const double d = v - hud;
                if (d < kDeltaMin || d > kDeltaMax) continue;
                g_cands.push_back({ slot, off, w, static_cast<int8_t>(d), true });
            }
        }
    };
    seedRegion(-1, f.root);
    for (size_t i = 0; i < f.slots.size(); ++i) seedRegion(f.slots[i], f.children[i]);
    g_seedSlots = f.slots;
    g_seedTargets = f.targets;
    g_seeded = true;
    GBX_INFO("scan: seeded %zu candidate(s) at hud gear %d across the car object (0x%X bytes) and %zu pointed-to object(s)",
             g_cands.size(), hud, static_cast<unsigned>(f.root.size()), f.slots.size());
}

const char* widthName(Width w) { return w == W8 ? "u8" : w == W32 ? "i32" : "f32"; }

size_t g_lastReportedGears = 0;

void report(int32_t hud, bool force = false)
{
    size_t alive = 0;
    for (const auto& c : g_cands) if (c.alive) ++alive;
    // 0.1.2: a new distinct gear reports too -- 0.1.1 printed only when the count changed, and its 2 survivors, which
    // followed seven gears for three minutes, were never named
    if (!force && alive == g_lastReported && g_huds.size() == g_lastReportedGears) return;
    g_lastReported = alive;
    g_lastReportedGears = g_huds.size();
    GBX_INFO("scan: %zu candidate(s) still follow the HUD gear after %zu distinct gear(s) (now %d)", alive, g_huds.size(), hud);
    if (g_huds.size() < 3 || alive > 60) return;
    for (const auto& c : g_cands) {
        if (!c.alive) continue;
        if (c.slot < 0) GBX_INFO("scan:   root:0x%X:%s  value = gear %+d", c.off, widthName(c.width), c.delta);
        else GBX_INFO("scan:   0x%X:0x%X:%s  value = gear %+d (pointer slot 0x%X -> 0x%llX)", c.slot, c.off, widthName(c.width),
                      c.delta, c.slot, static_cast<unsigned long long>(seedTarget(c.slot)));
    }
}

// ------------------------------------------------------------------------------------------------- the trial
// Once the scan has settled (4+ distinct gears seen, 1-4 survivors) and the car is in 2nd or higher, each survivor in
// turn is written with the gear the car is in RIGHT NOW (value = gear + its delta) every frame for 6 s, then released for
// 4 s. If it is the gear, the car stays in it: the HUD gear does not move and the revs climb with the speed. Writing the
// value that is already there cannot throw the car into a gear it is not in.
using Clock = std::chrono::steady_clock;
enum class Trial { Idle, Running, Cooldown, Done };
Trial g_trial = Trial::Idle;
size_t g_trialIndex = 0;          // which survivor (in g_cands order among the alive)
int32_t g_trialGear = 0;
Clock::time_point g_trialAt{}, g_trialLog{};
const Cand* g_trialCand = nullptr;

bool converged(size_t& alive)
{
    alive = 0;
    for (const auto& c : g_cands) if (c.alive) ++alive;
    return g_huds.size() >= 4 && alive >= 1 && alive <= 4;
}

const Cand* nthAlive(size_t n)
{
    for (const auto& c : g_cands) if (c.alive) { if (n == 0) return &c; --n; }
    return nullptr;
}

std::string pathOf(const Cand& c)
{
    char buf[64];
    if (c.slot < 0) std::snprintf(buf, sizeof(buf), "root:0x%X:%s", c.off, widthName(c.width));
    else std::snprintf(buf, sizeof(buf), "0x%X:0x%X:%s", c.slot, c.off, widthName(c.width));
    return buf;
}

void writeCand(const void* vehicle, const Cand& c, int32_t gear)
{
    uintptr_t base = reinterpret_cast<uintptr_t>(vehicle);
    if (c.slot >= 0) {
        uint64_t p = 0;
        if (!readSelf(base + static_cast<uint32_t>(c.slot), &p, 8) || !plausiblePointer(p)) return;
        base = static_cast<uintptr_t>(p);
    }
    const int32_t v = gear + c.delta;
    SIZE_T wrote = 0;
    if (c.width == W8) { const int8_t b = static_cast<int8_t>(v); WriteProcessMemory(GetCurrentProcess(), reinterpret_cast<LPVOID>(base + c.off), &b, 1, &wrote); }
    else if (c.width == W32) { WriteProcessMemory(GetCurrentProcess(), reinterpret_cast<LPVOID>(base + c.off), &v, 4, &wrote); }
    else { const float f = static_cast<float>(v); WriteProcessMemory(GetCurrentProcess(), reinterpret_cast<LPVOID>(base + c.off), &f, 4, &wrote); }
}

/// One frame of the trial. Returns true while a survivor is being written (elimination pauses).
bool trialStep(const void* vehicle, int32_t hud, float rpm, float speed)
{
    if (!g_trialEnabled || g_trial == Trial::Done) return false;
    const auto now = Clock::now();
    size_t alive = 0;
    if (g_trial == Trial::Idle) {
        if (!converged(alive) || hud < 2) return false;
        g_trialCand = nthAlive(g_trialIndex);
        if (!g_trialCand) { g_trial = Trial::Done; GBX_INFO("trial: done -- every survivor tried"); return false; }
        g_trial = Trial::Running;
        g_trialGear = hud;
        g_trialAt = g_trialLog = now;
        GBX_WARN("trial %zu: HOLDING gear %d in %s for 6 s (keep the throttle down)", g_trialIndex + 1, g_trialGear, pathOf(*g_trialCand).c_str());
    }
    if (g_trial == Trial::Running) {
        writeCand(vehicle, *g_trialCand, g_trialGear);
        if (now - g_trialLog >= std::chrono::milliseconds(500)) {
            g_trialLog = now;
            GBX_INFO("trial %zu: held %d | hud gear %d rpm %.0f speed %.1f m/s", g_trialIndex + 1, g_trialGear, hud, rpm, speed);
        }
        if (now - g_trialAt >= std::chrono::seconds(6)) {
            GBX_WARN("trial %zu: released %s", g_trialIndex + 1, pathOf(*g_trialCand).c_str());
            g_trial = Trial::Cooldown;
            g_trialAt = now;
        }
        return true;
    }
    if (g_trial == Trial::Cooldown) {
        if (now - g_trialAt >= std::chrono::seconds(4)) { ++g_trialIndex; g_trial = Trial::Idle; }
        return true;   // let the box settle before elimination resumes
    }
    return false;
}

}  // namespace

void setTrial(bool enabled) { g_trialEnabled = enabled; }

void step(const void* vehicle, uint32_t objectSize, int32_t hudGear, float rpm, float speed)
{
    if (!vehicle) return;
    g_size = std::min<uint32_t>(objectSize ? objectSize : kRootDefault, kRootMax);
    Frame f;
    if (!g_seeded) {
        if (!capture(vehicle, g_size, f)) return;
        seed(f, hudGear); g_lastHud = hudGear; g_huds.insert(hudGear); ++g_frames;
        return;
    }
    std::set<int32_t> live;
    for (const auto& c : g_cands) if (c.alive && c.slot >= 0) live.insert(c.slot);
    if (!capture(vehicle, g_size, f, &live)) return;
    ++g_frames;
    const bool trialing = trialStep(vehicle, hudGear, rpm, speed);
    // every frame, not only on a shift: a field that follows the gear must agree on EVERY frame -- except while the trial
    // writes one, when disagreeing with the HUD is the point
    for (auto& c : g_cands) {
        if (trialing) break;
        if (!c.alive) continue;
        uint64_t target = 0;
        const auto* r = regionFor(f, c.slot, target);
        if (!r || (c.slot >= 0 && target != seedTarget(c.slot))) { c.alive = false; continue; }   // pointer moved: not this
        double v;
        if (!valueAt(*r, c.off, c.width, v) || v - hudGear != c.delta) c.alive = false;
    }
    if (hudGear != g_lastHud) {
        g_huds.insert(hudGear);
        g_lastHud = hudGear;
        report(hudGear);
    }
}

void reset(const char* why)
{
    if (!g_seeded) return;
    size_t alive = 0;
    for (const auto& c : g_cands) if (c.alive) ++alive;
    GBX_INFO("scan: %s after %llu frame(s): %zu candidate(s) followed %zu distinct HUD gear(s)", why,
             static_cast<unsigned long long>(g_frames), alive, g_huds.size());
    report(g_lastHud, true);
    g_cands.clear(); g_seedSlots.clear(); g_seedTargets.clear(); g_huds.clear();
    g_seeded = false; g_frames = 0; g_lastHud = -999;
    g_lastReported = static_cast<size_t>(-1); g_lastReportedGears = 0;
    g_trial = Trial::Idle; g_trialIndex = 0; g_trialCand = nullptr;
}

bool resolve(const void* vehicle, const std::string& path, uintptr_t& address)
{
    address = 0;
    if (!vehicle || path.empty()) return false;
    const auto a = path.find(':'), b = path.rfind(':');
    if (a == std::string::npos || b == a) return false;
    const std::string slotText = path.substr(0, a);
    uintptr_t base = reinterpret_cast<uintptr_t>(vehicle);
    if (slotText != "root") {
        uint64_t p = 0;
        if (!readSelf(base + std::stoul(slotText, nullptr, 0), &p, 8) || !plausiblePointer(p)) return false;
        base = static_cast<uintptr_t>(p);
    }
    address = base + static_cast<uint32_t>(std::stoul(path.substr(a + 1, b - a - 1), nullptr, 0));
    int8_t probe = 0;
    return readSelf(address, &probe, 1);
}

bool hold(const void* vehicle, const std::string& path, int32_t gear)
{
    if (!vehicle || path.empty()) return false;
    // "root:0x2C4:i32" | "0x5C8:0x1F4:u8"
    const auto a = path.find(':'), b = path.rfind(':');
    if (a == std::string::npos || b == a) return false;
    const std::string slotText = path.substr(0, a), offText = path.substr(a + 1, b - a - 1), widthText = path.substr(b + 1);
    const uint32_t off = static_cast<uint32_t>(std::stoul(offText, nullptr, 0));
    uintptr_t base = reinterpret_cast<uintptr_t>(vehicle);
    if (slotText != "root") {
        uint64_t p = 0;
        if (!readSelf(base + std::stoul(slotText, nullptr, 0), &p, 8) || !plausiblePointer(p)) return false;
        base = static_cast<uintptr_t>(p);
    }
    SIZE_T wrote = 0;
    BOOL ok = FALSE;
    if (widthText == "u8" || widthText == "i8") { const int8_t v = static_cast<int8_t>(gear); ok = WriteProcessMemory(GetCurrentProcess(), reinterpret_cast<LPVOID>(base + off), &v, 1, &wrote); }
    else if (widthText == "i32") { const int32_t v = gear; ok = WriteProcessMemory(GetCurrentProcess(), reinterpret_cast<LPVOID>(base + off), &v, 4, &wrote); }
    else if (widthText == "f32") { const float v = static_cast<float>(gear); ok = WriteProcessMemory(GetCurrentProcess(), reinterpret_cast<LPVOID>(base + off), &v, 4, &wrote); }
    static bool first = true;
    if (ok && first) { first = false; GBX_WARN("hold: first write of %d to %s", gear, path.c_str()); }
    return ok == TRUE;
}

}  // namespace ncm::gearbox::scan
