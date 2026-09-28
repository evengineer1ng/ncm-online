#include "log.hpp"

#include <windows.h>

#include <chrono>
#include <ctime>
#include <fstream>
#include <mutex>

namespace ncm::rig::log {
namespace {
std::mutex mutex;
std::wstring path;
}

void init(const std::wstring& directory)
{
    std::lock_guard lock(mutex);
    path = directory + L"\\ncm_rig_bridge-" + std::to_wstring(GetCurrentProcessId()) + L".log";
    std::ofstream out(path, std::ios::trunc);
    out << "ncm_rig_bridge " << NCM_RIG_BRIDGE_VERSION << " pid=" << GetCurrentProcessId() << "\n";
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

