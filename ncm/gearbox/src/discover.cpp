#include "discover.hpp"

#include "log.hpp"
#include "scan.hpp"
#include "manual.hpp"
#include "stepper.hpp"

#include <RED4ext/RED4ext.hpp>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <unordered_map>
#include <vector>

// Clean room (L306): everything here comes from the game's own RTTI at runtime and the RED4ext SDK. No other mod's
// code, offsets or names are used; the census is how we learn the names.
namespace ncm::gearbox::discover {
namespace {

// ---------------------------------------------------------------------------------------------------------- config

struct Config {
    bool observe = true;
    std::string holdField;   // an RTTI field name (0.1.0; the census found none) -- empty = not used
    std::string holdPath;    // 0.1.1: an address path from the scan, "root:0x2C4:i32" / "0x5C8:0x1F4:u8" -- empty = not used
    int32_t holdGear = 2;
    bool ab = false;         // 0.1.3: the A/B trial on holdPath -- A writes once a frame, B also inside every physics step
};
Config g_config;
std::mutex g_mutex;

// ---------------------------------------------------------------------------------------------------------- names

std::string lower(std::string s)
{
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

const char* kWords[] = { "gear", "clutch", "transmission", "shift", "neutral", "rpm" };

bool interesting(const std::string& name)
{
    const std::string l = lower(name);
    for (const char* w : kWords) if (l.find(w) != std::string::npos) return true;
    return false;
}

std::string typeName(RED4ext::rtti::IType* t)
{
    return t ? std::string(t->GetName().ToString()) : std::string("?");
}

// ---------------------------------------------------------------------------------------------------------- reading

enum class Kind { None, I8, U8, I16, U16, I32, U32, I64, U64, F32, Bool };

Kind kindOf(RED4ext::rtti::IType* t)
{
    if (!t) return Kind::None;
    const std::string n = typeName(t);
    if (n == "Int8") return Kind::I8;
    if (n == "Uint8") return Kind::U8;
    if (n == "Int16") return Kind::I16;
    if (n == "Uint16") return Kind::U16;
    if (n == "Int32") return Kind::I32;
    if (n == "Uint32") return Kind::U32;
    if (n == "Int64") return Kind::I64;
    if (n == "Uint64") return Kind::U64;
    if (n == "Float") return Kind::F32;
    if (n == "Bool") return Kind::Bool;
    return Kind::None;
}

double readValue(const uint8_t* base, uint32_t offset, Kind k)
{
    const uint8_t* p = base + offset;
    switch (k) {
    case Kind::I8: return *reinterpret_cast<const int8_t*>(p);
    case Kind::U8: return *reinterpret_cast<const uint8_t*>(p);
    case Kind::I16: return *reinterpret_cast<const int16_t*>(p);
    case Kind::U16: return *reinterpret_cast<const uint16_t*>(p);
    case Kind::I32: return *reinterpret_cast<const int32_t*>(p);
    case Kind::U32: return *reinterpret_cast<const uint32_t*>(p);
    case Kind::I64: return static_cast<double>(*reinterpret_cast<const int64_t*>(p));
    case Kind::U64: return static_cast<double>(*reinterpret_cast<const uint64_t*>(p));
    case Kind::F32: return *reinterpret_cast<const float*>(p);
    case Kind::Bool: return *reinterpret_cast<const bool*>(p) ? 1.0 : 0.0;
    default: return 0.0;
    }
}

bool isInteger(Kind k) { return k != Kind::None && k != Kind::F32 && k != Kind::Bool; }

struct Field {
    std::string name;     // Class.prop
    std::string prop;     // prop
    uint32_t offset = 0;
    Kind kind = Kind::None;
    double last = 0.0;
    bool seen = false;
};

struct Layout {
    std::vector<Field> fields;
    int holdIndex = -1;   // into fields
};

std::unordered_map<RED4ext::CClass*, Layout> g_layouts;

void collect(RED4ext::CClass* cls, Layout& out, bool everyNumeric)
{
    for (auto* c = cls; c; c = c->parent) {
        const std::string owner = c->name.ToString();
        auto take = [&](RED4ext::CProperty* p) {
            if (!p || !p->type) return;
            const std::string prop = p->name.ToString();
            const Kind k = kindOf(p->type);
            if (k == Kind::None) return;
            if (!everyNumeric && !interesting(prop)) return;
            for (const auto& f : out.fields) if (f.offset == p->valueOffset && f.prop == prop) return;   // listed twice
            Field f;
            f.name = owner + "." + prop;
            f.prop = prop;
            f.offset = p->valueOffset;
            f.kind = k;
            out.fields.push_back(f);
        };
        for (auto* p : c->props) take(p);
        for (auto* p : c->unk118) take(p);   // native properties live here too
    }
}

Layout& layoutFor(RED4ext::CClass* cls)
{
    auto it = g_layouts.find(cls);
    if (it != g_layouts.end()) return it->second;
    Layout layout;
    collect(cls, layout, false);
    for (size_t i = 0; i < layout.fields.size(); ++i) {
        if (!g_config.holdField.empty() && layout.fields[i].prop == g_config.holdField && isInteger(layout.fields[i].kind)) {
            layout.holdIndex = static_cast<int>(i);
        }
    }
    GBX_INFO("observe: %s has %zu gear-like numeric field(s) on its class chain%s", cls->name.ToString(),
             layout.fields.size(), layout.fields.empty() ? " -- the gear is not an RTTI field of the vehicle object" : "");
    for (const auto& f : layout.fields) GBX_INFO("observe:   %s @0x%X (%s)", f.name.c_str(), f.offset,
        f.kind == Kind::F32 ? "float" : f.kind == Kind::Bool ? "bool" : "int");
    if (!g_config.holdField.empty()) {
        if (layout.holdIndex >= 0) GBX_WARN("hold: EXPERIMENT ARMED on %s -- writing gear %d every tick", layout.fields[layout.holdIndex].name.c_str(), g_config.holdGear);
        else GBX_WARN("hold: field '%s' is not an integer field of %s -- nothing will be written", g_config.holdField.c_str(), cls->name.ToString());
    }
    return g_layouts.emplace(cls, std::move(layout)).first->second;
}

std::atomic<int> g_lines{0};
constexpr int kLineBudget = 4000;
bool budget() { return g_lines.fetch_add(1) < kLineBudget; }

int32_t g_lastHud = -999;
std::chrono::steady_clock::time_point g_lastBeat{};
std::atomic<uint64_t> g_observations{0}, g_writes{0};

// ---------------------------------------------------------------------------------------------------------- A/B trial
// 0.1.3 (L306 S2). The gear is one byte (0.1.2: `0x2D0:0x3A4:u8`), and a once-a-frame write held it but flickered.
// When the car is in 2nd or higher: phase A holds the current gear with the frame write only for 6 s; 4 s rest; phase B
// holds it with the frame write AND the physics-step write (stepper) for 6 s; rest; twice over. Each phase ends with the
// count of frames where the HUD disagreed with the held gear and of physics steps where the automatic had moved it.
enum class Ab { Idle, Running, Rest, Done };
Ab g_ab = Ab::Idle;
int g_abPhase = 0;             // 0 A, 1 B, 2 A, 3 B
int32_t g_abGear = 0;
std::chrono::steady_clock::time_point g_abAt{}, g_abLog{};
uint64_t g_abFrames = 0, g_abDisagree = 0, g_abOverrides0 = 0, g_abCalls0 = 0;

void abStep(RED4ext::IScriptable* vehicle, int32_t hud, float rpm, float speed)
{
    if (!g_config.ab || g_config.holdPath.empty() || g_ab == Ab::Done) return;
    const auto now = std::chrono::steady_clock::now();
    if (g_ab == Ab::Idle) {
        if (hud < 2) return;
        g_ab = Ab::Running; g_abGear = hud; g_abAt = g_abLog = now; g_abFrames = g_abDisagree = 0;
        g_abOverrides0 = stepper::overrides(); g_abCalls0 = stepper::calls();
        const bool b = (g_abPhase % 2) == 1;
        GBX_WARN("ab %d%s: HOLDING gear %d for 6 s with %s (keep the throttle down)", g_abPhase / 2 + 1, b ? "B" : "A", g_abGear,
                 b ? "the frame write AND the physics-step write" : "the frame write only");
        if (b && !stepper::attached()) GBX_ERR("ab: the physics-step hold is NOT attached -- phase B is the same as A");
    }
    if (g_ab == Ab::Running) {
        const bool b = (g_abPhase % 2) == 1;
        scan::hold(vehicle, g_config.holdPath, g_abGear);
        if (b) {
            uintptr_t address = 0;
            if (scan::resolve(vehicle, g_config.holdPath, address)) stepper::arm(address, static_cast<int8_t>(g_abGear));
        }
        ++g_abFrames;
        if (hud != g_abGear) ++g_abDisagree;
        if (now - g_abLog >= std::chrono::milliseconds(500)) {
            g_abLog = now;
            GBX_INFO("ab %d%s: held %d | hud gear %d rpm %.0f speed %.1f m/s", g_abPhase / 2 + 1, b ? "B" : "A", g_abGear, hud, rpm, speed);
        }
        if (now - g_abAt >= std::chrono::seconds(6)) {
            stepper::disarm();
            GBX_WARN("ab %d%s: RESULT held %d for %llu frame(s): the HUD disagreed on %llu (%.1f%%); the automatic moved the gear in %llu of %llu physics step(s)",
                     g_abPhase / 2 + 1, b ? "B" : "A", g_abGear, static_cast<unsigned long long>(g_abFrames),
                     static_cast<unsigned long long>(g_abDisagree), g_abFrames ? 100.0 * g_abDisagree / g_abFrames : 0.0,
                     static_cast<unsigned long long>(stepper::overrides() - g_abOverrides0),
                     static_cast<unsigned long long>(stepper::calls() - g_abCalls0));
            g_ab = Ab::Rest; g_abAt = now;
        }
        return;
    }
    if (g_ab == Ab::Rest && now - g_abAt >= std::chrono::seconds(4)) {
        if (++g_abPhase >= 4) { g_ab = Ab::Done; GBX_INFO("ab: done (A, B, A, B)"); }
        else g_ab = Ab::Idle;
    }
}

}  // namespace

// ------------------------------------------------------------------------------------------------------------ api

std::wstring g_configPath;
std::filesystem::file_time_type g_configStamp{};
std::chrono::steady_clock::time_point g_configPolled{};

void loadConfig(const std::wstring& path)
{
    std::lock_guard<std::mutex> _(g_mutex);
    g_configPath = path;
    { std::error_code ec; g_configStamp = std::filesystem::last_write_time(path, ec); }
    std::ifstream in(path);
    if (!in) { GBX_INFO("config: none (observe on, hold off)"); return; }
    try {
        const auto j = nlohmann::json::parse(in);
        g_config.observe = j.value("observe", true);
        if (j.contains("manual") && j["manual"].is_object())
            manual::configure(j["manual"].value("upKey", std::string("LSHIFT")), j["manual"].value("downKey", std::string("LCTRL")),
                              j["manual"].value("padUp", std::string("X")), j["manual"].value("padDown", std::string("A")));
        if (j.contains("manual") && j["manual"].is_object()) {
            manual::setEngineAudio(j["manual"].value("engineAudio", true));
            manual::setEngineAudioScale(j["manual"].value("engineAudioScale", std::string("band")));
            {
                float lo = 1500.0f, hi = 5300.0f, gamma = 1.6f, follow = 0.3f, smoothMs = 120.0f;
                if (j["manual"].contains("curve") && j["manual"]["curve"].is_object()) {
                    const auto& c = j["manual"]["curve"];
                    lo = c.value("lo", lo); hi = c.value("hi", hi); gamma = c.value("gamma", gamma);
                    follow = c.value("follow", follow); smoothMs = c.value("smoothMs", smoothMs);
                }
                manual::setCurve(lo, hi, gamma, follow, smoothMs);
            }
            {
                float landing = 2600.0f, redline = 5300.0f, floorRpm = -30000.0f;
                int slices = 7;
                if (j["manual"].contains("band") && j["manual"]["band"].is_object()) {
                    const auto& b = j["manual"]["band"];
                    landing = b.value("landingRpm", landing); redline = b.value("redlineRpm", redline);
                    floorRpm = b.value("minRpmFloor", floorRpm);
                    slices = b.value("slices", slices);
                }
                manual::setBand(landing, redline, floorRpm);
                manual::setSlices(slices);
            }
            manual::setAudioCycleKey(j["manual"].value("audioCycleKey", std::string("PAGEUP")));
            std::vector<std::string> layers = {"fraction", "off", "rpm", "limiter"};
            float floor = 0.12f;
            if (j["manual"].contains("blend") && j["manual"]["blend"].is_object()) {
                const auto& b = j["manual"]["blend"];
                if (b.contains("layers") && b["layers"].is_array()) layers = b["layers"].get<std::vector<std::string>>();
                floor = b.value("floor", floor);
            }
            manual::setBlend(layers, floor);
        }
        else manual::configure("LSHIFT", "LCTRL", "X", "A");
        if (j.contains("hold") && j["hold"].is_object()) {
            g_config.holdField = j["hold"].value("field", std::string());
            g_config.holdPath = j["hold"].value("path", std::string());
            scan::setTrial(j["hold"].value("trial", false));
            g_config.ab = j["hold"].value("ab", false);
            if (g_config.ab) GBX_WARN("config: the A/B hold trial is on (path %s)", g_config.holdPath.c_str());
            if (j["hold"].value("trial", false)) GBX_WARN("config: the automatic hold TRIAL is on");
            g_config.holdGear = j["hold"].value("gear", 2);
        }
        manual::setConfigError("");
        const std::string target = !g_config.holdPath.empty() ? g_config.holdPath : g_config.holdField;
        GBX_INFO("config: observe %s, hold %s", g_config.observe ? "on" : "off",
                 target.empty() ? "off" : (target + " = " + std::to_string(g_config.holdGear)).c_str());
    } catch (const std::exception& e) {
        GBX_ERR("config unreadable (%s): last good audio values kept, observe off, hold off", e.what());
        manual::setConfigError(e.what());
        g_config = Config{};
        g_config.observe = false;   // a typo while tuning should not switch the census log on
    }
}

bool instrumenting() { return g_config.observe; }

void census()
{
    static bool done = false;
    if (done) return;
    done = true;
    auto* rtti = RED4ext::CRTTISystem::Get();
    if (!rtti) { GBX_ERR("census: no RTTI"); return; }
    RED4ext::DynArray<RED4ext::CClass*> classes;
    rtti->GetClasses(nullptr, classes);
    size_t props = 0, funcs = 0, logged = 0;
    for (auto* cls : classes) {
        if (!cls) continue;
        const std::string owner = cls->name.ToString();
        const bool ownerHit = interesting(owner);
        auto prop = [&](RED4ext::CProperty* p) {
            if (!p || p->parent != cls) return;   // each property once, on the class that declares it
            const std::string name = p->name.ToString();
            if (!ownerHit && !interesting(name)) return;
            ++props;
            if (logged++ < 1500) GBX_INFO("census prop %s.%s : %s @0x%X", owner.c_str(), name.c_str(), typeName(p->type).c_str(), p->valueOffset);
        };
        for (auto* p : cls->props) prop(p);
        for (auto* p : cls->unk118) prop(p);
        auto fn = [&](RED4ext::CBaseFunction* f, bool isStatic) {
            if (!f) return;
            const std::string name = f->shortName.ToString();
            if (!interesting(name) && !(ownerHit && f->flags.isNative)) return;
            ++funcs;
            std::string sig = owner + (isStatic ? "::" : ".") + name + "(";
            bool first = true;
            for (auto* p : f->params) {
                if (!p) continue;
                if (!first) sig += ", ";
                first = false;
                sig += std::string(p->name.ToString()) + ": " + typeName(p->type);
            }
            sig += ")";
            if (f->returnType && f->returnType->type) sig += " -> " + typeName(f->returnType->type);
            if (logged++ < 1500) GBX_INFO("census func %s%s", sig.c_str(), f->flags.isNative ? " [native]" : "");
        };
        for (auto* f : cls->funcs) fn(f, false);
        for (auto* f : cls->staticFuncs) fn(f, true);
    }
    RED4ext::DynArray<RED4ext::CEnum*> enums;
    rtti->GetEnums(enums, false);
    size_t enumHits = 0;
    for (auto* e : enums) {
        if (!e) continue;
        const std::string name = e->name.ToString();
        bool hit = interesting(name);
        for (auto& member : e->hashList) if (interesting(member.ToString())) hit = true;
        if (!hit) continue;
        ++enumHits;
        std::string members;
        for (uint32_t i = 0; i < e->hashList.size() && i < 40; ++i) {
            if (!members.empty()) members += ", ";
            members += e->hashList[i].ToString();
            if (i < e->valueList.size()) members += "=" + std::to_string(e->valueList[i]);
        }
        if (logged++ < 1500) GBX_INFO("census enum %s { %s }", name.c_str(), members.c_str());
    }
    GBX_INFO("census: %zu class(es) scanned; %zu gear-like propert(ies), %zu function(s), %zu enum(s)%s", static_cast<size_t>(classes.size()), props,
             funcs, enumHits, logged > 1500 ? " (log capped at 1500 lines)" : "");
}

void observe(RED4ext::IScriptable* vehicle, int32_t hudGear, float hudRpm, float speed)
{
    if (!vehicle || !g_config.observe) return;
    std::lock_guard<std::mutex> _(g_mutex);
    auto* cls = vehicle->GetType();
    if (!cls) return;
    Layout& layout = layoutFor(cls);
    ++g_observations;
    // a different car: the scan starts over
    static const void* lastCar = nullptr;
    if (lastCar && lastCar != vehicle) scan::reset("changed car");
    lastCar = vehicle;
    // with a known gear path the scan has done its job; the A/B trial runs instead
    if (g_config.holdPath.empty()) { try { scan::step(vehicle, cls->GetSize(), hudGear, hudRpm, speed); } catch (...) {} }
    else { try { abStep(vehicle, hudGear, hudRpm, speed); } catch (...) {} }
    const auto* base = reinterpret_cast<const uint8_t*>(vehicle);
    std::string changed;
    for (auto& f : layout.fields) {
        const double v = readValue(base, f.offset, f.kind);
        if (f.seen && v != f.last) {
            char buf[160];
            std::snprintf(buf, sizeof(buf), " %s %g->%g", f.prop.c_str(), f.last, v);
            changed += buf;
        }
        f.last = v;
        f.seen = true;
    }
    const auto now = std::chrono::steady_clock::now();
    const bool shifted = hudGear != g_lastHud;
    if ((shifted || now - g_lastBeat > std::chrono::seconds(3)) && budget()) {
        std::string all;
        for (const auto& f : layout.fields) {
            char buf[120];
            std::snprintf(buf, sizeof(buf), " %s=%g", f.prop.c_str(), f.last);
            all += buf;
        }
        GBX_INFO("%s hud gear %d (was %d) rpm %.0f speed %.1f m/s |%s%s%s", shifted ? "SHIFT" : "beat ", hudGear, g_lastHud,
                 hudRpm, speed, all.c_str(), changed.empty() ? "" : " | changed:", changed.c_str());
        g_lastBeat = now;
    }
    g_lastHud = hudGear;
}

bool hold(RED4ext::IScriptable* vehicle)
{
    if (g_config.ab) return false;   // the A/B trial does its own writing, only while it runs
    if (vehicle && !g_config.holdPath.empty()) {
        bool wrote = false;
        try { wrote = scan::hold(vehicle, g_config.holdPath, g_config.holdGear); } catch (...) {}
        if (wrote) ++g_writes;
        return wrote;
    }
    if (!vehicle || g_config.holdField.empty()) return false;
    std::lock_guard<std::mutex> _(g_mutex);
    auto* cls = vehicle->GetType();
    if (!cls) return false;
    Layout& layout = layoutFor(cls);
    if (layout.holdIndex < 0) return false;
    const Field& f = layout.fields[static_cast<size_t>(layout.holdIndex)];
    auto* p = reinterpret_cast<uint8_t*>(vehicle) + f.offset;
    const int64_t g = g_config.holdGear;
    switch (f.kind) {
    case Kind::I8: *reinterpret_cast<int8_t*>(p) = static_cast<int8_t>(g); break;
    case Kind::U8: *reinterpret_cast<uint8_t*>(p) = static_cast<uint8_t>(g); break;
    case Kind::I16: *reinterpret_cast<int16_t*>(p) = static_cast<int16_t>(g); break;
    case Kind::U16: *reinterpret_cast<uint16_t*>(p) = static_cast<uint16_t>(g); break;
    case Kind::I32: *reinterpret_cast<int32_t*>(p) = static_cast<int32_t>(g); break;
    case Kind::U32: *reinterpret_cast<uint32_t*>(p) = static_cast<uint32_t>(g); break;
    case Kind::I64: *reinterpret_cast<int64_t*>(p) = g; break;
    case Kind::U64: *reinterpret_cast<uint64_t*>(p) = static_cast<uint64_t>(g); break;
    default: return false;
    }
    if (g_writes.fetch_add(1) == 0) GBX_WARN("hold: first write of %d to %s", g_config.holdGear, f.name.c_str());
    return true;
}

void leftCar()
{
    std::lock_guard<std::mutex> _(g_mutex);
    stepper::disarm();
    if (g_ab == Ab::Running) { g_ab = Ab::Rest; g_abAt = std::chrono::steady_clock::now(); GBX_INFO("ab: phase cut short (out of the car)"); }
    scan::reset("out of the car");
}

std::string status()
{
    return "observations=" + std::to_string(g_observations.load()) + " writes=" + std::to_string(g_writes.load()) +
           " steps=" + std::to_string(stepper::calls()) + " overrides=" + std::to_string(stepper::overrides()) +
           " hold=" + (!g_config.holdPath.empty() ? g_config.holdPath : g_config.holdField.empty() ? std::string("off") : g_config.holdField);
}

/// 0.2.8: re-read the config when the file changes (checked once a second), so the engine voice can be tuned while
/// the game runs -- edit `ncm_gearbox_config.json`, save, keep driving.
void pollConfig()
{
    const auto now = std::chrono::steady_clock::now();
    if (g_configPath.empty() || now - g_configPolled < std::chrono::seconds(1)) return;
    g_configPolled = now;
    std::error_code ec;
    const auto stamp = std::filesystem::last_write_time(g_configPath, ec);
    if (ec || stamp == g_configStamp) return;
    GBX_INFO("config: changed on disk -- reloading");
    loadConfig(g_configPath);
}

}  // namespace ncm::gearbox::discover
