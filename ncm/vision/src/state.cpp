#include "state.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace ncm::vision {

State& state()
{
    static State instance;
    return instance;
}

std::string clean(const std::string& text, size_t limit)
{
    std::string out;
    out.reserve(std::min(text.size(), limit));
    for (const char c : text) {
        if (out.size() >= limit) break;
        if (c == '|' || c == '~' || static_cast<unsigned char>(c) < 0x20) continue;
        out.push_back(c);
    }
    return out;
}

uint32_t crc32(std::string_view text)
{
    uint32_t crc = 0xFFFFFFFFu;
    for (const char c : text) {
        crc ^= static_cast<uint8_t>(c);
        for (int i = 0; i < 8; ++i) crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

// The identity half of a TweakDBID: CRC32 of the name, then its length. `TDBID.ToNumber` returns the same
// 64 bits with the TweakDB offset in the top three bytes, which is why both sides are masked.
uint64_t recordKey(std::string_view name)
{
    return (static_cast<uint64_t>(crc32(name)) | (static_cast<uint64_t>(name.size() & 0xFF) << 32)) & kRecordMask;
}

bool State::apply(const std::string& message, Clock::time_point now)
{
    const auto m = nlohmann::json::parse(message, nullptr, false);
    if (!m.is_object()) return false;
    const auto cmd = m.value("cmd", std::string());
    std::lock_guard lock(mutex_);
    if (cmd == "frame") {
        const int s = m.value("state", 0);
        state_ = (s >= 0 && s <= 6) ? s : 0;
        progress_ = std::clamp(m.value("progress", 0.0f), 0.0f, 1.0f);
        title_ = clean(m.value("title", std::string()), 64);
        detail_ = clean(m.value("detail", std::string()), 96);
        lastFrame_ = now;
        haveFrame_ = true;
        staleCleared_ = false;
        ++revision_;
        return true;
    }
    return cmd == "ping";
}

void State::disconnect()
{
    std::lock_guard lock(mutex_);
    haveFrame_ = false;
    state_ = 0;
    progress_ = 0.0f;
    title_.clear();
    detail_.clear();
    ++revision_;
}

std::string State::reticle(Clock::time_point now)
{
    std::lock_guard lock(mutex_);
    if (haveFrame_ && now - lastFrame_ > std::chrono::milliseconds(kStaleMs)) {
        haveFrame_ = false;
        staleCleared_ = true;
        state_ = 0;
        progress_ = 0.0f;
        title_.clear();
        detail_.clear();
        ++revision_;
    }
    char progress[16]{};
    std::snprintf(progress, sizeof(progress), "%.3f", progress_);
    return std::to_string(revision_) + "|" + std::to_string(state_) + "|" + progress + "|" +
           (title_.empty() ? "~" : title_) + "|" + (detail_.empty() ? "~" : detail_);
}

void State::report(bool active, uint64_t entity, uint64_t record, int kind, float distance)
{
    std::lock_guard lock(mutex_);
    const uint64_t masked = record & kRecordMask;
    if (target_.active == active && target_.entity == entity && target_.record == masked && target_.kind == kind &&
        std::abs(target_.distance - distance) < 0.5f)
        return;
    target_.active = active;
    target_.entity = active ? entity : 0;
    target_.record = active ? masked : 0;
    target_.kind = active ? kind : 0;
    target_.distance = active ? distance : -1.0f;
    ++target_.seq;
}

std::string State::targetJson()
{
    std::lock_guard lock(mutex_);
    nlohmann::json v{
        { "active", target_.active },
        // Strings, not numbers: a 64-bit hash does not survive a JSON double, and Lua compares these as text.
        { "entity", target_.entity ? std::to_string(target_.entity) : std::string() },
        { "recordKey", target_.record ? std::to_string(target_.record) : std::string() },
        { "kind", target_.kind == 1 ? "vehicle" : (target_.kind == 2 ? "other" : "none") },
        { "distance", target_.distance },
        { "seq", target_.seq },
    };
    return nlohmann::json{ { "vision", v } }.dump();
}

std::string State::health()
{
    std::lock_guard lock(mutex_);
    nlohmann::json h{
        { "version", NCM_VISION_VERSION },
        { "staleCleared", staleCleared_ },
        { "active", target_.active },
    };
    return nlohmann::json{ { "health", h } }.dump();
}

}
