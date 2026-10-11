#include "rtti.hpp"

#include "log.hpp"
#include "state.hpp"

#include <RED4ext/GameEngine.hpp>
#include <RED4ext/RED4ext.hpp>
#include <RED4ext/ResourceReference.hpp>
#include <RED4ext/Scripting/CProperty.hpp>
#include <RED4ext/Scripting/Natives/Generated/Quaternion.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector4.hpp>
#include <RED4ext/Scripting/Natives/Generated/WorldTransform.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/EntityID.hpp>

#include <cmath>

// The natives `NcmSkyNatives.reds` declares. Script -> native only, polled: native code must never call a scripted
// function (doing so without a script frame terminates the process).
//
// SPAWN / DESPAWN: vanilla redscript has no general entity spawner. KB-440 (2026-10-10): the first live Deep stay logged
// "exEntitySpawner.Spawn: not found in RTTI" -- that class is CET's, and CET's RTTI additions are not there under Open77
// -- so nothing was ever spawned and the player saw the game's own sky. The spawn now goes through Codeware's
// DynamicEntitySystem when it is loaded (alwaysSpawned: a dome 17 km off the map streams in regardless), reached
// through RTTI so the redscript side stays vanilla-only; exEntitySpawner stays as the fallback. Both are called
// from INSIDE a script call, so on the game thread with a frame. The orientation is left to the caller: the script
// spawns at identity and turns the body with the game's TeleportationFacility, so one Euler convention is in play.
namespace ncm::sky::rtti {
namespace {
using Flags = RED4ext::CBaseFunction::Flags;

// The spawner's static functions, looked up once and described in the log (so a game update that changes them is a
// log line, not a crash).
RED4ext::CBaseFunction* staticFunction(const char* cls, const char* name)
{
    auto* rtti = RED4ext::CRTTISystem::Get();
    auto* c = rtti ? rtti->GetClass(cls) : nullptr;
    if (!c) return nullptr;
    for (auto* f : c->staticFuncs) {
        if (f && f->shortName == RED4ext::CName(name)) return f;
    }
    return nullptr;
}

void describe(RED4ext::CBaseFunction* f, const char* label)
{
    static int told = 0;
    if (told++ > 4) return;
    if (!f) { SKY_ERR("%s: not found in RTTI; nothing can be spawned", label); return; }
    std::string params;
    for (auto* p : f->params) {
        if (!params.empty()) params += ", ";
        params += p && p->type ? p->type->GetName().ToString() : "?";
    }
    SKY_INFO("%s(%s) -> %s", label, params.c_str(), f->returnType && f->returnType->type ? f->returnType->type->GetName().ToString() : "void");
}

// ---- Codeware's DynamicEntitySystem (when loaded)
RED4ext::IScriptable* dynamicEntitySystem(RED4ext::CClass*& cls)
{
    auto* rtti = RED4ext::CRTTISystem::Get();
    cls = rtti ? rtti->GetClass("DynamicEntitySystem") : nullptr;
    auto* engine = RED4ext::CGameEngine::Get();
    if (!cls || !engine || !engine->framework || !engine->framework->gameInstance) return nullptr;
    return engine->framework->gameInstance->GetSystem(cls);
}

template <typename T>
bool setProp(RED4ext::CClass* cls, void* inst, const char* name, const T& v)
{
    auto* p = cls->GetProperty(RED4ext::CName(name));
    if (!p || !p->type || p->type->GetSize() != sizeof(T)) return false;
    p->SetValue<T>(inst, v);
    return true;
}

bool codewareSpawn(const RED4ext::CString& tmpl, const RED4ext::CString& app, float x, float y, float z, RED4ext::ent::EntityID& id)
{
    static int told = 0;
    RED4ext::CClass* sysCls = nullptr;
    auto* sys = dynamicEntitySystem(sysCls);
    auto* rtti = RED4ext::CRTTISystem::Get();
    auto* specCls = rtti ? rtti->GetClass("DynamicEntitySpec") : nullptr;
    auto* create = sysCls ? sysCls->GetFunction(RED4ext::CName("CreateEntity")) : nullptr;
    if (!sys || !specCls || !create) {
        if (told++ < 3) SKY_INFO("Codeware DynamicEntitySystem not available (system %s, spec %s, CreateEntity %s)", sys ? "yes" : "no",
                                 specCls ? "yes" : "no", create ? "yes" : "no");
        return false;
    }
    auto* inst = static_cast<RED4ext::IScriptable*>(specCls->CreateInstance());   // constructed: the spec's own defaults
    if (!inst) return false;
    RED4ext::Handle<RED4ext::IScriptable> spec(inst);
    RED4ext::ResourcePath path(tmpl.c_str());
    RED4ext::Vector4 pos{x, y, z, 1.0f};
    RED4ext::Quaternion q{0.0f, 0.0f, 0.0f, 1.0f};
    const bool okPath = setProp(specCls, inst, "templatePath", path);
    setProp(specCls, inst, "position", pos);
    setProp(specCls, inst, "orientation", q);
    if (app.Length() > 0) setProp(specCls, inst, "appearanceName", RED4ext::CName(app.c_str()));
    setProp(specCls, inst, "alwaysSpawned", true);
    setProp(specCls, inst, "persistState", false);
    setProp(specCls, inst, "persistSpawn", false);
    setProp(specCls, inst, "active", true);
    setProp(specCls, inst, "spawnInView", true);
    if (!okPath) { SKY_ERR("DynamicEntitySpec.templatePath not settable; Codeware spawn skipped"); return false; }
    RED4ext::StackArgs_t args;
    args.emplace_back(nullptr, &spec);
    if (!RED4ext::ExecuteFunction(sys, create, &id, args)) { SKY_ERR("DynamicEntitySystem.CreateEntity refused %s", tmpl.c_str()); return false; }
    if (told++ < 6) SKY_INFO("spawned %s through Codeware (entity %llu)", tmpl.c_str(), static_cast<unsigned long long>(id.hash));
    return id.hash != 0;
}

bool codewareDespawn(RED4ext::Handle<RED4ext::IScriptable>& entity)
{
    RED4ext::CClass* sysCls = nullptr;
    auto* sys = dynamicEntitySystem(sysCls);
    auto* del = sysCls ? sysCls->GetFunction(RED4ext::CName("DeleteEntity")) : nullptr;
    auto* entCls = entity ? entity->GetType() : nullptr;
    auto* getId = entCls ? entCls->GetFunction(RED4ext::CName("GetEntityID")) : nullptr;
    if (!sys || !del || !getId) return false;
    RED4ext::ent::EntityID id{};
    if (!RED4ext::ExecuteFunction(entity.instance, getId, &id) || id.hash == 0) return false;
    bool ok = false;
    RED4ext::StackArgs_t args;
    args.emplace_back(nullptr, &id);
    return RED4ext::ExecuteFunction(sys, del, &ok, args) && ok;
}

void spawn(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::ent::EntityID* out, int64_t)
{
    RED4ext::CString tmpl;
    RED4ext::CString app;
    float x = 0.0f, y = 0.0f, z = 0.0f;
    RED4ext::GetParameter(stack, &tmpl);
    RED4ext::GetParameter(stack, &app);
    RED4ext::GetParameter(stack, &x);
    RED4ext::GetParameter(stack, &y);
    RED4ext::GetParameter(stack, &z);
    stack->code++;
    RED4ext::ent::EntityID id{};
    if (codewareSpawn(tmpl, app, x, y, z, id)) { if (out) *out = id; return; }
    static auto* fn = staticFunction("exEntitySpawner", "Spawn");
    static bool described = (describe(fn, "exEntitySpawner.Spawn"), true);
    (void)described;
    if (fn && fn->params.size() >= 2) {
        RED4ext::WorldTransform t{};
        t.Position.x.Bits = static_cast<int32_t>(std::lround(static_cast<double>(x) * 131072.0));
        t.Position.y.Bits = static_cast<int32_t>(std::lround(static_cast<double>(y) * 131072.0));
        t.Position.z.Bits = static_cast<int32_t>(std::lround(static_cast<double>(z) * 131072.0));
        t.Orientation.i = 0.0f; t.Orientation.j = 0.0f; t.Orientation.k = 0.0f; t.Orientation.r = 1.0f;
        RED4ext::ResourceAsyncReference<> ref(RED4ext::ResourcePath(tmpl.c_str()));
        RED4ext::CName appearance(app.c_str());
        RED4ext::TweakDBID record{};
        RED4ext::StackArgs_t args;
        args.emplace_back(nullptr, &ref);
        args.emplace_back(nullptr, &t);
        if (fn->params.size() >= 3) args.emplace_back(nullptr, &appearance);
        if (fn->params.size() >= 4) args.emplace_back(nullptr, &record);
        if (!RED4ext::ExecuteFunction(RED4ext::CName("exEntitySpawner"), RED4ext::CName("Spawn"), &id, args))
            SKY_ERR("exEntitySpawner.Spawn refused %s", tmpl.c_str());
    }
    if (out) *out = id;
}

void despawn(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    RED4ext::Handle<RED4ext::IScriptable> entity;
    RED4ext::GetParameter(stack, &entity);
    stack->code++;
    if (entity && codewareDespawn(entity)) { if (out) *out = true; return; }
    static auto* fn = staticFunction("exEntitySpawner", "Despawn");
    static bool described = (describe(fn, "exEntitySpawner.Despawn"), true);
    (void)described;
    bool ok = false;
    if (fn && entity) {
        RED4ext::StackArgs_t args;
        args.emplace_back(nullptr, &entity);
        ok = RED4ext::ExecuteFunction(RED4ext::CName("exEntitySpawner"), RED4ext::CName("Despawn"), nullptr, args);
    }
    if (out) *out = ok;
}

void scene(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    stack->code++;
    if (out) *out = RED4ext::CString(state().scene().c_str());
}

void report(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    RED4ext::CString id;
    int32_t value = 0;
    uint64_t entity = 0;
    RED4ext::CString why;
    RED4ext::GetParameter(stack, &id);
    RED4ext::GetParameter(stack, &value);
    RED4ext::GetParameter(stack, &entity);
    RED4ext::GetParameter(stack, &why);
    stack->code++;
    state().report(id.c_str(), value, entity, why.c_str());
    static int count = 0;
    if (value == 3 || ++count <= 40) SKY_INFO("body %s -> %d entity=%llu %s", id.c_str(), value, static_cast<unsigned long long>(entity), why.c_str());
    if (out) *out = true;
}

void note(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    RED4ext::CString text;
    RED4ext::GetParameter(stack, &text);
    stack->code++;
    static int count = 0;
    if (++count <= 400) SKY_INFO("reds: %s", std::string(text.c_str()).substr(0, 300).c_str());
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
    add("NcmSky_Scene", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&scene), "String", {});
    add("NcmSky_Report", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&report), "Bool",
        {{"String", "id"}, {"Int32", "state"}, {"Uint64", "entity"}, {"String", "why"}});
    add("NcmSky_Log", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&note), "Bool", {{"String", "text"}});
    add("NcmSky_Spawn", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&spawn), "entEntityID",
        {{"String", "template"}, {"String", "appearance"}, {"Float", "x"}, {"Float", "y"}, {"Float", "z"}});
    add("NcmSky_Despawn", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&despawn), "Bool", {{"handle:entEntity", "entity"}});
    SKY_INFO("redscript natives registered");
}
}

void registerNatives()
{
    if (auto* system = RED4ext::CRTTISystem::Get()) {
        system->AddRegisterCallback(registerTypes);
        system->AddPostRegisterCallback(postRegister);
    } else {
        SKY_ERR("RTTI unavailable while registering natives");
    }
}
}
