#pragma once

#include <cstdio>
#include <string>

namespace ncm::gearbox::log {
void init(const std::wstring& directory);
void write(const char* level, const std::string& value);

template <typename... Args>
void line(const char* level, const char* format, Args... args)
{
    char buffer[2048]{};
    const int n = std::snprintf(buffer, sizeof(buffer), format, args...);
    write(level, n > 0 ? std::string(buffer, static_cast<size_t>(n)) : std::string(format));
}
}

#define GBX_INFO(...) ::ncm::gearbox::log::line("info", __VA_ARGS__)
#define GBX_WARN(...) ::ncm::gearbox::log::line("warn", __VA_ARGS__)
#define GBX_ERR(...)  ::ncm::gearbox::log::line("err ", __VA_ARGS__)
