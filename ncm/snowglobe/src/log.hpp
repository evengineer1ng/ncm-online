#pragma once

#include <cstdio>
#include <string>

namespace ncm::snowglobe::log {
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

#define SNG_INFO(...) ::ncm::snowglobe::log::line("info", __VA_ARGS__)
#define SNG_WARN(...) ::ncm::snowglobe::log::line("warn", __VA_ARGS__)
#define SNG_ERR(...)  ::ncm::snowglobe::log::line("err ", __VA_ARGS__)
