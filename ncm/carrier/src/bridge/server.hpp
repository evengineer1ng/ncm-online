// NCM Carrier -- the bridge.
//
// **THE DIRECTION IS INVERTED, AND THAT IS THE WHOLE TRICK** (`L129`, MASTER_TEST section AJ, LIVE PASS).
//
// A bundled OPEN//77 WebUI page has no outbound network at all: `ws`, `wss`, `http` and `https` are refused
// in about 0 ms from the private `cym-ui` origin, with no socket ever opened. So the listener serves a page,
// NCM creates a hidden surface whose entry is that URL, and the page talks to its own origin -- which is
// allowed. This plugin takes over the role the Python companion used to play, on the same port, serving the
// same page, speaking the same events. The client resource barely changes.
//
// Loopback only. No TLS, because loopback is already a secure context, so there is no certificate for a
// player to install and nothing to expire.
#pragma once

#include "effects/tweak.hpp"

#include <atomic>
#include <functional>
#include <string>
#include <thread>
#include <vector>

namespace ncm::bridge {

/// One projection, as `machine.projection` composed it. The plugin applies this and interprets nothing:
/// which part moved which flat, and why, was decided server-side in Lua (`L135`).
struct Projection {
    int version = 1;
    std::string record;                          // the drive-model record to write
    std::vector<effects::FlatChange> flats;
    bool restore = false;                        // "put back what you captured" -- not the same as "apply nothing"
};

/// One telemetry frame, the shape `driver.feedback.frame` produces. **A channel that could not be read is
/// ABSENT, not zero** (`IDEA-361`) -- so every field is optional and `has*` means what it says.
struct Frame {
    double at = 0.0;
    bool hasEngine = false;    double engine = 0.0;      // rev ratio 0..1
    bool hasSpeed = false;     double speed = 0.0;       // m/s
    bool hasSteering = false;  double steering = 0.0;    // -1..1
    bool hasSlipLong = false;  double slipLong = 0.0;
    bool hasSlipLat = false;   double slipLat = 0.0;
    bool hasSlipTotal = false; double slipTotal = 0.0;
    bool hasSuspLong = false;  double suspLong = 0.0;
    bool hasSuspLat = false;   double suspLat = 0.0;
    bool idle = false;                                    // seated but nothing measurable
};

class Server {
public:
    explicit Server(uint16_t port);
    ~Server();

    Server(const Server&) = delete;
    Server& operator=(const Server&) = delete;

    void start();
    void stop();
    bool listening() const { return listening_.load(); }
    bool connected() const { return connected_.load(); }

    void onProjection(std::function<void(const Projection&)> fn) { onProjection_ = std::move(fn); }
    void onFrame(std::function<void(const Frame&)> fn) { onFrame_ = std::move(fn); }
    void onDisconnect(std::function<void()> fn) { onDisconnect_ = std::move(fn); }

    /// Fired once per accepted WebSocket, AFTER the handshake and after `connected()` is true, so a
    /// handler may send immediately. This is the missing half of `KB-134`: the carrier never introduced
    /// itself because nothing was listening for the moment a peer appeared.
    void onConnect(std::function<void()> fn) { onConnect_ = std::move(fn); }

    /// Send one JSON text frame upward. Was `sendDevice`, which had no caller and named only one of the
    /// two payloads the page already routes (`device` and `health`).
    void sendJson(const std::string& json);

private:
    void run();
    void serveHttp(uintptr_t client, const std::string& request);
    void serveWebSocket(uintptr_t client, const std::string& key);
    void dispatch(const std::string& payload);

    uint16_t port_;
    std::thread thread_;
    std::atomic<bool> running_{false};
    std::atomic<bool> listening_{false};
    std::atomic<bool> connected_{false};
    std::atomic<uintptr_t> socket_{0};
    std::atomic<uintptr_t> client_{0};

    std::function<void(const Projection&)> onProjection_;
    std::function<void(const Frame&)> onFrame_;
    std::function<void()> onDisconnect_;
    std::function<void()> onConnect_;
};

/// The page served to the WebUI surface. Identical in behaviour to the companion's `BRIDGE_HTML`: it opens a
/// socket back to its own origin and relays NCM's events across it in both directions.
extern const char* kBridgeHtml;

}  // namespace ncm::bridge
