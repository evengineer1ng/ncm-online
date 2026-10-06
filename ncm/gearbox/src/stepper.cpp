#include "stepper.hpp"

#include "log.hpp"

#include <RED4ext/RED4ext.hpp>

#include <windows.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <vector>

namespace ncm::gearbox::stepper {
namespace {

constexpr uint32_t kRecalculateHash = 593628708u;   // RigidBody::Recalculate (NCM Carrier's verified hook point)
constexpr uint64_t kLeaseMs = 150;

using RecalculateFn = uint64_t(__fastcall*)(void*);
RecalculateFn g_original = nullptr;
std::atomic<bool> g_attached{false};

std::atomic<uintptr_t> g_address{0};
std::atomic<int8_t> g_gear{0};
std::atomic<uint64_t> g_leaseUntil{0};
std::atomic<uint64_t> g_calls{0}, g_overrides{0};

uint64_t nowMs() { return GetTickCount64(); }

inline void apply()
{
    const uintptr_t a = g_address.load(std::memory_order_acquire);
    if (!a || nowMs() > g_leaseUntil.load(std::memory_order_relaxed)) return;
    auto* p = reinterpret_cast<volatile int8_t*>(a);
    const int8_t want = g_gear.load(std::memory_order_relaxed);
    if (*p != want) { *p = want; g_overrides.fetch_add(1, std::memory_order_relaxed); }
}

uint64_t __fastcall recalculateDetour(void* body)
{
    g_calls.fetch_add(1, std::memory_order_relaxed);
    apply();
    const uint64_t r = g_original(body);
    apply();
    return r;
}

std::wstring addressTablePath()
{
    wchar_t exe[MAX_PATH] = {};
    if (!GetModuleFileNameW(nullptr, exe, MAX_PATH)) return {};
    std::wstring full(exe);
    const auto slash = full.find_last_of(L'\\');
    return slash == std::wstring::npos ? std::wstring() : full.substr(0, slash) + L"\\cyberpunk2077_addresses.json";
}

/// `UniversalRelocBase::Resolve` terminates the process on a miss, so the hash is looked up in the table first.
bool tableCarries(uint32_t hash)
{
    std::ifstream in(addressTablePath(), std::ios::binary);
    if (!in) { GBX_ERR("step hold: the address table is not readable -- declining"); return false; }
    char needle[64];
    const int n = std::snprintf(needle, sizeof(needle), "\"hash\": \"%u\"", hash);
    if (n <= 0) return false;
    const size_t len = static_cast<size_t>(n);
    std::vector<char> buf((1u << 20) + len);
    size_t carried = 0;
    while (in) {
        in.read(buf.data() + carried, static_cast<std::streamsize>(1u << 20));
        const size_t got = static_cast<size_t>(in.gcount());
        if (!got) break;
        const size_t filled = carried + got;
        for (size_t i = 0; i + len <= filled; ++i) {
            if (buf[i] == needle[0] && std::memcmp(buf.data() + i, needle, len) == 0) return true;
        }
        carried = filled >= len - 1 ? len - 1 : filled;
        std::memmove(buf.data(), buf.data() + filled - carried, carried);
    }
    return false;
}

}  // namespace

bool attach(void* pluginHandle, const void* sdkOpaque)
{
    if (g_attached.load()) return true;
    const auto* sdk = static_cast<const RED4ext::v1::Sdk*>(sdkOpaque);
    if (!sdk || !sdk->hooking || !sdk->hooking->Attach) { GBX_ERR("step hold: no RED4ext hooking API -- declining"); return false; }
    if (!tableCarries(kRecalculateHash)) { GBX_ERR("step hold: the address table does not carry hash %u -- declining", kRecalculateHash); return false; }
    const uintptr_t target = RED4ext::UniversalRelocBase::Resolve(kRecalculateHash);
    if (!target) { GBX_ERR("step hold: hash %u resolved to null -- declining", kRecalculateHash); return false; }
    if (!sdk->hooking->Attach(static_cast<RED4ext::v1::PluginHandle>(pluginHandle), reinterpret_cast<void*>(target),
                              reinterpret_cast<void*>(&recalculateDetour), reinterpret_cast<void**>(&g_original))) {
        GBX_ERR("step hold: could not attach to RigidBody::Recalculate -- declining");
        return false;
    }
    g_attached = true;
    GBX_INFO("step hold: attached to RigidBody::Recalculate (hash %u); inert until armed", kRecalculateHash);
    return true;
}

void arm(uintptr_t address, int8_t gear)
{
    g_gear.store(gear, std::memory_order_relaxed);
    g_address.store(address, std::memory_order_release);
    g_leaseUntil.store(nowMs() + kLeaseMs, std::memory_order_relaxed);
}

void disarm()
{
    g_leaseUntil.store(0, std::memory_order_relaxed);
    g_address.store(0, std::memory_order_release);
}

uint64_t calls() { return g_calls.load(); }
uint64_t overrides() { return g_overrides.load(); }
bool attached() { return g_attached.load(); }

}  // namespace ncm::gearbox::stepper
