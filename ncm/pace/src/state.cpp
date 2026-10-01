#include "state.hpp"
#include "road_graph.hpp"
#include "speed_profile.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <tuple>

namespace ncm::pace {
namespace {
double dist(const Point& a, const Point& b) { return std::hypot(a.x - b.x, a.y - b.y); }

std::string fmt(double v)
{
    char b[32];
    std::snprintf(b, sizeof(b), "%.2f", v);
    return b;
}
}

uint64_t parseHash(const std::string& text)
{
    uint64_t v = 0;
    for (const char c : text) {
        if (c < '0' || c > '9') return 0;
        v = v * 10 + static_cast<uint64_t>(c - '0');
    }
    return v;
}

double signedDistance(const Gate& g, const Point& p, double* perp)
{
    const double rx = p.x - g.x, ry = p.y - g.y;
    const double along = rx * (-g.dx) + ry * (-g.dy);
    if (perp) *perp = std::fabs(rx * g.dy - ry * g.dx);
    return along;
}

double crossFraction(const Gate& g, const Point& a, const Point& b)
{
    const Point gp{g.x, g.y, g.z};
    if (dist(b, gp) <= g.capture) {
        // reached the point: a real sign flip still dates it precisely; otherwise the later report
        const double before = signedDistance(g, a), after = signedDistance(g, b);
        if (before > 0 && after <= 0 && before - after > 0) return before / (before - after);
        return 1.0;
    }
    if (dist(b, gp) > g.arm) return -1.0;
    double perp = 0;
    const double before = signedDistance(g, a);
    const double after = signedDistance(g, b, &perp);
    if (!(before > 0 && after <= 0 && perp <= g.halfWidth)) return -1.0;
    const double span = before - after;
    if (span <= 0) return 1.0;
    const double f = before / span;
    return f < 0 ? 0.0 : (f > 1 ? 1.0 : f);
}

void State::push(const std::string& json)
{
    if (out_.size() < 512) out_.push_back(json);
}

void State::stopAll(const char* why)
{
    if (!active_) return;
    for (auto& c : cars_) {
        if (c.mode != 2) { c.mode = 2; c.seq++; }
    }
    active_ = false;
    stoppedAt_ = Clock::now();
    revision_++;
    push(nlohmann::json{{"ack", {{"what", "stop"}, {"detail", why}}}}.dump());
}

void State::setRoadGraph(std::shared_ptr<const RoadGraph> graph)
{
    std::lock_guard lock(mutex_);
    roadGraph_ = std::move(graph);
    if (active_ && complete_) planRoad();
}

void State::planRoad()
{
    road_.clear(); roadLimits_.clear(); roadLegs_.clear(); pointRoad_.clear();
    if (!roadGraph_ || points_.size()<2 || haveRing) return;
    // Every leg scans the whole graph twice and runs a search over it, under the lock the game thread takes every
    // tick. A route's authored points are a handful; a dense line (a ghost tape, 48 points) would stall the game for
    // seconds and needs no road plan anyway (KB-241).
    if (points_.size()-1 > kMaxRoadLegs) {
        if (logQueue_.size()<2000) logQueue_.push_back("road speed plan skipped: "+std::to_string(points_.size()-1)+
            " legs is over "+std::to_string(kMaxRoadLegs)+" (a dense line, not a route's checkpoints)");
        return;
    }
    roadLegs_.resize(points_.size()-1);
    bool connected=true;
    size_t validLegs=0;
    for (size_t i=1;i<points_.size();++i) {
        // 0.5.0: a leg after the first continues from where the previous leg's road ENDS, not from the checkpoint
        // coordinate. Snapped separately, the two legs could meet on different lanes (the opposite carriageway, a
        // cross street), and the joint read as a hairpin that braked every car into the checkpoint.
        const Point from=(i>1 && !roadLegs_[i-2].points.empty()) ? roadLegs_[i-2].points.back() : points_[i-1];
        auto segment=roadGraph_->route(from,points_[i]);
        if (segment.empty() && i>1) segment=roadGraph_->route(points_[i-1],points_[i]);
        if (segment.empty()) {
            if (logQueue_.size()<2000) logQueue_.push_back("road speed plan unavailable: leg "+std::to_string(i)+
                " of "+std::to_string(points_.size()-1)+" from "+std::to_string(static_cast<int>(points_[i-1].x))+","+
                std::to_string(static_cast<int>(points_[i-1].y))+" to "+std::to_string(static_cast<int>(points_[i].x))+","+
                std::to_string(static_cast<int>(points_[i].y)));
            connected=false;continue;
        }
        auto legProfile=buildSpeedProfile(segment);
        if (!legProfile.valid) {
            if (logQueue_.size()<2000) logQueue_.push_back("road speed plan unavailable: invalid spacing in leg "+std::to_string(i));
            connected=false;continue;
        }
        roadLegs_[i-1]={segment,std::move(legProfile.limitMps)};
        ++validLegs;
        if (!connected || road_.size()+segment.size()>32000) {connected=false;continue;}
        if (!road_.empty()) {
            const Point a=road_.back(), b=segment.front();
            const double gap=std::hypot(a.x-b.x,a.y-b.y);
            if (gap>75.0) {
                if (logQueue_.size()<2000) logQueue_.push_back("road speed plan segmented at checkpoint "+
                    std::to_string(i)+" (lane gap "+std::to_string(static_cast<int>(gap))+" m)");
                connected=false;continue;
            }
            if (gap<0.5) segment.erase(segment.begin());
            else for (int k=1,n=static_cast<int>(std::ceil(gap/15.0));k<n;++k) {
                const double t=static_cast<double>(k)/n;
                road_.push_back({a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,a.z+(b.z-a.z)*t});
            }
        }
        road_.insert(road_.end(),segment.begin(),segment.end());
    }
    if (connected) {
        auto profile=buildSpeedProfile(road_);
        if (profile.valid) roadLimits_=std::move(profile.limitMps);
        else if (logQueue_.size()<2000) logQueue_.push_back("road speed plan segmented: invalid checkpoint spacing");
    }
    if (roadLimits_.empty()) road_.clear();
    // where each plan point sits on the road, searched forward so a road that passes near a checkpoint twice keeps
    // race order: "past point k" is judged by road progress, not a chord (KB-243: on a bending approach the chord test
    // fired ~130 m before the finish)
    if (!road_.empty()) {
        pointRoad_.assign(points_.size(),0);
        size_t from=0;
        for (size_t i=1;i<points_.size();++i) {
            size_t at=from; double best=1e100;
            for (size_t k=from;k<road_.size();++k) {const double d=std::hypot(road_[k].x-points_[i].x,road_[k].y-points_[i].y);if(d<best){best=d;at=k;}}
            pointRoad_[i]=at; from=at;
        }
        pointRoad_.back()=road_.size()-1;
    }
    // every checkpoint joint, said out loud: how sharp the road turns there and how slow the plan goes near it
    if (!road_.empty()) for (size_t i=1;i+1<points_.size();++i) {
        size_t at=0; double best=1e100;
        for (size_t k=0;k<road_.size();++k) {const double d=std::hypot(road_[k].x-points_[i].x,road_[k].y-points_[i].y);if(d<best){best=d;at=k;}}
        const size_t a=at>=3?at-3:0, b=std::min(road_.size()-1,at+3);
        const double ux=road_[at].x-road_[a].x, uy=road_[at].y-road_[a].y, vx=road_[b].x-road_[at].x, vy=road_[b].y-road_[at].y;
        const double nu=std::hypot(ux,uy), nv=std::hypot(vx,vy);
        const double turn=(nu>1e-6&&nv>1e-6)?std::acos(std::clamp((ux*vx+uy*vy)/(nu*nv),-1.0,1.0))*57.2958:0.0;
        double slow=1e100; double walked=0;
        for (size_t k=at;k>0&&walked<150.0;--k) {walked+=std::hypot(road_[k].x-road_[k-1].x,road_[k].y-road_[k-1].y);slow=std::min(slow,roadLimits_[k-1]);}
        walked=0;
        for (size_t k=at;k+1<road_.size()&&walked<150.0;++k) {walked+=std::hypot(road_[k+1].x-road_[k].x,road_[k+1].y-road_[k].y);slow=std::min(slow,roadLimits_[k+1]);}
        char line[200]{};
        std::snprintf(line,sizeof(line),"road joint at checkpoint %zu: road %.0f m from it, turn %.0f deg, slowest %.1f m/s within 150 m",
            i,best,turn,std::min(slow,roadLimits_[at]));
        if (logQueue_.size()<2000) logQueue_.emplace_back(line);
    }
    for (auto& c:cars_) {c.roadLocated=false;c.roadAimed=false;}
    if (logQueue_.size()<2000) logQueue_.push_back("road speed plan ready: "+std::to_string(validLegs)+"/"+
        std::to_string(roadLegs_.size())+" legs, "+(roadLimits_.empty()?"segmented":"continuous")+" profile");
}

bool State::apply(const std::string& text, Clock::time_point now)
{
    std::lock_guard lock(mutex_);
    // every refusal says why (0.4.0, KB-223); the bridge logs it with the head of the payload
    auto no = [this](std::string why) { refusal_ = std::move(why); return false; };
    const auto j = nlohmann::json::parse(text, nullptr, false);
    if (!j.is_object()) return no("not a JSON object");
    const std::string cmd = j.value("cmd", std::string());
    if (cmd == "banner") {
        auto clean = [](std::string t) {
            for (char& ch : t) if (ch == '|' || ch == 10 || ch == 13) ch = ' ';   // '|' splits fields; no line breaks
            return t.substr(0, 120);
        };
        bannerTitle_ = clean(j.value("title", std::string()));
        bannerDetail_ = clean(j.value("detail", std::string()));
        const double secs = j.value("seconds", 0.0);
        bannerUntil_ = now + std::chrono::milliseconds(static_cast<int64_t>(secs < 0 ? 0 : secs * 1000.0));
        bannerRev_++;
        return true;
    }
    if (cmd == "area") {
        const double secs = j.value("seconds", 0.0);
        areaAt_ = {j.value("x", 0.0), j.value("y", 0.0), j.value("z", 0.0)};
        areaHalf_ = std::min(400.0, std::max(0.0, j.value("half", 140.0)));
        areaHalfZ_ = std::min(100.0, std::max(5.0, j.value("halfZ", 30.0)));
        areaUntil_ = now + std::chrono::milliseconds(static_cast<int64_t>(secs < 0 ? 0 : std::min(secs, 3600.0) * 1000.0));
        areaRev_++;
        return true;
    }
    if (cmd == "drive.end" || cmd == "drive.cancel") {
        stopAll(cmd.c_str());
        return true;
    }
    if (cmd == "drive.more") {
        // the next stretch of the tape: appended as a whole or not at all
        if (!active_) return no("drive.more with no active plan");
        if (complete_) return no("drive.more after the tape was complete");
        if (j.value("raceId", std::string()) != raceId_) return no("drive.more for race " + j.value("raceId", std::string()) + ", plan is " + raceId_);
        const auto& pts = j.value("points", nlohmann::json::array());
        const auto& gts = j.value("gates", nlohmann::json::array());
        const auto& spd = j.value("speeds", nlohmann::json::array());
        if (!pts.is_array() || !gts.is_array() || !spd.is_array()) return no("drive.more: points/gates/speeds not arrays");
        if (points_.size() + pts.size() > kMaxPoints || gates_.size() + gts.size() > kMaxGates) return no("drive.more: over the point or gate cap");
        if (!spd.empty() && spd.size() != cars_.size()) return no("drive.more: " + std::to_string(spd.size()) + " speed lists for " + std::to_string(cars_.size()) + " cars");
        std::vector<Point> morePoints;
        for (const auto& p : pts) {
            if (!p.is_object()) return no("drive.more: a point is not an object");
            morePoints.push_back({p.value("x", 0.0), p.value("y", 0.0), p.value("z", 0.0)});
        }
        std::vector<Gate> moreGates;
        for (const auto& g : gts) {
            if (!g.is_object()) return no("drive.more: a gate is not an object");
            Gate x;
            x.x = g.value("x", 0.0); x.y = g.value("y", 0.0); x.z = g.value("z", 0.0);
            x.dx = g.value("dx", 1.0); x.dy = g.value("dy", 0.0);
            const double len = std::hypot(x.dx, x.dy);
            if (len < 1e-6) return no("drive.more: a gate with no direction");
            x.dx /= len; x.dy /= len;
            x.halfWidth = g.value("halfWidth", 28.0);
            x.capture = g.value("capture", 35.0);
            moreGates.push_back(x);
        }
        for (size_t i = 0; i < spd.size(); ++i) {
            if (!spd[i].is_array()) return no("drive.more: a speed list is not an array");
            for (const auto& s : spd[i]) if (s.is_number()) cars_[i].speeds.push_back(static_cast<float>(s.get<double>()));
        }
        points_.insert(points_.end(), morePoints.begin(), morePoints.end());
        gates_.insert(gates_.end(), moreGates.begin(), moreGates.end());
        complete_ = j.value("last", false);
        if (complete_) planRoad();
        push(nlohmann::json{{"ack", {{"what", "drive.more"}, {"detail", std::to_string(points_.size()) + " points, " +
            std::to_string(gates_.size()) + " gates" + (complete_ ? ", complete" : "")}}}}.dump());
        return true;
    }
    if (cmd == "car.add") {
        // a car joins a dynamic plan mid-race (the bubble made it physical near this player): appended, never inserted
        if (!active_ || !dynamic_) return no("car.add with no active dynamic plan");
        if (j.value("raceId", std::string()) != raceId_) return no("car.add for race " + j.value("raceId", std::string()) + ", plan is " + raceId_);
        if (cars_.size() >= kMaxCars) return no("car.add: the plan already holds " + std::to_string(kMaxCars) + " cars");
        Car car;
        if (j.contains("entity") && j["entity"].is_string()) car.entity = parseHash(j["entity"].get<std::string>());
        else if (j.contains("entity") && j["entity"].is_number_unsigned()) car.entity = j["entity"].get<uint64_t>();
        if (car.entity == 0) return no("car.add: no usable entity (" + (j.contains("entity") ? j["entity"].dump() : std::string("missing")) + ")");
        for (const auto& c : cars_) if (c.entity == car.entity && !c.finished) return no("car.add: that entity is already driving");
        car.vehicleId = j.value("vehicleId", static_cast<int64_t>(0));
        const auto from = j.value("from", static_cast<int64_t>(1));
        car.target = static_cast<size_t>(std::max<int64_t>(1, std::min<int64_t>(from, static_cast<int64_t>(points_.size()) - 1)));
        car.speeds.assign(1, static_cast<float>(std::max(5.0, j.value("speed", 25.0))));
        car.nextGate = gates_.size();                     // mid-race: no Pace gate counts for it (see step)
        car.dynamic = true;
        cars_.push_back(car);
        push(nlohmann::json{{"ack", {{"what", "car.add"}, {"detail", "car " + std::to_string(cars_.size() - 1) + " vehicle " +
            std::to_string(car.vehicleId) + " from point " + std::to_string(car.target)}}}}.dump());
        return true;
    }
    if (cmd == "car.set") {
        // a car's ceiling follows its own sim pace mid-race (0.4.4, KB-223): every bubble car was a clone at the
        // same ceiling, so the field ran single file in grid order. Changes nothing else; releases nothing.
        if (j.value("raceId", std::string()) != raceId_) return no("car.set for race " + j.value("raceId", std::string()) + ", plan is " + raceId_);
        uint64_t entity = 0;
        if (j.contains("entity") && j["entity"].is_string()) entity = parseHash(j["entity"].get<std::string>());
        else if (j.contains("entity") && j["entity"].is_number_unsigned()) entity = j["entity"].get<uint64_t>();
        if (!j.contains("speed") || !j["speed"].is_number()) return no("car.set: no speed");
        for (auto& c : cars_) {
            if (c.entity == entity && entity != 0 && !c.finished) {
                c.speeds.assign(1, static_cast<float>(std::max(5.0, j["speed"].get<double>())));
                return true;
            }
        }
        return no("car.set: no such car driving");
    }
    if (cmd == "car.remove") {
        // retired IN PLACE: redscript keys its state by index, so the list never shrinks or reorders mid-race
        if (j.value("raceId", std::string()) != raceId_) return no("car.remove for race " + j.value("raceId", std::string()) + ", plan is " + raceId_);
        uint64_t entity = 0;
        if (j.contains("entity") && j["entity"].is_string()) entity = parseHash(j["entity"].get<std::string>());
        else if (j.contains("entity") && j["entity"].is_number_unsigned()) entity = j["entity"].get<uint64_t>();
        for (auto& c : cars_) {
            if (c.entity == entity && !c.finished) {
                c.finished = true;
                c.entity = 0;                               // redscript finds no vehicle for it and leaves the slot alone
                push(nlohmann::json{{"ack", {{"what", "car.remove"}, {"detail", "vehicle " + std::to_string(c.vehicleId)}}}}.dump());
                return true;
            }
        }
        return no("car.remove: no such car driving");
    }
    if (cmd != "drive.start") return no("unknown cmd \"" + cmd + "\"");
    const auto& pts = j.value("points", nlohmann::json::array());
    const auto& gts = j.value("gates", nlohmann::json::array());
    const auto& crs = j.value("cars", nlohmann::json::array());
    const bool dynamic = j.value("dynamic", false);
    if (!pts.is_array() || pts.size() < 2 || pts.size() > kMaxPoints) return no("drive.start: " + std::string(pts.is_array() ? std::to_string(pts.size()) : "no") + " points (2.." + std::to_string(kMaxPoints) + ")");
    if (!gts.is_array() || gts.size() < 2 || gts.size() > kMaxGates) return no("drive.start: " + std::string(gts.is_array() ? std::to_string(gts.size()) : "no") + " gates (2.." + std::to_string(kMaxGates) + ")");
    if (!crs.is_array() || (crs.empty() && !dynamic) || crs.size() > kMaxCars) return no("drive.start: " + std::string(crs.is_array() ? std::to_string(crs.size()) : "no") + " cars");
    std::vector<Point> points;
    for (const auto& p : pts) {
        if (!p.is_object()) return no("drive.start: a point is not an object");
        points.push_back({p.value("x", 0.0), p.value("y", 0.0), p.value("z", 0.0)});
    }
    std::vector<Gate> gates;
    for (const auto& g : gts) {
        if (!g.is_object()) return no("drive.start: a gate is not an object");
        Gate x;
        x.x = g.value("x", 0.0); x.y = g.value("y", 0.0); x.z = g.value("z", 0.0);
        x.dx = g.value("dx", 1.0); x.dy = g.value("dy", 0.0);
        const double len = std::hypot(x.dx, x.dy);
        if (len < 1e-6) return no("drive.start: a gate with no direction");
        x.dx /= len; x.dy /= len;
        x.halfWidth = g.value("halfWidth", 28.0);
        x.capture = g.value("capture", 35.0);
        gates.push_back(x);
    }
    std::vector<Car> cars;
    for (const auto& c : crs) {
        if (!c.is_object()) return no("drive.start: a car is not an object");
        Car car;
        if (c.contains("entity") && c["entity"].is_string()) car.entity = parseHash(c["entity"].get<std::string>());
        else if (c.contains("entity") && c["entity"].is_number_unsigned()) car.entity = c["entity"].get<uint64_t>();
        if (car.entity == 0) return no("drive.start: a car with no usable entity (" + (c.contains("entity") ? c["entity"].dump() : std::string("missing")) + ")");
        car.vehicleId = c.value("vehicleId", static_cast<int64_t>(0));
        for (const auto& s : c.value("speeds", nlohmann::json::array())) {
            if (s.is_number()) car.speeds.push_back(static_cast<float>(s.get<double>()));
        }
        if (car.speeds.empty()) car.speeds.push_back(20.0f);
        cars.push_back(car);
    }
    raceId_ = j.value("raceId", std::string());
    points_ = std::move(points);
    gates_ = std::move(gates);
    cars_ = std::move(cars);
    advanceM = j.value("advanceM", 40.0);
    lookaheadM = std::max(0.0, j.value("lookaheadM", 0.0));
    reaimFrac = std::min(0.98, std::max(0.1, j.value("reaimFrac", 0.5)));
    roadAimM = std::clamp(j.value("roadAimM", 300.0), 80.0, 1000.0);
    roadReaimM = std::clamp(j.value("roadReaimM", 180.0), 40.0, roadAimM - 20.0);
    haveRing = false;
    if (j.contains("ring") && j["ring"].is_object()) {
        ringCx = j["ring"].value("cx", 0.0);
        ringCy = j["ring"].value("cy", 0.0);
        ringSign = j["ring"].value("sign", 1.0) >= 0 ? 1.0 : -1.0;
        wrongWayMs = std::max<int64_t>(150, j["ring"].value("wrongWayMs", static_cast<int64_t>(300)));
        haveRing = true;
    }
    complete_ = !j.value("more", false);
    dynamic_ = dynamic;
    Launch l;
    if (j.contains("launch") && j["launch"].is_object()) {
        const auto& x = j["launch"];
        l.graceS = x.value("graceS", l.graceS);
        l.relMax = x.value("relMax", l.relMax); l.relMin = x.value("relMin", l.relMin);
        l.relForced = x.value("relForced", l.relForced); l.relDist = x.value("relDist", l.relDist);
        l.minFrac = x.value("minFrac", l.minFrac); l.forcedFrac = x.value("forcedFrac", l.forcedFrac);
        l.raceDist = x.value("raceDist", l.raceDist);
        l.recommandS = std::max(0.6, x.value("recommandS", l.recommandS));
        l.stallMps = x.value("stallMps", l.stallMps); l.stallS = std::max(0.5, x.value("stallS", l.stallS));
    }
    launch = l;
    const int64_t goIn = j.value("goInMs", static_cast<int64_t>(0));
    goAt_ = now + std::chrono::milliseconds(goIn < 0 ? 0 : goIn);
    active_ = true;
    if (complete_) planRoad();
    revision_++;
    push(nlohmann::json{{"ack", {{"what", "drive.start"}, {"detail", std::to_string(cars_.size()) + " cars, " +
        std::to_string(points_.size()) + " points, " + std::to_string(gates_.size()) + " gates"}}}}.dump());
    return true;
}

void State::disconnect()
{
    std::lock_guard lock(mutex_);
    stopAll("resource disconnected");
}

int State::count(Clock::time_point now)
{
    std::lock_guard lock(mutex_);
    // After a stop the cars stay listed for ten seconds, so redscript sees mode 2 and brakes them; then the list
    // goes and redscript falls back to its idle poll.
    if (!active_ && (cars_.empty() || now - stoppedAt_ > std::chrono::seconds(10))) return 0;
    // redscript steps only the cars whose vehicle it can find, so a car the game has streamed out or destroyed
    // simply stops being stepped. This is the one place that still runs every tick: say so once per dropout.
    if (active_) for (size_t i=0;i<cars_.size();++i) {
        Car& c=cars_[i];
        if (!c.haveStep || c.missing || c.finished || c.entity==0 || now-c.lastStepAt<std::chrono::milliseconds(1500)) continue;
        c.missing=true; c.dropouts++;
        char line[200]{};
        std::snprintf(line,sizeof(line),"car %zu DROPOUT #%u: not reported for 1.5 s (the game has no vehicle for it); last at %.0f,%.0f, %.1f m/s, point %zu/%zu",
            i,c.dropouts,c.last.x,c.last.y,c.speed,c.target,points_.size());
        if (logQueue_.size()<2000) logQueue_.emplace_back(line);
    }
    return static_cast<int>(cars_.size());
}

int State::revision()
{
    std::lock_guard lock(mutex_);
    return revision_;
}

uint64_t State::entity(int index)
{
    std::lock_guard lock(mutex_);
    if (index < 0 || static_cast<size_t>(index) >= cars_.size()) return 0;
    return cars_[static_cast<size_t>(index)].entity;
}

std::string State::step(int index, double x, double y, double z, Clock::time_point now)
{
    std::lock_guard lock(mutex_);
    if (index < 0 || static_cast<size_t>(index) >= cars_.size()) return "0|2|0|0|0|0|0|0|0|0";
    Car& c = cars_[static_cast<size_t>(index)];
    const Point pos{x, y, z};
    const int64_t tMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - goAt_).count();
    // Back after a gap (streamed back in, or re-created under the same id): find it on the road afresh, measure its
    // speed afresh, and send it a fresh command whatever it held before -- a new vehicle object has none.
    bool reacquired = false;
    if (c.haveStep && active_ && !c.finished && now - c.lastStepAt > std::chrono::milliseconds(1000)) {
        reacquired = true;
        const double gapS = std::chrono::duration<double>(now - c.lastStepAt).count();
        char line[220]{};
        std::snprintf(line, sizeof(line), "car %d BACK after %.1f s at %.0f,%.0f (%.0f m from where it was last seen), point %zu/%zu",
            index, gapS, x, y, c.haveLast ? dist(pos, c.last) : 0.0, c.target, points_.size());
        if (logQueue_.size() < 2000) logQueue_.emplace_back(line);
        c.roadLocated = false; c.roadAimed = false; c.haveSpeedAt = false; c.stallMs = 0;
    }
    c.missing = false;
    c.lastStepAt = now;
    c.haveStep = true;
    if (active_ && tMs >= 0 && !c.finished) {
        if (c.haveLast) {
            while (c.nextGate < gates_.size()) {
                const double f = crossFraction(gates_[c.nextGate], c.last, pos);
                if (f < 0) break;
                const int64_t at = c.lastMs + static_cast<int64_t>(std::llround((tMs - c.lastMs) * f));
                gateReports_++;
                push(nlohmann::json{{"gate", {{"entity", std::to_string(c.entity)}, {"vehicleId", c.vehicleId},
                    {"gate", static_cast<int>(c.nextGate) + 1}, {"tMs", at}}}}.dump());   // Lua's 1-based index
                c.nextGate++;
            }
            // a car that joined mid-race never finishes by a gate: on an oval the finish IS the start line it crosses
            // leaving the grid (KB-223: every car was told to stop). The server ends it with car.remove.
            if (complete_ && !c.dynamic && c.nextGate >= gates_.size()) c.finished = true;
        }
        c.last = pos;
        c.prevMs = c.lastMs;
        c.lastMs = tMs;
        c.haveLast = true;
        // Move the target on before the car reaches it (so the planner never brakes for an intermediate point),
        // and past any point the car has already gone beyond along its leg (a slow tick must not leave it chasing
        // a point behind it).
        while (c.target < points_.size()) {
            const Point& t = points_[c.target];
            const Point& p = points_[c.target - 1];
            const bool near = dist(pos, t) < advanceM;
            const bool byRoad = !pointRoad_.empty() && c.roadLocated && c.onRoad;
            const bool passed = byRoad ? c.roadIndex >= pointRoad_[c.target]
                                       : (pos.x - t.x) * (t.x - p.x) + (pos.y - t.y) * (t.y - p.y) > 0;
            if (!near && !passed) break;
            c.target++;
            char line[200]{};
            std::snprintf(line, sizeof(line), "car %d past point %zu/%zu at %.0f,%.0f, %.1f m/s (%s)",
                index, c.target - 1, points_.size(), pos.x, pos.y, c.speed, near ? "reached" : (byRoad ? "passed on the road" : "went beyond"));
            if (logQueue_.size() < 2000) logQueue_.emplace_back(line);
        }
    }
    // speed over >= 250 ms windows of the reported positions (20 Hz reports are too close together to difference)
    if (active_ && tMs >= 0) {
        if (!c.haveSpeedAt) { c.speedAt = pos; c.speedAtMs = tMs; c.haveSpeedAt = true; }
        else if (tMs - c.speedAtMs >= 250) {
            c.speed = dist(pos, c.speedAt) / ((tMs - c.speedAtMs) / 1000.0);
            c.speedAt = pos; c.speedAtMs = tMs;
        }
    }
    int mode;
    Point want{};
    float speed = 0;
    bool roadGuided = false;
    bool roadSteer = false;          // want comes from the road plan, not the checkpoint line
    Point roadWant{};
    double roadOff = -1;
    if (!active_ || c.finished) {
        mode = 2;
    } else if (tMs < 0) {
        mode = 0;
    } else {
        mode = 1;
        const size_t leg = c.target >= 1 ? c.target - 1 : 0;
        speed = c.speeds[leg < c.speeds.size() ? leg : c.speeds.size() - 1];
        const std::vector<Point>* speedRoad = nullptr;
        const std::vector<double>* speedLimits = nullptr;
        if (!roadLimits_.empty()) {speedRoad=&road_;speedLimits=&roadLimits_;}
        else if (!roadLegs_.empty()) {
            const size_t chosen=std::min(leg,roadLegs_.size()-1);
            if (!roadLegs_[chosen].limits.empty()) {
                speedRoad=&roadLegs_[chosen].points;speedLimits=&roadLegs_[chosen].limits;
                if (c.roadLeg!=chosen) {c.roadLeg=chosen;c.roadLocated=false;c.roadAimed=false;}
            }
        }
        roadGuided=speedRoad && speedLimits;
        if (roadGuided) {
            auto closest = [&](size_t lo, size_t hi) {
                double best = 1e100; size_t found = lo;
                for (size_t k=lo;k<hi;++k) {
                    const auto& p=(*speedRoad)[k];
                    const double d=std::hypot(p.x-pos.x,p.y-pos.y,2.0*(p.z-pos.z));
                    if (d<best) {best=d;found=k;}
                }
                return std::pair<double,size_t>{best,found};
            };
            auto [distance,at] = c.roadLocated ? closest(c.roadIndex>10?c.roadIndex-10:0,
                std::min(speedRoad->size(),c.roadIndex+100)) : closest(0,speedRoad->size());
            if (distance>60.0) std::tie(distance,at)=closest(0,speedRoad->size());
            roadOff=distance;
            // a car behind the plan's first point is on the road INTO it: the back of a twelve-car grid sat 51-74 m
            // behind and raced the whole first leg off the plan at a flat ceiling (KB-243)
            const bool on=distance<(at==0 ? kBehindStartM : 50.0);
            if (on!=c.onRoad && c.roadEvents<60) {
                c.roadEvents++;
                char line[200]{};
                std::snprintf(line,sizeof(line),"car %d %s the road plan at %.0f,%.0f: nearest plan point %.0f m (index %zu/%zu)",
                    index,on?"back on":"OFF",pos.x,pos.y,distance,at,speedRoad->size());
                if (logQueue_.size()<2000) logQueue_.emplace_back(line);
            }
            c.onRoad=on;
            if (on) {
                c.roadIndex=at;c.roadLocated=true;
                // The profile already propagates corner limits upstream. Sampling beyond a bend
                // can pick the post-corner acceleration and cancel the required braking.
                const size_t preview=at;
                // Driver variation raises only straight speed. Corner and upstream braking
                // limits stay common, so faster entrants do not exceed the lateral grip budget.
                const double straightCap=std::clamp(static_cast<double>(speed)*1.6,38.0,44.0);
                speed=static_cast<float>(std::min((*speedLimits)[preview],straightCap));
                // Steer along the plan (0.5.0). The native driver picks its own way to whatever destination it is
                // given; given the next checkpoint, then the finish 1+ km off, it replanned at the checkpoint and the
                // field left the road the speeds were computed for. A destination roadAimM along the plan keeps it on
                // that road, through every checkpoint, and beyond its braking distance (a near one makes it brake).
                auto along=[&](size_t from,size_t to){double s=0;for(size_t k=from;k<to&&k+1<speedRoad->size();++k)s+=std::hypot((*speedRoad)[k+1].x-(*speedRoad)[k].x,(*speedRoad)[k+1].y-(*speedRoad)[k].y);return s;};
                if (!c.roadAimed || c.roadAim<=at || along(at,c.roadAim)<roadReaimM) {
                    size_t k=at; double acc=0;
                    while (k+1<speedRoad->size() && acc<roadAimM) {acc+=std::hypot((*speedRoad)[k+1].x-(*speedRoad)[k].x,(*speedRoad)[k+1].y-(*speedRoad)[k].y);++k;}
                    c.roadAim=k; c.roadAimed=true;
                }
                // the plan's last stretch hands back to the line, which knows to aim beyond the finish
                if (c.roadAim+1<speedRoad->size()) {roadSteer=true;roadWant=(*speedRoad)[c.roadAim];}
            }
        }
        // off the plan in a road-planned race, the line's ceiling is the server's flat estimate (77.8 m/s for one car at
        // 20:30, KB-243): never above the plan's own straight-line cap
        if (roadGuided && !c.onRoad) speed = std::min(speed, static_cast<float>(kOffPlanCapMps));
        if (roadSteer) {
            want = roadWant;
        } else if (c.target < points_.size() && lookaheadM > 0) {
            // aim far along the line (0.4.1): re-aim only when the car is within half the lookahead of its aim
            bool reaim = c.aim < c.target || c.aim >= points_.size();
            if (!reaim) {
                double left = dist(pos, points_[c.target]);
                for (size_t k = c.target; k < c.aim; ++k) left += dist(points_[k], points_[k + 1]);
                // re-aim once the car has closed reaimFrac of the look-ahead: 0.5 (0.4.1), or ~0.9 for a ROLLING aim
                // that stays ahead of braking distance -- a near destination makes the AI brake for it (0.4.5)
                reaim = left < lookaheadM * reaimFrac && c.aim + 1 < points_.size();
            }
            if (reaim) {
                double acc = dist(pos, points_[c.target]);
                size_t k = c.target;
                while (k + 1 < points_.size() && acc < lookaheadM) { acc += dist(points_[k], points_[k + 1]); ++k; }
                c.aim = k;
            }
            want = points_[c.aim];
        } else if (c.target < points_.size()) {
            want = points_[c.target];
        } else if (!complete_) {
            want = points_.back();          // the tape has not caught up: hold the last known point, never run off it
        } else {
            // past the last point: aim beyond the finish so the car crosses the line instead of parking on it
            const Point& a = points_[points_.size() - 2];
            const Point& b = points_.back();
            const double len = std::max(1e-6, dist(a, b));
            want = {b.x + (b.x - a.x) / len * 80.0, b.y + (b.y - a.y) / len * 80.0, b.z};
        }
    }
    // the wrong-way guard (0.4.6): judged on real motion, never on a heading the car has not yet acted on
    if (mode == 1 && haveRing) {
        if (!c.haveMotion) { c.motionFrom = pos; c.motionMs = tMs; c.haveMotion = true; }
        else if (tMs - c.motionMs >= 150) {
            const double mx = pos.x - c.motionFrom.x, my = pos.y - c.motionFrom.y;
            const double mlen = std::hypot(mx, my);
            const double rx = pos.x - ringCx, ry = pos.y - ringCy;
            const double tx = -ry * ringSign, ty = rx * ringSign;           // the race direction round the ring here
            const double tlen = std::hypot(tx, ty);
            const bool backwards = mlen > 0.5 && tlen > 1e-6 && (mx * tx + my * ty) / (mlen * tlen) < -0.2;
            c.wrongMs = backwards ? c.wrongMs + (tMs - c.motionMs) : 0;
            c.motionFrom = pos;
            c.motionMs = tMs;
            if (c.wrongMs >= wrongWayMs && tMs >= c.forceUntil) {
                const double r = std::max(10.0, std::hypot(rx, ry));
                const double a = std::atan2(ry, rx) + ringSign * (25.0 / r);
                c.forceAt = {ringCx + r * std::cos(a), ringCy + r * std::sin(a), pos.z};
                c.forceUntil = tMs + 2500;
                c.wrongMs = 0;
                c.wrongEvents++;
                char line[200]{};
                std::snprintf(line, sizeof(line), "car %d WRONG WAY #%u at %.0f,%.0f: sent 25 m round the ring to %.0f,%.0f for 2.5 s",
                    index, c.wrongEvents, pos.x, pos.y, c.forceAt.x, c.forceAt.y);
                if (logQueue_.size() < 2000) logQueue_.emplace_back(line);
            }
        }
        if (tMs < c.forceUntil) want = c.forceAt;
    }
    bool renew = false;
    const char* why = (mode == 1 && haveRing && tMs < c.forceUntil) ? "wrong-way guard" : "target moved";
    if (mode == 1) {
        const double sinceGo = tMs / 1000.0;
        const int phase = sinceGo < launch.graceS ? 1 : 2;
        if (phase != c.phase) { c.phase = phase; renew = true; why = phase == 1 ? "launch release" : "race command"; }        // the release, then SP's post-launch command
        if (phase == 2) {
            // SP's stall rule: under stallMps for stallS -> a fresh command now; otherwise one every recommandS
            if (c.speed < launch.stallMps) {
                c.stallMs += std::max<int64_t>(0, tMs - c.prevMs);
            } else {
                c.stallMs = 0;
            }
            if (c.stallMs > static_cast<int64_t>(launch.stallS * 1000)) { renew = true; c.stallMs = 0; why = "stall kick"; }
            else if (tMs - c.cmdMs > static_cast<int64_t>((roadGuided ? std::max(3.0,launch.recommandS) : launch.recommandS) * 1000)) { renew = true; why = "recommand"; }
        }
        if (reacquired) { renew = true; c.stallMs = 0; why = "back: fresh command"; }
    } else {
        c.phase = 0;
    }
    if (renew || mode != c.mode || (mode == 1 && (std::fabs(want.x - c.cmd.x) > 0.5 || std::fabs(want.y - c.cmd.y) > 0.5 ||
                                         (std::fabs(speed - c.cmdSpeed) > (roadGuided ? 1.5f : 0.05f) &&
                                          (speed < c.cmdSpeed || tMs-c.cmdMs>=300))))) {
        if (renew && mode == c.mode) c.renewals++;
        if (mode != c.mode) why = mode == 1 ? "go" : (mode == 2 ? "stop" : "hold");
        // 0.4.2 (KB-223): every command a car is given, and why, so a car that starts and stops can be read, not
        // guessed at. 0.5.0: 400, not 40 -- 40 ran out a minute into a street race, before its first checkpoint.
        if (c.logged < 400) {
            c.logged++;
            // queued, not written: this runs on the GAME thread; the bridge thread writes it (drainLog)
            char line[320]{};
            std::snprintf(line, sizeof(line), "car %d cmd %u: %s, mode %d, at %.0f,%.0f speed %.1f m/s, to %.0f,%.0f (%.0f m away, %s, point %zu/%zu), ceiling %.1f",
                index, c.seq + 1, why, mode, pos.x, pos.y, c.speed, want.x, want.y, dist(pos, want),
                roadSteer ? "along road" : "line", c.target, points_.size(), static_cast<double>(speed));
            if (logQueue_.size() < 2000) logQueue_.emplace_back(line);
        }
        c.mode = mode;
        c.cmd = want;
        c.cmdSpeed = speed;
        c.cmdMs = tMs;
        c.seq++;
    }
    // one line per car every 5 s whatever happens, so a race can be followed end to end
    if (mode == 1 && tMs - c.statusMs >= 5000) {
        c.statusMs = tMs;
        char line[320]{};
        std::snprintf(line, sizeof(line), "car %d status: at %.0f,%.0f %.1f m/s, ceiling %.1f, %s, road %s (%.0f m off, index %zu), point %zu/%zu, %.0f m to destination, cmds %u, dropouts %u",
            index, pos.x, pos.y, c.speed, static_cast<double>(c.cmdSpeed), roadSteer ? "along road" : "line",
            roadGuided ? (c.onRoad ? "on" : "OFF") : "none", roadOff, c.roadIndex, c.target, points_.size(), dist(pos, c.cmd), c.seq, c.dropouts);
        if (logQueue_.size() < 2000) logQueue_.emplace_back(line);
    }
    // what to hold: the capped launch release, or the race command (SP buildLaunchReleaseProfile / buildDriveProfile)
    double mx = c.cmdSpeed, mn = 0, forced = 0, dd = launch.raceDist;
    int boost = 0;
    if (c.mode == 1 && c.phase == 1) {
        mx = std::min<double>(c.cmdSpeed, launch.relMax);
        mn = std::min(launch.relMin, mx);
        forced = std::min(launch.relForced, mx);
        dd = std::max(4.0, launch.relDist);
    } else if (c.mode == 1) {
        mn = mx * launch.minFrac;
        forced = mx * launch.forcedFrac;
        boost = 1;
    }
    return std::to_string(c.seq) + "|" + std::to_string(c.mode) + "|" + fmt(c.cmd.x) + "|" + fmt(c.cmd.y) + "|" +
           fmt(c.cmd.z) + "|" + fmt(mx) + "|" + fmt(mn) + "|" + fmt(forced) + "|" + fmt(dd) + "|" + std::to_string(boost);
}

std::vector<std::string> State::outbox()
{
    std::lock_guard lock(mutex_);
    std::vector<std::string> out;
    out.swap(out_);
    return out;
}

std::vector<std::string> State::drainLog()
{
    std::lock_guard lock(mutex_);
    std::vector<std::string> out;
    out.swap(logQueue_);
    return out;
}

std::string State::refusal()
{
    std::lock_guard lock(mutex_);
    return refusal_;
}

std::string State::health()
{
    std::lock_guard lock(mutex_);
    return nlohmann::json{{"health", {{"version", NCM_PACE_VERSION}, {"active", active_}, {"cars", cars_.size()},
        {"race", raceId_}, {"revision", revision_}, {"gateReports", gateReports_}}}}.dump();
}

std::string State::banner(Clock::time_point now)
{
    std::lock_guard lock(mutex_);
    const int64_t left = std::chrono::duration_cast<std::chrono::milliseconds>(bannerUntil_ - now).count();
    const bool visible = left > 0 && !bannerTitle_.empty();
    auto field = [](const std::string& t) { return t.empty() ? std::string("~") : t; };
    return std::to_string(bannerRev_) + "|" + (visible ? "1" : "0") + "|" + field(bannerTitle_) + "|" + field(bannerDetail_) + "|" +
           std::to_string(visible ? (left + 999) / 1000 : 0);
}

std::string State::area(Clock::time_point now)
{
    std::lock_guard lock(mutex_);
    const int64_t left = std::chrono::duration_cast<std::chrono::milliseconds>(areaUntil_ - now).count();
    const bool visible = left > 0 && areaHalf_ > 0;
    return std::to_string(areaRev_) + "|" + (visible ? "1" : "0") + "|" + fmt(areaAt_.x) + "|" + fmt(areaAt_.y) + "|" +
           fmt(areaAt_.z) + "|" + fmt(areaHalf_) + "|" + fmt(areaHalfZ_) + "|" + std::to_string(visible ? (left + 999) / 1000 : 0);
}

State& state()
{
    static State instance;
    return instance;
}
}
