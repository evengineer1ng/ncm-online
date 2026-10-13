// The AV, flown by NCM engineering (L368). 0.1.40, after the first live flights (2026-10-13): the AV's rigid body never
// passes through RigidBody::Recalculate -- the probe counted 0 calls while it was bound and switched on 31 times -- so a
// force added there never reached it. This file now does what tidusmd's Drive an Aerial Vehicle plugin does (MIT,
// RED4EXT-DAV, on Jack Humbert's SDK layout), on the GAME THREAD, every frame, for the one bound AV only:
//
//   * physics ON only when the body's physics state says it is off (vehicleBaseObject +0x260 != 0 ->
//     ForceEnablePhysics, hash 2793083181) -- not on a timer, which kept re-enabling it;
//   * its own gravity OFF (vehiclePhysicsData +0x1B0) while NCM flies it, back ON when the lease ends;
//   * NCM's acceleration integrated into the body: velocity (+0x18) += (F / NCM mass + g) dt, spin (+0x24) += alpha dt.
//
// The physics data is reached from the vehicle (+0x2D0) and used ONLY if it points back at that vehicle (+0x180, the
// back-pointer the probe already verified on 2.31). Every access is SEH-guarded; one fault stops the writer for the
// session. Once a second it reports what it read and wrote, upward to NCM (and so to the server log).
#include "vehicle/av_physics.hpp"

#include "log.hpp"
#include "vehicle/physics_probe.hpp"

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Natives/ScriptGameInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/EntityID.hpp>

#include <Windows.h>
#include <cmath>
#include <cstdio>

namespace ncm::vehicle::av {
namespace {

constexpr uint32_t kForceEnablePhysicsHash = 2793083181u;
constexpr uint32_t kOffPhysicsState = 0x260;   // vehicleBaseObject: PhysicsState (0 = Enabled)
constexpr uint32_t kOffPhysicsData = 0x2D0;    // vehicleBaseObject: vehiclePhysicsData*
constexpr uint32_t kOffPdVelocity = 0x18;
constexpr uint32_t kOffPdSpin = 0x24;
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

// one-second report
uint64_t g_nextReportMs = 0;
uint32_t g_frames = 0, g_enables = 0, g_notAv = 0, g_notFound = 0, g_badPd = 0;
uint32_t g_lastState = 0xFFFFFFFF;
float g_lastMass = 0, g_lastV[3] = {0, 0, 0}, g_lastF[3] = {0, 0, 0}, g_lastNcmMass = 0;
uint8_t g_lastGravity = 0xFF;
std::function<void(const std::string&)> g_report;

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

/// One frame of NCM flight on the physics data: gravity off, v += a dt, w += alpha dt. Returns false on a fault.
bool fly(uint8_t* pd, const float* acc, const float* alpha, float dt, float* outV, float* outMass, uint8_t* outGravity) noexcept
{
    __try {
        *outGravity = *(pd + kOffPdGravity);
        *(pd + kOffPdGravity) = 0;
        auto* v = reinterpret_cast<float*>(pd + kOffPdVelocity);
        auto* w = reinterpret_cast<float*>(pd + kOffPdSpin);
        for (int i = 0; i < 3; ++i) {
            const float nv = v[i] + acc[i] * dt;
            const float nw = w[i] + alpha[i] * dt;
            if (nv == nv && std::fabs(nv) < 400.0f) v[i] = nv;
            if (nw == nw && std::fabs(nw) < 20.0f) w[i] = nw;
            outV[i] = v[i];
        }
        *outMass = *reinterpret_cast<float*>(pd + kOffPdMass);
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
    if (!active && g_frames == 0 && g_enables == 0) return;
    char line[512];
    std::snprintf(line, sizeof line,
        "frames=%u state=%u gravity=%u enables=%u notAv=%u notFound=%u badPd=%u bodyMass=%.0f ncmMass=%.0f "
        "v=(%.2f,%.2f,%.2f) F=(%.0f,%.0f,%.0f) entity=%llu%s",
        g_frames, g_lastState, static_cast<unsigned>(g_lastGravity), g_enables, g_notAv, g_notFound, g_badPd,
        g_lastMass, g_lastNcmMass, g_lastV[0], g_lastV[1], g_lastV[2], g_lastF[0], g_lastF[1], g_lastF[2],
        static_cast<unsigned long long>(entity), g_dead ? " DEAD" : "");
    NCM_INFO("AV: %s", line);
    if (g_report) g_report(line);
    g_frames = g_enables = g_notAv = g_notFound = g_badPd = 0;
}

}  // namespace

void setReporter(std::function<void(const std::string&)> fn) { g_report = std::move(fn); }

void prepare() noexcept
{
    if (g_hash != Hash::Unknown) return;
    g_hash = ncm::vehicle::probe::addressTableCarries(kForceEnablePhysicsHash) ? Hash::Present : Hash::Absent;
    if (g_hash == Hash::Present) {
        g_forceEnable = reinterpret_cast<void*>(RED4ext::UniversalRelocBase::Resolve(kForceEnablePhysicsHash));
        if (!g_forceEnable) g_hash = Hash::Absent;
    }
    if (g_hash == Hash::Absent)
        NCM_ERR("AV: this build's address table has no ForceEnablePhysics (hash %u) -- an AV cannot be flown here", kForceEnablePhysicsHash);
    else
        NCM_INFO("AV: ForceEnablePhysics resolved at %p -- a bound AV can be flown (game-thread writer)", g_forceEnable);
    QueryPerformanceFrequency(&g_freq);
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
        // the lease ended (the pilot got out, the world went away): give the AV its own gravity back, once
        if (g_flying) {
            g_flying = false;
            uint8_t* veh = currentVehicle();
            uint8_t* pd = nullptr; uint32_t st = 0;
            if (veh && readLinks(veh, &pd, &st)) setGravity(pd, 1);
            NCM_INFO("AV: lease ended -- gravity handed back to the body");
        }
        report(now, entity, false);
        return;
    }

    try {
        find(entity, now);
    } catch (...) {}
    uint8_t* veh = currentVehicle();
    if (!veh) { report(now, entity, true); return; }

    uint8_t* pd = nullptr;
    uint32_t state = 0;
    if (!readLinks(veh, &pd, &state)) { ++g_badPd; report(now, entity, true); return; }
    g_lastState = state;
    if (state != 0) {
        if (callForceEnable(g_forceEnable, veh)) ++g_enables;
        else { g_dead = true; NCM_ERR("AV: ForceEnablePhysics faulted -- the AV writer is off for this session"); return; }
    }

    // NCM's acceleration (its Machine's mass, not the body's) plus real gravity, the body's own being off
    const float m = ncmMass > 100.0f ? ncmMass : 1.0f;
    const float acc[3] = { F[0] / m, F[1] / m, F[2] / m - kG };
    float v[3]; float bodyMass = 0; uint8_t gravity = 0;
    if (!fly(pd, acc, alpha, dt, v, &bodyMass, &gravity)) {
        g_dead = true;
        NCM_ERR("AV: a physics-data write faulted -- the AV writer is off for this session");
        return;
    }
    g_flying = true;
    ++g_frames;
    g_lastGravity = gravity;
    g_lastMass = bodyMass;
    g_lastNcmMass = ncmMass;
    for (int i = 0; i < 3; ++i) { g_lastV[i] = v[i]; g_lastF[i] = F[i]; }
    report(now, entity, true);
}

}  // namespace ncm::vehicle::av
