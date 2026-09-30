#include "road_graph.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <queue>
#include <utility>

namespace ncm::pace {
namespace {
double length(const Point& a, const Point& b) { return std::hypot(a.x-b.x, a.y-b.y); }
struct Near { uint32_t lane; size_t point; double distance; };
std::vector<Near> nearest(const RoadGraph& graph, const Point& p)
{
    std::vector<Near> near;
    for (uint32_t i=0; i<graph.lanes.size(); ++i) {
        double best=std::numeric_limits<double>::infinity(); size_t at=0;
        const auto& line=graph.lanes[i].line;
        for (size_t j=0;j<line.size();++j) {
            const auto& q=line[j];
            // A nearby overpass is a different road. All configured anchors
            // have a cooked lane within 12 m vertically in the archive sweep.
            if (std::fabs(q.z-p.z)>14.0) continue;
            const double d=std::hypot(q.x-p.x,q.y-p.y,2.0*(q.z-p.z));
            if (d<best) {best=d;at=j;}
        }
        // Race anchors can be offset from their cooked lane. The sweep over all
        // 35 configured nodes found one connected candidate 75-85 m away.
        if (best > 85.0) continue;
        near.push_back({i,at,best});
    }
    std::sort(near.begin(),near.end(),[](const Near& a,const Near& b){return a.distance<b.distance;});
    if (near.size()>32) near.resize(32);
    return near;
}
}

std::vector<Point> RoadGraph::route(const Point& from, const Point& to) const
{
    if (lanes.empty()) return {};
    const auto starts=nearest(*this,from), ends=nearest(*this,to);
    if (starts.empty() || ends.empty()) return {};
    std::vector<std::vector<double>> cumulative(lanes.size());
    for (size_t i=0;i<lanes.size();++i) {
        const auto& line=lanes[i].line;
        auto& sums=cumulative[i];sums.resize(line.size());
        for (size_t j=1;j<line.size();++j) sums[j]=sums[j-1]+length(line[j-1],line[j]);
    }
    std::vector<double> distance(lanes.size(),std::numeric_limits<double>::infinity());
    std::vector<int32_t> previous(lanes.size(),-1);
    using Item=std::pair<double,uint32_t>;
    std::priority_queue<Item,std::vector<Item>,std::greater<Item>> queue;
    double best=std::numeric_limits<double>::infinity();
    int32_t hit=-1, chosenStart=-1, chosenEnd=-1;
    bool direct=false;
    for (size_t si=0;si<starts.size();++si) {
        const auto& s=starts[si];
        const double tail=cumulative[s.lane].back()-cumulative[s.lane][s.point];
        for (size_t ei=0;ei<ends.size();++ei) {
            const auto& e=ends[ei];
            if (e.lane!=s.lane || e.point<s.point+2) continue;
            const double cost=3.0*(s.distance+e.distance)+cumulative[s.lane][e.point]-cumulative[s.lane][s.point];
            if (cost<best) {best=cost;chosenStart=static_cast<int32_t>(si);chosenEnd=static_cast<int32_t>(ei);direct=true;}
        }
        for (uint32_t next:lanes[s.lane].out) {
            if (next>=lanes.size() || lanes[next].line.empty() ||
                length(lanes[s.lane].line.back(),lanes[next].line.front())>12.0) continue;
            const double nd=3.0*s.distance+tail+cumulative[next].back();
            if (nd<distance[next]) {
                distance[next]=nd;previous[next]=-2-static_cast<int32_t>(si);queue.push({nd,next});
            }
        }
    }
    while (!queue.empty()) {
        const auto [d,i]=queue.top();queue.pop();
        if (d>distance[i]) continue;
        for (size_t ei=0;ei<ends.size();++ei) {
            const auto& e=ends[ei];
            if (e.lane!=i) continue;
            const double cost=d+3.0*e.distance-(cumulative[i].back()-cumulative[i][e.point]);
            if (cost<best) {best=cost;hit=static_cast<int32_t>(i);chosenEnd=static_cast<int32_t>(ei);direct=false;}
        }
        for (uint32_t next:lanes[i].out) {
            if (next>=lanes.size() || lanes[next].line.empty()) continue;
            // Cooked connections normally meet within a lane width. Reject corrupt or mismatched layouts.
            if (length(lanes[i].line.back(),lanes[next].line.front())>12.0) continue;
            const double nd=d+cumulative[next].back();
            if (nd<distance[next]) {distance[next]=nd;previous[next]=static_cast<int32_t>(i);queue.push({nd,next});}
        }
    }
    std::vector<uint32_t> order;
    if (direct) order.push_back(starts[chosenStart].lane);
    else {
        if (hit<0) return {};
        int32_t i=hit;
        while (i>=0) {
            order.push_back(static_cast<uint32_t>(i));
            const int32_t prev=previous[i];
            if (prev<=-2) {chosenStart=-2-prev;order.push_back(starts[chosenStart].lane);break;}
            i=prev;
        }
        if (chosenStart<0) return {};
        std::reverse(order.begin(),order.end());
    }
    std::vector<Point> road;
    for (size_t k=0;k<order.size();++k) {
        const auto& line=lanes[order[k]].line;
        const size_t fromPoint=k==0?starts[chosenStart].point:0;
        const size_t toPoint=k+1==order.size()?ends[chosenEnd].point:line.size()-1;
        if (fromPoint>toPoint) return {};
        for (size_t j=fromPoint;j<=toPoint;++j)
            if (road.empty() || length(road.back(),line[j])>=0.5) road.push_back(line[j]);
    }
    if (road.size()<3 || road.size()>kMaxPoints) return {};
    // Long straight segments are interpolated so the curvature planner has bounded spacing.
    std::vector<Point> dense;
    dense.push_back(road.front());
    for (size_t i=1;i<road.size();++i) {
        const double d=length(road[i-1],road[i]);
        const int pieces=std::max(1,static_cast<int>(std::ceil(d/20.0)));
        for (int k=1;k<=pieces;++k) {
            const double t=static_cast<double>(k)/pieces;
            dense.push_back({road[i-1].x+(road[i].x-road[i-1].x)*t,
                             road[i-1].y+(road[i].y-road[i-1].y)*t,
                             road[i-1].z+(road[i].z-road[i-1].z)*t});
        }
    }
    return dense.size()<=kMaxPoints ? dense : std::vector<Point>{};
}
} // namespace ncm::pace
