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
    std::string record;                          // the vehicle record to write against
    std::vector<effects::FlatChange> flats;      // drive-model flats
    std::vector<effects::GearChange> gears;      // gear-chain flats, via `.vehEngineData` -> `.gears`
    bool restore = false;                        // "put back what you captured" -- not the same as "apply nothing"
};

/// One handling setup -- the INSTANCE channel, which is the half of Parts that is per-player.
///
/// **This is not a Projection and the difference is the whole point.** A `Projection` writes TweakDB flats
/// on a RECORD: shared by every instance of that model on this client, and spawn-cached, so it reaches a car
/// when the car spawns. A `Handling` setup scales the force the solver is about to apply to ONE BODY -- the
/// latched player vehicle -- live, in this client's own physics step. Two drivers in the same model with
/// different engines feel different, which the record channel cannot do at all.
///
/// Three levers, because three is how many quantities have been driven and confirmed (MASTER_TEST AU5, AW1,
/// AW2). `ncm/core/parts/handling.lua` composed this from the driver's fitted parts and the plugin
/// interprets none of it (`L135`) -- it clamps and applies.
struct Handling {
    int version = 2;
    // KB-146: levers are not meaningful until they are bound to one authoritative physical Machine.
    // `vehicleId` is OPEN//77's ephemeral id and is carried for diagnostics. `engineEntity` is the
    // exact REDengine ent::EntityID published by the streamed vehicle snapshot; it is the join key the
    // native probe can compare with vehicle::BaseObject::entityID without guessing a pointer.
    bool bound = false;
    bool valid = false;
    std::string assetId;
    std::string vehicleId;
    std::string authorityEpoch;
    uint64_t engineEntity = 0;
    std::string invalidReason;
    bool hasGrip = false;  double grip = 1.0;    // across travel -- tyre grip
    bool hasDrive = false; double drive = 1.0;   // along travel, pushing -- power delivery
    bool hasBrake = false; double brake = 1.0;   // along travel, retarding -- stopping ability
    // The governor: an absolute km/h this Machine is tapered down to. NOT a lever -- it withholds drive
    // near the target rather than scaling it everywhere, so top speed and acceleration stay separable.
    bool hasDrag = false;     double drag = 0.0;        // retarding force while COASTING (aero drag)
    bool hasTopSpeed = false; double topSpeedKph = 0.0;
};

/// `L324`: installed components as a force on the bound Machine. World-space Newtons, held for `ttlMs` (a lease the
/// client refreshes), plus at most one PULSE per message (a new `pulseSeq` starts one, timed in physics time).
/// `supersedeLift` = this Machine's propulsion belongs to its installed components: NCM Thrust's legacy lift lever is
/// ignored while the lease is fresh. Same identity rule as Handling: refused unless `assetId` is the bound Machine.
struct Wrench {
    int version = 1;
    std::string assetId;
    std::string vehicleId;
    double fx = 0, fy = 0, fz = 0;
    int ttlMs = 0;
    bool supersedeLift = false;
    bool hasPulse = false;
    uint32_t pulseSeq = 0;
    double px = 0, py = 0, pz = 0;
    int pulseMs = 0;
    // 2026-10-12, a Machine flown by an installed flight computer (the AV): `massKg` is the NCM Machine's mass, so the
    // force lands as the acceleration NCM computed whatever mass the host body has; `ax/ay/az` is the angular
    // acceleration (world rad/s^2) the model's torque makes; `av` asks for an AV body's physics to be switched on.
    bool av = false;
    bool hasMass = false; double massKg = 0;
    double ax = 0, ay = 0, az = 0;
};

/// One telemetry frame, the shape `driver.feedback.frame` produces. **A channel that could not be read is
/// ABSENT, not zero** (`IDEA-361`) -- so every field is optional and `has*` means what it says.
struct Frame {
    double at = 0.0;
    bool hasEngine = false;    double engine = 0.0;      // rev ratio 0..1
    bool hasSpeed = false;     double speed = 0.0;       // m/s
    bool hasSteering = false;  double steering = 0.0;    // -1..1
    // **The brake PEDAL, not brake force.** This is what separates drag from braking at the write site:
    // a retarding force with the pedal at rest is drag by definition. See `physics_probe.cpp`.
    bool hasBrake = false;     double brake = 0.0;       // 0..1
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
    /// `IDEA-507`: NCM asks the carrier to read the game's own drive-model data for a list of records and
    /// write it to a file. Read-only -- it mutates nothing, so `L148` is not engaged.
    void onArchDump(std::function<void(const std::vector<std::string>&)> fn) { onArchDump_ = std::move(fn); }
    /// Read the gear chain of one or more vehicle records and log it. Read-only; `L148` is not engaged.
    void onGearDump(std::function<void(const std::vector<std::string>&)> fn) { onGearDump_ = std::move(fn); }
    /// `L152`: the driver's fitted parts, as live force scales. A v2 bound setup is also a short lease;
    /// the sender must heartbeat the complete identity and levers while the binding remains authoritative.
    void onHandling(std::function<void(const Handling&)> fn) { onHandling_ = std::move(fn); }
    void onWrench(std::function<void(const Wrench&)> fn) { onWrench_ = std::move(fn); }
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
    std::function<void(const std::vector<std::string>&)> onArchDump_;
    std::function<void(const std::vector<std::string>&)> onGearDump_;
    std::function<void(const Handling&)> onHandling_;
    std::function<void(const Wrench&)> onWrench_;
    std::function<void(const Frame&)> onFrame_;
    std::function<void()> onDisconnect_;
    std::function<void()> onConnect_;
};

/// The page served to the WebUI surface. Identical in behaviour to the companion's `BRIDGE_HTML`: it opens a
/// socket back to its own origin and relays NCM's events across it in both directions.
extern const char* kBridgeHtml;

}  // namespace ncm::bridge
