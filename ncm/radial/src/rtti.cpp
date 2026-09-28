#include "rtti.hpp"

#include "log.hpp"
#include "state.hpp"

#include <RED4ext/RED4ext.hpp>

// The three natives `redscript/ncm_radial.reds` declares. Strings, not structs: a delimited string is one
// native call per tick and cannot drift out of step with a struct layout declared twice.
namespace ncm::radial::rtti {
namespace {
using Flags = RED4ext::CBaseFunction::Flags;

void frame(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    stack->code++;
    if (out) *out = RED4ext::CString(state().frame().c_str());
}

void layout(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    stack->code++;
    if (out) *out = RED4ext::CString(state().layout().c_str());
}

void reportHost(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    RED4ext::CString host;
    int32_t drawn = 0;
    RED4ext::GetParameter(stack, &host);
    RED4ext::GetParameter(stack, &drawn);
    stack->code++;
    state().reportHost(host.c_str(), drawn);
    RADIAL_INFO("host=%s drawn=%d", host.c_str(), drawn);
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
    add("NcmRadial_Frame", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&frame), "String", {});
    add("NcmRadial_Layout", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&layout), "String", {});
    add("NcmRadial_ReportHost", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&reportHost), "Bool",
        {{"String", "host"}, {"Int32", "drawn"}});
    RADIAL_INFO("redscript natives registered");
}
}

void registerNatives()
{
    if (auto* system = RED4ext::CRTTISystem::Get()) {
        system->AddRegisterCallback(registerTypes);
        system->AddPostRegisterCallback(postRegister);
    } else {
        RADIAL_ERR("RTTI unavailable while registering natives");
    }
}
}
