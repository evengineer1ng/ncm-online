// NCM Carrier -- the diagnostic channel that survives a failed load.
//
// A RED4ext plugin that fails badly can stop the game launching. When that happens there is no panel, no
// bridge and no console -- only this file. It is written beside the DLL, opened lazily, and it never throws.
#pragma once

#include <string>

namespace ncm::log {

void init(const std::wstring& dllDirectory);
void write(const char* level, const std::string& message);

template <typename... Args>
void line(const char* level, const char* fmt, Args... args)
{
    char buffer[1024];
    const int n = std::snprintf(buffer, sizeof(buffer), fmt, args...);
    write(level, n > 0 ? std::string(buffer, static_cast<size_t>(n)) : std::string(fmt));
}

#define NCM_INFO(...) ::ncm::log::line("info", __VA_ARGS__)
#define NCM_WARN(...) ::ncm::log::line("warn", __VA_ARGS__)
#define NCM_ERR(...)  ::ncm::log::line("err ", __VA_ARGS__)

}  // namespace ncm::log
