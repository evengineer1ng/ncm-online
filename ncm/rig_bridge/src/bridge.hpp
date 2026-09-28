#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>
#include <string>
#include <thread>

namespace ncm::rig {
class DirectInputRig;

class Bridge {
public:
    Bridge(uint16_t port, DirectInputRig& rig, std::wstring directory);
    ~Bridge();
    void start();
    void stop();
    bool listening() const { return listening_.load(); }
    uint16_t port() const { return port_; }

private:
    void run();
    void serveHttp(uintptr_t client);
    void serveWebSocket(uintptr_t client, const std::string& key);
    void dispatch(const std::string& payload);
    void sendSnapshot();

    std::chrono::steady_clock::time_point lastSnapshot_{};
    std::wstring directory_;
    uint16_t port_;
    DirectInputRig& rig_;
    std::atomic<bool> running_{false};
    std::atomic<bool> listening_{false};
    std::atomic<uintptr_t> listener_{0};
    std::atomic<uintptr_t> client_{0};
    std::thread thread_;
};
}
