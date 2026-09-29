#include "state.hpp"

#include <nlohmann/json.hpp>

#include <cmath>
#include <cstdio>

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

bool State::apply(const std::string& text, Clock::time_point now)
{
    const auto j = nlohmann::json::parse(text, nullptr, false);
    if (!j.is_object()) return false;
    const std::string cmd = j.value("cmd", std::string());
    std::lock_guard lock(mutex_);
    if (cmd == "drive.end" || cmd == "drive.cancel") {
        stopAll(cmd.c_str());
        return true;
    }
    if (cmd != "drive.start") return false;
    const auto& pts = j.value("points", nlohmann::json::array());
    const auto& gts = j.value("gates", nlohmann::json::array());
    const auto& crs = j.value("cars", nlohmann::json::array());
    if (!pts.is_array() || pts.size() < 2 || pts.size() > kMaxPoints) return false;
    if (!gts.is_array() || gts.size() < 2 || gts.size() > kMaxGates) return false;
    if (!crs.is_array() || crs.empty() || crs.size() > kMaxCars) return false;
    std::vector<Point> points;
    for (const auto& p : pts) {
        if (!p.is_object()) return false;
        points.push_back({p.value("x", 0.0), p.value("y", 0.0), p.value("z", 0.0)});
    }
    std::vector<Gate> gates;
    for (const auto& g : gts) {
        if (!g.is_object()) return false;
        Gate x;
        x.x = g.value("x", 0.0); x.y = g.value("y", 0.0); x.z = g.value("z", 0.0);
        x.dx = g.value("dx", 1.0); x.dy = g.value("dy", 0.0);
        const double len = std::hypot(x.dx, x.dy);
        if (len < 1e-6) return false;
        x.dx /= len; x.dy /= len;
        x.halfWidth = g.value("halfWidth", 28.0);
        x.capture = g.value("capture", 35.0);
        gates.push_back(x);
    }
    std::vector<Car> cars;
    for (const auto& c : crs) {
        if (!c.is_object()) return false;
        Car car;
        if (c.contains("entity") && c["entity"].is_string()) car.entity = parseHash(c["entity"].get<std::string>());
        else if (c.contains("entity") && c["entity"].is_number_unsigned()) car.entity = c["entity"].get<uint64_t>();
        if (car.entity == 0) return false;
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
    const int64_t goIn = j.value("goInMs", static_cast<int64_t>(0));
    goAt_ = now + std::chrono::milliseconds(goIn < 0 ? 0 : goIn);
    active_ = true;
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
    if (index < 0 || static_cast<size_t>(index) >= cars_.size()) return "0|2|0|0|0|0";
    Car& c = cars_[static_cast<size_t>(index)];
    const Point pos{x, y, z};
    const int64_t tMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - goAt_).count();
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
            if (c.nextGate >= gates_.size()) c.finished = true;
        }
        c.last = pos;
        c.lastMs = tMs;
        c.haveLast = true;
        // Move the target on before the car reaches it (so the planner never brakes for an intermediate point),
        // and past any point the car has already gone beyond along its leg (a slow tick must not leave it chasing
        // a point behind it).
        while (c.target < points_.size()) {
            const Point& t = points_[c.target];
            const Point& p = points_[c.target - 1];
            const bool near = dist(pos, t) < advanceM;
            const bool passed = (pos.x - t.x) * (t.x - p.x) + (pos.y - t.y) * (t.y - p.y) > 0;
            if (!near && !passed) break;
            c.target++;
        }
    }
    int mode;
    Point want{};
    float speed = 0;
    if (!active_ || c.finished) {
        mode = 2;
    } else if (tMs < 0) {
        mode = 0;
    } else {
        mode = 1;
        const size_t leg = c.target >= 1 ? c.target - 1 : 0;
        speed = c.speeds[leg < c.speeds.size() ? leg : c.speeds.size() - 1];
        if (c.target < points_.size()) {
            want = points_[c.target];
        } else {
            // past the last point: aim 80 m beyond the finish so the car crosses the line instead of parking on it
            const Point& a = points_[points_.size() - 2];
            const Point& b = points_.back();
            const double len = std::max(1e-6, dist(a, b));
            want = {b.x + (b.x - a.x) / len * 80.0, b.y + (b.y - a.y) / len * 80.0, b.z};
        }
    }
    if (mode != c.mode || (mode == 1 && (std::fabs(want.x - c.cmd.x) > 0.5 || std::fabs(want.y - c.cmd.y) > 0.5 ||
                                         std::fabs(speed - c.cmdSpeed) > 0.05f))) {
        c.mode = mode;
        c.cmd = want;
        c.cmdSpeed = speed;
        c.seq++;
    }
    return std::to_string(c.seq) + "|" + std::to_string(c.mode) + "|" + fmt(c.cmd.x) + "|" + fmt(c.cmd.y) + "|" +
           fmt(c.cmd.z) + "|" + fmt(c.cmdSpeed);
}

std::vector<std::string> State::outbox()
{
    std::lock_guard lock(mutex_);
    std::vector<std::string> out;
    out.swap(out_);
    return out;
}

std::string State::health()
{
    std::lock_guard lock(mutex_);
    return nlohmann::json{{"health", {{"version", NCM_PACE_VERSION}, {"active", active_}, {"cars", cars_.size()},
        {"race", raceId_}, {"revision", revision_}, {"gateReports", gateReports_}}}}.dump();
}

State& state()
{
    static State instance;
    return instance;
}
}
