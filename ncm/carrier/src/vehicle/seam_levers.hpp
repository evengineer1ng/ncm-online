// NCM Snowglobe -> NCM Carrier: the seam's velocity restore (L317 SEAM-1c).
//
// The server's move (`Open77.vehicles.setTransform`) holds and keeps the driver, but it erases the car's velocity
// (§SG4: 83.6 -> 0 m/s), freezes the car until the physics lease comes back (~3 s), and unbinds Carrier until the
// lease does (§SG5: unbound 01:46:47, BOUND again 01:46:51 -- a kick sent at :49-:50 was refused). So v2 carries a
// TARGET velocity, published the moment NCM Snowglobe sees the jump, and NCM Carrier HOLDS it for up to kHoldMs: at
// the first gravity entry of the re-bound car it adds m * (target - v_now) once, through the force channel F0 proved
// (Carrier's gates: KB-146 binding, kill switch, SEH). The binding returns with the lease, so the gate is exactly
// "the car is ours to push again".
//
// Shared memory, named per PROCESS (`Local\NCM_Seam_Levers_<pid>`). A new `kickSeq` with a stamp younger than
// kHoldMs is a request; anything older is ignored. This header is duplicated verbatim in
// ncm/carrier/src/vehicle/seam_levers.hpp (and ncm/snowglobe/src/seam_levers.hpp).
#pragma once

#include <cstdint>
#include <cstdio>

namespace ncm::seam_levers {

constexpr uint32_t kMagic = 0x4D45534Eu;   // "NSEM"
constexpr uint32_t kVersion = 2;
constexpr uint64_t kHoldMs = 8000;
constexpr float kMaxDv = 150.0f;           // m/s per axis, on the applied change; Carrier clamps

struct Block {
    uint32_t magic;
    uint32_t version;
    volatile uint64_t stampMs;     // GetTickCount64() of the request
    volatile uint32_t kickSeq;     // +1 per request
    volatile float target[3];      // m/s, world frame: the velocity the car should have again
};

inline void name(wchar_t* out, size_t size, unsigned long pid)
{
    swprintf_s(out, size, L"Local\\NCM_Seam_Levers_%lu", pid);
}

}  // namespace ncm::seam_levers
