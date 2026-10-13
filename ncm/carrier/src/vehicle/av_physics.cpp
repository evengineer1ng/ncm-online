// The AV, flown by NCM engineering (L368). 0.1.41 (2026-10-13, KB-467): fly it the way Drive an Aerial Vehicle does
// with the player INSIDE (tidusmd0806/CP2077-RED4EXT-DAV + CP2077-DriveAerialVehicle, MIT; read 2026-10-13):
//
//   * physics ON whenever the body's physics state says it is off (vehicleBaseObject +0x260 != 0 -> ForceEnablePhysics,
//     hash 2793083181), every game frame -- DAV's Engine:Update does exactly this;
//   * the game's OWN forces on that AV dropped ("EnableOriginalPhysics(false)"): detours on vehicle::RigidBody
//     ApplyImpulse (hash 611586815) and ApplyAngularImpulse (hash 3303544265) return early for the bound AV only, so
//     the AV's built-in air controller cannot fight the pilot;
//   * its own gravity OFF (physics data +0x1B0) while NCM flies it, back ON when the lease ends;
//   * NCM's acceleration ADDED TO THE FORCE / TORQUE ACCUMULATORS (physics data +0x00 / +0x0C, world frame), as a
//     per-frame impulse the body consumes on its next step: force += a dt / inverseMass, torque += I_world alpha dt
//     (Let There Be Flight scales the same way: force *= timeDelta * mass).
//
// 0.1.40 wrote the VELOCITY (+0x18) instead -- DAV's mode for an EMPTY AV. Live (01:25 UTC) the written velocity ran to
// -20 m/s on the pad while the body never moved: the body does not take a written velocity while it is flown. KB-467.
//
// Layout (vehicle::RigidBody, jackhumbert/RED4ext.SDK, the commit DAV builds against): force 0x00, torque 0x0C,
// velocity 0x18, angularVelocity 0x24, inverseMass 0x40, worldInertiaTensor 0x90 (4x Vector4 rows), vehicle 0x180,
// gravity 0x1B0, total_mass 0x1BC. The physics data is reached from the vehicle (+0x2D0) and used ONLY if it points back
// at that vehicle. Every access is SEH-guarded; one fault stops the writer for the session. Once a second it reports
// what it read and wrote, upward to NCM (and so to the server log).
#include "vehicle/av_physics.hpp"

#include "log.hpp"
#include "vehicle/physics_probe.hpp"

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Natives/ScriptGameInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/EntityID.hpp>

#include <Windows.h>
#include <atomic>
#include <cmath>
#include <cstdio>

namespace ncm::vehicle::av {
namespace {

constexpr uint32_t kForceEnablePhysicsHash = 2793083181u;
constexpr uint32_t kApplyImpulseHash = 611586815u;          // vehicle::RigidBody::ApplyImpulse (DAV, LTBF)
constexpr uint32_t kApplyAngularImpulseHash = 3303544265u;  // vehicle::RigidBody::ApplyAngularImpulse (DAV, LTBF)
constexpr uint32_t kOffPhysicsState = 0x260;   // vehicleBaseObject: PhysicsState (0 = Enabled)
constexpr uint32_t kOffPhysicsData = 0x2D0;    // vehicleBaseObject: vehiclePhysicsData*
constexpr uint32_t kOffPdForce = 0x00;
constexpr uint32_t kOffPdTorque = 0x0C;
constexpr uint32_t kOffPdVelocity = 0x18;
constexpr uint32_t kOffPdSpin = 0x24;
constexpr uint32_t kOffPdInverseMass = 0x40;
constexpr uint32_t kOffPdWorldInertia = 0x90;  // Matrix: rows X, Y, Z, W of Vector4
constexpr uint32_t kOffPdBack = 0x180;         // vehiclePhysicsData: owning vehicle
constexpr uint32_t kOffPdGravity = 0x1B0;      // vehiclePhysicsData: gravity on (byte)
constexpr uint32_t kOffPdMass = 0x1BC;
constexpr float kG = 9.81f;

enum class Hash { Unknown, Present, Absent };
Hash g_hash = Hash::Unknown;
void* g_forceEnable = nullptr;
bool g_dead = false;                      // a fault: never touch an AV again this session

RED4ext::Handle<RED4ext::IScriptable> g_vehicle;   // keeps the AV alive while we hold its pointer
uint64_t g_vehicleEntity = 0;
uint64_t g_nextFindMs = 0;
bool g_flying = false;
LARGE_INTEGER g_freq{}, g_last{};

// the AV whose own forces are dropped (the detours run wherever the game applies them; a plain pointer compare)
std::atomic<void*> g_blockVehicle{nullptr};
std::atomic<uint32_t> g_blockedForces{0}, g_blockedTorques{0};
bool g_hooksAttached = false;
void* g_impulseTarget = nullptr;
void* g_angularTarget = nullptr;

using ImpulseFn = void (*)(void* pd, void* offset, void* vec);
ImpulseFn g_impulseOriginal = nullptr;
ImpulseFn g_angularOriginal = nullptr;

// one-second report
uint64_t g_nextReportMs = 0;
uint32_t g_frames = 0, g_enables = 0, g_notAv = 0, g_notFound = 0, g_badPd = 0;
uint32_t g_lastState = 0xFFFFFFFF;
float g_lastMass = 0, g_lastV[3] = {0, 0, 0}, g_lastF[3] = {0, 0, 0}, g_lastNcmMass = 0, g_lastInvMass = 0;
float g_lastAccF[3] = {0, 0, 0};          // the accumulator as found this frame, before we added (was it consumed?)
uint8_t g_lastGravity = 0xFF;
bool g_lastInertiaFallback = false;
std::function<void(const std::string&)> g_report;

bool ownedByBlocked(void* pd) noexcept
{
    void* veh = g_blockVehicle.load(std::memory_order_acquire);
    if (!veh || !pd) return false;
    __try {
        return *reinterpret_cast<void**>(static_cast<uint8_t*>(pd) + kOffPdBack) == veh;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

void impulseDetour(void* pd, void* offset, void* force)
{
    if (ownedByBlocked(pd)) { g_blockedForces.fetch_add(1, std::memory_order_relaxed); return; }
    g_impulseOriginal(pd, offset, force);
}

void angularDetour(void* pd, void* offset, void* torque)
{
    if (ownedByBlocked(pd)) { g_blockedTorques.fetch_add(1, std::memory_order_relaxed); return; }
    g_angularOriginal(pd, offset, torque);
}

using ForceEnableFn = void (*)(void*);

bool callForceEnable(void* fn, void* vehicle) noexcept
{
    __try {
        reinterpret_cast<ForceEnableFn>(fn)(vehicle);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

/// The vehicle's physics data, only if it points back at the vehicle. Also its physics state.
bool readLinks(uint8_t* vehicle, uint8_t** outPd, uint32_t* outState) noexcept
{
    __try {
        *outState = *reinterpret_cast<uint32_t*>(vehicle + kOffPhysicsState);
        auto* pd = *reinterpret_cast<uint8_t**>(vehicle + kOffPhysicsData);
        if (!pd || (reinterpret_cast<uintptr_t>(pd) & 0x7) != 0) return false;
        if (*reinterpret_cast<uint8_t**>(pd + kOffPdBack) != vehicle) return false;
        *outPd = pd;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

struct FrameOut {
    float v[3];
    float accBefore[3];
    float bodyMass;
    float invMass;
    uint8_t gravity;
    bool inertiaFallback;
};

/// One frame of NCM flight on the physics data: gravity off, then the frame's impulse into the accumulators --
/// force += acc dt / inverseMass, torque += I_world alpha dt. Returns false on a fault.
bool fly(uint8_t* pd, const float* acc, const float* alpha, float dt, FrameOut& out) noexcept
{
    __try {
        out.gravity = *(pd + kOffPdGravity);
        *(pd + kOffPdGravity) = 0;
        out.bodyMass = *reinterpret_cast<float*>(pd + kOffPdMass);
        float inv = *reinterpret_cast<float*>(pd + kOffPdInverseMass);
        if (!(inv > 1e-7f && inv < 1.0f)) inv = out.bodyMass > 1.0f ? 1.0f / out.bodyMass : 0.0f;   // a sane 1/m only
        out.invMass = inv;
        auto* f = reinterpret_cast<float*>(pd + kOffPdForce);
        auto* t = reinterpret_cast<float*>(pd + kOffPdTorque);
        const auto* v = reinterpret_cast<const float*>(pd + kOffPdVelocity);
        const auto* I = reinterpret_cast<const float*>(pd + kOffPdWorldInertia);   // row r, column c at r * 4 + c
        if (inv <= 0.0f) return true;
        // a body whose world tensor reads empty would never turn: stand in a solid of its mass, 2 m radius of gyration
        const float trace = I[0] + I[5] + I[10];
        out.inertiaFallback = !(trace > 1.0f && trace == trace);
        const float iso = (1.0f / inv) * 4.0f;
        for (int i = 0; i < 3; ++i) {
            out.accBefore[i] = f[i];
            const float df = acc[i] * dt / inv;
            float dt_ = 0.0f;
            if (out.inertiaFallback) dt_ = iso * alpha[i] * dt;
            else for (int c = 0; c < 3; ++c) dt_ += I[i * 4 + c] * alpha[c] * dt;
            if (df == df && std::fabs(df) < 1.0e6f) f[i] += df;
            if (dt_ == dt_ && std::fabs(dt_) < 1.0e6f) t[i] += dt_;
            out.v[i] = v[i];
        }
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

bool setGravity(uint8_t* pd, uint8_t on) noexcept
{
    __try {
        *(pd + kOffPdGravity) = on;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

uint8_t* currentVehicle()
{
    return g_vehicle ? reinterpret_cast<uint8_t*>(g_vehicle.GetPtr()) : nullptr;
}

void find(uint64_t entity, uint64_t now)
{
    if (entity == g_vehicleEntity && g_vehicle && now < g_nextFindMs) return;
    g_nextFindMs = now + 1000;
    g_vehicleEntity = entity;
    g_vehicle.Reset();
    try {
        RED4ext::ScriptGameInstance game;
        RED4ext::ent::EntityID id;
        id.hash = entity;
        RED4ext::Handle<RED4ext::IScriptable> found;
        if (!RED4ext::ExecuteFunction("ScriptGameInstance", "FindEntityByID", &found, game, id) || !found) { ++g_notFound; return; }
        auto* rtti = RED4ext::CRTTISystem::Get();
        auto* avClass = rtti ? rtti->GetClass("vehicleAVBaseObject") : nullptr;
        auto* type = found->GetType();
        if (!avClass || !type || !type->IsA(avClass)) { ++g_notAv; return; }
        g_vehicle = found;
    } catch (...) {
        ++g_notFound;
    }
}

void report(uint64_t now, uint64_t entity, bool active)
{
    if (now < g_nextReportMs) return;
    g_nextReportMs = now + 1000;
    const uint32_t bf = g_blockedForces.exchange(0), bt = g_blockedTorques.exchange(0);
    if (!active && g_frames == 0 && g_enables == 0) return;
    char line[640];
    std::snprintf(line, sizeof line,
        "frames=%u state=%u gravity=%u enables=%u notAv=%u notFound=%u badPd=%u bodyMass=%.0f invMass=%.6f ncmMass=%.0f "
        "v=(%.2f,%.2f,%.2f) F=(%.0f,%.0f,%.0f) acc0=(%.0f,%.0f,%.0f) blocked=%u/%u hooks=%s inertia=%s entity=%llu%s",
        g_frames, g_lastState, static_cast<unsigned>(g_lastGravity), g_enables, g_notAv, g_notFound, g_badPd,
        g_lastMass, g_lastInvMass, g_lastNcmMass, g_lastV[0], g_lastV[1], g_lastV[2], g_lastF[0], g_lastF[1], g_lastF[2],
        g_lastAccF[0], g_lastAccF[1], g_lastAccF[2], bf, bt, g_hooksAttached ? "on" : "OFF", g_lastInertiaFallback ? "FALLBACK" : "body",
        static_cast<unsigned long long>(entity), g_dead ? " DEAD" : "");
    NCM_INFO("AV: %s", line);
    if (g_report) g_report(line);
    g_frames = g_enables = g_notAv = g_notFound = g_badPd = 0;
}

void* resolveHash(uint32_t hash)
{
    if (!ncm::vehicle::probe::addressTableCarries(hash)) return nullptr;
    return reinterpret_cast<void*>(RED4ext::UniversalRelocBase::Resolve(hash));
}

}  // namespace

void setReporter(std::function<void(const std::string&)> fn) { g_report = std::move(fn); }

void prepare(void* pluginHandle, const void* sdkOpaque) noexcept
{
    if (g_hash != Hash::Unknown) return;
    QueryPerformanceFrequency(&g_freq);
    g_forceEnable = resolveHash(kForceEnablePhysicsHash);
    g_hash = g_forceEnable ? Hash::Present : Hash::Absent;
    if (g_hash == Hash::Absent) {
        NCM_ERR("AV: this build's address table has no ForceEnablePhysics (hash %u) -- an AV cannot be flown here", kForceEnablePhysicsHash);
        return;
    }
    // DAV's EnableOriginalPhysics(false): without these the AV's own controller keeps pushing against the pilot.
    // An AV is still flown if they cannot attach; the report says hooks=OFF.
    const auto* sdk = static_cast<const RED4ext::v1::Sdk*>(sdkOpaque);
    g_impulseTarget = resolveHash(kApplyImpulseHash);
    g_angularTarget = resolveHash(kApplyAngularImpulseHash);
    if (sdk && sdk->hooking && sdk->hooking->Attach && g_impulseTarget && g_angularTarget) {
        const auto h = static_cast<RED4ext::v1::PluginHandle>(pluginHandle);
        const bool a = sdk->hooking->Attach(h, g_impulseTarget, reinterpret_cast<void*>(&impulseDetour),
                                            reinterpret_cast<void**>(&g_impulseOriginal));
        const bool b = a && sdk->hooking->Attach(h, g_angularTarget, reinterpret_cast<void*>(&angularDetour),
                                                 reinterpret_cast<void**>(&g_angularOriginal));
        if (a && !b) sdk->hooking->Detach(h, g_impulseTarget);
        g_hooksAttached = a && b;
    }
    NCM_INFO("AV: ForceEnablePhysics at %p; the AV's own impulses %s -- a bound AV is flown on its force accumulators",
             g_forceEnable, g_hooksAttached ? "dropped while NCM flies it (hooks on)" : "NOT dropped (hooks could not attach)");
}

void release(void* pluginHandle, const void* sdkOpaque) noexcept
{
    g_blockVehicle.store(nullptr, std::memory_order_release);
    if (!g_hooksAttached) return;
    const auto* sdk = static_cast<const RED4ext::v1::Sdk*>(sdkOpaque);
    if (sdk && sdk->hooking && sdk->hooking->Detach) {
        const auto h = static_cast<RED4ext::v1::PluginHandle>(pluginHandle);
        sdk->hooking->Detach(h, g_impulseTarget);
        sdk->hooking->Detach(h, g_angularTarget);
    }
    g_hooksAttached = false;
}

void tick() noexcept
{
    LARGE_INTEGER t;
    QueryPerformanceCounter(&t);
    float dt = 0.0f;
    if (g_last.QuadPart != 0 && g_freq.QuadPart != 0) dt = static_cast<float>(t.QuadPart - g_last.QuadPart) / static_cast<float>(g_freq.QuadPart);
    g_last = t;
    if (dt <= 0.0f || dt > 0.1f) dt = 1.0f / 60.0f;
    const uint64_t now = GetTickCount64();

    uint64_t entity = 0;
    float F[3], alpha[3], ncmMass = 0;
    const bool active = !g_dead && g_hash == Hash::Present && ncm::vehicle::probe::avCommand(entity, F, alpha, ncmMass);

    if (!active) {
        // the lease ended (the pilot got out, the world went away): the AV's own forces and gravity back, once
        if (g_flying) {
            g_flying = false;
            g_blockVehicle.store(nullptr, std::memory_order_release);
            uint8_t* veh = currentVehicle();
            uint8_t* pd = nullptr; uint32_t st = 0;
            if (veh && readLinks(veh, &pd, &st)) setGravity(pd, 1);
            NCM_INFO("AV: lease ended -- gravity and the AV's own forces handed back to the body");
        }
        report(now, entity, false);
        return;
    }

    try {
        find(entity, now);
    } catch (...) {}
    uint8_t* veh = currentVehicle();
    if (!veh) { g_blockVehicle.store(nullptr, std::memory_order_release); report(now, entity, true); return; }

    uint8_t* pd = nullptr;
    uint32_t state = 0;
    if (!readLinks(veh, &pd, &state)) { ++g_badPd; report(now, entity, true); return; }
    g_lastState = state;
    if (state != 0) {
        if (callForceEnable(g_forceEnable, veh)) ++g_enables;
        else { g_dead = true; g_blockVehicle.store(nullptr); NCM_ERR("AV: ForceEnablePhysics faulted -- the AV writer is off for this session"); return; }
    }
    g_blockVehicle.store(veh, std::memory_order_release);

    // NCM's acceleration (its Machine's mass, not the body's) plus real gravity, the body's own being off
    const float m = ncmMass > 100.0f ? ncmMass : 1.0f;
    const float acc[3] = { F[0] / m, F[1] / m, F[2] / m - kG };
    FrameOut out{};
    if (!fly(pd, acc, alpha, dt, out)) {
        g_dead = true;
        g_blockVehicle.store(nullptr);
        NCM_ERR("AV: a physics-data write faulted -- the AV writer is off for this session");
        return;
    }
    g_flying = true;
    ++g_frames;
    g_lastGravity = out.gravity;
    g_lastMass = out.bodyMass;
    g_lastInvMass = out.invMass;
    g_lastInertiaFallback = out.inertiaFallback;
    g_lastNcmMass = ncmMass;
    for (int i = 0; i < 3; ++i) { g_lastV[i] = out.v[i]; g_lastF[i] = F[i]; g_lastAccF[i] = out.accBefore[i]; }
    report(now, entity, true);
}

}  // namespace ncm::vehicle::av
