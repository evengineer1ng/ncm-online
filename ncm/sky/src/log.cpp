#include "log.hpp"

#include <windows.h>

#include <chrono>
#include <ctime>
#include <fstream>
#include <mutex>

namespace ncm::sky::log {
namespace {
std::mutex mutex;
std::wstring path;
}

// One file per process: two game instances on one PC load this DLL from the same folder.
void init(const std::wstring& directory)
{
    std::lock_guard lock(mutex);
    path = directory + L"\\ncm_sky-" + std::to_wstring(GetCurrentProcessId()) + L".log";
    std::ofstream out(path, std::ios::trunc);
    out << "ncm_sky " << NCM_SKY_VERSION << " pid=" << GetCurrentProcessId() << "\n";
}

void write(const char* level, const std::string& value)
{
    try {
        std::lock_guard lock(mutex);
        if (path.empty()) return;
        std::ofstream out(path, std::ios::app);
        const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
        char stamp[32]{};
        std::tm local{};
        localtime_s(&local, &now);
        std::strftime(stamp, sizeof(stamp), "%H:%M:%S", &local);
        out << '[' << stamp << "][" << level << "] " << value << '\n';
    } catch (...) {}
}
}
