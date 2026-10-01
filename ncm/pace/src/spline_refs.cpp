#include "spline_refs.hpp"
#include "log.hpp"
#include "state.hpp"

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/ResourceLoader.hpp>

#include <algorithm>
#include <cstdio>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

// The race splines' NodeRefs AS THE ENGINE HASHED THEM (0.7.2, L246). The first race on splines (22:30) had every
// racing command end in FAILURE at once: the streaming block merged, so either the engine resolves a NodeRef path to a
// different hash than Pace's FNV-1a 64, or the racer refuses for another reason. Instead of guessing the hash, Pace
// loads its own baked sectors through the engine's resource loader and reads, by reflection, each race spline node's
// debugName ({ncm_leg_<from>__<to>}) beside the sector's nodeRefs entry (written in node order), and uses those.
namespace ncm::pace {
namespace {
std::mutex refMutex;
std::unordered_map<std::string, uint64_t> engineRefs;   // "$/mod/ncm_pace/#leg_a__b" -> the engine's NodeRef hash
std::vector<RED4ext::SharedPtr<RED4ext::ResourceToken<>>> tokens;
bool done = false, started = false;
int matched = 0, mismatched = 0;
constexpr int kMaxSectors = 64;

template<typename T> T* field(RED4ext::ISerializable* obj, const char* name)
{
    if (!obj) return nullptr;
    const RED4ext::CName wanted(name);
    for (auto* c = obj->GetType(); c; c = c->parent)          // the whole class chain, not only the leaf
        for (auto* prop : c->props)
            if (prop && prop->name == wanted) return prop->GetValuePtr<T>(obj);
    return nullptr;
}
}

void pollSplineRefs()
{
    if (done) return;
    auto* loader = RED4ext::ResourceLoader::Get();
    if (!loader) return;
    if (!started) {
        started = true;
        for (int i = 0; i < kMaxSectors; ++i) {
            char path[128]{};
            std::snprintf(path, sizeof(path), "mod\\ncm_pace\\race_splines\\legs_%03d.streamingsector", i);
            tokens.push_back(loader->LoadAsync(RED4ext::ResourcePath(path)));
        }
        return;
    }
    for (auto& t : tokens) if (t && !t->IsLoaded() && !t->IsFailed()) return;      // still loading
    int sectors = 0;
    for (auto& t : tokens) {
        if (!t || t->IsFailed() || !t->IsLoaded()) continue;
        auto* sector = t->Get().GetPtr();
        if (!sector) continue;
        ++sectors;
        // 0.7.3: say what the engine's sector type really is and what its properties are called (0.7.2 assumed
        // WolvenKit's names and found neither), then use the ones that hold node refs and nodes
        static bool described = false;
        if (!described) {
            described = true;
            auto* cls = sector->GetType();
            PACE_INFO("spline refs: loaded sector class %s", cls ? cls->GetName().ToString() : "?");
            for (auto* c = cls; c; c = c->parent)
                for (auto* prop : c->props) if (prop)
                    PACE_INFO("spline refs: <%s> %s: %s", c->GetName().ToString(), prop->name.ToString(),
                              prop->type ? prop->type->GetName().ToString() : "?");
        }
        auto* refs = field<RED4ext::DynArray<uint64_t>>(sector, "nodeRefs");
        auto* nodes = field<RED4ext::DynArray<RED4ext::Handle<RED4ext::ISerializable>>>(sector, "nodes");
        if (!refs || !nodes) continue;      // the engine keeps a sector's nodes in packed content, not as properties
        const uint32_t n = std::min<uint32_t>(refs->size(), nodes->size());
        for (uint32_t i = 0; i < n; ++i) {
            auto* node = (*nodes)[i].GetPtr();
            auto* debugName = field<RED4ext::CName>(node, "debugName");
            if (!debugName) continue;
            std::string name = debugName->ToString();          // {ncm_leg_<from>__<to>}
            if (name.size() < 10 || name.rfind("{ncm_leg_", 0) != 0) continue;
            const std::string path = "$/mod/ncm_pace/#leg_" + name.substr(9, name.size() - 10);
            const uint64_t engine = (*refs)[i];
            const uint64_t ours = nodeRefHash(path);
            if (engine == ours) ++matched; else ++mismatched;
            if (matched + mismatched <= 3)
                PACE_INFO("spline refs: %s engine=%016llx fnv1a64=%016llx %s", path.c_str(),
                          static_cast<unsigned long long>(engine), static_cast<unsigned long long>(ours),
                          engine == ours ? "MATCH" : "DIFFERENT");
            std::lock_guard lock(refMutex);
            engineRefs[path] = engine;
        }
    }
    tokens.clear();
    done = true;
    if (matched + mismatched == 0)
        PACE_INFO("spline refs: %d sector(s) loaded; their nodes are not exposed by reflection, so the NodeRef hash cannot be "
                  "checked here -- Pace uses FNV-1a 64 of the path", sectors);
    else
        PACE_INFO("spline refs: %d sector(s), %zu race splines; FNV-1a 64 %s (%d match, %d differ)", sectors, engineRefs.size(),
                  mismatched == 0 ? "IS the engine's NodeRef hash" : "is NOT the engine's NodeRef hash -- using the engine's",
                  matched, mismatched);
}

uint64_t engineSplineRef(const std::string& path)
{
    std::lock_guard lock(refMutex);
    auto it = engineRefs.find(path);
    return it == engineRefs.end() ? 0 : it->second;
}
} // namespace ncm::pace
