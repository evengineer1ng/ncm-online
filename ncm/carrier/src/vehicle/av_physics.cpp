// 2026-10-12 (owner: "make it fly ... aren't we using our engineering parts"): an AV's body is SCRIPTED -- the game
// moves it along quest splines with its rigid-body physics off, so Recalculate never sees it and no NCM force can reach
// it. This switches the physics of the one bound AV on, the way the "Drive an Aerial Vehicle" mod does (its RED4ext
// plugin, MIT: `vehicleBaseObject::ForceEnablePhysics`, address hash 2793083181), and nothing else: the forces, the
// spin and the gravity are then NCM's engineering through the ordinary wrench (physics_probe.cpp).
//
// Game thread only (RED4ext's Running::OnUpdate). Gated on every count: an `av` wrench lease must be fresh, the handling
// binding must name the entity, the entity must be a `vehicleAVBaseObject`, and its body must not already be ticking.
// The hash is checked against the shipped address table before it is ever resolved (Resolve terminates on a miss).
#include "vehicle/av_physics.hpp"

#include "log.hpp"
#include "vehicle/physics_probe.hpp"

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Natives/ScriptGameInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/EntityID.hpp>

#include <Windows.h>

namespace ncm::vehicle::av {
namespace {

constexpr uint32_t kForceEnablePhysicsHash = 2793083181u;

enum class Hash { Unknown, Present, Absent };
Hash g_hash = Hash::Unknown;
void* g_forceEnable = nullptr;
uint64_t g_nextTryMs = 0;
uint64_t g_lastEntity = 0;
uint32_t g_enables = 0, g_notAv = 0, g_notFound = 0, g_faults = 0;
uint64_t g_nextLogMs = 0;

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

}  // namespace

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
        NCM_INFO("AV: ForceEnablePhysics resolved at %p -- a bound AV's physics can be switched on", g_forceEnable);
}

void tick() noexcept
{
    const uint64_t entity = ncm::vehicle::probe::avEntityNeedingPhysics();
    if (entity == 0) return;
    const uint64_t now = GetTickCount64();
    if (now < g_nextTryMs && entity == g_lastEntity) return;
    g_nextTryMs = now + 400;
    g_lastEntity = entity;

    if (g_hash != Hash::Present) return;   // prepare() decided at startup

    try {
        RED4ext::ScriptGameInstance game;
        RED4ext::ent::EntityID id;
        id.hash = entity;
        RED4ext::Handle<RED4ext::IScriptable> found;
        if (!RED4ext::ExecuteFunction("ScriptGameInstance", "FindEntityByID", &found, game, id) || !found) {
            ++g_notFound;
        } else {
            auto* rtti = RED4ext::CRTTISystem::Get();
            auto* avClass = rtti ? rtti->GetClass("vehicleAVBaseObject") : nullptr;
            auto* type = found->GetType();
            if (!avClass || !type || !type->IsA(avClass)) {
                ++g_notAv;
            } else if (callForceEnable(g_forceEnable, found.GetPtr())) {
                ++g_enables;
            } else {
                ++g_faults;
                g_hash = Hash::Absent;   // one fault and it is never called again this session
                NCM_ERR("AV: ForceEnablePhysics faulted -- disabled for this session");
            }
        }
    } catch (...) {
        ++g_faults;
    }

    if (now >= g_nextLogMs) {
        g_nextLogMs = now + 2000;
        NCM_INFO("AV: physics switch for entity %llu -- %u enable(s), %u not an AV, %u not found, %u fault(s)",
                 static_cast<unsigned long long>(entity), g_enables, g_notAv, g_notFound, g_faults);
    }
}

}  // namespace ncm::vehicle::av
