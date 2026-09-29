#pragma once

// The loopback guard shared by every Rig Bridge listener: only a process in THIS game's process tree (the
// game itself or its CEF children) may connect. Moved out of bridge.cpp so the gamepad API enforces the
// identical rule rather than a copy of it.

#include <winsock2.h>

#include <cstdint>

namespace ncm::rig {
bool sameProcessTree(uint32_t peer, uint32_t self);
uint32_t peerPid(SOCKET client);
}
