#include "effects/tweak.hpp"

#include "log.hpp"

#include <RED4ext/RED4ext.hpp>

#include <cmath>

namespace ncm::effects {
namespace {

RED4ext::CBaseRTTIType* floatType()
{
    static RED4ext::CBaseRTTIType* cached = nullptr;
    if (!cached) {
        if (auto* rtti = RED4ext::CRTTISystem::Get()) cached = rtti->GetType("Float");
    }
    return cached;
}

}  // namespace

uint64_t composeFlatId(uint64_t recordId, const std::string& suffix)
{
    // Exactly what `TweakDBID.new(driveModelRef, ".brakingFriction")` builds on the CET side: the flat's
    // identity is the record's hash extended by the suffix.
    const RED4ext::TweakDBID base(recordId);
    const RED4ext::TweakDBID flat(base, suffix);
    return flat.value;
}

bool readFlat(uint64_t flatId, float& out)
{
    auto* tdb = RED4ext::TweakDB::Get();
    if (!tdb) return false;

    float value = 0.0f;
    if (!tdb->TryGetValue<float>(RED4ext::TweakDBID(flatId), value)) return false;
    if (std::isnan(value) || std::isinf(value)) return false;

    out = value;
    return true;
}

// ---------------------------------------------------------------------------------------------------------
// Writing a flat.
//
// **This is the least obvious code in the plugin, and it is worth understanding before changing.** A
// `FlatValue` has no setter, because flat storage is a shared append-only buffer: the value is not owned by
// the record, the record holds an OFFSET into the buffer. So writing is three steps --
//
//   1. append a brand new value to the flat buffer (`CreateFlatValue`), which returns its offset;
//   2. repoint the flat's own `TweakDBID` at that offset;
//   3. tell the record to re-read its offsets (`UpdateRecord`).
//
// Mutating the existing value in place would change it for every flat sharing that storage, which on a
// default value is most of the game. This is the same approach TweakXL takes, and the reason it exists.
// ---------------------------------------------------------------------------------------------------------
bool writeFlat(uint64_t flatId, uint64_t recordId, float value)
{
    if (std::isnan(value) || std::isinf(value)) return false;

    auto* tdb = RED4ext::TweakDB::Get();
    auto* type = floatType();
    if (!tdb || !type) return false;

    RED4ext::CStackType stackType(type, &value);
    const int32_t offset = tdb->CreateFlatValue(stackType);
    if (offset < 0) {
        NCM_WARN("flat buffer would not accept a new value");
        return false;
    }

    // `flats` is sorted and compares on hash and length only, so the lookup key does not need the offset
    // we are about to write into it.
    RED4ext::TweakDBID key(flatId);
    RED4ext::TweakDBID* existing = nullptr;
    {
        std::shared_lock<RED4ext::SharedSpinLock> _(tdb->mutex00);
        existing = tdb->flats.Find(key);
        if (existing == tdb->flats.End()) existing = nullptr;
    }
    if (!existing) return false;

    existing->SetTDBOffset(offset);
    tdb->UpdateRecord(RED4ext::TweakDBID(recordId));
    return true;
}

uint64_t resolveDriveModel(const std::string& vehicleRecord)
{
    auto* tdb = RED4ext::TweakDB::Get();
    if (!tdb) return 0;

    const RED4ext::TweakDBID vehicle(vehicleRecord);
    // Cars first, then bikes -- the same order and the same two suffixes the single-player mod uses.
    for (const char* suffix : { ".vehDriveModelData", ".bikeDriveModelData" }) {
        RED4ext::TweakDBID ref;
        if (tdb->TryGetValue<RED4ext::TweakDBID>(RED4ext::TweakDBID(vehicle, suffix), ref) && ref.IsValid())
            return ref.value;
    }
    return 0;
}

uint64_t resolveEngineData(const std::string& vehicleRecord)
{
    auto* tdb = RED4ext::TweakDB::Get();
    if (!tdb) return 0;

    const RED4ext::TweakDBID vehicle(vehicleRecord);
    RED4ext::TweakDBID ref;
    if (tdb->TryGetValue<RED4ext::TweakDBID>(RED4ext::TweakDBID(vehicle, ".vehEngineData"), ref)
        && ref.IsValid())
        return ref.value;
    return 0;
}

bool resolveGears(uint64_t engineDataId, std::vector<uint64_t>& out)
{
    out.clear();
    auto* tdb = RED4ext::TweakDB::Get();
    if (!tdb || engineDataId == 0) return false;

    // `.gears` is `array<TweakDBID>`. `TryGetValue` is generic over the stored type, so the only thing
    // that makes this different from reading a float is asking for the right one.
    RED4ext::DynArray<RED4ext::TweakDBID> gears;
    if (!tdb->TryGetValue<RED4ext::DynArray<RED4ext::TweakDBID>>(
            RED4ext::TweakDBID(RED4ext::TweakDBID(engineDataId), ".gears"), gears))
        return false;

    out.reserve(gears.size());
    for (uint32_t i = 0; i < gears.size(); ++i) {
        if (gears[i].IsValid()) out.push_back(gears[i].value);
    }
    return !out.empty();
}

// ---------------------------------------------------------------------------------------------------------
// The ledger.
// ---------------------------------------------------------------------------------------------------------

ApplyResult TweakStore::apply(const std::string& vehicleRecord, const std::vector<FlatChange>& flats)
{
    ApplyResult result;

    const uint64_t driveModel = resolveDriveModel(vehicleRecord);
    if (driveModel == 0) {
        NCM_WARN("no drive model on '%s' -- nothing applied", vehicleRecord.c_str());
        result.resolved = false;
        return result;
    }

    std::lock_guard<std::mutex> lock(mutex_);
    auto& captured = originals_[driveModel];

    for (const auto& change : flats) {
        const uint64_t flatId = composeFlatId(driveModel, change.suffix);

        // Capture once, before the first write, and never again. If we cannot read it we do not write it:
        // a flat we cannot put back is a flat we have no business touching.
        auto it = captured.find(change.suffix);
        if (it == captured.end()) {
            float original = 0.0f;
            if (!readFlat(flatId, original)) {
                NCM_WARN("unreadable flat %s on '%s' -- refusing to write it",
                         change.suffix.c_str(), vehicleRecord.c_str());
                ++result.refused;
                continue;
            }
            it = captured.emplace(change.suffix, Captured{ flatId, original }).first;
            ++result.captured;
        }

        const double target = static_cast<double>(it->second.original) * change.multiplier;
        if (writeFlat(it->second.flatId, driveModel, static_cast<float>(target))) {
            ++result.applied;
        } else {
            NCM_WARN("write refused for %s on '%s'", change.suffix.c_str(), vehicleRecord.c_str());
            ++result.refused;
        }
    }

    if (captured.empty()) originals_.erase(driveModel);
    return result;
}

// ---------------------------------------------------------------------------------------------------------
// The gear chain.
//
// **What this is for, concretely.** Every gear declares a speed BAND -- `minSpeed` to `maxSpeed`, in metres
// per second -- and the engine applies force to keep the car inside the band of whichever gear it is in.
// The floor is not advisory: a car in a high gear has a high floor, and NCM's own Manual Transmission work
// found that full brake from speed would not bring a car to a stop, because the gearbox kept pushing it up
// to the floor. That is a FORWARD force, so `brakeScale` -- which only ever scales RETARDING force -- cannot
// reach it, and `driveScale` can only ever remove 70 percent of it and takes all the car's power with it.
// Zeroing `.minSpeed` is the targeted fix and it is the one that was proven to work.
//
// The ceiling is the other half: the top gear's `maxSpeed` is the highest speed the drivetrain will pull a
// car to. It is not a hard clamp -- a car can be drag-limited well below it -- but nothing pushes past it.
// ---------------------------------------------------------------------------------------------------------
ApplyResult TweakStore::applyGears(const std::string& vehicleRecord, const std::vector<GearChange>& gears)
{
    ApplyResult result;
    if (gears.empty()) return result;

    const uint64_t engineData = resolveEngineData(vehicleRecord);
    if (engineData == 0) {
        NCM_WARN("no engine data on '%s' -- no gear chain to write", vehicleRecord.c_str());
        result.resolved = false;
        return result;
    }

    std::vector<uint64_t> chain;
    if (!resolveGears(engineData, chain)) {
        NCM_WARN("engine data on '%s' has no readable .gears array", vehicleRecord.c_str());
        result.resolved = false;
        return result;
    }

    std::lock_guard<std::mutex> lock(mutex_);

    for (const auto& change : gears) {
        // Address the array. 0 is every gear, -1 is the last one, otherwise a 1-based index. An index past
        // the end is a request we cannot honour and is refused rather than clamped: silently writing gear 5
        // when gear 7 was asked for would be a wrong car that logged success.
        size_t first = 0, last = 0;
        if (change.gear == 0) {
            first = 0;
            last = chain.size() - 1;
        } else if (change.gear == -1) {
            first = last = chain.size() - 1;
        } else if (change.gear >= 1 && static_cast<size_t>(change.gear) <= chain.size()) {
            first = last = static_cast<size_t>(change.gear) - 1;
        } else {
            NCM_WARN("gear %d is outside the %zu-gear chain on '%s' -- refused",
                     change.gear, chain.size(), vehicleRecord.c_str());
            ++result.refused;
            continue;
        }

        for (size_t i = first; i <= last; ++i) {
            const uint64_t gearId = chain[i];
            const uint64_t flatId = composeFlatId(gearId, change.suffix);
            auto& captured = originals_[gearId];

            auto it = captured.find(change.suffix);
            if (it == captured.end()) {
                float original = 0.0f;
                if (!readFlat(flatId, original)) {
                    NCM_WARN("unreadable gear flat %s on gear %zu of '%s' -- refusing to write it",
                             change.suffix.c_str(), i + 1, vehicleRecord.c_str());
                    ++result.refused;
                    if (captured.empty()) originals_.erase(gearId);
                    continue;
                }
                it = captured.emplace(change.suffix, Captured{ flatId, original }).first;
                ++result.captured;
            }

            const double target = static_cast<double>(it->second.original) * change.multiplier;
            if (writeFlat(it->second.flatId, gearId, static_cast<float>(target))) {
                ++result.applied;
            } else {
                NCM_WARN("write refused for gear flat %s on gear %zu of '%s'",
                         change.suffix.c_str(), i + 1, vehicleRecord.c_str());
                ++result.refused;
            }
        }
    }

    return result;
}

int TweakStore::restoreRecord(uint64_t driveModelId)
{
    auto it = originals_.find(driveModelId);
    if (it == originals_.end()) return 0;

    int restored = 0;
    for (const auto& [suffix, captured] : it->second) {
        if (writeFlat(captured.flatId, driveModelId, captured.original)) ++restored;
    }
    originals_.erase(it);
    return restored;
}

int TweakStore::restore(const std::string& vehicleRecord)
{
    // Resolve both halves BEFORE taking the lock: `resolveGears` reads TweakDB, and `restoreRecord` writes
    // it, so doing the reads inside our own mutex would nest two different locks in two different orders
    // depending on which path got here first.
    const uint64_t driveModel = resolveDriveModel(vehicleRecord);
    const uint64_t engineData = resolveEngineData(vehicleRecord);
    std::vector<uint64_t> chain;
    if (engineData != 0) resolveGears(engineData, chain);

    std::lock_guard<std::mutex> lock(mutex_);
    int restored = 0;
    if (driveModel != 0) restored += restoreRecord(driveModel);
    // **The gear chain has to be named to be put back.** `restoreAll` walks the ledger and so needs no
    // help, but a single-vehicle restore only knows the vehicle record -- and a gear record is reachable
    // from it only by walking the engine data again.
    for (uint64_t gearId : chain) restored += restoreRecord(gearId);
    return restored;
}

int TweakStore::restoreAll()
{
    std::lock_guard<std::mutex> lock(mutex_);

    std::vector<uint64_t> records;
    records.reserve(originals_.size());
    for (const auto& [id, _] : originals_) records.push_back(id);

    int restored = 0;
    for (uint64_t id : records) restored += restoreRecord(id);
    if (restored > 0) NCM_INFO("restored %d flat(s) to their original values", restored);
    return restored;
}

size_t TweakStore::recordsHeld() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return originals_.size();
}

}  // namespace ncm::effects
