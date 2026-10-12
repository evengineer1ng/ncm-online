#pragma once

#include "timeline.hpp"

#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace ncm::radio {

// Plays the server's programme through miniaudio, only while the player is listening (doc 59 §6).
//
//   * the bridge thread hands it items (`apply`), the game thread ticks it (`update`) and reports listening/volume;
//   * whether or not anyone listens, the item's clock runs: tuning in seeks to where the broadcast is now;
//   * no heartbeat from redscript for 750 ms (pause menu, loading, alt-tab with the game suspended) = silence.
class Player {
public:
    explicit Player(std::wstring packDir);
    ~Player();

    bool start();                                     // opens the audio device; false = no audio, plugin stays inert
    bool apply(const std::string& json);              // a resource message; false = refused
    void heartbeat(bool listening, float volume);     // from redscript, every tick
    void update();                                    // game thread
    std::string status() const;                       // for redscript: "" or the current beat id
    std::string health() const;                       // JSON for the resource
    std::vector<std::string> outbox();                // JSON messages to the resource
    void disconnect();                                // resource gone: stop airing

    bool packPresent() const { return packPresent_; }

private:
    void stopSound();
    bool startClip(const Clip& clip, int32_t intoMs);

    struct Audio;
    std::unique_ptr<Audio> audio_;
    std::wstring packDir_;
    bool packPresent_ = false;
    std::string packVersion_;

    mutable std::mutex mutex_;
    Item item_;
    bool hasItem_ = false;
    std::chrono::steady_clock::time_point itemStart_{};
    bool listening_ = false;
    float volume_ = 0.8f;
    std::chrono::steady_clock::time_point lastBeat_{};
    int playingIndex_ = -1;
    uint64_t playingSeq_ = 0;
    bool reportedListening_ = false;
    bool reportedOnce_ = false;
    std::vector<std::string> outbox_;
    int missing_ = 0;
};
}
