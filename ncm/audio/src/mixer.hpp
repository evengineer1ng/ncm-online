#pragma once
// NCM Audio's mixer: looping VOICES that Lua keeps alive by naming them every update (gain, pitch, position glide to
// the new targets; a voice Lua stops naming fades out and is released), and ONE-SHOTS that play once and free
// themselves. Files come only from the pack folder beside the DLL, by bare file name.

#include "mixer_math.hpp"

#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <atomic>

namespace ncm::audio {

class Mixer {
public:
    ~Mixer();
    bool start(const std::wstring& pluginDir);
    void stop();
    // a JSON message from the resource: {cmd:"voices", listener, voices:[...]} | {cmd:"shot", ...} | {cmd:"volume", v}
    bool apply(const std::string& json);
    // when the resource goes away: everything fades out
    void silence();
    std::string health() const;

private:
    struct Voice;
    void run();
    void tick(double dtS);
    Voice* open(const std::string& file, bool loop);

    std::wstring pack_;
    std::map<std::string, std::unique_ptr<Voice>> voices_;   // key -> looping voice
    std::map<uint64_t, std::unique_ptr<Voice>> shots_;       // one-shots until they end
    uint64_t nextShot_ = 1;
    math::Listener listener_;
    double master_ = 1.0;
    mutable std::mutex mutex_;
    std::atomic<bool> running_{false};
    std::thread thread_;
    struct Engine;
    std::unique_ptr<Engine> engine_;
    std::atomic<int> refused_{0};
};

Mixer& mixer();
}
