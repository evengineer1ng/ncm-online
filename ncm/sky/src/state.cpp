#include "state.hpp"

#include <nlohmann/json.hpp>

#include <cmath>
#include <cstdio>

namespace ncm::sky {

State& state()
{
    static State instance;
    return instance;
}

bool validId(const std::string& id)
{
    if (id.empty() || id.size() > 24) return false;
    for (const char c : id) {
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) return false;
    }
    return true;
}

namespace {
// REDengine's world box (KB-411): nothing NCM places may sit outside it
constexpr double kBoxM = 16000.0;

bool finite(double v) { return std::isfinite(v); }

std::string number(double v)
{
    char buffer[48]{};
    std::snprintf(buffer, sizeof(buffer), "%.3f", v);
    return buffer;
}

std::string quat(double v)
{
    char buffer[48]{};
    std::snprintf(buffer, sizeof(buffer), "%.7f", v);
    return buffer;
}
}

bool State::apply(const std::string& message, Clock::time_point now)
{
    const auto m = nlohmann::json::parse(message, nullptr, false);
    if (!m.is_object() || m.value("cmd", std::string()) != "scene") return false;
    // an empty Lua table arrives as {} rather than []: both mean "nothing in the sky"
    const auto& given = m.contains("bodies") ? m["bodies"] : nlohmann::json();
    const auto list = (given.is_object() && given.empty()) ? nlohmann::json::array() : given;
    if (!list.is_array() || list.size() > kMaxBodies) return false;
    std::vector<Body> next;
    for (const auto& b : list) {
        if (!b.is_object()) return false;
        Body body;
        body.id = b.value("id", std::string());
        body.kind = b.value("kind", 0);
        body.appearance = b.value("app", std::string());
        const auto& p = b.contains("p") ? b["p"] : nlohmann::json();
        const auto& q = b.contains("q") ? b["q"] : nlohmann::json();
        if (!validId(body.id) || body.kind <= 0 || (!body.appearance.empty() && !validId(body.appearance))) return false;
        if (!p.is_array() || p.size() != 3 || !q.is_array() || q.size() != 4) return false;
        for (int i = 0; i < 3; ++i) if (!p[i].is_number()) return false;
        for (int i = 0; i < 4; ++i) if (!q[i].is_number()) return false;
        body.x = p[0].get<double>(); body.y = p[1].get<double>(); body.z = p[2].get<double>();
        body.qi = q[0].get<double>(); body.qj = q[1].get<double>(); body.qk = q[2].get<double>(); body.qr = q[3].get<double>();
        for (const double v : { body.x, body.y, body.z, body.qi, body.qj, body.qk, body.qr }) {
            if (!finite(v)) return false;
        }
        // a rotation is a UNIT quaternion: normalise one that drifted, refuse one that is not a rotation at all
        const double n = std::sqrt(body.qi * body.qi + body.qj * body.qj + body.qk * body.qk + body.qr * body.qr);
        if (n < 0.5 || n > 1.5) return false;
        body.qi /= n; body.qj /= n; body.qk /= n; body.qr /= n;
        if (std::fabs(body.x) > kBoxM || std::fabs(body.y) > kBoxM || std::fabs(body.z) > kBoxM) return false;
        for (const auto& seen : next) {
            if (seen.id == body.id) return false;
        }
        next.push_back(body);
    }
    std::lock_guard lock(mutex_);
    bool same = next.size() == bodies_.size();
    for (size_t i = 0; same && i < next.size(); ++i) {
        const auto& a = next[i];
        const auto& b = bodies_[i];
        same = a.id == b.id && a.kind == b.kind && a.appearance == b.appearance && a.x == b.x && a.y == b.y && a.z == b.z &&
            a.qi == b.qi && a.qj == b.qj && a.qk == b.qk && a.qr == b.qr;
    }
    if (!same) {
        bodies_ = std::move(next);
        ++revision_;
    }
    lastScene_ = now;
    haveScene_ = true;
    staleCleared_ = false;
    return true;
}

void State::disconnect()
{
    std::lock_guard lock(mutex_);
    if (!bodies_.empty()) ++revision_;
    bodies_.clear();
    haveScene_ = false;
}

std::string State::scene(Clock::time_point now)
{
    std::lock_guard lock(mutex_);
    if (haveScene_ && std::chrono::duration_cast<std::chrono::milliseconds>(now - lastScene_).count() > kStaleMs) {
        if (!bodies_.empty()) ++revision_;
        bodies_.clear();
        haveScene_ = false;
        staleCleared_ = true;
    }
    std::string out = std::to_string(revision_) + "|";
    for (size_t i = 0; i < bodies_.size(); ++i) {
        const auto& b = bodies_[i];
        if (i) out += "^";
        out += b.id + "`" + std::to_string(b.kind) + "`" + (b.appearance.empty() ? "~" : b.appearance) + "`" + number(b.x) + "`" +
            number(b.y) + "`" + number(b.z) + "`" + quat(b.qi) + "`" + quat(b.qj) + "`" + quat(b.qk) + "`" + quat(b.qr);
    }
    return out;
}

void State::report(const std::string& id, int value, uint64_t entity, const std::string& why)
{
    if (!validId(id)) return;
    std::lock_guard lock(mutex_);
    if (value == 4) { reports_.erase(id); return; }
    auto& r = reports_[id];
    r.state = value;
    r.entity = entity;
    r.why = why.substr(0, 120);
}

std::string State::statusJson()
{
    std::lock_guard lock(mutex_);
    nlohmann::json bodies = nlohmann::json::object();
    for (const auto& [id, r] : reports_) {
        bodies[id] = { { "state", r.state }, { "entity", std::to_string(r.entity) }, { "why", r.why } };
    }
    return nlohmann::json{ { "sky", { { "rev", revision_ }, { "bodies", bodies } } } }.dump();
}

std::string State::health()
{
    std::lock_guard lock(mutex_);
    nlohmann::json h{ { "version", NCM_SKY_VERSION }, { "staleCleared", staleCleared_ }, { "bodies", bodies_.size() } };
    return nlohmann::json{ { "health", h } }.dump();
}

}
