// NCM Carrier -- drive-model flats, and the ledger that guarantees we can put them back.
//
// SEMANTICS PORTED VERBATIM from NCM's own single-player mod, which has done this for months
// (`ncm-localized/.../MT_Ecosystem/modules/tuning.lua:633-670`):
//
//   1. Capture the original value BEFORE the first write, once, per record and suffix.
//   2. Every multiplier applies against that captured original -- never against the current value.
//      Re-multiplying an already-multiplied value is how tuning drifts to zero over a session.
//   3. Restore writes the captured originals back and forgets them.
//
// Rule 2 is why the wire format carries a multiplier and not a final number. The server does not know what
// the factory value is on this player's install -- another mod may have changed it -- and inventing one
// would silently overwrite somebody else's work.
//
// WHY THE LEDGER IS KEYED BY ID AND NOT BY NAME. TweakDB does not store the strings it hashes, so a
// `TweakDBID` cannot be turned back into text. The drive-model record is resolved from the vehicle record
// once, and everything after that is keyed by the resolved id -- which also means restoring on unload needs
// no lookups at all, and works even if TweakDB is half torn down.
//
// SCOPE, STATED PLAINLY. These are per-RECORD and **spawn-cached**. A change reaches a car when the car
// spawns and not before (Report 36 section 4). Nothing here is live, and no amount of rewriting makes it so.
#pragma once

#include <cstdint>
#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace ncm::effects {

struct FlatChange {
    std::string id;         // NCM's stable name, for the trace
    std::string suffix;     // the TweakDB flat, e.g. ".brakingFriction"
    double multiplier = 1.0;
};

/// One change to ONE FLAT on the gear records hanging off a vehicle's engine data.
///
/// **Why gears are a separate type from `FlatChange`.** A drive-model flat has exactly one home per
/// vehicle; a gear flat has one home PER GEAR, and the gears are an ordered array. `.maxSpeed` means
/// nothing without saying which gear, and the two most useful operations address the array differently:
/// removing the crawl floor touches EVERY gear, while lengthening the top of the box touches the last one.
struct GearChange {
    std::string id;         // NCM's stable name, for the trace
    int gear = 0;           // 1-based index into `.gears`; 0 means EVERY gear; -1 means the LAST gear
    std::string suffix;     // ".minSpeed", ".maxSpeed", ".torqueMultiplier", ".minEngineRPM", ...
    double multiplier = 1.0;
};

struct ApplyResult {
    int applied = 0;
    int captured = 0;
    int refused = 0;        // flats that could not be read, and were therefore never written
    bool resolved = true;   // false when the vehicle record has no drive model we could find
};

class TweakStore {
public:
    /// Apply a projection to the drive model of one vehicle record. Idempotent: applying the same envelope
    /// twice produces the same values, because both apply against the captured originals.
    ApplyResult apply(const std::string& vehicleRecord, const std::vector<FlatChange>& flats);

    /// Apply a projection to the GEAR CHAIN of one vehicle record.
    ///
    /// Same ledger, same capture-before-write rule, same multiplier-against-original semantics. The only
    /// new thing is the traversal: `vehicle -> .vehEngineData -> .gears -> gear[i] -> suffix`, which is
    /// the path NCM's own Manual Transmission work uses to zero the per-gear speed floor.
    ApplyResult applyGears(const std::string& vehicleRecord, const std::vector<GearChange>& gears);

    /// Put back what was captured for one vehicle record, and forget it.
    int restore(const std::string& vehicleRecord);

    /// Put everything back. Called on disconnect, on world change, and on unload -- a player who alt-F4s
    /// out of NCM must not find their single-player brakes altered next week.
    int restoreAll();

    size_t recordsHeld() const;

private:
    struct Captured {
        uint64_t flatId = 0;
        float original = 0.0f;
    };

    int restoreRecord(uint64_t driveModelId);

    mutable std::mutex mutex_;
    // driveModelId -> (suffix -> what it was)
    std::map<uint64_t, std::map<std::string, Captured>> originals_;
};

/// The engine seam, isolated so the rest of the plugin never includes a RED4ext header.
bool readFlat(uint64_t flatId, float& out);
bool writeFlat(uint64_t flatId, uint64_t recordId, float value);
uint64_t composeFlatId(uint64_t recordId, const std::string& suffix);

/// Resolve the drive-model record a vehicle record points at: `.vehDriveModelData`, or `.bikeDriveModelData`
/// for two wheels. Mirrors `tuning.lua:137-139`. Returns 0 when neither exists.
uint64_t resolveDriveModel(const std::string& vehicleRecord);

/// Resolve the ENGINE DATA record: `.vehEngineData`. Returns 0 when it does not exist.
///
/// **This is a sibling of the drive model, not a child of it, and that distinction cost us months.** The
/// architecture dump has only ever probed `driveModel + suffix`, so every flat that actually lives on the
/// engine data -- `maxRPM`, `engineMaxTorque`, `gearChangeTime` -- reads as ABSENT from a probe that was
/// never going to find it. Engine data is also where the gears hang.
uint64_t resolveEngineData(const std::string& vehicleRecord);

/// Read the ordered `.gears` array off an engine-data record. Returns false when the flat is missing or
/// is not an array of ids.
///
/// The array is `array<TweakDBID>` and every entry is a record in its own right, with its own flats. That
/// is why a float-only probe cannot see a gearbox: there is no float at `engineData + ".gears"`, there is
/// a list of records, and each one has to be visited.
bool resolveGears(uint64_t engineDataId, std::vector<uint64_t>& out);

}  // namespace ncm::effects
