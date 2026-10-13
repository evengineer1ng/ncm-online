#pragma once

namespace ncm::vehicle::av {

/// At startup (Running::OnEnter, after the physics probe): check the ForceEnablePhysics hash against the address table.
void prepare() noexcept;

/// Once per game frame (Running::OnUpdate, the game thread): if the bound Machine is an AV whose physics is off and an
/// `av` wrench lease is fresh, switch its physics on (vehicleBaseObject::ForceEnablePhysics). Never throws.
void tick() noexcept;

}  // namespace ncm::vehicle::av
