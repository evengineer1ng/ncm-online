#include "net_guard.hpp"

#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <tlhelp32.h>

#include <utility>
#include <vector>

namespace ncm::rig {
bool sameProcessTree(uint32_t peer, uint32_t self)
{
    if (peer == 0 || peer == self) return true;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return true;
    std::vector<std::pair<uint32_t, uint32_t>> parents;
    PROCESSENTRY32W item{}; item.dwSize = sizeof(item);
    if (Process32FirstW(snapshot, &item)) do {
        parents.emplace_back(item.th32ProcessID, item.th32ParentProcessID);
    } while (Process32NextW(snapshot, &item));
    CloseHandle(snapshot);
    uint32_t current = peer;
    for (int depth = 0; depth < 8; ++depth) {
        uint32_t parent = 0;
        for (const auto& [pid, ppid] : parents) if (pid == current) { parent = ppid; break; }
        if (parent == 0) return false;
        if (parent == self) return true;
        current = parent;
    }
    return false;
}

uint32_t peerPid(SOCKET client)
{
    sockaddr_in peer{}, local{}; int peerSize = sizeof(peer), localSize = sizeof(local);
    if (getpeername(client, reinterpret_cast<sockaddr*>(&peer), &peerSize) == SOCKET_ERROR ||
        getsockname(client, reinterpret_cast<sockaddr*>(&local), &localSize) == SOCKET_ERROR) return 0;
    DWORD size = 0;
    if (GetExtendedTcpTable(nullptr, &size, FALSE, AF_INET, TCP_TABLE_OWNER_PID_CONNECTIONS, 0) != ERROR_INSUFFICIENT_BUFFER) return 0;
    std::vector<uint8_t> bytes(size);
    if (GetExtendedTcpTable(bytes.data(), &size, FALSE, AF_INET, TCP_TABLE_OWNER_PID_CONNECTIONS, 0) != NO_ERROR) return 0;
    const auto* table = reinterpret_cast<const MIB_TCPTABLE_OWNER_PID*>(bytes.data());
    for (DWORD i = 0; i < table->dwNumEntries; ++i) {
        const auto& row = table->table[i];
        if (row.dwLocalPort == static_cast<DWORD>(peer.sin_port) && row.dwRemotePort == static_cast<DWORD>(local.sin_port) &&
            row.dwState == MIB_TCP_STATE_ESTAB) return row.dwOwningPid;
    }
    return 0;
}

}
