#include "rtti.hpp"

#include "log.hpp"
#include "state.hpp"

#include <RED4ext/RED4ext.hpp>

// The natives `NcmScannerReticle.reds` declares. Script -> native only, polled: native code must never call a
// scripted function (doing so without a script frame terminates the process).
namespace ncm::vision::rtti {
namespace {
using Flags = RED4ext::CBaseFunction::Flags;

void reticle(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    stack->code++;
    if (out) *out = RED4ext::CString(state().reticle().c_str());
}

void report(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    bool active = false;
    uint64_t entity = 0;
    uint64_t record = 0;
    int32_t kind = 0;
    float distance = -1.0f;
    RED4ext::GetParameter(stack, &active);
    RED4ext::GetParameter(stack, &entity);
    RED4ext::GetParameter(stack, &record);
    RED4ext::GetParameter(stack, &kind);
    RED4ext::GetParameter(stack, &distance);
    stack->code++;
    state().report(active, entity, record, kind, distance);
    if (out) *out = true;
}

void note(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    RED4ext::CString text;
    RED4ext::GetParameter(stack, &text);
    stack->code++;
    static int count = 0;
    if (++count <= 200) VISION_INFO("reds: %s", clean(text.c_str(), 300).c_str());
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
    add("NcmScanner_Reticle", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&reticle), "String", {});
    add("NcmScanner_Report", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&report), "Bool",
        {{"Bool", "active"}, {"Uint64", "entity"}, {"Uint64", "record"}, {"Int32", "kind"}, {"Float", "distance"}});
    add("NcmScanner_Log", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&note), "Bool", {{"String", "text"}});
    VISION_INFO("redscript natives registered");
}
}

void registerNatives()
{
    if (auto* system = RED4ext::CRTTISystem::Get()) {
        system->AddRegisterCallback(registerTypes);
        system->AddPostRegisterCallback(postRegister);
    } else {
        VISION_ERR("RTTI unavailable while registering natives");
    }
}
}
