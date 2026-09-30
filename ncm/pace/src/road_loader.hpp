#pragma once

#include "road_graph.hpp"

#include <memory>

namespace ncm::pace {
// Called from the game's Running update. Copies the installed game's traffic resources;
// consumers never hold an engine resource pointer.
void pollRoadGraph();
std::shared_ptr<const RoadGraph> currentRoadGraph();
} // namespace ncm::pace
