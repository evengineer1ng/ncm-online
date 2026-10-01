#include "rtti.hpp"

#include "log.hpp"
#include "state.hpp"

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/ResourceLoader.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/EntityID.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/TrafficPersistentResource.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/StreamingWorld.hpp>

#include <array>
#include <cstring>
#include <shared_mutex>
#include <windows.h>

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

// 0.7.0 (L246): the race spline car `index` is on, as the NodeRef AIVehicleRacingCommand.splineRef takes. A NodeRef is
// one 64-bit hash, so it is written straight into the result.
void spline(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, uint64_t* out, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(stack, &index);
    stack->code++;
    if (out) *out = state().spline(index);
}

// 0.7.5: the NodeRef for any node path, hashed as Pace hashes its race splines -- so a vanilla spline can be probed
// by its path as a control (KB-249).
void nodeRef(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, uint64_t* out, int64_t)
{
    RED4ext::CString path;
    RED4ext::GetParameter(stack, &path);
    stack->code++;
    if (out) *out = nodeRefHash(path.c_str());
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

void banner(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    stack->code++;
    if (out) *out = RED4ext::CString(state().banner().c_str());
}

void area(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, RED4ext::CString* out, int64_t)
{
    stack->code++;
    if (out) *out = RED4ext::CString(state().area().c_str());
}

void note(RED4ext::IScriptable*, RED4ext::CStackFrame* stack, bool* out, int64_t)
{
    RED4ext::CString text;
    RED4ext::GetParameter(stack, &text);
    stack->code++;
    // two budgets (0.7.1): the startup TweakDB dump (`tdb:`) has its own, so it can never use up the lines a race needs
    // -- in 0.7.0 its 355 lines spent the shared 300 and every racing-command report of the next race was dropped
    static int logged = 0, dumped = 0;
    const std::string line(text.c_str());
    const bool dump = line.rfind("tdb:", 0) == 0;
    if (dump ? (++dumped <= 600) : (++logged <= 3000)) PACE_INFO("reds: %s", line.substr(0, 300).c_str());
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
    add("NcmPace_Spline", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&spline), "NodeRef", {{"Int32", "index"}});
    add("NcmPace_NodeRef", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&nodeRef), "NodeRef", {{"String", "path"}});
    add("NcmPace_Banner", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&banner), "String", {});
    add("NcmPace_Area", reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(&area), "String", {});
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
// What the engine says the crowd/traffic null-area and density methods take (KB-219): their script signature could not
// be found by compiling guesses, so the plugin reads it from the game's own type information at startup and logs it.
// 0.3.0 calls EnableDynamicCrowdNullArea(Box, WorldTransform, Bool, Float) from NcmPace.reds with exactly that.
void dumpSignatures()
{
    auto* rtti = RED4ext::CRTTISystem::Get();
    if (!rtti) return;
    for (const char* name : {"gameCommunitySystem", "CommunitySystem", "worldTrafficSystem", "gameTrafficSystem"}) {
        RED4ext::CClass* cls = rtti->GetClass(RED4ext::CName(name));
        if (!cls) cls = rtti->GetClassByScriptName(RED4ext::CName(name));
        if (!cls) { PACE_INFO("rtti: no class %s", name); continue; }
        int shown = 0;
        for (auto* fn : cls->funcs) {
            if (!fn) continue;
            const std::string shortName = fn->shortName.ToString();
            if (shortName.find("NullArea") == std::string::npos && shortName.find("Density") == std::string::npos &&
                shortName.find("Traffic") == std::string::npos && shortName.find("Crowd") == std::string::npos) continue;
            std::string sig = shortName + "(";
            bool first = true;
            for (auto* p : fn->params) {
                if (!p) continue;
                if (!first) sig += ", ";
                first = false;
                sig += std::string(p->name.ToString()) + ": " + (p->type ? p->type->GetName().ToString() : "?");
                if (p->flags.isOut) sig += " out";
                if (p->flags.isOptional) sig += " opt";
            }
            sig += ") -> ";
            sig += (fn->returnType && fn->returnType->type) ? fn->returnType->type->GetName().ToString() : "Void";
            PACE_INFO("rtti: %s.%s", name, sig.c_str());
            ++shown;
        }
        PACE_INFO("rtti: %s -- %d matching method(s) of %u", name, shown, static_cast<uint32_t>(cls->funcs.size()));
    }
    // 0.5.3: the engine's own RACING driver, read before it is used. Pace drives with the drive-to-point command; the
    // game also has AIVehicleRacingCommand (what vanilla street races use) and every vehicle record carries a
    // drivingParamsRace profile beside drivingParamsGeneric. Every property of every class in each chain, with its type,
    // and every method of the handler/agent, so the next build binds to what this game build really has.
    for (const char* name : {"AIVehicleRacingCommand", "AIVehicleDriveToPointAutonomousCommand", "AIVehicleOnSplineCommand",
                              "AIVehicleToNodeCommand", "AIVehicleChaseCommand", "AIVehiclePanicCommand",
                              "AIDriveRacingCommandHandler", "AIbehaviorDriveRacingTreeNodeDefinition",
                              "gamedataVehicleDrivingParameters_Record", "gamedataDriving_Record", "AIVehicleAgent"}) {
        RED4ext::CClass* cls = rtti->GetClass(RED4ext::CName(name));
        if (!cls) cls = rtti->GetClassByScriptName(RED4ext::CName(name));
        if (!cls) { PACE_INFO("race-rtti: no class %s", name); continue; }
        for (RED4ext::CClass* c = cls; c; c = c->parent) {
            for (auto* prop : c->props) if (prop)
                PACE_INFO("race-rtti: %s <%s> prop %s: %s", name, c->GetName().ToString(), prop->name.ToString(),
                          prop->type ? prop->type->GetName().ToString() : "?");
            if (std::string(c->GetName().ToString()) == "IScriptable") break;
        }
        int shown = 0;
        for (auto* fn : cls->funcs) {
            if (!fn) continue;
            std::string sig = std::string(fn->shortName.ToString()) + "(";
            bool first = true;
            for (auto* p : fn->params) {
                if (!p) continue;
                if (!first) sig += ", ";
                first = false;
                sig += std::string(p->name.ToString()) + ": " + (p->type ? p->type->GetName().ToString() : "?");
            }
            sig += ") -> ";
            sig += (fn->returnType && fn->returnType->type) ? fn->returnType->type->GetName().ToString() : "Void";
            PACE_INFO("race-rtti: %s method %s", name, sig.c_str());
            if (++shown >= 80) break;
        }
    }
    // Engine route probe: discover callable GPS/traffic path methods in the running game build before
    // binding Pace to any of them. The in-world navigation mod reads the player's minimap polyline via
    // a build-specific hook; Pace needs a route request for arbitrary race legs instead.
    for (const char* name : {"gamegpsGPSSystem", "gamegpsIGPSSystem", "gameuiMinimapContainerController",
                              "worldITrafficSystem", "navRuntimeSystemPathfinding", "worldNavigationScriptInterface",
                              "AIVehicleAgent"}) {
        RED4ext::CClass* cls = rtti->GetClass(RED4ext::CName(name));
        if (!cls) cls = rtti->GetClassByScriptName(RED4ext::CName(name));
        if (!cls) { PACE_INFO("route-rtti: no class %s", name); continue; }
        int shown = 0;
        for (auto* fn : cls->funcs) {
            if (!fn) continue;
            const std::string shortName = fn->shortName.ToString();
            if (shortName.find("Path") == std::string::npos && shortName.find("Route") == std::string::npos &&
                shortName.find("GPS") == std::string::npos && shortName.find("Lane") == std::string::npos &&
                shortName.find("Navigation") == std::string::npos) continue;
            std::string sig = shortName + "(";
            bool first = true;
            for (auto* p : fn->params) {
                if (!p) continue;
                if (!first) sig += ", ";
                first = false;
                sig += std::string(p->name.ToString()) + ": " + (p->type ? p->type->GetName().ToString() : "?");
                if (p->flags.isOut) sig += " out";
                if (p->flags.isOptional) sig += " opt";
            }
            sig += ") -> ";
            sig += (fn->returnType && fn->returnType->type) ? fn->returnType->type->GetName().ToString() : "Void";
            PACE_INFO("route-rtti: %s.%s", name, sig.c_str());
            ++shown;
        }
        PACE_INFO("route-rtti: %s -- %d matching method(s) of %u", name, shown, static_cast<uint32_t>(cls->funcs.size()));
    }
}

// Dev-only, read-only resource probe. This is invoked by the Running update only when the local
// probe_traffic.flag marker exists beside the DLL. It copies a few primitive values while holding
// the loader's shared lock and never retains engine pointers across frames.
bool probeTrafficResources()
{
    // These depot paths are referenced by the installed 03_night_city.streamingworld.
    // Request all three; cooked lane metadata stores outlines and edges in separate resources.
    static constexpr const char* paths[] = {
        "base\\worlds\\03_night_city\\sectors\\_generated\\traffic\\all.traffic_persistent",
        "base\\worlds\\03_night_city\\sectors\\_generated\\traffic\\all.lane_connections",
        "base\\worlds\\03_night_city\\sectors\\_generated\\traffic\\all.lane_polygons"
    };
    static RED4ext::SharedPtr<RED4ext::ResourceToken<>> direct[3];
    auto* directLoader = RED4ext::ResourceLoader::Get();
    if (!directLoader) { PACE_INFO("traffic-direct: no loader"); return false; }
    bool complete = true;
    for (size_t i = 0; i < 3; ++i) {
        if (!direct[i]) {
            direct[i] = directLoader->LoadAsync(RED4ext::ResourcePath(paths[i]));
            PACE_INFO("traffic-direct: request %zu path=%s token=%d", i, paths[i], direct[i] ? 1 : 0);
        }
        if (!direct[i] || (!direct[i]->IsLoaded() && !direct[i]->IsFailed())) { complete = false; continue; }
        auto* resource = direct[i]->IsLoaded() ? direct[i]->Get().GetPtr() : nullptr;
        PACE_INFO("traffic-direct: %zu loaded=%d failed=%d class=%s", i,
                  direct[i]->IsLoaded() ? 1 : 0, direct[i]->IsFailed() ? 1 : 0,
                  resource && resource->GetType() ? resource->GetType()->name.ToString() : "null");
        if (i == 0 && resource) {
            auto* road = static_cast<RED4ext::world::TrafficPersistentResource*>(resource);
            PACE_INFO("traffic-direct: persistent lanes=%u first-outline=%u first-out=%u",
                      static_cast<unsigned>(road->data.lanes.size()),
                      road->data.lanes.size() ? static_cast<unsigned>(road->data.lanes[0].outline.size()) : 0,
                      road->data.lanes.size() ? static_cast<unsigned>(road->data.lanes[0].outLanes.size()) : 0);
        }
        if (resource && i > 0) {
            auto* cls = resource->GetType();
            for (auto* prop : cls->props) if (prop)
                PACE_INFO("traffic-direct: %zu property=%s offset=%u type=%s", i,
                          prop->name.ToString(), prop->valueOffset,
                          prop->type ? prop->type->GetName().ToString() : "null");
            const auto* bytes = reinterpret_cast<const uint8_t*>(resource);
            for (size_t at = 0x40; at < 0x70; at += 16) {
                uint64_t low = 0, high = 0;
                std::memcpy(&low, bytes + at, sizeof(low));
                std::memcpy(&high, bytes + at + 8, sizeof(high));
                PACE_INFO("traffic-direct: %zu memory+%02zx=%016llx %016llx", i, at,
                          static_cast<unsigned long long>(low), static_cast<unsigned long long>(high));
            }
            for (size_t at : {size_t(0x40), size_t(0x50)}) {
                uintptr_t pointer = 0;
                std::memcpy(&pointer, bytes + at, sizeof(pointer));
                MEMORY_BASIC_INFORMATION region{};
                const bool readable = pointer && VirtualQuery(reinterpret_cast<const void*>(pointer), &region, sizeof(region)) == sizeof(region) &&
                    region.State == MEM_COMMIT && (region.Protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) &&
                    pointer + 64 <= reinterpret_cast<uintptr_t>(region.BaseAddress) + region.RegionSize;
                PACE_INFO("traffic-direct: %zu array+%02zx ptr=%llx readable=%d", i, at,
                          static_cast<unsigned long long>(pointer), readable ? 1 : 0);
                if (!readable) continue;
                for (size_t offset = 0; offset < 64; offset += 16) {
                    uint64_t low = 0, high = 0;
                    std::memcpy(&low, reinterpret_cast<const uint8_t*>(pointer) + offset, sizeof(low));
                    std::memcpy(&high, reinterpret_cast<const uint8_t*>(pointer) + offset + 8, sizeof(high));
                    PACE_INFO("traffic-direct: %zu array+%02zx data+%02zx=%016llx %016llx", i, at, offset,
                              static_cast<unsigned long long>(low), static_cast<unsigned long long>(high));
                }
            }
        }
    }
    if (complete) return true;
    static RED4ext::ResourcePath trafficPath;
    static RED4ext::SharedPtr<RED4ext::ResourceToken<>> requested;
    auto* loader = RED4ext::ResourceLoader::Get();
    auto* rtti = RED4ext::CRTTISystem::Get();
    auto* wanted = rtti ? rtti->GetClass(RED4ext::CName("worldTrafficPersistentResource")) : nullptr;
    auto* worldClass = rtti ? rtti->GetClass(RED4ext::CName("worldStreamingWorld")) : nullptr;
    if (!loader || !wanted || !worldClass) {
        PACE_INFO("traffic-resource: loader=%d class=%d worldClass=%d",
                  loader ? 1 : 0, wanted ? 1 : 0, worldClass ? 1 : 0);
        return false;
    }
    struct Sample { uint32_t lane = 0, points = 0, out = 0, edge[3]{}; float x = 0, y = 0, z = 0; };
    std::array<Sample, 8> samples{};
    uint32_t tokens = 0, loaded = 0, matched = 0, worlds = 0, lanes = 0;
    uint64_t path = 0;
    {
        std::shared_lock lock(loader->tokenLock);
        loader->tokens.ForEach([&](const RED4ext::ResourcePath& key,
                                   RED4ext::WeakPtr<RED4ext::ResourceToken<>>& weak) {
            ++tokens;
            auto token = weak.Lock();
            if (!token || !token->IsLoaded()) return;
            auto* resource = token->Get().GetPtr();
            if (!resource) return;
            ++loaded;
            if (resource->GetType() == worldClass) {
                ++worlds;
                auto* world = static_cast<RED4ext::world::StreamingWorld*>(resource);
                if (trafficPath.IsEmpty()) trafficPath = world->trafficPersistentResource.path;
            }
            if (resource->GetType() != wanted) return;
            ++matched;
            path = key.hash;
            auto* road = static_cast<RED4ext::world::TrafficPersistentResource*>(resource);
            lanes = static_cast<uint32_t>(road->data.lanes.size());
            for (uint32_t i = 0, n = 0; i < lanes && n < samples.size(); ++i) {
                const auto& lane = road->data.lanes[i];
                if (lane.outline.size() == 0) continue;
                const auto& p = lane.outline[0];
                Sample sample{};
                sample.lane = i; sample.points = static_cast<uint32_t>(lane.outline.size());
                sample.out = static_cast<uint32_t>(lane.outLanes.size());
                sample.x = p.X; sample.y = p.Y; sample.z = p.Z;
                if (sample.out) std::memcpy(sample.edge, lane.outLanes[0].unk00, sizeof(sample.edge));
                samples[n++] = sample;
            }
        });
    }
    if (!trafficPath.IsEmpty() && !requested) {
        requested = loader->LoadAsync(trafficPath);
        PACE_INFO("traffic-resource: requested async path=%llu", static_cast<unsigned long long>(trafficPath.hash));
    }
    if (requested && requested->IsLoaded()) {
        auto* resource = requested->Get().GetPtr();
        if (resource && resource->GetType() == wanted) {
            auto* road = static_cast<RED4ext::world::TrafficPersistentResource*>(resource);
            matched = 1;
            path = trafficPath.hash;
            lanes = static_cast<uint32_t>(road->data.lanes.size());
            for (uint32_t i = 0, n = 0; i < lanes && n < samples.size(); ++i) {
                const auto& lane = road->data.lanes[i];
                if (lane.outline.size() == 0) continue;
                const auto& p = lane.outline[0];
                Sample sample{};
                sample.lane = i; sample.points = static_cast<uint32_t>(lane.outline.size());
                sample.out = static_cast<uint32_t>(lane.outLanes.size());
                sample.x = p.X; sample.y = p.Y; sample.z = p.Z;
                if (sample.out) std::memcpy(sample.edge, lane.outLanes[0].unk00, sizeof(sample.edge));
                samples[n++] = sample;
            }
        }
    }
    PACE_INFO("traffic-resource: tokens=%u loaded=%u worlds=%u matched=%u lanes=%u path=%llu target=%llu request=%d failed=%d",
              tokens, loaded, worlds, matched, lanes, static_cast<unsigned long long>(path),
              static_cast<unsigned long long>(trafficPath.hash), requested ? 1 : 0,
              requested && requested->IsFailed() ? 1 : 0);
    for (const auto& s : samples) if (s.points)
        PACE_INFO("traffic-resource: lane=%u points=%u out=%u first=(%.1f,%.1f,%.1f) edge=%08x/%08x/%08x",
                  s.lane, s.points, s.out, s.x, s.y, s.z, s.edge[0], s.edge[1], s.edge[2]);
    return matched > 0;
}
}
