#include "vehicle_hook.hpp"

#include "config.hpp"
#include "log.hpp"
#include "state.hpp"

#include <RED4ext/Relocation.hpp>
#include <RED4ext/RTTISystem.hpp>
#include <RED4ext/RTTITypes.hpp>
#include <RED4ext/Scripting/Natives/vehicleBaseObject.hpp>
#include <RED4ext/Scripting/Utils.hpp>

#include <atomic>
#include <cmath>

namespace ncm::rig::vehicle {
namespace {
using UpdateFn = void (*)(void*);
constexpr uint32_t kUpdateVehicleCameraInputHash = 501486464u;
constexpr std::ptrdiff_t kSteeringOffset = 0x278;
UpdateFn original = nullptr;
void* target = nullptr;
std::atomic<bool> active{false};
std::atomic<uint64_t> count{0};
std::atomic<RED4ext::CClassFunction*> speedFunction{nullptr};
std::atomic<bool> speedLookupAttempted{false};
bool inputEnabled = true;

float currentSpeed(void* self)
{
    auto* fn = speedFunction.load(std::memory_order_acquire);
    if (!fn && !speedLookupAttempted.exchange(true)) {
        if (auto* rtti = RED4ext::CRTTISystem::Get()) {
            if (auto* cls = rtti->GetClass(RED4ext::CName("vehicleBaseObject"))) {
                fn = cls->GetFunction(RED4ext::CName("GetCurrentSpeed"));
                speedFunction.store(fn, std::memory_order_release);
            }
        }
        if (!fn) RIG_WARN("vehicle speed RTTI unavailable; input works but speed FFB remains stationary");
    }
    if (!fn) return 0.0f;
    float value = 0.0f;
    RED4ext::ExecuteFunction(reinterpret_cast<RED4ext::IScriptable*>(self), fn, &value);
    return value;
}

void detour(void* self)
{
    if (original) original(self);
    if (!self || self != state().playerVehicle()) return;
    const auto frame = state().input();
    if (!frame.connected) return;

    auto* vehicle = static_cast<RED4ext::vehicle::BaseObject*>(self);
    if (inputEnabled) {
        auto* steer = reinterpret_cast<float*>(static_cast<char*>(self) + kSteeringOffset);
        if (std::fabs(frame.steering) > std::fabs(*steer)) *steer = frame.steering;
        if (frame.throttle > vehicle->acceleration) vehicle->acceleration = frame.throttle;
        if (frame.brake > vehicle->deceleration) vehicle->deceleration = frame.brake;
        const auto n = count.fetch_add(1) + 1;
        if (n == 1) RIG_INFO("first native rig injection: steer=%.3f throttle=%.3f brake=%.3f",
                             *steer, vehicle->acceleration, vehicle->deceleration);
    }

    // **The detour is a FALLBACK telemetry source, not the primary one.** It can only see speed (via RTTI)
    // and the steering the rig itself asked for. Slip and suspension -- the channels the hands actually
    // read -- come off the client's vehicle snapshot over the bridge. So this fills the two fields it can
    // and leaves the rest untouched, which keeps the wheel alive with centring and damping if the WebUI
    // feed drops, without ever claiming the road went smooth.
    auto feedback = state().feedback();
    feedback.inVehicle = true;
    feedback.telemetry.speed = std::fabs(currentSpeed(self));
    feedback.telemetry.hasSpeed = true;
    feedback.telemetry.steering = frame.steering;
    feedback.telemetry.hasSteering = true;
    feedback.updated = std::chrono::steady_clock::now();
    state().publishFeedback(feedback);
}
}

bool install(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk, bool enabled)
{
    inputEnabled = enabled;
    if (!sdk || !sdk->hooking || !sdk->hooking->Attach) { RIG_ERR("RED4ext hooking API unavailable"); return false; }
    const auto address = RED4ext::UniversalRelocBase::Resolve(kUpdateVehicleCameraInputHash);
    target = reinterpret_cast<void*>(address);
    if (!target) { RIG_ERR("UpdateVehicleCameraInput resolved null"); return false; }
    const bool ok = sdk->hooking->Attach(handle, target, reinterpret_cast<void*>(&detour),
                                          reinterpret_cast<void**>(&original));
    active.store(ok);
    RIG_INFO("vehicle input detour %s at %p", ok ? "installed" : "FAILED", target);
    return ok;
}

void remove(RED4ext::v1::PluginHandle handle, const RED4ext::v1::Sdk* sdk)
{
    if (active.exchange(false) && sdk && sdk->hooking && sdk->hooking->Detach && target)
        sdk->hooking->Detach(handle, target);
    original = nullptr;
    target = nullptr;
    state().setPlayerVehicle(nullptr);
}
bool installed() { return active.load(); }
uint64_t injections() { return count.load(); }
void setPlayerVehicle(void* value)
{
    void* before = state().playerVehicle();
    state().setPlayerVehicle(value);
    auto feedback = state().feedback();
    feedback.inVehicle = value != nullptr;
    feedback.updated = std::chrono::steady_clock::now();
    // Leaving a car clears the whole picture. A stale slip or suspension reading held across a dismount
    // would keep the wheel buzzing about a road the driver is no longer on.
    if (!value) feedback.telemetry = feel::Telemetry{};
    state().publishFeedback(feedback);
    if (before != value) RIG_INFO("player vehicle changed: %p -> %p", before, value);
}
}

