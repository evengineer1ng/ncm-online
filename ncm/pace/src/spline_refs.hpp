#pragma once
#include <cstdint>
#include <string>

namespace ncm::pace {
// Load Pace's own race-spline sectors and learn each spline's NodeRef as the engine hashed it (0.7.2, L246).
void pollSplineRefs();
// The engine's NodeRef hash for a race spline path, or 0 if it has not been read (yet, or ever).
uint64_t engineSplineRef(const std::string& path);
}
