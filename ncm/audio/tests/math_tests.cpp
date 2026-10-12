// NCM Audio's arithmetic: pan, distance gain, glide, clamps.
#include "mixer_math.hpp"

#include <cstdio>
#include <cmath>

using namespace ncm::audio::math;
static int failed = 0, passed = 0;
static void check(bool ok, const char* what) { if (ok) { ++passed; std::printf("  PASS %s\n", what); } else { ++failed; std::printf("  FAIL %s\n", what); } }

int main()
{
    Listener l; l.valid = true; l.pos = {0, 0, 0}; l.right = {1, 0, 0}; l.forward = {0, 1, 0};
    check(std::abs(pan(l, {10, 0, 0}) - 0.85) < 1e-9, "a voice to the right pans right (never hard)");
    check(std::abs(pan(l, {-10, 0, 0}) + 0.85) < 1e-9, "a voice to the left pans left");
    check(std::abs(pan(l, {0, 10, 0})) < 1e-9, "a voice ahead is centred");
    check(pan(l, {0.1, 0, 0}) == 0.0, "a voice on top of the listener is centred");
    check(distanceGain(3) == 1.0 && std::abs(distanceGain(12) - 0.5) < 1e-9, "full inside 6 m, half at 12 m");
    check(distanceGain(1e6) == 0.02, "never fully silent with distance");
    double g = 0; for (int i = 0; i < 60; ++i) g = glide(g, 1.0, 1.0 / 60, 0.08);
    check(g > 0.99, "a glide reaches its target within a second");
    check(glide(0.2, 1.0, 0.016, 0.08) < 0.4, "but not in one frame (no clicks)");
    check(clampPitch(10) == 4.0 && clampPitch(0) == 0.25 && clampGain(-1) == 0.0, "clamps");
    Listener none;
    check(pan(none, {10, 0, 0}) == 0.0 && positionalGain(none, {100, 0, 0}) == 1.0, "no listener yet: centred and full");
    std::printf("audio math: %d passed, %d failed\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
