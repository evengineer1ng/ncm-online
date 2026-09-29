// The parts of the Pace plugin that can be wrong without a game running: the command wire redscript splits on '|',
// the gate crossing math (it must agree with ncm-core course.gates, or the server's corroboration fails every race),
// target advance, the hold before the lights, and the stop a dropped socket must cause.
#include "state.hpp"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

using ncm::pace::State;
using namespace std::chrono_literals;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

static std::vector<std::string> split(const std::string& s)
{
    std::vector<std::string> out(1);
    for (char c : s) { if (c == '|') out.emplace_back(); else out.back().push_back(c); }
    return out;
}

// A straight 1 km road east, eleven points; gates at 0 (start), 500 and 1000 (finish).
static const char* kPlan = R"({"cmd":"drive.start","raceId":"pr-test","goInMs":2000,
  "points":[{"x":0,"y":0,"z":0},{"x":100,"y":0,"z":0},{"x":200,"y":0,"z":0},{"x":300,"y":0,"z":0},{"x":400,"y":0,"z":0},
            {"x":500,"y":0,"z":0},{"x":600,"y":0,"z":0},{"x":700,"y":0,"z":0},{"x":800,"y":0,"z":0},{"x":900,"y":0,"z":0},
            {"x":1000,"y":0,"z":0}],
  "gates":[{"x":0,"y":0,"z":0,"dx":1,"dy":0},{"x":500,"y":0,"z":0,"dx":1,"dy":0},{"x":1000,"y":0,"z":0,"dx":1,"dy":0}],
  "cars":[{"entity":"18446744073709551557","vehicleId":5001,"speeds":[30,31,32,33,34,35,36,37,38,39]},
          {"entity":"42","vehicleId":5002,"speeds":[20]}]})";

int main()
{
    const auto t0 = State::Clock::now();

    {   // gate math: a sign flip dates the crossing inside the move; a miss is -1; the capture radius counts.
        ncm::pace::Gate g;
        g.x = 100; g.dx = 1; g.dy = 0;
        CHECK(std::fabs(ncm::pace::crossFraction(g, {90, 0, 0}, {110, 0, 0}) - 0.5) < 1e-9);
        CHECK(ncm::pace::crossFraction(g, {0, 0, 0}, {10, 0, 0}) < 0);
        CHECK(ncm::pace::crossFraction(g, {100, 90, 0}, {110, 90, 0}) < 0);           // 90 m off the line
        CHECK(ncm::pace::crossFraction(g, {60, 20, 0}, {80, 20, 0}) == 1.0);          // reached, no flip yet
        CHECK(ncm::pace::parseHash("18446744073709551557") == 18446744073709551557ull);
        CHECK(ncm::pace::parseHash("12a") == 0);
    }
    {   // a plan: held before the lights, then driven, gates timed, target advanced ahead, stop at the end
        State s;
        CHECK(!s.apply(R"({"cmd":"drive.start","points":[],"gates":[],"cars":[]})", t0));
        CHECK(s.count(t0) == 0);
        CHECK(s.apply(kPlan, t0));
        CHECK(s.count(t0) == 2);
        CHECK(s.entity(0) == 18446744073709551557ull);
        CHECK(s.entity(1) == 42);
        CHECK(s.entity(7) == 0);
        auto f = split(s.step(0, -10, 0, 0, t0 + 1000ms));
        CHECK(f.size() == 6);
        CHECK(f[1] == "0");                                      // hold: the lights are not out
        f = split(s.step(0, -10, 0, 0, t0 + 2000ms));
        CHECK(f[1] == "1");                                      // go: drive
        CHECK(f[2] == "100.00");                                 // to the first point after the grid
        CHECK(f[5] == "30.00");                                  // at the first leg's ceiling
        const std::string seq = f[0];
        f = split(s.step(0, -5, 0, 0, t0 + 2100ms));
        CHECK(f[0] == seq);                                      // nothing changed: same seq, no re-dispatch
        f = split(s.step(0, 70, 0, 0, t0 + 5000ms));             // within 40 m of point 1: aim at point 2
        CHECK(f[0] != seq && f[2] == "200.00" && f[5] == "31.00");
        s.outbox();
        s.step(0, 460, 0, 0, t0 + 18000ms);                      // 40 m short of the line: outside its capture
        s.step(0, 540, 0, 0, t0 + 19000ms);                      // crosses 500 halfway between 16.0 and 17.0 s after the go
        auto out = s.outbox();
        CHECK(out.size() == 1);
        CHECK(out.size() == 1 && out[0].find("\"gate\":2") != std::string::npos);
        CHECK(out.size() == 1 && out[0].find("\"tMs\":16500") != std::string::npos);
        CHECK(out.size() == 1 && out[0].find("\"vehicleId\":5001") != std::string::npos);
        f = split(s.step(0, 962, 0, 0, t0 + 34000ms));           // inside 40 m of the last point: aim beyond it
        CHECK(f[1] == "1" && f[2] == "1080.00");
        f = split(s.step(0, 1010, 0, 0, t0 + 35000ms));          // crossed the finish: stop
        CHECK(f[1] == "2");
        out = s.outbox();
        CHECK(out.size() == 1 && out[0].find("\"gate\":3") != std::string::npos);
        // the other car still drives at its only ceiling
        f = split(s.step(1, -20, 0, 0, t0 + 35000ms));
        CHECK(f[1] == "1" && f[5] == "20.00");
    }
    {   // a dropped socket stops every car and bumps the revision; the list goes after ten seconds
        State s;
        CHECK(s.apply(kPlan, t0));
        const int rev = s.revision();
        s.step(1, 0, 0, 0, t0 + 3000ms);
        s.disconnect();
        CHECK(s.revision() == rev + 1);
        CHECK(split(s.step(1, 10, 0, 0, t0 + 3100ms))[1] == "2");
        CHECK(s.count(State::Clock::now() + 1s) == 2);
        CHECK(s.count(State::Clock::now() + 11s) == 0);
        CHECK(s.apply(R"({"cmd":"drive.end"})", t0));            // idempotent
    }
    {   // health is JSON the resource can read
        State s;
        const auto h = s.health();
        CHECK(h.find("\"health\"") != std::string::npos && h.find("\"version\"") != std::string::npos);
    }

    if (failures == 0) std::printf("pace state: all checks passed\n");
    return failures == 0 ? 0 : 1;
}
