#pragma once

#include <functional>
#include <string>

namespace ncm::vehicle::av {

/// At startup (Running::OnEnter, after the physics probe): check the ForceEnablePhysics hash against the address table
/// and attach the two detours that drop the AV's own impulses while NCM flies it (DAV's EnableOriginalPhysics(false)).
void prepare(void* pluginHandle, const void* sdk) noexcept;

/// At teardown (Running::OnExit): detach those detours.
void release(void* pluginHandle, const void* sdk) noexcept;

/// Once per game frame (Running::OnUpdate, the game thread): while an `av` wrench lease is fresh, keep the bound AV's
/// physics on, its gravity off, and add NCM's acceleration to its force / torque accumulators. Never throws.
void tick() noexcept;

/// Where the one-second AV report goes besides the log (the bridge: up to NCM, and from there to the server log).
void setReporter(std::function<void(const std::string&)> fn);

}  // namespace ncm::vehicle::av
