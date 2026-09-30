#include "speed_profile.hpp"

#include <algorithm>
#include <cmath>

namespace ncm::pace {
SpeedProfile buildSpeedProfile(const std::vector<Point>& road, SpeedProfileConfig cfg)
{
    SpeedProfile result;
    if (road.size() < 3 || !std::isfinite(cfg.straightMps) || cfg.straightMps <= 0 ||
        !std::isfinite(cfg.lateralMps2) || cfg.lateralMps2 <= 0 ||
        !std::isfinite(cfg.brakingMps2) || cfg.brakingMps2 <= 0) return result;

    std::vector<double> segment;
    segment.reserve(road.size() - 1);
    for (size_t i = 1; i < road.size(); ++i) {
        const auto& a = road[i - 1];
        const auto& b = road[i];
        if (!std::isfinite(a.x) || !std::isfinite(a.y) || !std::isfinite(b.x) || !std::isfinite(b.y))
            return result;
        const double d = std::hypot(b.x - a.x, b.y - a.y);
        if (d < 0.5 || d > cfg.maxSpacingM) return result;
        segment.push_back(d);
    }

    result.limitMps.assign(road.size(), cfg.straightMps);
    for (size_t i = 1; i + 1 < road.size(); ++i) {
        const double ax = (road[i].x - road[i - 1].x) / segment[i - 1];
        const double ay = (road[i].y - road[i - 1].y) / segment[i - 1];
        const double bx = (road[i + 1].x - road[i].x) / segment[i];
        const double by = (road[i + 1].y - road[i].y) / segment[i];
        const double angle = std::acos(std::clamp(ax * bx + ay * by, -1.0, 1.0));
        // Heading change per metre of road. A bend becomes a lateral acceleration limit.
        const double curvature = angle / (0.5 * (segment[i - 1] + segment[i]));
        if (curvature > 1e-5)
            result.limitMps[i] = std::clamp(std::sqrt(cfg.lateralMps2 / curvature),
                                            cfg.minimumMps, cfg.straightMps);
    }
    // Propagate every corner limit upstream using v^2 = v_corner^2 + 2 a_brake distance.
    for (size_t i = road.size() - 1; i > 0; --i) {
        const double approach = std::sqrt(result.limitMps[i] * result.limitMps[i] +
                                          2.0 * cfg.brakingMps2 * segment[i - 1]);
        result.limitMps[i - 1] = std::min(result.limitMps[i - 1], approach);
    }
    result.valid = true;
    return result;
}
} // namespace ncm::pace
