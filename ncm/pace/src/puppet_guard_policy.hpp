#pragma once

#include <cstdint>

namespace ncm::pace::puppet_guard {
// Native Handle<T> layout, verified against the crash dump and RED4ext Handle.
// No reference-count operations: this borrowed handle is valid for the duration of the call.
struct BorrowedHandle { void* instance; void* refCount; };

template <typename Original, typename Blocked>
bool dispatch(const BorrowedHandle* handle, uintptr_t caller, uintptr_t expectedCaller,
              Original original, Blocked blocked)
{
    // Only the observed movement caller. Other callers retain the engine's behavior.
    if (caller == expectedCaller && (!handle || !handle->instance)) {
        blocked();
        return false;
    }
    return original(handle);
}
}
