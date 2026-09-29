#include "state.hpp"

#include <algorithm>
#include <cmath>

namespace ncm::rig {
void SharedState::publishInput(InputFrame frame) { std::lock_guard lock(inputMutex_); input_ = frame; }
InputFrame SharedState::input() const { std::lock_guard lock(inputMutex_); return input_; }
void SharedState::publishFeedback(const FeedbackFrame& frame) { std::lock_guard lock(feedbackMutex_); feedback_ = frame; }
FeedbackFrame SharedState::feedback() const { std::lock_guard lock(feedbackMutex_); return feedback_; }

void SharedState::applyCollision(float kick, float thud)
{
    const auto now = std::chrono::steady_clock::now();
    std::lock_guard lock(collisionMutex_);
    // A heavier hit overrides a lighter one still in flight; a lighter one never truncates a heavy jolt.
    // "Heavier" is the thud: a head-on crash with no lateral kick still outranks a side scrape.
    if (thud >= collisionAtLocked_(now).thud) {
        collision_.kick = std::clamp(kick, -1.0f, 1.0f);
        collision_.thud = std::clamp(thud, 0.0f, 1.0f);
        collision_.at = now;
    }
}

Collision SharedState::collisionAt(std::chrono::steady_clock::time_point now) const
{
    std::lock_guard lock(collisionMutex_);
    return collisionAtLocked_(now);
}

Collision SharedState::collisionAtLocked_(std::chrono::steady_clock::time_point now) const
{
    if (collision_.at.time_since_epoch().count() == 0) return {};
    const auto age = std::chrono::duration_cast<std::chrono::milliseconds>(now - collision_.at).count();
    if (age < 0 || age >= kCollisionDecayMs) return {};
    const float remaining = 1.0f - static_cast<float>(age) / static_cast<float>(kCollisionDecayMs);
    return {collision_.kick * remaining, collision_.thud * remaining, collision_.at};
}

void SharedState::setPlayerVehicle(void* value) { playerVehicle_.store(value, std::memory_order_release); }
void* SharedState::playerVehicle() const { return playerVehicle_.load(std::memory_order_acquire); }
void SharedState::setBridgeConnected(bool value) { bridgeConnected_.store(value, std::memory_order_release); }
bool SharedState::bridgeConnected() const { return bridgeConnected_.load(std::memory_order_acquire); }
SharedState& state() { static SharedState instance; return instance; }
}
