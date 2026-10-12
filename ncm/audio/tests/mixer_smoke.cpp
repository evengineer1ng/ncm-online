// NCM Audio smoke test: the real mixer (miniaudio, the pack), fed the messages the resource sends. On a machine with
// no audio device it says so and passes the parsing checks only.
#include "mixer.hpp"

#include <chrono>
#include <cstdio>
#include <string>
#include <thread>
#include <windows.h>

static int failed = 0, passed = 0;
static void check(bool ok, const char* what) { if (ok) { ++passed; std::printf("  PASS %s\n", what); } else { ++failed; std::printf("  FAIL %s\n", what); } }

static int count(const std::string& health, const char* field)
{
    const auto at = health.find(std::string("\"") + field + "\":");
    return at == std::string::npos ? -1 : std::atoi(health.c_str() + at + std::strlen(field) + 3);
}

int main(int argc, char** argv)
{
    std::wstring dir = L".";
    if (argc > 1) { std::string a(argv[1]); dir.assign(a.begin(), a.end()); }
    auto& m = ncm::audio::mixer();
    const bool device = m.start(dir);
    std::printf("device: %s\n", device ? "yes" : "none (parsing checks only)");
    check(!m.apply("not json"), "garbage is refused");
    check(!m.apply("{\"cmd\":\"nonsense\"}"), "an unknown command is refused");
    check(m.apply("{\"cmd\":\"volume\",\"v\":0.2}"), "volume");
    const std::string voices = "{\"cmd\":\"voices\",\"listener\":{\"pos\":{\"x\":0,\"y\":0,\"z\":0},\"right\":{\"x\":1,\"y\":0,\"z\":0},\"forward\":{\"x\":0,\"y\":1,\"z\":0}},"
        "\"voices\":[{\"key\":\"m1:c1#plume\",\"file\":\"rocket_roar.wav\",\"gain\":0.8,\"pitch\":1.1,\"pos\":{\"x\":2,\"y\":-2,\"z\":0}},"
        "{\"key\":\"bad\",\"file\":\"a/x.wav\"}]}";
    check(m.apply(voices), "a voices message");
    if (device) {
        check(count(m.health(), "voices") == 1, "one looping voice open (the bad path refused)");
        check(m.apply("{\"cmd\":\"shot\",\"shots\":[{\"file\":\"pulse_thump.wav\",\"gain\":1}]}"), "a one-shot");
        check(count(m.health(), "shots") == 1, "the one-shot is playing");
        std::this_thread::sleep_for(std::chrono::milliseconds(300));
        check(m.apply("{\"cmd\":\"voices\",\"voices\":[]}"), "naming nothing");
        std::this_thread::sleep_for(std::chrono::milliseconds(1500));
        check(count(m.health(), "voices") == 0, "an unnamed voice faded out and was released");
        check(count(m.health(), "shots") == 0, "the finished one-shot was released");
    }
    m.stop();
    std::printf("audio smoke: %d passed, %d failed\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
