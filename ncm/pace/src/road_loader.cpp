#include "road_loader.hpp"
#include "log.hpp"
#include "state.hpp"

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/ResourceLoader.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/TrafficPersistentLaneConnections.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/TrafficLanePolygonRepresentation.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <mutex>

namespace ncm::pace {
namespace {
constexpr const char* connectionPath = "base\\worlds\\03_night_city\\sectors\\_generated\\traffic\\all.lane_connections";
constexpr const char* polygonPath = "base\\worlds\\03_night_city\\sectors\\_generated\\traffic\\all.lane_polygons";
RED4ext::SharedPtr<RED4ext::ResourceToken<>> connectionToken, polygonToken;
std::mutex graphMutex;
std::shared_ptr<const RoadGraph> graph;
bool failed = false;

template<typename T> struct SparseEntry {
    int32_t previous;
    uint32_t index;
    uint64_t unknown;
    T value;
};
static_assert(sizeof(SparseEntry<RED4ext::world::TrafficPersistentLaneConnections>) == 0x30);
static_assert(sizeof(SparseEntry<RED4ext::world::TrafficLanePolygonRepresentation>) == 0x30);

template<typename T> struct SparseView {
    const SparseEntry<T>* entries = nullptr;
    uint32_t count = 0;
    uint32_t stride = 0;
};
template<typename T> SparseView<T> view(const RED4ext::CResource* resource)
{
    SparseView<T> result;
    const auto* base = reinterpret_cast<const uint8_t*>(resource);
    std::memcpy(&result, base + 0x50, sizeof(result));
    if (!result.entries || result.count < 30000 || result.count > 50000 || result.stride != sizeof(SparseEntry<T>))
        return {};
    return result;
}

uint32_t decodeLane(const RED4ext::world::TrafficConnectivityOutLane& edge, int layout)
{
    uint32_t value = 0;
    if (layout == 0 || layout == 1) {
        uint16_t shortValue = 0;
        std::memcpy(&shortValue, edge.unk00 + (layout == 0 ? 0 : 2), sizeof(shortValue));
        value = shortValue;
    } else {
        std::memcpy(&value, edge.unk00 + (layout - 2) * 4, sizeof(value));
    }
    return value;
}

double gap(const std::vector<RoadLane>& lanes, uint32_t from, uint32_t to)
{
    if (to >= lanes.size() || lanes[from].line.empty() || lanes[to].line.empty()) return 1e9;
    const auto& a = lanes[from].line.back();
    const auto& b = lanes[to].line.front();
    return std::hypot(a.x-b.x,a.y-b.y);
}
}

void pollRoadGraph()
{
    if (failed || currentRoadGraph()) return;
    auto* loader = RED4ext::ResourceLoader::Get();
    if (!loader) return;
    if (!connectionToken) connectionToken = loader->LoadAsync(RED4ext::ResourcePath(connectionPath));
    if (!polygonToken) polygonToken = loader->LoadAsync(RED4ext::ResourcePath(polygonPath));
    if (!connectionToken || !polygonToken) return;
    if (connectionToken->IsFailed() || polygonToken->IsFailed()) {
        PACE_ERR("road graph: game traffic resources failed to load"); failed=true; return;
    }
    if (!connectionToken->IsLoaded() || !polygonToken->IsLoaded()) return;
    auto* connectionResource = connectionToken->Get().GetPtr();
    auto* polygonResource = polygonToken->Get().GetPtr();
    if (!connectionResource || !polygonResource) return;
    const auto connections = view<RED4ext::world::TrafficPersistentLaneConnections>(connectionResource);
    const auto polygons = view<RED4ext::world::TrafficLanePolygonRepresentation>(polygonResource);
    if (!connections.entries || !polygons.entries || connections.count != polygons.count) {
        PACE_ERR("road graph: unrecognized traffic resource layout conn=%u/%u polygon=%u/%u",
                 connections.count,connections.stride,polygons.count,polygons.stride);
        failed=true;return;
    }
    auto built=std::make_shared<RoadGraph>();
    built->lanes.resize(polygons.count);
    size_t points=0;
    for (uint32_t i=0;i<polygons.count;++i) {
        const auto& item=polygons.entries[i];
        if (item.index>=built->lanes.size() || item.value.outline.size()>1000) {failed=true;PACE_ERR("road graph: invalid polygon entry %u",i);return;}
        auto& line=built->lanes[item.index].line;
        line.reserve(item.value.outline.size());
        for (const auto& p:item.value.outline) line.push_back({p.X,p.Y,p.Z});
        points+=line.size();
    }
    // The SDK leaves the 12-byte out-lane type opaque. Detect the lane-index offset by
    // checking which layout joins nearby road centreline endpoints in this game build.
    std::array<uint32_t,5> continuity{};
    for (uint32_t i=0;i<connections.count;++i) {
        const auto& item=connections.entries[i];
        if (item.index>=built->lanes.size() || item.value.outlanes.size()>100) {failed=true;PACE_ERR("road graph: invalid connection entry %u",i);return;}
        for (const auto& edge:item.value.outlanes)
            for (int layout=0;layout<5;++layout)
                if (gap(built->lanes,item.index,decodeLane(edge,layout))<12.0) ++continuity[layout];
    }
    const int layout=static_cast<int>(std::max_element(continuity.begin(),continuity.end())-continuity.begin());
    PACE_INFO("road graph: %u lanes %zu points edge-continuity=%u/%u/%u/%u/%u selected=%d",
              polygons.count,points,continuity[0],continuity[1],continuity[2],continuity[3],continuity[4],layout);
    if (points<100000 || continuity[layout]<10000) {failed=true;PACE_ERR("road graph: failed geometry or edge validation");return;}
    size_t edges=0;
    for (uint32_t i=0;i<connections.count;++i) {
        const auto& item=connections.entries[i];
        auto& out=built->lanes[item.index].out;
        for (const auto& edge:item.value.outlanes) {
            const uint32_t next=decodeLane(edge,layout);
            if (gap(built->lanes,item.index,next)<12.0) {out.push_back(next);++edges;}
        }
    }
    PACE_INFO("road graph: copied %zu connected edges; routing uses incoming race checkpoint coordinates",edges);
    std::lock_guard lock(graphMutex);
    graph=std::move(built);
    state().setRoadGraph(graph);
}

std::shared_ptr<const RoadGraph> currentRoadGraph()
{
    std::lock_guard lock(graphMutex);
    return graph;
}
} // namespace ncm::pace
