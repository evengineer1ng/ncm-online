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

int main(int argc, char** argv)
{
    if (argc < 3) { std::cerr << "usage: bake_legs <road-data dir> <nodes.lua> [fromId toId]\n"; return 2; }
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
    const std::string onlyFrom = argc >= 5 ? argv[3] : "", onlyTo = argc >= 5 ? argv[4] : "";
    int written = 0, failed = 0;
    for (const auto& a : nodes) {
        for (const auto& b : nodes) {
            if (a.id == b.id) continue;
            if (!onlyFrom.empty() && (a.id != onlyFrom || b.id != onlyTo)) continue;
            const auto road = g.route(a.p, b.p);
            if (road.size() < 3) { std::cerr << "no route " << a.id << " -> " << b.id << "\n"; ++failed; continue; }
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
    return 0;
}
