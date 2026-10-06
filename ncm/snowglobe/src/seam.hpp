#pragma once

#include <string>

namespace ncm::snowglobe::seam {
void start(const std::wstring& directory);
void stop();
int consumeRequests();       // presses of the seam key since the last call
float offset(int axis);      // 0 = x, 1 = y, 2 = z (metres)
float minZ();                // refuse below this height: never teleport a car into the ground
int watchFrames();           // how long to measure after a move
}
