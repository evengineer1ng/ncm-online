#include "state.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cstdio>

namespace ncm::broadcast {
namespace {
std::string fmt(double v)
{
    char b[32];
    std::snprintf(b, sizeof(b), "%.2f", v);
    return b;
}

std::string field(const std::string& t) { return t.empty() ? std::string("~") : t; }

std::string text(const nlohmann::json& j, const char* key, size_t max)
{
    if (!j.contains(key)) return {};
    const auto& v = j[key];
    if (v.is_string()) return clean(v.get<std::string>(), max);
    if (v.is_number_integer()) return clean(std::to_string(v.get<int64_t>()), max);
    return {};
}

std::chrono::milliseconds ttlOf(const nlohmann::json& j, double fallback)
{
    double s = j.value("ttl", fallback);
    s = std::min(60.0, std::max(0.5, s));
    return std::chrono::milliseconds(static_cast<int64_t>(s * 1000));
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

std::string clean(std::string t, size_t max)
{
    for (char& ch : t) if (ch == '|' || ch == 10 || ch == 13) ch = ' ';
    if (t.size() > max) t.resize(max);
    return t;
}

bool State::apply(const std::string& raw, Clock::time_point now)
{
    const auto j = nlohmann::json::parse(raw, nullptr, false);
    if (!j.is_object()) return false;
    const std::string cmd = j.value("cmd", std::string());
    std::lock_guard lock(mutex_);
    if (cmd == "labels") {
        const auto& items = j.value("items", nlohmann::json::array());
        if (!items.is_array()) return false;
        std::vector<Label> next;
        for (const auto& it : items) {
            if (!it.is_object() || next.size() >= kMaxLabels) continue;
            Label l;
            if (it.contains("entity") && it["entity"].is_string()) l.entity = parseHash(it["entity"].get<std::string>());
            else if (it.contains("entity") && it["entity"].is_number_unsigned()) l.entity = it["entity"].get<uint64_t>();
            if (l.entity == 0) continue;
            l.title = text(it, "title", 40);
            l.sub = text(it, "sub", 40);
            l.chip = text(it, "chip", 6);
            l.accent = std::min(3, std::max(0, it.value("accent", 0)));
            next.push_back(std::move(l));
        }
        labels_ = std::move(next);
        labelsUntil_ = now + ttlOf(j, 3.0);
        ++messages_;
        return true;
    }
    if (cmd == "tower") {
        const auto& rows = j.value("rows", nlohmann::json::array());
        if (!rows.is_array()) return false;
        std::vector<Row> next;
        for (const auto& r : rows) {
            if (!r.is_object() || next.size() >= kMaxRows) continue;
            next.push_back({text(r, "pos", 4), text(r, "name", 28), text(r, "gap", 12), text(r, "flag", 6)});
        }
        towerTitle_ = text(j, "title", 40);
        towerSub_ = text(j, "sub", 48);
        rows_ = std::move(next);
        towerUntil_ = rows_.empty() ? now : now + ttlOf(j, 5.0);
        ++towerRev_;
        ++messages_;
        return true;
    }
    if (cmd == "view") {
        View v = view_;
        v.range = std::min(1000.0, std::max(20.0, j.value("range", v.range)));
        v.scale = std::min(3.0, std::max(0.3, j.value("scale", v.scale)));
        v.projX = std::min(8000.0, std::max(100.0, j.value("projX", v.projX)));
        v.projY = std::min(8000.0, std::max(100.0, j.value("projY", v.projY)));
        v.lift = std::min(10.0, std::max(0.0, j.value("lift", v.lift)));
        v.towerX = std::min(3000.0, std::max(0.0, j.value("towerX", v.towerX)));
        v.towerY = std::min(2000.0, std::max(0.0, j.value("towerY", v.towerY)));
        view_ = v;
        ++viewRev_;
        return true;
    }
    return false;
}

void State::disconnect()
{
    std::lock_guard lock(mutex_);
    labels_.clear();
    rows_.clear();
    ++towerRev_;
}

int State::labelCount(Clock::time_point now)
{
    std::lock_guard lock(mutex_);
    if (now > labelsUntil_) return 0;
    return static_cast<int>(labels_.size());
}

uint64_t State::labelEntity(int index)
{
    std::lock_guard lock(mutex_);
    if (index < 0 || static_cast<size_t>(index) >= labels_.size()) return 0;
    return labels_[static_cast<size_t>(index)].entity;
}

std::string State::labelText(int index)
{
    std::lock_guard lock(mutex_);
    if (index < 0 || static_cast<size_t>(index) >= labels_.size()) return "~|~|~|0";
    const Label& l = labels_[static_cast<size_t>(index)];
    return field(l.title) + "|" + field(l.sub) + "|" + field(l.chip) + "|" + std::to_string(l.accent);
}

std::string State::tower(Clock::time_point now)
{
    std::lock_guard lock(mutex_);
    const bool visible = !rows_.empty() && now <= towerUntil_;
    // the revision moves when the tower expires too, so redscript hides it without a message
    const int rev = towerRev_ * 2 + (visible ? 1 : 0);
    return std::to_string(rev) + "|" + (visible ? "1" : "0") + "|" + field(towerTitle_) + "|" + field(towerSub_) + "|" +
           std::to_string(visible ? rows_.size() : 0);
}

std::string State::towerRow(int index)
{
    std::lock_guard lock(mutex_);
    if (index < 0 || static_cast<size_t>(index) >= rows_.size()) return "~|~|~|~";
    const Row& r = rows_[static_cast<size_t>(index)];
    return field(r.pos) + "|" + field(r.name) + "|" + field(r.gap) + "|" + field(r.flag);
}

std::string State::view()
{
    std::lock_guard lock(mutex_);
    const View& v = view_;
    return std::to_string(viewRev_) + "|" + fmt(v.range) + "|" + fmt(v.scale) + "|" + fmt(v.projX) + "|" + fmt(v.projY) + "|" +
           fmt(v.lift) + "|" + fmt(v.towerX) + "|" + fmt(v.towerY);
}

std::string State::health()
{
    std::lock_guard lock(mutex_);
    return nlohmann::json{{"health", {{"version", NCM_BROADCAST_VERSION}, {"labels", labels_.size()}, {"rows", rows_.size()},
        {"messages", messages_}}}}.dump();
}

std::vector<std::string> State::outbox()
{
    std::lock_guard lock(mutex_);
    std::vector<std::string> out;
    out.swap(out_);
    return out;
}

State& state()
{
    static State instance;
    return instance;
}
}
