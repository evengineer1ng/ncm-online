#pragma once

#include "state.hpp"

#include <cstdint>
#include <vector>

namespace ncm::pace {

struct RoadLane {
    std::vector<Point> line;
    std::vector<uint32_t> out;
};

class RoadGraph {
public:
    std::vector<RoadLane> lanes;
    // A continuous directed centreline through the traffic graph. Empty means no safe route.
    std::vector<Point> route(const Point& from, const Point& to) const;
};

} // namespace ncm::pace
