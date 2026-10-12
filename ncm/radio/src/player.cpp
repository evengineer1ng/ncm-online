#include "player.hpp"

#include "log.hpp"

#include <miniaudio.h>
#include <nlohmann/json.hpp>

#include <windows.h>

#include <fstream>

namespace ncm::radio {

struct Player::Audio {
    ma_engine engine{};
    ma_sound sound{};
    bool engineUp = false;
    bool soundUp = false;
};

namespace {
constexpr auto kHeartbeatTimeout = std::chrono::milliseconds(750);
constexpr size_t kMaxClips = 600;

bool fileExists(const std::wstring& path)
{
    return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

std::string readSmall(const std::wstring& path)
{
    std::ifstream in(path, std::ios::binary);
    if (!in) return {};
    std::string s((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    if (s.size() > 256) s.resize(256);
    while (!s.empty() && (s.back() == '\n' || s.back() == '\r' || s.back() == ' ')) s.pop_back();
    return s;
}
}

Player::Player(std::wstring packDir) : audio_(std::make_unique<Audio>()), packDir_(std::move(packDir))
{
    packPresent_ = fileExists(packDir_ + L"\\clips");
    packVersion_ = readSmall(packDir_ + L"\\VERSION");
}

Player::~Player()
{
    stopSound();
    if (audio_->engineUp) ma_engine_uninit(&audio_->engine);
}

bool Player::start()
{
    if (audio_->engineUp) return true;
    ma_engine_config config = ma_engine_config_init();
    config.listenerCount = 1;
    if (ma_engine_init(&config, &audio_->engine) != MA_SUCCESS) {
        RADIO_ERR("no audio device; the station stays silent");
        return false;
    }
    audio_->engineUp = true;
    RADIO_INFO("audio up: %u Hz; pack %s (version %s)", ma_engine_get_sample_rate(&audio_->engine),
               packPresent_ ? "present" : "MISSING", packVersion_.empty() ? "?" : packVersion_.c_str());
    return true;
}

bool Player::apply(const std::string& json)
{
    const auto m = nlohmann::json::parse(json, nullptr, false);
    if (!m.is_object()) return false;
    const auto cmd = m.value("cmd", std::string());
    std::lock_guard lock(mutex_);
    if (cmd == "item") {
        const auto& clips = m.value("clips", nlohmann::json::array());
        if (!clips.is_array() || clips.size() > kMaxClips) return false;
        Item next;
        next.seq = m.value("seq", uint64_t{0});
        next.beat = m.value("beat", std::string());
        for (const auto& c : clips) {
            if (!c.is_object()) return false;
            Clip clip;
            clip.key = c.value("k", std::string());
            clip.ms = c.value("ms", 0);
            clip.gapMs = c.value("gap", 0);
            if (clip.ms < 0 || clip.ms > 10 * 60 * 1000 || clip.gapMs < 0 || clip.gapMs > 5 * 60 * 1000) return false;
            next.clips.push_back(std::move(clip));
        }
        const int64_t offset = m.value("offsetMs", int64_t{0});
        item_ = std::move(next);
        hasItem_ = true;
        itemStart_ = std::chrono::steady_clock::now() - std::chrono::milliseconds(offset < 0 ? 0 : offset);
        playingIndex_ = -1;       // the next update starts the right clip at the right place
        return true;
    }
    if (cmd == "stop") {
        hasItem_ = false;
        playingIndex_ = -1;
        return true;
    }
    return false;
}

void Player::heartbeat(bool listening, float volume)
{
    std::lock_guard lock(mutex_);
    listening_ = listening;
    if (volume >= 0.0f && volume <= 1.5f) volume_ = volume;
    lastBeat_ = std::chrono::steady_clock::now();
}

void Player::stopSound()
{
    if (audio_->soundUp) {
        ma_sound_stop(&audio_->sound);
        ma_sound_uninit(&audio_->sound);
        audio_->soundUp = false;
    }
}

bool Player::startClip(const Clip& clip, int32_t intoMs)
{
    stopSound();
    const std::wstring path = clipPath(packDir_, clip.key);
    if (!fileExists(path)) {
        if (++missing_ <= 50) RADIO_WARN("missing clip %s", clip.key.c_str());
        return false;
    }
    const ma_uint32 flags = MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_SPATIALIZATION | MA_SOUND_FLAG_NO_PITCH;
    if (ma_sound_init_from_file_w(&audio_->engine, path.c_str(), flags, nullptr, nullptr, &audio_->sound) != MA_SUCCESS) {
        if (++missing_ <= 50) RADIO_WARN("cannot open clip %s", clip.key.c_str());
        return false;
    }
    audio_->soundUp = true;
    if (intoMs > 40) {
        ma_uint32 rate = 0;
        ma_sound_get_data_format(&audio_->sound, nullptr, nullptr, &rate, nullptr, 0);
        if (rate == 0) rate = 24000;
        ma_sound_seek_to_pcm_frame(&audio_->sound, static_cast<ma_uint64>(intoMs) * rate / 1000);
    }
    ma_sound_set_volume(&audio_->sound, volume_);
    ma_sound_start(&audio_->sound);
    return true;
}

void Player::update()
{
    if (!audio_->engineUp) return;
    std::lock_guard lock(mutex_);
    const auto now = std::chrono::steady_clock::now();
    const bool alive = (now - lastBeat_) < kHeartbeatTimeout;
    const bool audible = alive && listening_ && hasItem_ && packPresent_;

    if (!reportedOnce_ || reportedListening_ != (alive && listening_)) {
        reportedOnce_ = true;
        reportedListening_ = alive && listening_;
        outbox_.push_back(nlohmann::json{{"listening", reportedListening_}}.dump());
    }
    if (!audible) {
        if (audio_->soundUp) stopSound();
        playingIndex_ = -1;
        return;
    }
    const int64_t elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - itemStart_).count();
    const Position at = locate(item_, elapsed);
    if (at.index < 0) {
        if (audio_->soundUp && !ma_sound_is_playing(&audio_->sound)) stopSound();
        if (at.ended) playingIndex_ = -1;
        return;
    }
    if (at.index != playingIndex_ || playingSeq_ != item_.seq) {
        playingIndex_ = at.index;
        playingSeq_ = item_.seq;
        startClip(item_.clips[static_cast<size_t>(at.index)], at.intoClipMs);
        return;
    }
    if (audio_->soundUp) ma_sound_set_volume(&audio_->sound, volume_);
}

std::string Player::status() const
{
    std::lock_guard lock(mutex_);
    return hasItem_ ? item_.beat : std::string();
}

std::string Player::health() const
{
    std::lock_guard lock(mutex_);
    return nlohmann::json{{"health", {{"version", NCM_RADIO_VERSION}, {"pack", packPresent_}, {"packVersion", packVersion_},
                                      {"audio", audio_->engineUp}, {"listening", listening_}}}}.dump();
}

std::vector<std::string> Player::outbox()
{
    std::lock_guard lock(mutex_);
    std::vector<std::string> out;
    out.swap(outbox_);
    return out;
}

void Player::disconnect()
{
    std::lock_guard lock(mutex_);
    hasItem_ = false;
    playingIndex_ = -1;
}
}
