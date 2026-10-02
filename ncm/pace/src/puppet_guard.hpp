#pragma once

#include <RED4ext/RED4ext.hpp>

namespace ncm::pace::puppet_guard {
bool attach(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk);
void report();
void detach(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk);
}
