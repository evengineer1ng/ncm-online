#include "state.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace ncm::radial {
namespace {
using json = nlohmann::json;

std::string text(const json& object, const char* key, size_t limit)
{
    if (!object.is_object() || !object.contains(key) || !object[key].is_string()) return {};
    return clean(object[key].get<std::string>(), limit);
}
}

std::string clean(const std::string& value, size_t limit)
{
    std::string out;
    out.reserve(std::min(value.size(), limit));
    for (const char c : value) {
        if (out.size() >= limit) break;
        const auto u = static_cast<unsigned char>(c);
        if (c == '|' || u < 0x20 || u == 0x7f) continue;   // '|' is the redscript field separator
        out.push_back(c);
    }
    return out;
}

bool State::apply(const std::string& message, Clock::time_point now)
{
    json m = json::parse(message, nullptr, false);
    if (!m.is_object()) return false;
    const std::string cmd = m.value("cmd", std::string());
    std::lock_guard lock(mutex_);

    if (cmd == "layout") {
        if (!m.contains("slots") || !m["slots"].is_array()) return false;
        std::array<Slot, kSlots> next{};
        const auto& list = m["slots"];
        for (size_t i = 0; i < list.size() && i < static_cast<size_t>(kSlots); ++i) {
            const auto& s = list[i];
            if (!s.is_object()) continue;          // null / absent = an open slot
            Slot slot;
            slot.state = std::clamp(s.value("state", 1), 0, 2);
            slot.label = text(s, "label", 40);
            slot.key = text(s, "key", 24);
            slot.detail = text(s, "detail", 90);
            if (slot.label.empty()) slot.state = 0;
            next[i] = std::move(slot);
        }
        slots_ = std::move(next);
        title_ = text(m, "title", 40);
        hint_ = text(m, "hint", 120);
        ++revision_;
        return true;
    }

    if (cmd == "frame") {
        open_ = m.value("open", false);
        const int sel = m.value("sel", -1);
        selected_ = (sel >= 0 && sel < kSlots) ? sel : -1;
        float p = -1.0f;
        if (m.contains("pointer") && m["pointer"].is_number()) p = m["pointer"].get<float>();
        pointer_ = (std::isfinite(p) && p >= 0.0f) ? std::fmod(p, 360.0f) : -1.0f;
        lastFrame_ = now;
        staleClosed_ = false;
        return true;
    }
    return false;
}

void State::disconnect()
{
    std::lock_guard lock(mutex_);
    open_ = false;
    selected_ = -1;
    pointer_ = -1.0f;
}

std::string State::frame(Clock::time_point now)
{
    std::lock_guard lock(mutex_);
    if (open_ && std::chrono::duration_cast<std::chrono::milliseconds>(now - lastFrame_).count() > kStaleMs) {
        open_ = false;
        selected_ = -1;
        pointer_ = -1.0f;
        staleClosed_ = true;
    }
    char buffer[96]{};
    std::snprintf(buffer, sizeof(buffer), "%d|%d|%.1f|%d", open_ ? 1 : 0, selected_, pointer_, revision_);
    return buffer;
}

std::string State::layout()
{
    std::lock_guard lock(mutex_);
    std::string out = std::to_string(revision_) + "|" + title_ + "|" + hint_;
    for (const auto& s : slots_) {
        out += "|" + std::to_string(s.state) + "|" + s.label + "|" + s.key + "|" + s.detail;
    }
    return out;
}

void State::reportHost(const std::string& host, int drawn)
{
    std::lock_guard lock(mutex_);
    host_ = clean(host, 64);
    drawn_ = drawn;
}

std::string State::health()
{
    std::lock_guard lock(mutex_);
    json h{{"version", NCM_RADIAL_VERSION}, {"host", host_}, {"drawn", drawn_}, {"open", open_},
           {"revision", revision_}, {"staleClosed", staleClosed_}};
    return json{{"radial", h}}.dump();
}

State& state()
{
    static State instance;
    return instance;
}
}
