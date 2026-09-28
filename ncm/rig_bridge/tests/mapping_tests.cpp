#include "mapping.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>

namespace {
void expectNear(const char* name, float actual, float expected, float epsilon = 0.001f)
{
    if (std::fabs(actual - expected) <= epsilon) return;
    std::cerr << name << ": expected " << expected << ", got " << actual << '\n';
    std::exit(1);
}
}

int main()
{
    ncm::rig::AxisBinding steer{"", "", "", "x", false, 0.0f, 1.0f, 0.0f};
    expectNear("steer left", ncm::rig::mapAxis(0, steer, true), -1.0f);
    expectNear("steer centre", ncm::rig::mapAxis(32768, steer, true), 0.0f);
    expectNear("steer right", ncm::rig::mapAxis(65535, steer, true), 1.0f);

    ncm::rig::AxisBinding pedal{"", "", "", "y", true, 0.0f, 1.0f, 0.0f};
    expectNear("inverted pedal rest", ncm::rig::mapAxis(65535, pedal, false), 0.0f);
    expectNear("inverted pedal full", ncm::rig::mapAxis(0, pedal, false), 1.0f);

    ncm::rig::AxisBinding calibrated{"", "", "", "z", false, 0.25f, 0.75f, 0.1f};
    expectNear("calibrated minimum", ncm::rig::mapAxis(16384, calibrated, false), 0.0f);
    expectNear("calibrated maximum", ncm::rig::mapAxis(49151, calibrated, false), 1.0f);
    expectNear("deadzone", ncm::rig::mapAxis(17000, calibrated, false), 0.0f);

    // ---- steering range scaling -----------------------------------------------------------------
    // Without this the wheel's WHOLE travel mapped to full lock, so a 900-degree wheel needed 450 degrees
    // to reach it and the car barely left centre however hard it was turned. 900/2 / 45 = 10x.
    ncm::rig::AxisBinding range{"", "", "", "x", false, 0.0f, 1.0f, 0.0f};
    expectNear("unscaled quarter turn is tiny", ncm::rig::mapAxis(41287, range, true, 1.0f), 0.26f, 0.01f);
    expectNear("10x scale reaches full lock well before the stop",
               ncm::rig::mapAxis(41287, range, true, 10.0f), 1.0f);
    expectNear("scaling keeps centre at centre", ncm::rig::mapAxis(32768, range, true, 10.0f), 0.0f);
    expectNear("scaling is symmetric", ncm::rig::mapAxis(24249, range, true, 10.0f), -1.0f);
    expectNear("clamped at the stop", ncm::rig::mapAxis(65535, range, true, 50.0f), 1.0f);

    std::cout << "NCM Rig Bridge mapping tests passed\n";
    return 0;
}
