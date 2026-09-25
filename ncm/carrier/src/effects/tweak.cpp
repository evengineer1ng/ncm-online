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
    const uint64_t driveModel = resolveDriveModel(vehicleRecord);
    if (driveModel == 0) return 0;
    std::lock_guard<std::mutex> lock(mutex_);
    return restoreRecord(driveModel);
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
