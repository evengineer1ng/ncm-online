// NCM Gearbox -> NCM Carrier: the virtual gear's levers (L306 phase 3, owner ruling 2026-10-04: "Carrier's live levers").
//
// A manual car's engine sees ONE long native gear (the clone's gear table, built at startup), so the native gearbox
// has nothing to shift and nothing of its live state is ever written. The gear the driver selected exists only here:
// NCM Gearbox publishes, every frame while a manual is driven, how much of the drive that gear keeps (`driveMul`,
// its torque against the long native gear's) and where it runs out of revs (`ceilingMps`). NCM Carrier -- which
// already scales the seated car's drive and governs its top speed live, every physics step (MASTER_TEST §AU/§AW) --
// multiplies them in. Carrier owns the physics; the Gearbox owns the gear.
//
// Shared memory, named per PROCESS (`Local\NCM_Gearbox_Levers_<pid>`), so two games on one PC never read each
// other's gear (the KB-147 / KB-329 lesson). A stamp older than kStaleMs means "no manual right now": Carrier then
// behaves exactly as before. This header is duplicated verbatim in ncm/carrier/src/vehicle/gearbox_levers.hpp (and ncm/gearbox/src/levers_shm.hpp).
#pragma once

#include <cstdint>
#include <cstdio>

namespace ncm::gearbox_levers {

constexpr uint32_t kMagic = 0x5842474Eu;   // "NGBX"
constexpr uint32_t kVersion = 1;
constexpr uint64_t kStaleMs = 200;

struct Block {
    uint32_t magic;
    uint32_t version;
    volatile uint64_t stampMs;    // GetTickCount64() of the last publish; 0 = never
    volatile float driveMul;      // 0 (neutral, or the shift cut) .. 1
    volatile float ceilingMps;    // this gear's limiter; 0 = none
    volatile int32_t gear;        // 0 = N, 1..n
    volatile uint32_t seq;
};

inline void name(wchar_t* out, size_t size, unsigned long pid)
{
    swprintf_s(out, size, L"Local\\NCM_Gearbox_Levers_%lu", pid);
}

}  // namespace ncm::gearbox_levers
