#pragma once

#include <atomic>
#include <cstdint>
#include <thread>

namespace ncm::audio {

// Loopback transport between the `ncm_audio` resource and this plugin (the L129 pattern: the plugin serves a
// page, the resource creates a hidden WebUI surface whose entry is that page, and the page talks to its own
// origin). One peer at a time, and only a peer inside this game's process tree.
class Bridge {
public:
    static constexpr uint16_t kPortBase = 38800;   // Sky 38760+; NCM Audio its own range
    static constexpr uint16_t kPortSpan = 4;

    ~Bridge();
    void start();
    void stop();
    uint16_t port() const { return port_.load(); }

private:
    void run();
    void serve(uintptr_t client);

    std::atomic<uint16_t> port_{0};
    std::atomic<bool> running_{false};
    std::atomic<uintptr_t> listener_{0};
    std::atomic<uintptr_t> client_{0};
    std::thread thread_;
};
}
