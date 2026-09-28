#pragma once

#include <RED4ext/Api/v1/PluginHandle.hpp>
#include <RED4ext/Api/v1/Sdk.hpp>

#include <cstdint>

namespace ncm::rig::vehicle {
bool install(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk, bool enabled);
void remove(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk);
bool installed();
uint64_t injections();
void setPlayerVehicle(void* value);
}

