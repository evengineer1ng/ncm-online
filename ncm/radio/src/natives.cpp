#include "natives.hpp"

#include "log.hpp"
#include "player.hpp"

#include <RED4ext/RED4ext.hpp>

#include <windows.h>

#include <fstream>

// The natives `NcmRadioNatives.reds` declares. Script -> native only, polled from the station's own tick: native code
// never calls a scripted function. Globals, never inside a redscript `module` (KB-182).
namespace ncm::radio::natives {
namespace {
using Flags = RED4ext::CBaseFunction::Flags;
Player* player = nullptr;
std::wstring prefsPath;

// listening + volume in, the current beat out; doubles as the heartbeat that keeps the station audible
void tick(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    bool listening = false;
    float volume = 0.8f;
    RED4ext::GetParameter(stack, &listening);
    RED4ext::GetParameter(stack, &volume);
    stack->code++;
    std::string beat;
    if (player) {
        player->heartbeat(listening, volume);
        beat = player->status();
    }
    if (out) *out = RED4ext::CString(beat.c_str());
}

// "ncm" (default: Race Week Live is on), "other" (the player picked another station; never override that)
void pref(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    stack->code++;
    std::string value = "ncm";
    std::ifstream in(prefsPath);
    if (in) {
        std::string line;
        std::getline(in, line);
        if (line == "other" || line == "ncm") value = line;
    }
    if (out) *out = RED4ext::CString(value.c_str());
}

void setPref(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    RED4ext::CString value;
    RED4ext::GetParameter(stack, &value);
    stack->code++;
    const std::string v(value.c_str());
    bool ok = false;
    if (v == "ncm" || v == "other") {
        std::ofstream o(prefsPath, std::ios::trunc);
        o << v << "\n";
        ok = static_cast<bool>(o);
        RADIO_INFO("station preference: %s", v.c_str());
    }
    if (out) *out = ok;
}

void note(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    RED4ext::CString text;
    RED4ext::GetParameter(stack, &text);
    stack->code++;
    static int logged = 0;
    if (++logged <= 2000) RADIO_INFO("reds: %.300s", text.c_str());
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
    add("NcmRadio_Tick", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&tick), "String",
        {{"Bool", "listening"}, {"Float", "volume"}});
    add("NcmRadio_Pref", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&pref), "String", {});
    add("NcmRadio_SetPref", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&setPref), "Bool", {{"String", "value"}});
    add("NcmRadio_Log", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&note), "Bool", {{"String", "text"}});
    RADIO_INFO("redscript natives registered");
}
}

void attach(Player* p, const std::wstring& directory)
{
    player = p;
    prefsPath = directory + L"\\prefs.txt";
}

void registerNatives()
{
    if (auto* system = RED4ext::CRTTISystem::Get()) {
        system->AddRegisterCallback(registerTypes);
        system->AddPostRegisterCallback(postRegister);
    } else {
        RADIO_ERR("RTTI unavailable while registering natives");
    }
}
}
