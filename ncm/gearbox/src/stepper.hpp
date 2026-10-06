// NCM Gearbox -- phase 3c (L306 S2): hold the gear inside every physics step.
//
// 0.1.2's trial proved the gear is one byte the car reaches through `0x2D0 -> +0x3A4` (and `0xBA8 -> +0x1C4`, the same
// address) and that writing it overrides the automatic: held in 3rd the car ran past its shift point to the limiter.
// But a once-a-frame write from script flickers -- the automatic shifts between writes (rpm dips, the HUD showing the
// next gear for a tick). So this writes it from inside the physics step: a detour on `RigidBody::Recalculate` (address
// hash 593628708, checked against the game's own address table first, as NCM Carrier does, because a miss terminates
// the process), writing before and after the original call while a LEASE is fresh.
//
// The lease is the safety: the script tick re-arms it every frame with the address it just resolved; stepping out
// disarms it at once; a lease older than 150 ms is ignored, so a despawned car is never written to.
#pragma once

#include <cstdint>
#include <string>

namespace ncm::gearbox::stepper {

/// Attach the detour (once, at Running). Returns false and stays inert if anything is not as expected.
bool attach(void* pluginHandle, const void* sdk);

/// Arm for one lease: write `gear` (u8) at `address` in every physics step for the next 150 ms.
void arm(uintptr_t address, int8_t gear);
void disarm();

/// Steps seen, and how many times the automatic had changed the gear since our last write (the fight, counted).
uint64_t calls();
uint64_t overrides();
bool attached();

}  // namespace ncm::gearbox::stepper
