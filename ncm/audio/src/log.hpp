#pragma once

#include <cstdio>
#include <string>

namespace ncm::audio::log {
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

#define AUDIO_INFO(...) ::ncm::audio::log::line("info", __VA_ARGS__)
#define AUDIO_WARN(...) ::ncm::audio::log::line("warn", __VA_ARGS__)
#define AUDIO_ERR(...)  ::ncm::audio::log::line("err ", __VA_ARGS__)
