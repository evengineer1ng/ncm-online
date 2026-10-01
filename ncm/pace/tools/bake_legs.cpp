// bake_legs -- the road line for every race leg, from the game's own lane graph (L246, IDEA-788).
//
// Every Paddock race is a chain of authored nodes (course.generator: 2-4 nodes from data.nodes; named roots the same),
// so one line per ORDERED node pair covers every race there is. Each line is: the start node -> onto the road ->
// the routed lanes (Pace's own road_graph.cpp, the same router the DLL runs) -> off the road -> the finish node. The
// ends are joined straight, because a race node can sit off every lane (Corpo Plaza is 136 m from the nearest) and a
// race spline, unlike a lane, may cross a plaza.
//
// Input:  the archive export of the traffic graph (all.lane_polygons.json, all.lane_connections.json -- the same files
//         the all-pairs harness reads) and ncm/core/data/nodes.lua.
// Output: JSON lines on stdout, one leg per line: {"from","to","lengthM","points":[[x,y,z],...]}; a leg the graph
//         cannot route is reported on stderr and left out.
// Usage:  bake_legs <road-data dir> <nodes.lua> [fromId toId]
#include "road_graph.hpp"
#include <nlohmann/json.hpp>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <regex>
#include <string>
#include <vector>

using namespace ncm::pace;

static nlohmann::json read(const std::string& path)
{
    std::ifstream f(path);
    if (!f) throw std::runtime_error("cannot open " + path);
    return nlohmann::json::parse(f);
}

struct Node { std::string id; Point p; };

static double dist(const Point& a, const Point& b) { return std::hypot(a.x - b.x, a.y - b.y); }

// A straight join every <= 8 m, so the spline has no long chord where it leaves or joins the road.
static void join(std::vector<Point>& out, const Point& a, const Point& b)
{
    const double d = dist(a, b);
    const int n = static_cast<int>(std::ceil(d / 8.0));
    for (int k = 1; k < n; ++k) {
        const double t = static_cast<double>(k) / n;
        out.push_back({a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t});
    }
}

// --grids (L247): the road BEHIND a leg's start, for the grid to stand on. From the lane point nearest the start node
// that runs the way the race leaves (the routed line's first 30 m), back along that lane and on through the
// predecessor that runs straightest into it, for `metres`. Start node first. Empty when the node is off every lane
// (more than 20 m) or no lane there runs the race's way -- the server then lays SP's straight grid.
static int whyNoGrid[4] = {0, 0, 0, 0};   // no direction, no lane near, chain too short, ok
static std::vector<Point> behind(const RoadGraph& g, const std::vector<std::vector<uint32_t>>& in, const Point& node,
                                 const std::vector<Point>& road, double metres)
{
    if (road.size() < 2) return {};
    size_t k = 1;
    double run = 0;
    while (k + 1 < road.size() && run < 30.0) { run += dist(road[k - 1], road[k]); ++k; }
    double fx = road[k].x - road.front().x, fy = road[k].y - road.front().y;
    const double fl = std::hypot(fx, fy);
    if (fl < 1) { ++whyNoGrid[0]; return {}; }
    fx /= fl; fy /= fl;
    // anchored on the node; a node off every lane (a plaza, a lot) on the point where the race joins the road
    int64_t bestLane = -1; size_t bestAt = 0;
    bool onNode = true;
    for (const Point* anchor : {&node, &road.front()}) {
        double bestD = 20.0;
        for (size_t i = 0; i < g.lanes.size(); ++i) {
            const auto& line = g.lanes[i].line;
            for (size_t j = 0; j + 1 < line.size(); ++j) {
                const double d = std::hypot(line[j].x - anchor->x, line[j].y - anchor->y);
                if (d >= bestD || std::fabs(line[j].z - anchor->z) > 8.0) continue;
                double dx = line[j + 1].x - line[j].x, dy = line[j + 1].y - line[j].y;
                const double l = std::hypot(dx, dy);
                if (l < 0.1 || (dx * fx + dy * fy) / l < 0.9) continue;
                bestD = d; bestLane = static_cast<int64_t>(i); bestAt = j;
            }
        }
        if (bestLane >= 0) break;
        onNode = false;
    }
    if (bestLane < 0) { ++whyNoGrid[1]; return {}; }
    std::vector<Point> out{onNode ? node : g.lanes[static_cast<size_t>(bestLane)].line[bestAt]};
    double total = 0;
    auto add = [&](const Point& p) {
        if (dist(out.back(), p) < 0.5) return;
        total += dist(out.back(), p);
        out.push_back(p);
    };
    size_t lane = static_cast<size_t>(bestLane);
    int64_t j = static_cast<int64_t>(bestAt);
    for (int hops = 0; hops < 40 && total < metres; ++hops) {
        const auto& line = g.lanes[lane].line;
        for (; j >= 0 && total < metres; --j) add(line[static_cast<size_t>(j)]);
        if (total >= metres || line.size() < 2) break;
        // the predecessor whose last stretch runs straightest into this lane's first
        double sx = line[1].x - line[0].x, sy = line[1].y - line[0].y;
        const double sl = std::max(1e-6, std::hypot(sx, sy));
        int64_t pick = -1; double pickDot = 0.34;   // the straightest on, down to a ~70 deg bend
        for (uint32_t p : in[lane]) {
            const auto& pl = g.lanes[p].line;
            if (pl.size() < 2 || dist(pl.back(), line.front()) > 12.0) continue;
            const double px = pl.back().x - pl[pl.size() - 2].x, py = pl.back().y - pl[pl.size() - 2].y;
            const double pll = std::max(1e-6, std::hypot(px, py));
            const double dot = (px * sx + py * sy) / (pll * sl);
            if (dot > pickDot) { pickDot = dot; pick = p; }
        }
        if (pick < 0) break;
        lane = static_cast<size_t>(pick);
        j = static_cast<int64_t>(g.lanes[lane].line.size()) - 1;
    }
    if (total < 20.0) { ++whyNoGrid[2]; return {}; }      // shorter than the field: the server runs on straight from its end
    ++whyNoGrid[3];
    return out;
}

int main(int argc, char** argv)
{
    if (argc < 3) { std::cerr << "usage: bake_legs <road-data dir> <nodes.lua> [fromId toId | --grids]\n"; return 2; }
    const bool grids = argc >= 4 && std::string(argv[3]) == "--grids";
    const std::string dir = argv[1];
    RoadGraph g;
    {
        auto polygons = read(dir + "/all.lane_polygons.json")["Data"]["RootChunk"]["data"];
        size_t maxIndex = 0;
        for (const auto& e : polygons) maxIndex = std::max(maxIndex, e["index"].get<size_t>());
        g.lanes.resize(maxIndex + 1);
        for (const auto& e : polygons) {
            auto& line = g.lanes[e["index"].get<size_t>()].line;
            for (const auto& p : e["value"]["outline"]) line.push_back({p["X"].get<double>(), p["Y"].get<double>(), p["Z"].get<double>()});
        }
    }
    {
        auto connections = read(dir + "/all.lane_connections.json")["Data"]["RootChunk"]["data"];
        for (const auto& e : connections) {
            const size_t i = e["index"].get<size_t>();
            if (i >= g.lanes.size()) continue;
            for (const auto& edge : e["value"]["outlanes"]) g.lanes[i].out.push_back(edge["laneIndex"].get<uint32_t>());
        }
    }
    std::vector<Node> nodes;
    {
        std::ifstream f(argv[2]);
        std::string line;
        const std::regex re(R"RE(x\s*=\s*(-?[\d.]+).*y\s*=\s*(-?[\d.]+).*z\s*=\s*(-?[\d.]+).*raceLegal\s*=\s*true.*id\s*=\s*"([^"]+)")RE");
        while (std::getline(f, line)) {
            std::smatch m;
            if (line.find("oval = true") != std::string::npos) continue;   // ovals are authored rings, not legs
            if (std::regex_search(line, m, re)) nodes.push_back({m[4], {std::stod(m[1]), std::stod(m[2]), std::stod(m[3])}});
        }
    }
    std::cerr << g.lanes.size() << " lanes, " << nodes.size() << " race nodes\n";
    std::vector<std::vector<uint32_t>> in(g.lanes.size());            // predecessors, for --grids
    for (uint32_t i = 0; i < g.lanes.size(); ++i) for (uint32_t o : g.lanes[i].out) if (o < in.size()) in[o].push_back(i);
    const std::string onlyFrom = (argc >= 5 && !grids) ? argv[3] : "", onlyTo = (argc >= 5 && !grids) ? argv[4] : "";
    int written = 0, failed = 0;
    for (const auto& a : nodes) {
        for (const auto& b : nodes) {
            if (a.id == b.id) continue;
            if (!onlyFrom.empty() && (a.id != onlyFrom || b.id != onlyTo)) continue;
            const auto road = g.route(a.p, b.p);
            if (road.size() < 3) { std::cerr << "no route " << a.id << " -> " << b.id << "\n"; ++failed; continue; }
            if (grids) {
                const auto back = behind(g, in, a.p, road, 120.0);
                if (back.empty()) { ++failed; continue; }
                nlohmann::json j{{"from", a.id}, {"to", b.id}};
                auto& arr = j["points"] = nlohmann::json::array();
                for (const auto& p : back) arr.push_back({std::round(p.x * 100) / 100, std::round(p.y * 100) / 100, std::round(p.z * 100) / 100});
                std::cout << j.dump() << "\n";
                ++written;
                continue;
            }
            std::vector<Point> pts{a.p};
            join(pts, a.p, road.front());
            pts.insert(pts.end(), road.begin(), road.end());
            join(pts, road.back(), b.p);
            pts.push_back(b.p);
            double length = 0;
            for (size_t k = 1; k < pts.size(); ++k) length += dist(pts[k - 1], pts[k]);
            // an 80 m run-out past the node, along the line's last 30 m: a car racing to the END of a spline crosses the
            // finish (or checkpoint) line rather than stopping on it. Not counted in lengthM.
            {
                size_t k = pts.size() - 1;
                double back = 0;
                while (k > 0 && back < 30.0) { back += dist(pts[k - 1], pts[k]); --k; }
                const Point& from = pts[k];
                const double len = std::max(1e-6, dist(from, b.p));
                const Point end{b.p.x + (b.p.x - from.x) / len * 80.0, b.p.y + (b.p.y - from.y) / len * 80.0, b.p.z};
                join(pts, b.p, end);
                pts.push_back(end);
            }
            nlohmann::json j{{"from", a.id}, {"to", b.id}, {"lengthM", std::round(length)},
                             {"onRoadFromM", std::round(dist(a.p, road.front()))}, {"offRoadToM", std::round(dist(road.back(), b.p))}};
            auto& arr = j["points"] = nlohmann::json::array();
            for (const auto& p : pts) arr.push_back({std::round(p.x * 100) / 100, std::round(p.y * 100) / 100, std::round(p.z * 100) / 100});
            std::cout << j.dump() << "\n";
            ++written;
        }
    }
    std::cerr << written << " legs written, " << failed << " unroutable\n";
    if (grids) std::cerr << "grids: " << whyNoGrid[3] << " ok, " << whyNoGrid[0] << " no direction, " << whyNoGrid[1]
                         << " no lane the race's way within 20 m of the node, " << whyNoGrid[2] << " road behind too short\n";
    return 0;
}
