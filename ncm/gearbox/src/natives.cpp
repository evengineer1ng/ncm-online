// NCM Gearbox -- the natives `NcmGearboxNatives.reds` declares (phase 3a). Script -> native only, called from the
// redscript tick in a script frame; native code never calls script. Registered as GLOBAL functions: the .reds file
// that declares them must never declare a `module` (KB-182 -- RED4ext would refuse to start the game).
#include "natives.hpp"

#include "discover.hpp"
#include "manual.hpp"
#include "log.hpp"

#include <RED4ext/RED4ext.hpp>

namespace ncm::gearbox::natives {
namespace {
using Flags = RED4ext::CBaseFunction::Flags;

RED4ext::IScriptable* vehicleParam(RED4ext::CStackFrame* frame)
{
    RED4ext::Handle<RED4ext::ISerializable> handle;
    RED4ext::GetParameter(frame, &handle);
    return static_cast<RED4ext::IScriptable*>(handle.instance);
}

// NcmGearbox_Observe(vehicle, hudGear, hudRpm, speed) -> Bool: observe the player's car; true when the S2 hold
// experiment wrote this tick.
void observe(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, bool* out, int64_t)
{
    RED4ext::IScriptable* vehicle = vehicleParam(frame);
    int32_t gear = 0;
    float rpm = 0.0f, speed = 0.0f;
    RED4ext::GetParameter(frame, &gear);
    RED4ext::GetParameter(frame, &rpm);
    RED4ext::GetParameter(frame, &speed);
    frame->code++;
    bool wrote = false;
    try {
        discover::pollConfig();
        manual::trace(rpm, speed);
        discover::observe(vehicle, gear, rpm, speed);
        wrote = discover::hold(vehicle);
    } catch (...) {
        static bool warned = false;
        if (!warned) { warned = true; GBX_ERR("observe threw; continuing"); }
    }
    if (out) *out = wrote;
}

// NcmGearbox_Drive(record, hudGear, speed) -> Int32: one frame of the manual. The virtual gear (0 = N), or -2 when
// this car is not a manual clone.
void drive(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, int32_t* out, int64_t)
{
    uint64_t record = 0;
    int32_t hud = 0;
    float speed = 0.0f;
    RED4ext::GetParameter(frame, &record);
    RED4ext::GetParameter(frame, &hud);
    RED4ext::GetParameter(frame, &speed);
    frame->code++;
    int32_t gear = -2;
    try { gear = manual::tick(record, speed, hud); } catch (...) {}
    if (out) *out = gear;
}

void rpm(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, float* out, int64_t)
{
    frame->code++;
    if (out) *out = manual::rpm();
}

void engineAudioValue(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, float* out, int64_t)
{
    frame->code++;
    if (out) *out = manual::engineAudioValue();
}

void rpmFraction(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, float* out, int64_t)
{
    frame->code++;
    if (out) *out = manual::rpmFraction();
}

void displayGear(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, int32_t* out, int64_t)
{
    int32_t native = 0;
    RED4ext::GetParameter(frame, &native);
    frame->code++;
    if (out) *out = manual::displayGear(native);
}

void displayRpm(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, float* out, int64_t)
{
    float native = 0.0f;
    RED4ext::GetParameter(frame, &native);
    frame->code++;
    if (out) *out = manual::displayRpm(native);
}

// NcmGearbox_DashSpeed(value) -> Bool: the vehicle blackboard's SpeedValue (the car's own dash), for the trace.
void dashSpeed(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, bool* out, int64_t)
{
    float value = 0.0f;
    RED4ext::GetParameter(frame, &value);
    frame->code++;
    manual::noteDashSpeed(value);
    if (out) *out = true;
}

void audioDetail(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, RED4ext::CString* out, int64_t)
{
    frame->code++;
    if (out) *out = RED4ext::CString(manual::audioDetail().c_str());
}

void audioMode(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, RED4ext::CString* out, int64_t)
{
    frame->code++;
    if (out) *out = RED4ext::CString(manual::audioMode().c_str());
}

void audioName(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, RED4ext::CString* out, int64_t)
{
    frame->code++;
    if (out) *out = RED4ext::CString(manual::audioName().c_str());
}

void engineAudio(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, bool* out, int64_t)
{
    frame->code++;
    if (out) *out = manual::engineAudio();
}

void shiftEvent(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, int32_t* out, int64_t)
{
    frame->code++;
    if (out) *out = manual::shiftEvent();
}

void left(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, bool* out, int64_t)
{
    frame->code++;
    try { manual::leave(); } catch (...) {}
    try { discover::leftCar(); } catch (...) {}
    if (out) *out = true;
}

void status(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, RED4ext::CString* out, int64_t)
{
    frame->code++;
    if (out) *out = RED4ext::CString(discover::status().c_str());
}

void note(RED4ext::IScriptable*, RED4ext::CStackFrame* frame, bool* out, int64_t)
{
    RED4ext::CString text;
    RED4ext::GetParameter(frame, &text);
    frame->code++;
    static int logged = 0;
    if (++logged <= 500) GBX_INFO("reds: %s", std::string(text.c_str()).substr(0, 300).c_str());
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
    add("NcmGearbox_Observe", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&observe), "Bool",
        {{"handle:vehicleBaseObject", "vehicle"}, {"Int32", "hudGear"}, {"Float", "hudRpm"}, {"Float", "speed"}});
    add("NcmGearbox_Drive", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&drive), "Int32",
        {{"Uint64", "record"}, {"Int32", "hudGear"}, {"Float", "speed"}});
    add("NcmGearbox_Rpm", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&rpm), "Float", {});
    add("NcmGearbox_EngineAudioValue", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&engineAudioValue), "Float", {});
    add("NcmGearbox_RpmFraction", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&rpmFraction), "Float", {});
    add("NcmGearbox_DisplayGear", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&displayGear), "Int32", {{"Int32", "value"}});
    add("NcmGearbox_DisplayRpm", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&displayRpm), "Float", {{"Float", "value"}});
    add("NcmGearbox_DashSpeed", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&dashSpeed), "Bool", {{"Float", "value"}});
    add("NcmGearbox_AudioDetail", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&audioDetail), "String", {});
    add("NcmGearbox_AudioMode", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&audioMode), "String", {});
    add("NcmGearbox_AudioName", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&audioName), "String", {});
    add("NcmGearbox_EngineAudio", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&engineAudio), "Bool", {});
    add("NcmGearbox_ShiftEvent", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&shiftEvent), "Int32", {});
    add("NcmGearbox_Left", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&left), "Bool", {});
    add("NcmGearbox_Status", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&status), "String", {});
    add("NcmGearbox_Log", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&note), "Bool", {{"String", "text"}});
    GBX_INFO("redscript natives registered");
}
}  // namespace

void registerNatives()
{
    if (auto* system = RED4ext::CRTTISystem::Get()) {
        system->AddRegisterCallback(registerTypes);
        system->AddPostRegisterCallback(postRegister);
    } else {
        GBX_ERR("RTTI unavailable while registering natives");
    }
}

}  // namespace ncm::gearbox::natives
