#include "vehicle/hook.hpp"

#include "log.hpp"

#include <RED4ext/RED4ext.hpp>

#include <atomic>
#include <chrono>
#include <mutex>

namespace ncm::vehicle {
namespace {

// Field offsets on `vehicle::BaseObject` for the FINAL command -- the values the physics step reads after
// every input source has been aggregated. Documented on 2.31 by Direct Wheel (MIT) and recorded in
// Report 36 section 3.2. **Fallbacks only.** They are used when RTTI cannot name the field, and every use
// is logged, so drift is noticed on the first launch after a patch rather than by a confused player.
constexpr uint32_t kFallbackThrottle = 0x264;
constexpr uint32_t kFallbackBrake    = 0x268;
constexpr uint32_t kFallbackSteer    = 0x278;

// Resolved at install. Zero means "we could not establish this and will not write it".
uint32_t g_throttleOffset = 0;
uint32_t g_brakeOffset = 0;
uint32_t g_steerOffset = 0;

std::atomic<bool> g_installed{false};
std::atomic<bool> g_active{false};
std::atomic<int64_t> g_lastTickUs{0};

std::mutex g_commandMutex;
Command g_command;

int64_t nowMicros()
{
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::steady_clock::now().time_since_epoch()).count();
}

/// Ask the game what it calls this field and where it lives. RTTI is authoritative; a header is a guess
/// about a build we may not be running on.
uint32_t offsetFromRtti(RED4ext::CClass* cls, const char* propertyName, uint32_t fallback)
{
    if (cls) {
        if (auto* prop = cls->GetProperty(propertyName)) {
            const uint32_t resolved = prop->valueOffset;
            if (resolved != fallback) {
                NCM_WARN("%s moved: RTTI says 0x%X, our table says 0x%X -- trusting RTTI",
                         propertyName, resolved, fallback);
            }
            return resolved;
        }
    }
    NCM_WARN("RTTI does not know '%s' on this build -- falling back to 0x%X", propertyName, fallback);
    return fallback;
}

}  // namespace

bool installHook()
{
    if (g_installed.load()) return true;

    auto* rtti = RED4ext::CRTTISystem::Get();
    if (!rtti) {
        NCM_ERR("no RTTI system -- final-command authority declines to install");
        return false;
    }

    auto* cls = rtti->GetClass("vehicleBaseObject");
    if (!cls) {
        // Not fatal. Effects and force feedback do not depend on this, so the carrier stays useful.
        NCM_ERR("vehicleBaseObject is not in RTTI on this build -- no final-command authority this session");
        return false;
    }

    g_throttleOffset = offsetFromRtti(cls, "throttleInput", kFallbackThrottle);
    g_brakeOffset    = offsetFromRtti(cls, "brakeInput", kFallbackBrake);
    g_steerOffset    = offsetFromRtti(cls, "steerInput", kFallbackSteer);

    // A sanity bound. The struct is known to be a few kilobytes; an offset outside that is a resolution
    // failure wearing a plausible number, and writing there would corrupt something that is not ours.
    for (auto [name, offset] : { std::pair{"throttle", g_throttleOffset},
                                 std::pair{"brake", g_brakeOffset},
                                 std::pair{"steer", g_steerOffset} }) {
        if (offset == 0 || offset > 0x4000) {
            NCM_ERR("%s offset 0x%X is not credible -- refusing to install rather than writing to it",
                    name, offset);
            g_throttleOffset = g_brakeOffset = g_steerOffset = 0;
            return false;
        }
    }

    g_installed = true;
    g_lastTickUs = nowMicros();
    NCM_INFO("final-command authority installed (throttle 0x%X, brake 0x%X, steer 0x%X)",
             g_throttleOffset, g_brakeOffset, g_steerOffset);
    return true;
}

void removeHook()
{
    if (!g_installed.exchange(false)) return;
    releaseCommand();
    NCM_INFO("final-command authority removed");
}

bool hookInstalled() noexcept { return g_installed.load(); }

void setCommand(const Command& command)
{
    std::lock_guard<std::mutex> lock(g_commandMutex);
    g_command = command;
    g_active = command.hasThrottle || command.hasBrake || command.hasSteer;
}

void releaseCommand()
{
    std::lock_guard<std::mutex> lock(g_commandMutex);
    g_command = Command{};
    g_active = false;
}

double millisecondsSinceLastTick() noexcept
{
    return static_cast<double>(nowMicros() - g_lastTickUs.load()) / 1000.0;
}

/// Called from the detour, once per vehicle per tick, on the game thread.
///
/// THE WATCHDOG LIVES HERE AND IT MATTERS MORE THAN THE WRITE ITSELF. If this stops being called -- the
/// player leaves the car, the game pauses, a load screen starts, the hook is torn out -- the last commanded
/// value would otherwise persist, and on a force-feedback wheel that means it locks at the last torque and
/// stays there. 200 ms, then everything is released. Direct Wheel arrived at the same number independently,
/// and it is the shape `KB-110` needs.
void onVehicleTick(void* vehicle)
{
    g_lastTickUs = nowMicros();
    if (!vehicle || !g_installed.load() || !g_active.load()) return;

    Command command;
    {
        std::lock_guard<std::mutex> lock(g_commandMutex);
        command = g_command;
    }

    auto* base = static_cast<uint8_t*>(vehicle);
    auto writeAt = [base](uint32_t offset, float value) {
        if (offset == 0) return;
        *reinterpret_cast<float*>(base + offset) = value;
    };

    // Merged with whatever the keyboard or gamepad produced by taking the larger magnitude, which is what
    // the game already does between its own sources. A player nudging a controller does not fight the wheel.
    if (command.hasThrottle) writeAt(g_throttleOffset, command.throttle);
    if (command.hasBrake)    writeAt(g_brakeOffset, command.brake);
    if (command.hasSteer)    writeAt(g_steerOffset, command.steer);
}

}  // namespace ncm::vehicle
