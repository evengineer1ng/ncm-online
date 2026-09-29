#include "rtti.hpp"

#include "log.hpp"
#include "state.hpp"

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/EntityID.hpp>

// The natives `NcmPaceNatives.reds` declares. Script -> native only, polled from redscript's own tick: native code
// must never call a scripted function (doing so without a script frame terminates the process). Every AI command
// is issued by redscript, in a script frame, exactly as OPEN//77 issues its own (Open77VehicleDriving.reds).
namespace ncm::pace::rtti {
namespace {
using Flags = RED4ext::CBaseFunction::Flags;

void count(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, int32_t* out, int64_t)
{
    stack->code++;
    if (out) *out = state().count();
}

void revision(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, int32_t* out, int64_t)
{
    stack->code++;
    if (out) *out = state().revision();
}

void entity(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::ent::EntityID* out, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(stack, &index);
    stack->code++;
    if (out) *out = RED4ext::ent::EntityID(state().entity(index));
}

void step(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    int32_t index = -1;
    float x = 0.0f, y = 0.0f, z = 0.0f;
    RED4ext::GetParameter(stack, &index);
    RED4ext::GetParameter(stack, &x);
    RED4ext::GetParameter(stack, &y);
    RED4ext::GetParameter(stack, &z);
    stack->code++;
    const std::string cmd = state().step(index, x, y, z);
    if (out) *out = RED4ext::CString(cmd.c_str());
}

void note(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    RED4ext::CString text;
    RED4ext::GetParameter(stack, &text);
    stack->code++;
    static int logged = 0;
    if (++logged <= 300) PACE_INFO("reds: %s", std::string(text.c_str()).substr(0, 300).c_str());
    if (out) *out = true;
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
    add("NcmPace_Count", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&count), "Int32", {});
    add("NcmPace_Revision", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&revision), "Int32", {});
    add("NcmPace_Entity", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&entity), "entEntityID", {{"Int32", "index"}});
    add("NcmPace_Step", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&step), "String",
        {{"Int32", "index"}, {"Float", "x"}, {"Float", "y"}, {"Float", "z"}});
    add("NcmPace_Log", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&note), "Bool", {{"String", "text"}});
    PACE_INFO("redscript natives registered");
}
}

void registerNatives()
{
    if (auto* system = RED4ext::CRTTISystem::Get()) {
        system->AddRegisterCallback(registerTypes);
        system->AddPostRegisterCallback(postRegister);
    } else {
        PACE_ERR("RTTI unavailable while registering natives");
    }
}
}
