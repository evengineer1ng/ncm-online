// NCM Thrust -> NCM Carrier: the lift lever (L316 F0, owner ruling 2026-10-04: dev-only experiments on the flight ladder).
//
// The first lever that ADDS force. Every Carrier lever before it is downward only (a gear takes drive away, a governor
// caps speed); this one pushes the seated car up. NCM Thrust owns the request -- which key, how hard, how long -- and
// NCM Carrier owns the physics: at the bound body's gravity entry it writes `gravZ * (1 - twr)`. The gravity entry's Z
// is -m*g*dt, so a thrust-to-weight ratio is exact without knowing either the mass or the step (§AU4).
//
// Shared memory, named per PROCESS (`Local\NCM_Thrust_Levers_<pid>`), so two games on one PC never push each other's
// car (the KB-147 / KB-329 lesson). A stamp older than kStaleMs means "no thrust": Carrier then behaves exactly as
// before, and a burn in progress stops. This header is duplicated verbatim in ncm/carrier/src/vehicle/thrust_levers.hpp (and ncm/thrust/src/thrust_levers.hpp).
#pragma once

#include <cstdint>
#include <cstdio>

namespace ncm::thrust_levers {

constexpr uint32_t kMagic = 0x5248544Eu;   // "NTHR"
constexpr uint32_t kVersion = 1;
constexpr uint64_t kStaleMs = 200;
constexpr float kMaxTwr = 3.0f;            // both sides clamp: a bad publish can never fling the car
constexpr uint32_t kMaxBurnMs = 2000;

struct Block {
    uint32_t magic;
    uint32_t version;
    volatile uint64_t stampMs;     // GetTickCount64() of the last publish; 0 = never
    volatile float twr;            // thrust-to-weight ratio, 0..kMaxTwr
    volatile uint32_t burnMs;      // length of one burn, measured by Carrier in physics time
    volatile uint32_t burnSeq;     // +1 per press; a new value starts one burn
    volatile uint32_t holding;     // 1 = burn for as long as this stays fresh (hold mode, the S0 elevator)
    volatile uint32_t seq;
};

inline void name(wchar_t* out, size_t size, unsigned long pid)
{
    swprintf_s(out, size, L"Local\\NCM_Thrust_Levers_%lu", pid);
}

}  // namespace ncm::thrust_levers
