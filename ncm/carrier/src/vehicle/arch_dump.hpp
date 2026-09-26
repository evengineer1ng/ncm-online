// NCM Carrier -- read the game's own drive-model data for a list of vehicle records and write it to a file.
//
// **Strictly read-only. Nothing here writes to the game.** `L148` is not involved, because nothing is
// mutated; this uses the same TweakDB traversal `effects::TweakStore` already performs and stops at the read.
//
// WHY IT EXISTS (`IDEA-507`). `parts.architecture` knows 124 of 378 (vehicle, facet) pairs. The rest -- is a
// Galena front- or rear-wheel drive, is it combustion or electric -- live in `vehDriveModelData`, which only a
// running game can read. Authoring 254 facts from memory would produce data indistinguishable from fact but
// not necessarily equal to it.
//
// IT ALSO SETTLES A SECOND QUESTION, and this may be the more valuable half. `machine.flats` grades half its
// vocabulary `documented`: *"named in the `vehDriveModelData` record schema but NCM has never written it.
// Inventory, not experience."* Six flats carry that grade, including `frictionMulLateral` -- **the grip
// field** -- and `total_mass`. This dump reports, per record, which candidate flats actually resolve on this
// build. That converts `documented` into present-or-absent before any Part is designed on top of one.
//
// WHAT IT CANNOT DO, stated up front so nobody reads more into the output than is there:
//
//   * **Floats only.** `TryGetValue<float>` is the only accessor used. `wheelsFrictionMap` is a `TweakDBID`
//     and per-wheel presets are nested records; both are reported as unresolved rather than chased, because
//     a half-correct traversal would produce confident wrong data.
//   * **A missing flat is not proof of absence.** It means this suffix, composed this way, did not resolve as
//     a float on this build. That is evidence, not a schema.
//   * **It does not infer.** No fwd/rwd guess is made from numbers here. If drivetrain layout turns out to be
//     derivable from what is dumped, the inference rule belongs somewhere reviewable -- in the importer, in
//     the open -- and not buried in a C++ probe (`IDEA-507` caution 2).
#pragma once

#include <string>
#include <vector>

namespace ncm::vehicle::arch {

struct DumpResult {
    int records = 0;         // vehicle records asked about
    int resolved = 0;        // records whose drive model we found
    int flatsRead = 0;       // (record, flat) pairs that produced a number
    bool written = false;    // did the file reach disk
    std::string path;        // where it went, for the log
};

/// Probe `records` and write the result as JSON beside the DLL. Safe to call with an empty list (does
/// nothing). Never throws; every failure is reported in the result and the log.
DumpResult dump(const std::vector<std::string>& records);

/// Where the dump is written. Set once at attach, from the same directory the log and config use.
void setOutputDirectory(const std::wstring& dllDirectory);

}  // namespace ncm::vehicle::arch
