#include "log.hpp"

#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <ctime>
#include <fstream>
#include <mutex>
#include <utility>
#include <vector>

namespace ncm::log {
namespace {
std::mutex g_mutex;
std::wstring g_path;

/// Keep the newest `keep` carrier logs and delete the rest, so one log per process does not turn into an
/// ever-growing directory. Best effort throughout: a log that will not delete is not worth failing a
/// startup over.
void pruneOldLogs(const std::wstring& directory, size_t keep)
{
    std::vector<std::pair<uint64_t, std::wstring>> found;   // last-write time, full path
    WIN32_FIND_DATAW data{};
    const std::wstring pattern = directory + L"\\ncm_carrier-*.log";
    const HANDLE handle = ::FindFirstFileW(pattern.c_str(), &data);
    if (handle == INVALID_HANDLE_VALUE) return;
    do {
        if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        const uint64_t when = (static_cast<uint64_t>(data.ftLastWriteTime.dwHighDateTime) << 32)
                            | data.ftLastWriteTime.dwLowDateTime;
        found.emplace_back(when, directory + L"\\" + data.cFileName);
    } while (::FindNextFileW(handle, &data));
    ::FindClose(handle);

    if (found.size() <= keep) return;
    std::sort(found.begin(), found.end(),
              [](const auto& a, const auto& b) { return a.first > b.first; });   // newest first
    for (size_t i = keep; i < found.size(); ++i) ::DeleteFileW(found[i].second.c_str());
}
}  // namespace

void init(const std::wstring& dllDirectory)
{
    std::lock_guard<std::mutex> lock(g_mutex);

    // ---------------------------------------------------------------------------------------------
    // ONE LOG PER PROCESS, and the previous sessions kept.
    // ---------------------------------------------------------------------------------------------
    //
    // This wrote a single `ncm_carrier.log` and truncated it on every start. Two failures came out of
    // that, and both cost real diagnosis time on 2026-09-26:
    //
    //   * **Two game instances shared one file.** Whichever carrier started second wiped the first's
    //     history, leaving one log that described one process with nothing saying which. A refusal line
    //     naming another pid was then read as a second client when it was this client's own WebHost
    //     (`KB-149`).
    //   * **A finished session could not be examined.** Relaunching the game to retest destroyed the
    //     evidence for the run being investigated -- precisely when it was wanted. A question about what
    //     a previous session did became unanswerable, and was answered by inference instead, wrongly.
    //
    // So the file is named for the process and old ones are pruned. Anyone asked for "the carrier log"
    // now finds several; that is a smaller problem than the one it replaces, and the newest is the one
    // they want.
    const auto pid = static_cast<unsigned long>(::GetCurrentProcessId());
    g_path = dllDirectory + L"\\ncm_carrier-" + std::to_wstring(pid) + L".log";

    pruneOldLogs(dllDirectory, 6);

    std::ofstream out(g_path, std::ios::trunc);
    out << "ncm_carrier " << NCM_CARRIER_VERSION << " log (pid " << pid << ")\n";
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
