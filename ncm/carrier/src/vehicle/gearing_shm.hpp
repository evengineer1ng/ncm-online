// NCM Carrier -> NCM Gearbox: the Machine's stacked-gearbox paths (owner, 2026-10-08: "relay through carrier").
//
// The server knows what driveline boxes a Machine carries; the client composes them into paths (core
// `engineering.gearing`) and sends them over the Carrier's Machine channel (`ncm:machine.gearing`). The Carrier only
// RELAYS: it copies the text and the driver's select request into this block. NCM Gearbox reads it every frame it drives a
// manual and owns everything after that -- the ladder, the `when` rules, the toggle back to the car's own box.
//
// Shared memory, named per PROCESS (`Local\NCM_Gearbox_Gearing_<pid>`), so two games on one PC never read each other's
// gearboxes (the KB-147 / KB-329 lesson). A stamp older than kStaleMs means "no stacked boxes": the Gearbox then drives
// the car's own box exactly as before. The client re-sends once a second while bound.
// This header is duplicated verbatim in ncm/carrier/src/vehicle/gearing_shm.hpp and ncm/gearbox/src/gearing_shm.hpp.
#pragma once

#include <cstdint>
#include <cstdio>

namespace ncm::gearing_shm {

constexpr uint32_t kMagic = 0x5247474Eu;   // "NGGR"
constexpr uint32_t kVersion = 1;
constexpr uint64_t kStaleMs = 3000;
constexpr uint32_t kTextBytes = 4000;

struct Block {
    uint32_t magic;
    uint32_t version;
    volatile uint64_t stampMs;      // GetTickCount64() of the last relay; 0 = never
    volatile uint32_t textSeq;      // +1 whenever `text` changes
    volatile uint32_t selectSeq;    // the driver's engage presses (the client's count)
    volatile int32_t selectPath;    // the path the last press asked for (0 = the car's own box)
    volatile uint32_t textLen;
    char text[kTextBytes];          // engineering.gearing wire text; "" = the car's own box alone
    volatile uint32_t seq;          // +1 per write (a reader that sees it change mid-copy copies again)
};

inline void name(wchar_t* out, size_t size, unsigned long pid)
{
    swprintf_s(out, size, L"Local\\NCM_Gearbox_Gearing_%lu", pid);
}

}  // namespace ncm::gearing_shm
