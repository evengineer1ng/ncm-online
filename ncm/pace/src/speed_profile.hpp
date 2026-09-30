#pragma once

#include "state.hpp"

#include <vector>

namespace ncm::pace {

// A road-centre polyline sampled densely enough to describe bends, not race checkpoints.
// The caller must establish that the points follow the actual drivable road in race order.
struct SpeedProfileConfig {
    double straightMps = 44.0;
    double lateralMps2 = 5.5;
    double brakingMps2 = 6.0;
    double minimumMps = 8.0;
    double maxSpacingM = 25.0;
};

struct SpeedProfile {
    std::vector<double> limitMps; // one target at each input point
    bool valid = false;
};

SpeedProfile buildSpeedProfile(const std::vector<Point>& road, SpeedProfileConfig config = {});

} // namespace ncm::pace
