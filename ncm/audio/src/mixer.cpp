#include "mixer.hpp"

#include "log.hpp"

#include <nlohmann/json.hpp>

#define MA_NO_ENCODING
#define MA_NO_GENERATION
#include "miniaudio.h"

#include <windows.h>

#include <chrono>
#include <vector>

namespace ncm::audio {

struct Mixer::Engine {
    ma_engine engine{};
    bool up = false;
};

struct Mixer::Voice {
    ma_sound sound{};
    bool up = false;
    bool loop = false;
    std::string file;
    double gain = 0, pitch = 1, pan = 0;            // current (glided)
    double wantGain = 0, wantPitch = 1, wantPan = 0;
    math::Vec3 at;
    bool positional = false;
    bool dying = false;                              // no longer named: fading to silence, then released
};

Mixer& mixer()
{
    static Mixer instance;
    return instance;
}

Mixer::~Mixer() { stop(); }

namespace {
bool bareName(const std::string& f)
{
    if (f.empty() || f.size() > 64) return false;
    for (const char c : f) {
        if (!(std::isalnum(static_cast<unsigned char>(c)) || c == '_' || c == '-' || c == '.')) return false;
    }
    return f.find("..") == std::string::npos;
}

math::Vec3 vec(const nlohmann::json& j)
{
    math::Vec3 v;
    if (j.is_object()) { v.x = j.value("x", 0.0); v.y = j.value("y", 0.0); v.z = j.value("z", 0.0); }
    else if (j.is_array() && j.size() >= 3) { v.x = j[0].get<double>(); v.y = j[1].get<double>(); v.z = j[2].get<double>(); }
    return v;
}
}

bool Mixer::start(const std::wstring& pluginDir)
{
    std::lock_guard lock(mutex_);
    if (running_) return true;
    pack_ = pluginDir + L"\\pack\\";
    engine_ = std::make_unique<Engine>();
    ma_engine_config config = ma_engine_config_init();
    config.listenerCount = 1;
    if (ma_engine_init(&config, &engine_->engine) != MA_SUCCESS) {
        AUDIO_ERR("audio device unavailable: nothing will be heard");
        engine_.reset();
        return false;
    }
    engine_->up = true;
    AUDIO_INFO("audio up: %u Hz", ma_engine_get_sample_rate(&engine_->engine));
    running_ = true;
    thread_ = std::thread([this] { run(); });
    return true;
}

void Mixer::stop()
{
    if (running_.exchange(false) && thread_.joinable()) thread_.join();
    std::lock_guard lock(mutex_);
    for (auto& [k, v] : voices_) if (v->up) ma_sound_uninit(&v->sound);
    for (auto& [k, v] : shots_) if (v->up) ma_sound_uninit(&v->sound);
    voices_.clear();
    shots_.clear();
    if (engine_ && engine_->up) ma_engine_uninit(&engine_->engine);
    engine_.reset();
}

Mixer::Voice* Mixer::open(const std::string& file, bool loop)
{
    if (!engine_ || !engine_->up || !bareName(file)) return nullptr;
    auto v = std::make_unique<Voice>();
    const std::wstring path = pack_ + std::wstring(file.begin(), file.end());
    const ma_uint32 flags = MA_SOUND_FLAG_DECODE | MA_SOUND_FLAG_NO_SPATIALIZATION;
    if (ma_sound_init_from_file_w(&engine_->engine, path.c_str(), flags, nullptr, nullptr, &v->sound) != MA_SUCCESS) {
        if (++refused_ <= 20) AUDIO_WARN("cannot open %s", file.c_str());
        return nullptr;
    }
    v->up = true;
    v->loop = loop;
    v->file = file;
    ma_sound_set_looping(&v->sound, loop ? MA_TRUE : MA_FALSE);
    ma_sound_set_volume(&v->sound, 0.0f);
    return v.release();
}

bool Mixer::apply(const std::string& payload)
{
    const auto j = nlohmann::json::parse(payload, nullptr, false);
    if (!j.is_object()) return false;
    const std::string cmd = j.value("cmd", std::string());
    std::lock_guard lock(mutex_);
    if (cmd == "volume") {
        master_ = math::clampGain(j.value("v", 1.0));
        return true;
    }
    if (j.contains("listener") && j["listener"].is_object()) {
        const auto& l = j["listener"];
        listener_.pos = vec(l.value("pos", nlohmann::json()));
        listener_.right = vec(l.value("right", nlohmann::json()));
        listener_.forward = vec(l.value("forward", nlohmann::json()));
        listener_.valid = math::len(listener_.right) > 0.5;
    }
    if (cmd == "shot") {
        for (const auto& s : j.value("shots", nlohmann::json::array())) {
            Voice* raw = open(s.value("file", std::string()), false);
            if (!raw) continue;
            std::unique_ptr<Voice> v(raw);
            v->positional = s.contains("pos");
            v->at = vec(s.value("pos", nlohmann::json()));
            const double g = math::clampGain(s.value("gain", 1.0)) * (v->positional ? math::positionalGain(listener_, v->at) : 1.0);
            v->gain = v->wantGain = g;
            v->pitch = v->wantPitch = math::clampPitch(s.value("pitch", 1.0));
            v->pan = v->wantPan = v->positional ? math::pan(listener_, v->at) : 0.0;
            ma_sound_set_volume(&v->sound, static_cast<float>(v->gain * master_));
            ma_sound_set_pitch(&v->sound, static_cast<float>(v->pitch));
            ma_sound_set_pan(&v->sound, static_cast<float>(v->pan));
            ma_sound_start(&v->sound);
            shots_[nextShot_++] = std::move(v);
        }
        return true;
    }
    if (cmd != "voices") return false;
    std::map<std::string, bool> named;
    for (const auto& s : j.value("voices", nlohmann::json::array())) {
        const std::string key = s.value("key", std::string());
        const std::string file = s.value("file", std::string());
        if (key.empty() || key.size() > 160) continue;
        auto it = voices_.find(key);
        if (it != voices_.end() && it->second->file != file) {   // the cue changed its sound: replace, never mix two
            it->second->dying = true;
            voices_.emplace(key + "#old" + std::to_string(nextShot_++), std::move(it->second));
            voices_.erase(it);
            it = voices_.end();
        }
        if (it == voices_.end()) {
            Voice* raw = open(file, true);
            if (!raw) continue;
            ma_sound_start(&raw->sound);
            it = voices_.emplace(key, std::unique_ptr<Voice>(raw)).first;
        }
        Voice& v = *it->second;
        v.dying = false;
        v.positional = s.contains("pos");
        v.at = vec(s.value("pos", nlohmann::json()));
        v.wantGain = math::clampGain(s.value("gain", 1.0)) * (v.positional ? math::positionalGain(listener_, v.at) : 1.0);
        v.wantPitch = math::clampPitch(s.value("pitch", 1.0));
        v.wantPan = v.positional ? math::pan(listener_, v.at) : 0.0;
        named[key] = true;
    }
    for (auto& [k, v] : voices_) if (!named.count(k)) v->dying = true;
    return true;
}

void Mixer::silence()
{
    std::lock_guard lock(mutex_);
    for (auto& [k, v] : voices_) v->dying = true;
}

void Mixer::tick(double dtS)
{
    std::lock_guard lock(mutex_);
    std::vector<std::string> gone;
    for (auto& [k, v] : voices_) {
        const double target = v->dying ? 0.0 : v->wantGain;
        v->gain = math::glide(v->gain, target, dtS, v->dying ? 0.12 : 0.08);
        v->pitch = math::glide(v->pitch, v->wantPitch, dtS, 0.10);
        v->pan = math::glide(v->pan, v->wantPan, dtS, 0.05);
        ma_sound_set_volume(&v->sound, static_cast<float>(v->gain * master_));
        ma_sound_set_pitch(&v->sound, static_cast<float>(v->pitch));
        ma_sound_set_pan(&v->sound, static_cast<float>(v->pan));
        if (v->dying && v->gain < 0.002) gone.push_back(k);
    }
    for (const auto& k : gone) {
        auto it = voices_.find(k);
        if (it->second->up) ma_sound_uninit(&it->second->sound);
        voices_.erase(it);
    }
    std::vector<uint64_t> done;
    for (auto& [id, v] : shots_) if (ma_sound_at_end(&v->sound)) done.push_back(id);
    for (const auto id : done) {
        auto it = shots_.find(id);
        if (it->second->up) ma_sound_uninit(&it->second->sound);
        shots_.erase(it);
    }
}

void Mixer::run()
{
    auto last = std::chrono::steady_clock::now();
    while (running_) {
        std::this_thread::sleep_for(std::chrono::milliseconds(16));
        const auto now = std::chrono::steady_clock::now();
        const double dt = std::chrono::duration<double>(now - last).count();
        last = now;
        try { tick(dt); } catch (...) {}
    }
}

std::string Mixer::health() const
{
    std::lock_guard lock(mutex_);
    nlohmann::json h;
    h["version"] = NCM_AUDIO_VERSION;
    h["device"] = engine_ && engine_->up;
    h["voices"] = voices_.size();
    h["shots"] = shots_.size();
    return nlohmann::json{{"health", h}}.dump();
}
}
