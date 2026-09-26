#include "log.hpp"

#include <chrono>
#include <cstdio>
#include <ctime>
#include <fstream>
#include <mutex>

namespace ncm::log {
namespace {
std::mutex g_mutex;
std::wstring g_path;
}  // namespace

void init(const std::wstring& dllDirectory)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    g_path = dllDirectory + L"\\ncm_carrier.log";
    // Truncate once per session so a log is about this run and not about every run ever.
    std::ofstream out(g_path, std::ios::trunc);
    out << "ncm_carrier " << NCM_CARRIER_VERSION << " log\n";
}

void write(const char* level, const std::string& message)
{
    try {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (g_path.empty()) return;
        std::ofstream out(g_path, std::ios::app);
        if (!out) return;
        const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
        char stamp[32];
        std::strftime(stamp, sizeof(stamp), "%H:%M:%S", std::localtime(&now));
        out << "[" << stamp << "][" << level << "] " << message << "\n";
    } catch (...) {
        // A logger that can take the process down is worse than no logger.
    }
}

}  // namespace ncm::log
