// NCM Snowglobe -- the natives NcmSnowglobeNatives.reds declares. Script -> native only. Registered as GLOBAL functions:
// the .reds file that declares them must never declare a `module` (KB-182: RED4ext would refuse to start the game).
#include "log.hpp"
#include "seam.hpp"
#include "seam_levers.hpp"

#include <RED4ext/RED4ext.hpp>

#include <algorithm>
#include <string>

#include <windows.h>

namespace ncm::snowglobe::natives {
namespace {
using Flags = RED4ext::CBaseFunction::Flags;

void poll(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, int32_t* out, int64_t)
{
    frame->code++;
    if (out) *out = seam::consumeRequests();
}

void offset(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, float* out, int64_t)
{
    int32_t axis = 0;
    RED4ext::GetParameter(frame, &axis);
    frame->code++;
    if (out) *out = seam::offset(axis);
}

void minZ(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, float* out, int64_t)
{
    frame->code++;
    if (out) *out = seam::minZ();
}

void watch(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, int32_t* out, int64_t)
{
    frame->code++;
    if (out) *out = seam::watchFrames();
}

void note(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, bool* out, int64_t)
{
    RED4ext::CString text;
    RED4ext::GetParameter(frame, &text);
    frame->code++;
    static int logged = 0;
    if (++logged <= 5000) SNG_INFO("reds: %s", std::string(text.c_str()).substr(0, 400).c_str());
    if (out) *out = true;
}

// SEAM-1c (v2): publish the target velocity for NCM Carrier to restore once the car is bound again. Returns the kick's sequence number, 0 when the block cannot be made.
HANDLE g_kickMapping = nullptr;
ncm::seam_levers::Block* g_kick = nullptr;

/// Made at load, not at the first kick: Carrier looks for the block every 2 s and a kick is stale after 0.5 s, so a
/// block born with its first kick would lose that kick.
void ensureKickBlock()
{
    if (!g_kick) {
        wchar_t name[96];
        ncm::seam_levers::name(name, 96, GetCurrentProcessId());
        g_kickMapping = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, sizeof(ncm::seam_levers::Block), name);
        if (g_kickMapping)
            g_kick = static_cast<ncm::seam_levers::Block*>(MapViewOfFile(g_kickMapping, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(ncm::seam_levers::Block)));
        if (g_kick) {
            g_kick->stampMs = 0;
            g_kick->kickSeq = 0;
            g_kick->magic = ncm::seam_levers::kMagic;
            g_kick->version = ncm::seam_levers::kVersion;
            SNG_INFO("publishing the seam kick lever for NCM Carrier");
        } else {
            SNG_ERR("could not create the seam kick block");
        }
    }
}

void kick(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, int32_t* out, int64_t)
{
    float dv[3] = {0.0f, 0.0f, 0.0f};
    RED4ext::GetParameter(frame, &dv[0]);
    RED4ext::GetParameter(frame, &dv[1]);
    RED4ext::GetParameter(frame, &dv[2]);
    frame->code++;
    int32_t seq = 0;
    ensureKickBlock();
    if (g_kick) {
        for (int i = 0; i < 3; ++i) g_kick->target[i] = std::clamp(dv[i], -400.0f, 400.0f);
        g_kick->stampMs = GetTickCount64();
        g_kick->kickSeq = g_kick->kickSeq + 1;   // last: Carrier never sees a new seq over half-written values
        seq = static_cast<int32_t>(g_kick->kickSeq);
        SNG_INFO("kick #%d published: target velocity (%.2f, %.2f, %.2f) m/s, held up to %llu ms for the binding", seq,
                 g_kick->target[0], g_kick->target[1], g_kick->target[2], static_cast<unsigned long long>(ncm::seam_levers::kHoldMs));
    }
    if (out) *out = seq;
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
    add("NcmSnowglobe_Poll", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&poll), "Int32", {});
    add("NcmSnowglobe_Offset", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&offset), "Float", {{"Int32", "axis"}});
    add("NcmSnowglobe_MinZ", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&minZ), "Float", {});
    add("NcmSnowglobe_WatchFrames", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&watch), "Int32", {});
    add("NcmSnowglobe_Kick", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&kick), "Int32",
        {{"Float", "vx"}, {"Float", "vy"}, {"Float", "vz"}});
    add("NcmSnowglobe_Log", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&note), "Bool", {{"String", "text"}});
    SNG_INFO("redscript natives registered");
}
}  // namespace

void registerNatives()
{
    ensureKickBlock();
    if (auto* system = RED4ext::CRTTISystem::Get()) {
        system->AddRegisterCallback(registerTypes);
        system->AddPostRegisterCallback(postRegister);
    } else {
        SNG_ERR("RTTI unavailable while registering natives");
    }
}

}  // namespace ncm::snowglobe::natives
