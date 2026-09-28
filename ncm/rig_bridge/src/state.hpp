#pragma once

#include "feel.hpp"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>

namespace ncm::rig {

struct InputFrame {
    float steering = 0.0f;
    float throttle = 0.0f;
    float brake = 0.0f;
    float clutch = 0.0f;
    uint64_t sequence = 0;
    bool connected = false;
};

/// What the car is DOING. Never how hard to push -- the mix decides that, from one place.
struct FeedbackFrame {
    feel::Telemetry telemetry{};
    bool inVehicle = false;
    std::chrono::steady_clock::time_point updated{};
};

/// A collision is an EVENT, not a sampled state, so it does not belong in the frame above: a frame that
/// arrives 40 ms later would erase a jolt that had not been felt yet. It is latched with its own clock and
/// decays over `kCollisionDecayMs`, so a hit is felt exactly once and for a bounded time.
struct Collision {
    float kick = 0.0f;      // -1..1, signed toward the side the impact came from
    std::chrono::steady_clock::time_point at{};
};

constexpr int kCollisionDecayMs = 220;

class SharedState {
public:
    void publishInput(InputFrame frame);
    InputFrame input() const;
    void publishFeedback(const FeedbackFrame& frame);
    FeedbackFrame feedback() const;

    /// Latches a jolt. The largest un-decayed kick wins, so a heavy hit is never overwritten by the light
    /// scrape that follows it a frame later.
    void applyCollision(float kick);
    /// The remaining jolt at `now`, linearly decayed, or 0 once it has expired.
    float collisionAt(std::chrono::steady_clock::time_point now) const;

    void setPlayerVehicle(void* value);
    void* playerVehicle() const;
    void setBridgeConnected(bool value);
    bool bridgeConnected() const;

private:
    /// `collisionMutex_` is already held. Kept separate so `applyCollision` can compare against the live
    /// decayed value without taking the lock twice.
    float collisionAtLocked_(std::chrono::steady_clock::time_point now) const;

    mutable std::mutex inputMutex_;
    mutable std::mutex feedbackMutex_;
    mutable std::mutex collisionMutex_;
    InputFrame input_{};
    FeedbackFrame feedback_{};
    Collision collision_{};
    std::atomic<void*> playerVehicle_{nullptr};
    std::atomic<bool> bridgeConnected_{false};
};

SharedState& state();
}
