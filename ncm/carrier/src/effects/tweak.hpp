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

}  // namespace ncm::effects
