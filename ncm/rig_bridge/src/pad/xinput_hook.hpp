#pragma once

// NCM Rig Bridge -- the virtual gamepad's way into the game: a detour on XInput itself.
//
// JoyMoco publishes through ViGEmBus, a kernel driver that is retired upstream and that every tester would
// have to install. Inside the game we do not need it. Cyberpunk2077.exe statically imports XINPUT9_1_0.dll
// and names xinput1_4.dll / xinput1_3.dll (measured 2026-09-28 from the binary's import table and strings);
// it imports no Windows.Gaming.Input. So `XInputGetState` IS the game's pad, and merging the virtual pad into
// one user slot there reaches exactly this game and nothing else on the PC.
//
// Merge rule, JoyMoco's: buttons OR; each stick axis and trigger takes whichever of physical and virtual is
// deflected further, so a resting stick never erases a pressed rim button and vice versa. With no physical
// pad in the slot, the slot reports connected once the virtual pad has produced output this session.
//
// `XInputSetState` is detoured too: the game's own rumble on this slot is handed to the Joy-Cons.

#include "pad_model.hpp"
#include "xinput_merge.hpp"

#include <RED4ext/Api/v1/PluginHandle.hpp>
#include <RED4ext/Api/v1/Sdk.hpp>

#include <nlohmann/json.hpp>

#include <functional>

namespace ncm::rig::pad::xinput {

bool install(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk);
void remove(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk);

void setUserIndex(unsigned index);
void publish(const VirtualPad& pad);
/// Game rumble on the merged slot, 0..1 per motor (left = large, right = small).
void setRumbleSink(std::function<void(float large, float small)> sink);
/// Rumble the PHYSICAL pad in the slot (a preset routed to `controller`), bypassing the sink.
void rumblePhysical(float large, float small);

nlohmann::json status();

}  // namespace ncm::rig::pad::xinput
