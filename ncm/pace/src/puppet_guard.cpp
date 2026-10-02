#include "puppet_guard.hpp"
#include "puppet_guard_policy.hpp"
#include "log.hpp"

#include <windows.h>
#include <intrin.h>
#include <atomic>
#include <chrono>
#include <cstring>

namespace ncm::pace::puppet_guard {
namespace {
// Cyberpunk 2.31, executable SHA256 a7de82945c03e041fc7339fcf9066224d98db2f5d80fea50f7947bb350a60991.
// See docs/research/open77/evidence/2026-10-01-154607/*disassembly.txt.
constexpr uintptr_t predicateRva = 0x2543388;
constexpr uintptr_t callerReturnRva = 0x2698A5A;
constexpr unsigned char predicateBytes[] = {
    0x40,0x53,0x48,0x83,0xEC,0x30,0x48,0x8B,0x01,0x48,0x8B,0xD9,0x48,0x8B,0x90,0xC0,0,0,0
};
constexpr unsigned char callerBytes[] = {
    0x48,0x8B,0xD3,0x48,0x8D,0x4C,0x24,0x20,0xE8,0x6E,0xD4,0xC4,0xFD,0x48,0x8B,0xC8,
    0xE8,0x2E,0xA9,0xEA,0xFF,0x48,0x8D,0x4C,0x24,0x20,0x8A,0xD8,0xE8,0x72,0xC5,0xA6,
    0xFD,0x84,0xDB,0x74,0x04
};
using Predicate = bool (*)(const BorrowedHandle*);
Predicate original = nullptr;
void* target = nullptr;
uintptr_t expectedCaller = 0;
std::atomic<uint64_t> prevented{0};
uint64_t reported = 0;
std::chrono::steady_clock::time_point nextReport;

// No logging, allocations or engine calls on the movement worker thread.
__declspec(noinline) bool guarded(const BorrowedHandle* handle)
{
    const auto caller = reinterpret_cast<uintptr_t>(_ReturnAddress());
    return dispatch(handle, caller, expectedCaller, original, [] {
        prevented.fetch_add(1, std::memory_order_relaxed);
    });
}
}

bool attach(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk)
{
    if (target) return true;
    if (!sdk || !sdk->hooking || !sdk->hooking->Attach) {
        PACE_ERR("KB-238 guard inactive: hooking API unavailable");
        return false;
    }
    const auto base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    if (!base) return false;
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return false;
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64 ||
        nt->FileHeader.TimeDateStamp != 0x68AF45EA || nt->OptionalHeader.SizeOfImage != 0x4EFC000) {
        PACE_ERR("KB-238 guard inactive: executable is not the inspected 2.31 build");
        return false;
    }
    if (std::memcmp(reinterpret_cast<const void*>(base + predicateRva), predicateBytes, sizeof(predicateBytes)) ||
        std::memcmp(reinterpret_cast<const void*>(base + 0x2698A45), callerBytes, sizeof(callerBytes))) {
        PACE_ERR("KB-238 guard inactive: native instruction bytes differ (build or another hook)");
        return false;
    }
    expectedCaller = base + callerReturnRva;
    auto* candidate = reinterpret_cast<void*>(base + predicateRva);
    if (!sdk->hooking->Attach(handle, candidate, reinterpret_cast<void*>(&guarded), reinterpret_cast<void**>(&original))) {
        PACE_ERR("KB-238 guard inactive: hook attach refused");
        return false;
    }
    target = candidate;
    PACE_INFO("KB-238 guard ACTIVE: 2.31 movement caller +0x2698A5A, empty puppet handle returns false");
    return true;
}

void report()
{
    const auto now = std::chrono::steady_clock::now();
    if (now < nextReport) return;
    nextReport = now + std::chrono::seconds(1);
    const auto count = prevented.load(std::memory_order_relaxed);
    if (count != reported) {
        PACE_WARN("KB-238 guard prevented %llu null puppet read(s), +%llu since last report",
                  static_cast<unsigned long long>(count), static_cast<unsigned long long>(count - reported));
        reported = count;
    }
}

void detach(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk)
{
    report();
    if (target && sdk && sdk->hooking && sdk->hooking->Detach) {
        if (sdk->hooking->Detach(handle, target)) target = nullptr;
        else PACE_ERR("KB-238 guard detach refused");
    }
}
}
