#pragma once
// NCM Audio's arithmetic, header-only so the tests can hold it without miniaudio: where a voice sits relative to the
// listener (stereo pan + distance gain), and how a voice's gain and pitch glide toward what Lua asked for.

#include <algorithm>
#include <cmath>

namespace ncm::audio::math {

struct Vec3 { double x = 0, y = 0, z = 0; };
inline Vec3 sub(Vec3 a, Vec3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline double dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline double len(Vec3 a) { return std::sqrt(dot(a, a)); }

struct Listener {
    Vec3 pos;
    Vec3 right{1, 0, 0};
    Vec3 forward{0, 1, 0};
    bool valid = false;
};

// Inverse-distance rolloff (the game's own feel: full inside refM, half at 2 x refM, never below floor).
inline double distanceGain(double distM, double refM = 6.0, double floor = 0.02)
{
    if (!(distM > refM)) return 1.0;
    return std::max(floor, refM / distM);
}

// -1 (left) .. +1 (right); a voice right on top of the listener is centred.
inline double pan(const Listener& l, Vec3 at)
{
    if (!l.valid) return 0.0;
    const Vec3 rel = sub(at, l.pos);
    const double d = len(rel);
    if (d < 0.5) return 0.0;
    return std::clamp(dot(rel, l.right) / d, -1.0, 1.0) * 0.85;   // never hard-panned: a car is not a pair of headphones
}

inline double positionalGain(const Listener& l, Vec3 at)
{
    return l.valid ? distanceGain(len(sub(at, l.pos))) : 1.0;
}

// First-order glide toward a target: a throttle step becomes a swell, not a click. tau in seconds.
inline double glide(double current, double target, double dtS, double tauS)
{
    if (tauS <= 0) return target;
    const double k = 1.0 - std::exp(-std::max(0.0, dtS) / tauS);
    return current + (target - current) * k;
}

inline double clampPitch(double p) { return std::clamp(p, 0.25, 4.0); }
inline double clampGain(double g) { return std::clamp(g, 0.0, 2.0); }
}
