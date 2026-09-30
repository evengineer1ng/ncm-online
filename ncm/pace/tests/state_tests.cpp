// The parts of the Pace plugin that can be wrong without a game running: the command wire redscript splits on '|',
// the gate crossing math (it must agree with ncm-core course.gates, or the server's corroboration fails every race),
// target advance, the hold before the lights, and the stop a dropped socket must cause.
#include "state.hpp"
#include "speed_profile.hpp"
#include "road_graph.hpp"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <memory>
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

    {   // A road-derived profile is fast on a straight and begins braking before a sharp bend.
        using ncm::pace::Point;
        std::vector<Point> road;
        for (int x = 0; x <= 200; x += 10) road.push_back({static_cast<double>(x), 0, 0});
        for (int y = 10; y <= 100; y += 10) road.push_back({200, static_cast<double>(y), 0});
        const auto p = ncm::pace::buildSpeedProfile(road);
        CHECK(p.valid && p.limitMps.size() == road.size());
        CHECK(std::fabs(p.limitMps.front() - 44.0) < 0.01);
        CHECK(p.limitMps[20] < 12.0);      // 90 degree corner at x=200
        CHECK(p.limitMps[16] < 44.0);      // braking starts upstream
        CHECK(std::fabs(p.limitMps.back() - 44.0) < 0.01);
        const auto sparse = ncm::pace::buildSpeedProfile({{0, 0, 0}, {500, 0, 0}, {1000, 0, 0}});
        CHECK(!sparse.valid);             // a checkpoint chain cannot masquerade as road geometry
        const auto duplicate = ncm::pace::buildSpeedProfile({{0, 0, 0}, {0, 0, 0}, {10, 0, 0}});
        CHECK(!duplicate.valid);
    }

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
    {   // a tape (0.3.1, KB-223): the first stretch, then the rest; nobody finishes on a partial plan
        State s;
        CHECK(s.apply(R"({"cmd":"drive.start","raceId":"pr-tape","goInMs":0,"more":true,
          "points":[{"x":0,"y":0},{"x":100,"y":0}],
          "gates":[{"x":0,"y":0,"dx":1,"dy":0},{"x":100,"y":0,"dx":1,"dy":0}],
          "cars":[{"entity":"42","speeds":[30]}]})", t0));
        s.step(0, -10, 0, 0, t0 + 100ms);
        auto f = split(s.step(0, 150, 0, 0, t0 + 5000ms));       // past every gate it knows of
        CHECK(f[1] == "1");                                      // still racing: the tape is not complete
        CHECK(f[2] == "100.00");                                 // holding the last known point, not running off it
        CHECK(!s.apply(R"({"cmd":"drive.more","raceId":"someone-else","points":[{"x":200,"y":0}]})", t0));
        CHECK(!s.apply(R"({"cmd":"drive.more","raceId":"pr-tape","speeds":[[1],[2]]})", t0));   // wrong car count
        CHECK(s.apply(R"({"cmd":"drive.more","raceId":"pr-tape","last":true,
          "points":[{"x":200,"y":0}],"gates":[{"x":200,"y":0,"dx":1,"dy":0}],"speeds":[[33]]})", t0));
        f = split(s.step(0, 160, 0, 0, t0 + 5500ms));
        CHECK(f[2] == "200.00" && f[5] == "33.00");              // the appended leg, at its appended ceiling
        s.step(0, 250, 0, 0, t0 + 9000ms);
        CHECK(split(s.step(0, 260, 0, 0, t0 + 9100ms))[1] == "2");   // complete, past the last gate: finished
        CHECK(!s.apply(R"({"cmd":"drive.more","raceId":"pr-tape","points":[{"x":300,"y":0}]})", t0));   // tape closed
    }
    {   // an oval's finish IS its start line (0.4.3, KB-223): a car that joined mid-race crosses it leaving the grid
        // and must keep driving -- it was told to stop, every car, every race. Only car.remove ends it.
        State s;
        CHECK(s.apply(R"({"cmd":"drive.start","raceId":"pr-ring","dynamic":true,"goInMs":0,
          "points":[{"x":0,"y":0},{"x":100,"y":0},{"x":100,"y":100},{"x":0,"y":100},{"x":0,"y":0}],
          "gates":[{"x":0,"y":0,"dx":1,"dy":0},{"x":0,"y":0,"dx":1,"dy":0}]})", t0));
        CHECK(s.apply(R"({"cmd":"car.add","raceId":"pr-ring","entity":"42","from":1,"speed":20})", t0));
        s.step(0, -12, 0, 0, t0 + 1000ms);                       // on the grid, behind the line
        auto f = split(s.step(0, 8, 0, 0, t0 + 2000ms));         // across the line (= the finish gate)
        CHECK(f[1] == "1");                                      // still racing
        s.drainLog();
        CHECK(s.apply(R"({"cmd":"car.remove","raceId":"pr-ring","entity":"42"})", t0));
        CHECK(split(s.step(0, 9, 0, 0, t0 + 2100ms))[1] == "2");   // ended by the server, not by a gate
    }
    {   // look-ahead (0.4.1, KB-223): on a dense line the car is sent far ahead, and re-aimed only halfway there --
        // not to the next point 15 m on, which completes inside minimumDistanceToTarget and stops the car
        std::string pts;
        for (int i = 0; i <= 40; ++i) pts += (i ? "," : "") + std::string("{\"x\":") + std::to_string(i * 15) + ",\"y\":0}";
        State s;
        CHECK(s.apply(std::string(R"({"cmd":"drive.start","raceId":"pr-look","dynamic":true,"goInMs":0,"advanceM":15,"lookaheadM":150,"points":[)")
            + pts + R"(],"gates":[{"x":0,"y":0,"dx":1,"dy":0},{"x":600,"y":0,"dx":1,"dy":0}]})", t0));
        CHECK(s.apply(R"({"cmd":"car.add","raceId":"pr-look","entity":"42","from":1,"speed":20})", t0));
        auto f = split(s.step(0, 0, 0, 0, t0 + 3000ms));
        const double aim1 = std::stod(f[2]);
        CHECK(aim1 >= 150 && aim1 <= 165);                       // ~150 m ahead, not the next point at 15 m
        f = split(s.step(0, 40, 0, 0, t0 + 4000ms));
        CHECK(std::stod(f[2]) == aim1);                          // still far from it: the same aim, no command churn
        f = split(s.step(0, 90, 0, 0, t0 + 6000ms));
        CHECK(std::stod(f[2]) >= 240);                           // within half the look-ahead: re-aimed 150 m on
    }
    {   // a rolling aim (0.4.5): with reaimFrac 0.9 the aim moves on as soon as the car has closed ~15 m of it, so the
        // destination never comes within braking distance
        std::string pts;
        for (int i = 0; i <= 40; ++i) pts += (i ? "," : "") + std::string("{\"x\":") + std::to_string(i * 15) + ",\"y\":0}";
        State s;
        CHECK(s.apply(std::string(R"({"cmd":"drive.start","raceId":"pr-roll","dynamic":true,"goInMs":0,"advanceM":15,"lookaheadM":90,"reaimFrac":0.9,"points":[)")
            + pts + R"(],"gates":[{"x":0,"y":0,"dx":1,"dy":0},{"x":600,"y":0,"dx":1,"dy":0}]})", t0));
        CHECK(s.apply(R"({"cmd":"car.add","raceId":"pr-roll","entity":"42","from":1,"speed":20})", t0));
        auto f = split(s.step(0, 0, 0, 0, t0 + 3000ms));
        const double a1 = std::stod(f[2]);
        f = split(s.step(0, 20, 0, 0, t0 + 4000ms));
        CHECK(std::stod(f[2]) > a1);                             // 20 m on: already re-aimed further ahead
        CHECK(std::stod(f[2]) - 20 >= 80);                       // and the aim is still ~90 m in front
    }
    {   // the wrong-way guard (0.4.6): a car going backwards round the ring for 0.3 s is sent 25 m forward round it
        State s;
        CHECK(s.apply(R"({"cmd":"drive.start","raceId":"pr-wrong","dynamic":true,"goInMs":0,"advanceM":20,
          "ring":{"cx":0,"cy":0,"sign":1},
          "points":[{"x":100,"y":0},{"x":0,"y":100},{"x":-100,"y":0},{"x":0,"y":-100},{"x":100,"y":0}],
          "gates":[{"x":100,"y":0,"dx":0,"dy":1},{"x":100,"y":0,"dx":0,"dy":1}]})", t0));
        CHECK(s.apply(R"({"cmd":"car.add","raceId":"pr-wrong","entity":"42","from":1,"speed":20})", t0));
        // anticlockwise is the race direction; the car drives CLOCKWISE (backwards) from 90 deg towards 0 deg
        int64_t ms = 1000;
        for (int k = 0; k <= 12; ++k) {
            const double a = (90.0 - k * 3.0) * 3.14159265 / 180.0;
            s.step(0, 100 * std::cos(a), 100 * std::sin(a), 0, t0 + std::chrono::milliseconds(ms));
            ms += 100;
        }
        auto f = split(s.step(0, 100 * std::cos(0.9), 100 * std::sin(0.9), 0, t0 + std::chrono::milliseconds(ms)));
        const double wx = std::stod(f[2]), wy = std::stod(f[3]);
        const double wantAng = std::atan2(wy, wx), carAng = 0.9;
        CHECK(wantAng > carAng && wantAng - carAng < 0.8);     // sent FORWARD round the ring (anticlockwise) of the car,
                                                               // 25 m on from where it was caught going backwards
        CHECK(std::fabs(std::hypot(wx, wy) - 100) < 1.0);       // on the ring, at the car's own radius
        bool logged = false;
        for (const auto& l : s.drainLog()) if (l.find("WRONG WAY") != std::string::npos) logged = true;
        CHECK(logged);
    }
    {   // a dynamic plan (0.4.0, KB-223): no cars at first; cars join mid-race and leave in place; refusals say why
        State s;
        CHECK(!s.apply(R"({"cmd":"car.add","raceId":"pr-dyn","entity":"42"})", t0));
        CHECK(s.refusal().find("no active dynamic plan") != std::string::npos);
        CHECK(!s.apply(R"({"cmd":"drive.start","raceId":"pr-dyn","points":[{"x":0,"y":0},{"x":100,"y":0}],
          "gates":[{"x":0,"y":0,"dx":1,"dy":0},{"x":100,"y":0,"dx":1,"dy":0}],"cars":[]})", t0));   // not dynamic: cars required
        CHECK(s.refusal().find("0 cars") != std::string::npos);
        CHECK(s.apply(R"({"cmd":"drive.start","raceId":"pr-dyn","dynamic":true,"goInMs":0,
          "points":[{"x":0,"y":0},{"x":100,"y":0},{"x":200,"y":0},{"x":300,"y":0}],
          "gates":[{"x":0,"y":0,"dx":1,"dy":0},{"x":300,"y":0,"dx":1,"dy":0}],"cars":[]})", t0));
        CHECK(s.count(t0) == 0);
        const int rev = s.revision();
        CHECK(s.apply(R"({"cmd":"car.add","raceId":"pr-dyn","entity":"42","vehicleId":7,"from":2,"speed":33})", t0 + 1000ms));
        CHECK(s.revision() == rev);                              // joining never releases the other cars
        CHECK(s.count(t0) == 1 && s.entity(0) == 42);
        auto f = split(s.step(0, 150, 0, 0, t0 + 1100ms));
        CHECK(f[1] == "1" && f[2] == "200.00");                  // drives on from the point it was set down before
        CHECK(!s.apply(R"({"cmd":"car.add","raceId":"pr-dyn","entity":"42"})", t0));         // already driving
        CHECK(s.apply(R"({"cmd":"car.set","raceId":"pr-dyn","entity":"42","speed":27.5})", t0 + 1150ms));   // 0.4.4
        CHECK(s.revision() == rev);                              // a new ceiling releases nobody
        f = split(s.step(0, 160, 0, 0, t0 + 1160ms));
        CHECK(f[5] == "27.50");                                  // the car now holds its own sim pace
        CHECK(!s.apply(R"({"cmd":"car.set","raceId":"pr-dyn","entity":"99","speed":20})", t0));    // no such car
        CHECK(s.apply(R"({"cmd":"car.add","raceId":"pr-dyn","entity":"43","from":1})", t0 + 1200ms));
        CHECK(s.apply(R"({"cmd":"car.remove","raceId":"pr-dyn","entity":"42"})", t0 + 1300ms));
        CHECK(s.revision() == rev && s.count(t0 + 1300ms) == 2);  // retired in place: the list neither shrinks nor moves
        CHECK(s.entity(0) == 0 && s.entity(1) == 43);
        CHECK(split(s.step(0, 150, 0, 0, t0 + 1400ms))[1] == "2");   // the retired slot is told to stop
        CHECK(!s.apply(R"({"cmd":"car.remove","raceId":"pr-dyn","entity":"42"})", t0));      // gone already
        CHECK(!s.apply(R"({"cmd":"wat"})", t0) && s.refusal().find("unknown cmd") != std::string::npos);
        CHECK(!s.apply("not json", t0) && s.refusal() == "not a JSON object");
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
        CHECK(f.size() == 10);
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

    {   // the race-start banner: shown for its seconds, separators cannot shift a field, seconds 0 clears it
        State s;
        CHECK(s.banner(t0) == "0|0|~|~|0");
        CHECK(s.apply(R"({"cmd":"banner","title":"WARNING: IMPENDING RACE START","detail":"CLEAR THE AREA|now","seconds":90})", t0));
        auto f = split(s.banner(t0 + 1500ms));
        CHECK(f.size() == 5);
        CHECK(f[1] == "1" && f[2] == "WARNING: IMPENDING RACE START" && f[3] == "CLEAR THE AREA now" && f[4] == "89");
        CHECK(split(s.banner(t0 + 91s))[1] == "0");
        CHECK(s.apply(R"({"cmd":"banner","title":"x","seconds":0})", t0));
        CHECK(split(s.banner(t0))[1] == "0");
    }

    {   // SP's launch (L234): a capped release off the line, the grace, then the race command; a stalled car and a
        // healthy one are both re-commanded -- SP's recommand loop -- so nothing ever parks after a crash.
        State s;
        std::string plan = kPlan;
        plan.insert(plan.size() - 1, R"(,"launch":{"graceS":1.75,"relMax":18,"relMin":8,"relForced":4,"relDist":5,
            "minFrac":0.72,"forcedFrac":0.25,"raceDist":12,"recommandS":3,"stallMps":5.5,"stallS":2})");
        CHECK(s.apply(plan, t0));
        auto f = split(s.step(0, -10, 0, 0, t0 + 2000ms));      // the lights: the release, capped
        CHECK(f[1] == "1" && f[5] == "18.00" && f[6] == "8.00" && f[7] == "4.00" && f[8] == "5.00" && f[9] == "0");
        const std::string launchSeq = f[0];
        f = split(s.step(0, -4, 0, 0, t0 + 3000ms));
        CHECK(f[0] == launchSeq);                                 // inside the grace nothing is judged
        f = split(s.step(0, 2, 0, 0, t0 + 3800ms));              // grace over: SP's post-launch race command
        CHECK(f[0] != launchSeq && f[5] == "30.00" && f[6] == "21.60" && f[7] == "7.50" && f[8] == "12.00" && f[9] == "1");
        std::string seq = f[0];
        // stuck against a wall: same place for over two seconds -> a fresh command without waiting for the cadence
        s.step(0, 2, 0, 0, t0 + 4100ms);
        s.step(0, 2, 0, 0, t0 + 4400ms);
        s.step(0, 2, 0, 0, t0 + 5200ms);
        f = split(s.step(0, 2, 0, 0, t0 + 6300ms));
        CHECK(f[0] != seq && f[1] == "1");
        seq = f[0];
        // a healthy car on the same leg is still re-commanded every recommandS (3 s)
        for (int ms = 6500; ms <= 9200; ms += 300) {
            f = split(s.step(0, 2 + (ms - 6300) * 0.02, 0, 0, t0 + std::chrono::milliseconds(ms)));
        }
        CHECK(f[0] == seq);
        f = split(s.step(0, 50, 0, 0, t0 + 9400ms));           // same leg (50 m from point 1): the cadence alone
        CHECK(f[0] != seq);
    }
    {   // the traffic null area over a staging grid: shown for its seconds, then gone; seconds 0 clears it
        State s;
        CHECK(s.area(t0) == "0|0|0.00|0.00|0.00|0.00|0.00|0");
        CHECK(s.apply(R"({"cmd":"area","x":10,"y":-20,"z":5,"half":140,"halfZ":30,"seconds":120})", t0));
        auto f = split(s.area(t0 + 1s));
        CHECK(f.size() == 8 && f[0] == "1" && f[1] == "1" && f[2] == "10.00" && f[5] == "140.00" && f[7] == "119");
        CHECK(split(s.area(t0 + 121s))[1] == "0");
        CHECK(s.apply(R"({"cmd":"area","seconds":0})", t0));
        CHECK(split(s.area(t0))[1] == "0" && split(s.area(t0))[0] == "2");
    }
    {   // A directed road line, not a start/finish chord, raises straight pace and brakes before a right angle.
        auto graph = std::make_shared<ncm::pace::RoadGraph>();
        graph->lanes.resize(3);
        graph->lanes[0].line = {{0,0,0},{10,0,0},{20,0,0},{30,0,0},{40,0,0},{50,0,0}};
        graph->lanes[0].out = {1};
        graph->lanes[1].line = {{50,0,0},{60,0,0},{70,0,0},{80,0,0},{90,0,0}};
        graph->lanes[1].out = {2};
        graph->lanes[2].line = {{90,0,0},{90,10,0},{90,20,0},{90,30,0},{90,40,0}};
        CHECK(graph->route({0,0,0},{90,40,0}).size() >= 10);
        CHECK(graph->route({0,-40,0},{90,40,0}).size() >= 10); // a grid anchor beside the lane
        State s;
        s.setRoadGraph(graph);
        CHECK(s.apply(R"({"cmd":"drive.start","raceId":"road-test","goInMs":0,
          "points":[{"x":0,"y":0,"z":0},{"x":90,"y":40,"z":0}],
          "gates":[{"x":0,"y":0,"z":0,"dx":1,"dy":0},{"x":90,"y":40,"z":0,"dx":0,"dy":1}],
          "cars":[{"entity":"42","vehicleId":5,"speeds":[25]}]})",t0));
        const auto start = split(s.step(0,0,0,0,t0+3000ms));
        const auto approach = split(s.step(0,80,0,0,t0+6000ms));
        CHECK(start[1] == "1" && std::stod(start[5]) > 25.0);
        CHECK(approach[1] == "1" && std::stod(approach[5]) < std::stod(start[5]));
    }
    {   // Two valid legs can snap to different roads at one checkpoint. Keep both speed plans.
        auto graph=std::make_shared<ncm::pace::RoadGraph>();
        graph->lanes.resize(2);
        graph->lanes[0].line={{0,0,0},{20,0,0},{40,0,0},{60,0,0},{80,0,0},{100,0,0}};
        graph->lanes[1].line={{100,100,0},{120,100,0},{140,100,0},{160,100,0},{180,100,0},{200,100,0}};
        State s;s.setRoadGraph(graph);
        CHECK(s.apply(R"({"cmd":"drive.start","raceId":"segmented","goInMs":0,
          "points":[{"x":0,"y":0,"z":0},{"x":100,"y":50,"z":0},{"x":200,"y":100,"z":0}],
          "gates":[{"x":0,"y":0,"dx":1,"dy":0},{"x":100,"y":50,"dx":1,"dy":0},{"x":200,"y":100,"dx":1,"dy":0}],
          "cars":[{"entity":"42","vehicleId":5,"speeds":[25,25]}]})",t0));
        bool segmented=false;
        for(const auto& line:s.drainLog()) if(line.find("2/2 legs, segmented")!=std::string::npos) segmented=true;
        CHECK(segmented);
    }

    if (failures == 0) std::printf("pace state: all checks passed\n");
    return failures == 0 ? 0 : 1;
}
