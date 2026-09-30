#include "rtti.hpp"

#include "log.hpp"
#include "state.hpp"

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/EntityID.hpp>

// The natives `NcmBroadcastNatives.reds` declares. Script -> native only, polled from redscript's own tick: native
// code never calls a scripted function. Every widget is created and moved by redscript.
namespace ncm::broadcast::rtti {
namespace {
using Flags = RED4ext::CBaseFunction::Flags;

void labelCount(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, int32_t* out, int64_t)
{
    stack->code++;
    if (out) *out = state().labelCount();
}

void labelEntity(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::ent::EntityID* out, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(stack, &index);
    stack->code++;
    if (out) *out = RED4ext::ent::EntityID(state().labelEntity(index));
}

void labelText(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(stack, &index);
    stack->code++;
    if (out) *out = RED4ext::CString(state().labelText(index).c_str());
}

void tower(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    stack->code++;
    if (out) *out = RED4ext::CString(state().tower().c_str());
}

void towerRow(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(stack, &index);
    stack->code++;
    if (out) *out = RED4ext::CString(state().towerRow(index).c_str());
}

void view(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    stack->code++;
    if (out) *out = RED4ext::CString(state().view().c_str());
}

void note(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    RED4ext::CString text;
    RED4ext::GetParameter(stack, &text);
    stack->code++;
    static int logged = 0;
    if (++logged <= 300) BCAST_INFO("reds: %s", std::string(text.c_str()).substr(0, 300).c_str());
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
    using F = RED4ext::ScriptingFunction_t<void*>;
    add("NcmBroadcast_LabelCount", reinterpret_cast<F>(&labelCount), "Int32", {});
    add("NcmBroadcast_LabelEntity", reinterpret_cast<F>(&labelEntity), "entEntityID", {{"Int32", "index"}});
    add("NcmBroadcast_LabelText", reinterpret_cast<F>(&labelText), "String", {{"Int32", "index"}});
    add("NcmBroadcast_Tower", reinterpret_cast<F>(&tower), "String", {});
    add("NcmBroadcast_TowerRow", reinterpret_cast<F>(&towerRow), "String", {{"Int32", "index"}});
    add("NcmBroadcast_View", reinterpret_cast<F>(&view), "String", {});
    add("NcmBroadcast_Log", reinterpret_cast<F>(&note), "Bool", {{"String", "text"}});
    BCAST_INFO("redscript natives registered");
}
}

void registerNatives()
{
    if (auto* system = RED4ext::CRTTISystem::Get()) {
        system->AddRegisterCallback(registerTypes);
        system->AddPostRegisterCallback(postRegister);
    } else {
        BCAST_ERR("RTTI unavailable while registering natives");
    }
}
}
