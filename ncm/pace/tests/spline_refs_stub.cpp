// The tests run without the game: no engine-read race-spline refs, so Pace's own FNV-1a 64 hash is used.
#include "spline_refs.hpp"
namespace ncm::pace {
void pollSplineRefs() {}
uint64_t engineSplineRef(const std::string&) { return 0; }
}
