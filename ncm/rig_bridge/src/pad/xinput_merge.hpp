#pragma once
// The XInput merge rule (JoyMoco's): buttons OR; each stick axis and trigger takes whichever of physical and
// virtual is deflected further. Its own header, free of RED4ext, so the tests hold the one real definition.
#include "pad_model.hpp"
#include <cstdint>
namespace ncm::rig::pad::xinput {
struct Gamepad { uint16_t buttons; uint8_t lt, rt; int16_t lx, ly, rx, ry; };
inline Gamepad merge(const Gamepad& p, const VirtualPad& v)
{
    auto stick = [](int16_t physical, float value) -> int16_t {
        const float c = value < -1.0f ? -1.0f : value > 1.0f ? 1.0f : value;
        const int virt = static_cast<int>(c * (c < 0 ? 32768.0f : 32767.0f));
        const int a = physical < 0 ? -physical : physical, b = virt < 0 ? -virt : virt;
        return static_cast<int16_t>(b > a ? virt : physical);
    };
    auto trigger = [](uint8_t physical, float value) -> uint8_t {
        const int virt = static_cast<int>((value < 0 ? 0 : value > 1 ? 1 : value) * 255.0f + 0.5f);
        return static_cast<uint8_t>(virt > physical ? virt : physical);
    };
    return {static_cast<uint16_t>(p.buttons | v.buttons), trigger(p.lt, v.lt), trigger(p.rt, v.rt),
            stick(p.lx, v.lx), stick(p.ly, v.ly), stick(p.rx, v.rx), stick(p.ry, v.ry)};
}
}
