#include "rtti.hpp"

#include "log.hpp"
#include "state.hpp"
#include "vehicle_hook.hpp"

#include <RED4ext/RED4ext.hpp>

namespace ncm::rig::rtti {
namespace {
using Flags = RED4ext::CBaseFunction::Flags;

void setVehicle(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, bool* out, int64_t)
{
    RED4ext::Handle<RED4ext::ISerializable> handle;
    RED4ext::GetParameter(frame, &handle);
    frame->code++;
    vehicle::setPlayerVehicle(static_cast<void*>(handle.instance));
    if (out) *out = true;
}

void clearVehicle(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, bool* out, int64_t)
{
    frame->code++;
    vehicle::setPlayerVehicle(nullptr);
    if (out) *out = true;
}

// **CDPR dispatches OnVehicleBumpEvent to the vehicle that got STRUCK, not the striker**, so the reds side
// forwards the event whenever EITHER party is the player's mount and computes the kick in the PLAYER's
// frame. By the time it reaches here the sign is already correct: negative = impact on the driver's left.
void onBump(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, bool* out, int64_t)
{
    RED4ext::Handle<RED4ext::ISerializable> handle;
    float kick = 0.0f;
    RED4ext::GetParameter(frame, &handle);
    RED4ext::GetParameter(frame, &kick);
    frame->code++;
    // Scoped exactly like the input detour: a jolt from any car but the one under the driver is discarded.
    if (handle.instance && static_cast<void*>(handle.instance) == state().playerVehicle())
        state().applyCollision(kick);
    if (out) *out = true;
}

void getStatus(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, RED4ext::CString* out, int64_t)
{
    frame->code++;
    if (!out) return;
    const auto input = state().input();
    std::string text = std::string("NCM Rig Bridge ") + NCM_RIG_BRIDGE_VERSION +
        " input=" + (input.connected ? "connected" : "absent") +
        " hook=" + (vehicle::installed() ? "installed" : "absent") +
        " injections=" + std::to_string(vehicle::injections());
    *out = RED4ext::CString(text.c_str());
}

void registerTypes() {}
void postRegister()
{
    auto* system = RED4ext::CRTTISystem::Get();
    auto add = [system](const char* name, RED4ext::ScriptingFunction_t<void*> callback, const char* result,
                        std::initializer_list<std::pair<const char*, const char*>> parameters) {
        auto* fn = RED4ext::CGlobalFunction::Create(name, name, callback);
        fn->flags = Flags{.isNative = true, .isStatic = true};
        if (result && *result) fn->SetReturnType(result);
        for (const auto& [type, param] : parameters) fn->AddParam(type, param);
        system->RegisterFunction(fn);
    };
    add("NcmRig_SetPlayerVehicle", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&setVehicle),
        "Bool", {{"handle:vehicleBaseObject", "vehicle"}});
    add("NcmRig_ClearPlayerVehicle", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&clearVehicle), "Bool", {});
    add("NcmRig_OnVehicleBump", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&onBump), "Bool",
        {{"handle:vehicleBaseObject", "vehicle"}, {"Float", "kick"}});
    add("NcmRig_GetStatus", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&getStatus), "String", {});
    RIG_INFO("redscript natives registered");
}
}

void registerNatives()
{
    if (auto* system = RED4ext::CRTTISystem::Get()) {
        system->AddRegisterCallback(registerTypes);
        system->AddPostRegisterCallback(postRegister);
    } else {
        RIG_ERR("RTTI unavailable while registering natives");
    }
}
}
