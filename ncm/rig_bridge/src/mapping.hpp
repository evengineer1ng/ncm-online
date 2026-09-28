#pragma once

#include "config.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace ncm::rig {

inline float mapAxis(uint32_t raw, const AxisBinding& binding, bool bipolar, float scale = 1.0f)
{
    const float normalized = static_cast<float>(std::min(raw, 65535u)) / 65535.0f;
    const float width = std::max(0.001f, binding.maximum - binding.minimum);
    float value = std::clamp((normalized - binding.minimum) / width, 0.0f, 1.0f);
    if (binding.invert) value = 1.0f - value;
    if (bipolar) {
        value = value * 2.0f - 1.0f;
        // Scale FIRST, then the deadzone -- a deadzone applied to the unscaled value would be multiplied
        // along with everything else and swallow a large part of the usable travel.
        value = std::clamp(value * scale, -1.0f, 1.0f);
        if (std::fabs(value) < binding.deadzone) return 0.0f;
        const float sign = value < 0.0f ? -1.0f : 1.0f;
        return sign * ((std::fabs(value) - binding.deadzone) / (1.0f - binding.deadzone));
    }
    if (value < binding.deadzone) return 0.0f;
    return (value - binding.deadzone) / (1.0f - binding.deadzone);
}
}

