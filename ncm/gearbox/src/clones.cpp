#include "clones.hpp"

#include "log.hpp"
#include "manual.hpp"

#include <RED4ext/RED4ext.hpp>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <cmath>
#include <fstream>
#include <mutex>
#include <shared_mutex>

// THE CLONE, BUILT AT RUNTIME (L306, phase 0 S1).
//
// TweakXL creates each manual's VEHICLE record from its model with `$base` -- that name is known. Its ENGINE DATA is
// a different record whose vanilla name we do not have offline, so it cannot be `$base`d from YAML. Instead, once
// TweakDB is loaded, this copies the model's engine data property by property into `<clone>_engine` (each new flat
// points at the model's existing value: flat values are immutable and pooled, so sharing an offset is how TweakDB
// itself shares defaults), replaces `gears` with the spec's own forward gears, and points the clone's
// `.vehEngineData` at it. Clean room: built from the SDK's TweakDB API and our own Carrier's flat discipline, never
// from another mod's code.
namespace ncm::gearbox {
namespace {

RED4ext::rtti::IType* type(const char* name)
{
    auto* rtti = RED4ext::CRTTISystem::Get();
    return rtti ? rtti->GetType(name) : nullptr;
}

/// Every property a TweakDB record class exposes, as its flat suffix: the class's getters, first letter lowered
/// (`MaxSpeed` -> `maxSpeed`). Helpers like `GetGearsCount` produce names with no flat and are skipped by the caller.
std::vector<std::string> propertiesOf(const char* className)
{
    std::vector<std::string> out;
    auto* rtti = RED4ext::CRTTISystem::Get();
    auto* cls = rtti ? rtti->GetClass(className) : nullptr;
    if (!cls) return out;
    for (auto* fn : cls->funcs) {
        if (!fn) continue;
        std::string name = fn->shortName.ToString();
        if (name.empty()) continue;
        name[0] = static_cast<char>(std::tolower(static_cast<unsigned char>(name[0])));
        out.push_back(name);
    }
    return out;
}

bool offsetOf(RED4ext::TweakDB* tdb, RED4ext::TweakDBID flat, int32_t& offset)
{
    std::shared_lock<RED4ext::SharedSpinLock> _(tdb->mutex00);
    auto* it = tdb->flats.Find(flat);
    if (it == tdb->flats.End()) return false;
    offset = it->ToTDBOffset();
    return true;
}

bool addFlatAt(RED4ext::TweakDB* tdb, RED4ext::TweakDBID flat, int32_t offset)
{
    flat.SetTDBOffset(offset);
    return tdb->AddFlat(flat);
}

template <typename T>
int32_t newValue(RED4ext::TweakDB* tdb, const char* typeName, T& value)
{
    auto* t = type(typeName);
    if (!t) return -1;
    RED4ext::CStackType st(t, &value);
    return tdb->CreateFlatValue(st);
}

/// Repoint an EXISTING flat at a new value (Carrier's writeFlat, generalised to any type).
template <typename T>
bool repoint(RED4ext::TweakDB* tdb, RED4ext::TweakDBID flat, const char* typeName, T& value)
{
    const int32_t offset = newValue(tdb, typeName, value);
    if (offset < 0) return false;
    std::shared_lock<RED4ext::SharedSpinLock> _(tdb->mutex00);
    auto* it = tdb->flats.Find(flat);
    if (it == tdb->flats.End()) return false;
    it->SetTDBOffset(offset);
    return true;
}

float readF(RED4ext::TweakDB* tdb, RED4ext::TweakDBID record, const char* suffix, float fallback = NAN)
{
    float v = 0.0f;
    if (tdb->TryGetValue<float>(RED4ext::TweakDBID(record, suffix), v) && std::isfinite(v)) return v;
    return fallback;
}

struct Gear {
    RED4ext::TweakDBID id;
    float minSpeed = 0, maxSpeed = 0, minRpm = 0, maxRpm = 0, torque = 1;
};

bool readChain(RED4ext::TweakDB* tdb, RED4ext::TweakDBID engine, std::vector<Gear>& out)
{
    RED4ext::DynArray<RED4ext::TweakDBID> gears;
    if (!tdb->TryGetValue<RED4ext::DynArray<RED4ext::TweakDBID>>(RED4ext::TweakDBID(engine, ".gears"), gears))
        return false;
    for (uint32_t i = 0; i < gears.size(); ++i) {
        Gear g;
        g.id = gears[i];
        g.minSpeed = readF(tdb, g.id, ".minSpeed", 0.0f);
        g.maxSpeed = readF(tdb, g.id, ".maxSpeed", 0.0f);
        g.minRpm = readF(tdb, g.id, ".minEngineRPM", 0.0f);
        g.maxRpm = readF(tdb, g.id, ".maxEngineRPM", 0.0f);
        g.torque = readF(tdb, g.id, ".torqueMultiplier", 1.0f);
        out.push_back(g);
    }
    return !out.empty();
}

RED4ext::TweakDBID engineOf(RED4ext::TweakDB* tdb, const std::string& vehicle)
{
    RED4ext::TweakDBID ref;
    if (tdb->TryGetValue<RED4ext::TweakDBID>(RED4ext::TweakDBID(RED4ext::TweakDBID(vehicle), ".vehEngineData"), ref))
        return ref;
    return RED4ext::TweakDBID();
}

/// The car's sound-event prefix from its model record: `Vehicle.v_standard2_archer_hella(_player)` -> `v_car_archer_hella`
/// (the game's events are `v_car_<maker>_<model>_gear_up` / `_gear_down`, found in eventsmetadata.json, 2026-10-04).
std::string audioPrefixOf(std::string record)
{
    if (record.rfind("Vehicle.", 0) == 0) record = record.substr(8);
    const std::string player = "_player";
    if (record.size() > player.size() && record.compare(record.size() - player.size(), player.size(), player) == 0)
        record = record.substr(0, record.size() - player.size());
    // drop the body-class segment: v_standard2_ / v_sport1_ / v_utility4_ ...
    if (record.rfind("v_", 0) == 0) {
        const auto second = record.find('_', 2);
        if (second != std::string::npos) record = record.substr(second + 1);
    }
    return "v_car_" + record;
}

/// The model gear whose band best matches a target top speed: the first forward gear reaching it, else the last.
const Gear& templateFor(const std::vector<Gear>& forward, float targetTop)
{
    for (const auto& g : forward)
        if (g.maxSpeed >= targetTop) return g;
    return forward.back();
}

}  // namespace

Specs loadSpecs(const std::wstring& path)
{
    Specs specs;
    try {
        std::ifstream in(path);
        if (!in) { GBX_WARN("no specs file -- no manual clones this session"); return specs; }
        const auto j = nlohmann::json::parse(in);
        specs.reverseFirst = j.value("reverseFirst", true);
        specs.gearHeadroom = j.value("gearHeadroom", 0.0);
        for (const auto& c : j.at("clones")) {
            CloneSpec s;
            s.record = c.at("record").get<std::string>();
            s.base = c.at("base").get<std::string>();
            s.spec = c.at("spec").get<std::string>();
            s.ratios = c.at("ratios").get<std::vector<double>>();
            s.shiftMs = c.value("shiftMs", 250);
            s.topKph = c.value("topKph", 0.0);
            if (s.ratios.size() >= 2 && s.ratios.size() <= 10) specs.clones.push_back(std::move(s));
        }
        GBX_INFO("specs: %zu clone(s), reverseFirst=%s", specs.clones.size(), specs.reverseFirst ? "true" : "false");
    } catch (const std::exception& e) {
        GBX_ERR("specs file unreadable: %s", e.what());
        specs.clones.clear();
    }
    return specs;
}

void dumpModel(const std::string& vehicleRecord)
{
    auto* tdb = RED4ext::TweakDB::Get();
    if (!tdb) return;
    const auto engine = engineOf(tdb, vehicleRecord);
    if (!engine.IsValid()) { GBX_WARN("dump %s: no .vehEngineData", vehicleRecord.c_str()); return; }
    GBX_INFO("---- %s engine data %016llX ----", vehicleRecord.c_str(), static_cast<unsigned long long>(engine.value));
    for (const auto& prop : propertiesOf("gamedataVehicleEngineData_Record")) {
        const RED4ext::TweakDBID flat(engine, "." + prop);
        int32_t off = 0;
        if (!offsetOf(tdb, flat, off)) continue;
        float f = 0.0f;
        if (tdb->TryGetValue<float>(flat, f)) GBX_INFO("  %s = %g", prop.c_str(), f);
        else GBX_INFO("  %s (non-float flat)", prop.c_str());
    }
    std::vector<Gear> chain;
    if (!readChain(tdb, engine, chain)) { GBX_WARN("  no readable .gears"); return; }
    for (size_t i = 0; i < chain.size(); ++i) {
        const auto& g = chain[i];
        GBX_INFO("  gear[%zu] %016llX: speed %.2f-%.2f m/s (%.0f-%.0f km/h) rpm %.0f-%.0f torqueMul %.3f", i,
                 static_cast<unsigned long long>(g.id.value), g.minSpeed, g.maxSpeed, g.minSpeed * 3.6, g.maxSpeed * 3.6,
                 g.minRpm, g.maxRpm, g.torque);
    }
}

bool buildClone(const CloneSpec& clone, bool reverseFirst, double gearHeadroom)
{
    auto* tdb = RED4ext::TweakDB::Get();
    auto* rtti = RED4ext::CRTTISystem::Get();
    if (!tdb || !rtti) return false;
    auto* engineClass = rtti->GetClass("gamedataVehicleEngineData_Record");
    auto* gearClass = rtti->GetClass("gamedataVehicleGear_Record");
    if (!engineClass || !gearClass) { GBX_ERR("record classes missing from RTTI -- no clones"); return false; }

    const RED4ext::TweakDBID vehicle(clone.record);
    if (!tdb->GetRecord(vehicle)) {
        GBX_WARN("%s: the TweakXL clone does not exist (clones.yaml not loaded?) -- skipped", clone.record.c_str());
        return false;
    }
    const auto baseEngine = engineOf(tdb, clone.base);
    if (!baseEngine.IsValid()) { GBX_WARN("%s: model %s has no engine data", clone.record.c_str(), clone.base.c_str()); return false; }
    const std::string engineName = clone.record + "_engine";
    const RED4ext::TweakDBID newEngine(engineName);
    const bool alreadyBuilt = engineOf(tdb, clone.record) == newEngine;   // a second Running enter: rebuild the spec only

    std::vector<Gear> chain;
    if (!readChain(tdb, baseEngine, chain) || chain.size() < 2) { GBX_WARN("%s: model gear chain unreadable", clone.record.c_str()); return false; }
    const Gear* reverse = reverseFirst ? &chain.front() : nullptr;
    std::vector<Gear> forward(chain.begin() + (reverseFirst ? 1 : 0), chain.end());
    const float nativeTop = forward.back().maxSpeed;
    if (!(nativeTop > 1.0f)) { GBX_WARN("%s: model top gear maxSpeed %.2f is not credible", clone.record.c_str(), nativeTop); return false; }
    // 0.2.5 (owner QA 2026-10-04: "i was doing upwards of 140 kph in this car previously"): the ratios are fractions of
    // what the SAME car reaches as an automatic on NCM, not of the model's native top gear (115 km/h on the Hella).
    // Carrier stretches every catalogued automatic's chain by `gearHeadroom` (x1.45, L162) and the governor aims at the
    // catalogue top; the automatic is the envelope (core machine.gearbox), so the reference is the lower of the two.
    // Hella: min(167, 115 x 1.45) = 167. Caliburn: min(337, 162 x 1.45) = 235 -- never past its automatic.
    float refTop = nativeTop;
    if (clone.topKph > 1.0 && gearHeadroom > 1.0) refTop = std::min(static_cast<float>(clone.topKph / 3.6), static_cast<float>(nativeTop * gearHeadroom));

    // ---- L306 phase 3 (owner design 2026-10-04): ONE long native gear; the spec's gears are virtual (manual.cpp).
    // The native gearbox then has nothing to shift, and its live state is never written (KB-330: writing it crashed
    // the game). Each spec gear becomes a virtual gear: its ceiling is the spec's band top, its share is the torque of
    // the model gear that band was taken from against the long gear's -- the model's strongest forward torque.
    float nativeTorque = 0.0f, maxRpm = 0.0f;
    for (const auto& g : forward) { nativeTorque = std::max(nativeTorque, g.torque); maxRpm = std::max(maxRpm, g.maxRpm); }
    if (!(nativeTorque > 0.0f)) nativeTorque = 1.0f;
    manual::VirtualSpec vspec;
    vspec.spec = clone.spec;
    vspec.audio = audioPrefixOf(clone.base);
    vspec.longGear = RED4ext::TweakDBID(engineName + "_long").value;
    vspec.shiftMs = clone.shiftMs;
    vspec.idleRpm = forward.front().minRpm > 0.0f ? forward.front().minRpm : 800.0f;
    vspec.maxRpm = maxRpm > vspec.idleRpm ? maxRpm : vspec.idleRpm + 4000.0f;
    // the engine note's top: where the model's own gears shift (the median forward maxRpm -- 4500 on the Hella), not the
    // top gear's limiter (5300). The game drives `veh_engine_rpm` from that rpm, so this is the range its sound knows.
    {
        std::vector<float> tops;
        for (const auto& g : forward) if (g.maxRpm > vspec.idleRpm) tops.push_back(g.maxRpm);
        std::sort(tops.begin(), tops.end());
        vspec.audioMaxRpm = tops.empty() ? vspec.maxRpm : tops[tops.size() / 2];
    }
    float top = 0.0f;
    for (size_t i = 0; i < clone.ratios.size(); ++i) {
        const float ceiling = static_cast<float>(clone.ratios[i] * refTop);
        const Gear& tpl = templateFor(forward, ceiling);
        manual::VirtualGear vg;
        vg.ceilingMps = ceiling;
        vg.share = std::clamp(tpl.torque / nativeTorque, 0.05f, 1.0f);
        vspec.gears.push_back(vg);
        top = std::max(top, ceiling);
        vspec.longTopMps = top * 1.02f;
        GBX_INFO("  %s virtual gear %zu: to %.0f km/h, %.0f%% of the long gear's torque (model band %.0f km/h, torqueMul %.3f)",
                 clone.spec.c_str(), i + 1, ceiling * 3.6, vg.share * 100.0, tpl.maxSpeed * 3.6, tpl.torque);
    }

    if (alreadyBuilt) { manual::registerSpec(vehicle.value, std::move(vspec)); return true; }

    RED4ext::DynArray<RED4ext::TweakDBID> gearIds;
    if (reverse) gearIds.EmplaceBack(reverse->id);   // the model's own reverse, shared
    {
        const auto gearProps = propertiesOf("gamedataVehicleGear_Record");
        const Gear& tpl = forward.front();
        const RED4ext::TweakDBID gid(engineName + "_long");
        float minSpeed = 0.0f, maxSpeed = top * 1.02f;        // a hair past the top virtual gear's limiter
        float minRpm = vspec.idleRpm, maxRpmV = vspec.maxRpm, torque = nativeTorque;
        for (const auto& prop : gearProps) {
            int32_t off = 0;
            if (offsetOf(tdb, RED4ext::TweakDBID(tpl.id, "." + prop), off)) addFlatAt(tdb, RED4ext::TweakDBID(gid, "." + prop), off);
        }
        auto put = [&](const char* suffix, float& v) {
            const RED4ext::TweakDBID flat(gid, suffix);
            int32_t probe = 0;
            if (offsetOf(tdb, flat, probe)) return repoint(tdb, flat, "Float", v);
            const int32_t off = newValue(tdb, "Float", v);
            return off >= 0 && addFlatAt(tdb, flat, off);
        };
        const bool ok = put(".minSpeed", minSpeed) && put(".maxSpeed", maxSpeed) && put(".minEngineRPM", minRpm)
                        && put(".maxEngineRPM", maxRpmV) && put(".torqueMultiplier", torque);
        if (!ok || !tdb->CreateRecord(gid, gearClass)) {
            if (!tdb->GetRecord(gid)) { GBX_ERR("%s: the long gear was refused", clone.record.c_str()); return false; }
        }
        tdb->UpdateRecord(gid);
        gearIds.EmplaceBack(gid);
        GBX_INFO("  %s native: ONE long gear 0-%.0f km/h, rpm %.0f-%.0f, torqueMul %.3f", clone.spec.c_str(), maxSpeed * 3.6,
                 minRpm, maxRpmV, torque);
    }

    // ---- the engine data: the model's, property by property, with our gears
    size_t copied = 0;
    for (const auto& prop : propertiesOf("gamedataVehicleEngineData_Record")) {
        if (prop == "gears") continue;
        int32_t off = 0;
        if (offsetOf(tdb, RED4ext::TweakDBID(baseEngine, "." + prop), off)
            && addFlatAt(tdb, RED4ext::TweakDBID(newEngine, "." + prop), off)) ++copied;
    }
    const int32_t gearsOff = newValue(tdb, "array:TweakDBID", gearIds);
    if (gearsOff < 0 || !addFlatAt(tdb, RED4ext::TweakDBID(newEngine, ".gears"), gearsOff)) {
        GBX_ERR("%s: could not write the gear list", clone.record.c_str());
        return false;
    }
    if (!tdb->CreateRecord(newEngine, engineClass) && !tdb->GetRecord(newEngine)) {
        GBX_ERR("%s: engine data record refused", clone.record.c_str());
        return false;
    }
    tdb->UpdateRecord(newEngine);

    // ---- point the clone at it
    RED4ext::TweakDBID ref = newEngine;
    if (!repoint(tdb, RED4ext::TweakDBID(vehicle, ".vehEngineData"), "TweakDBID", ref)) {
        GBX_ERR("%s: could not repoint .vehEngineData", clone.record.c_str());
        return false;
    }
    tdb->UpdateRecord(vehicle);
    manual::registerSpec(vehicle.value, std::move(vspec));
    GBX_INFO("%s: %zu-speed %s built (%zu engine properties shared, one long native gear, gears against %s top %.0f km/h, model top %.0f km/h, reverse %s)",
             clone.record.c_str(), clone.ratios.size(), clone.spec.c_str(), copied, refTop > nativeTop ? "automatic-reach" : "model",
             refTop * 3.6, nativeTop * 3.6, reverse ? "shared" : "none");
    return true;
}

bool retuneLongGear(uint64_t gearId, float maxSpeedMps, float minRpm, float maxRpm)
{
    auto* tdb = RED4ext::TweakDB::Get();
    if (!tdb || !gearId || !(maxSpeedMps > 0.5f)) return false;
    const RED4ext::TweakDBID gid(gearId);
    float v = maxSpeedMps, lo = minRpm, hi = maxRpm;
    if (!repoint(tdb, RED4ext::TweakDBID(gid, ".maxSpeed"), "Float", v)) return false;
    // 0.3.1: the rpm window -- `.minEngineRPM` is the rpm at 0 km/h, `.maxEngineRPM` at the band's top
    if (std::isfinite(lo) && std::isfinite(hi) && hi > lo) {
        repoint(tdb, RED4ext::TweakDBID(gid, ".minEngineRPM"), "Float", lo);
        repoint(tdb, RED4ext::TweakDBID(gid, ".maxEngineRPM"), "Float", hi);
    }
    tdb->UpdateRecord(gid);
    return true;
}

}  // namespace ncm::gearbox
