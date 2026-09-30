// The parts of NCM Broadcast that can be wrong without a game running: the '|' wire redscript splits, the scrub
// that keeps a name from shifting a field, the label/tower expiry that stops stale names hanging in the air, and
// the calibration clamps.
#include "state.hpp"

#include <chrono>
#include <cstdio>
#include <string>
#include <vector>

using ncm::broadcast::State;
using namespace std::chrono_literals;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

static std::vector<std::string> split(const std::string& s)
{
    std::vector<std::string> out(1);
    for (char c : s) { if (c == '|') out.emplace_back(); else out.back().push_back(c); }
    return out;
}

int main()
{
    const auto t0 = State::Clock::now();
    {   // labels: replaced wholesale, scrubbed, dark after their ttl
        State s;
        CHECK(s.labelCount(t0) == 0);
        CHECK(s.apply(R"({"cmd":"labels","ttl":3,"items":[
            {"entity":"18446744073709551557","title":"Derek|Smith","sub":"Kabuki Wolves","chip":"P1","accent":1},
            {"entity":"0","title":"no entity"},
            {"entity":"42","title":"Emilia Vargas","chip":"P12"}]})", t0));
        CHECK(s.labelCount(t0 + 1s) == 2);
        CHECK(s.labelEntity(0) == 18446744073709551557ull);
        auto f = split(s.labelText(0));
        CHECK(f.size() == 4 && f[0] == "Derek Smith" && f[1] == "Kabuki Wolves" && f[2] == "P1" && f[3] == "1");
        f = split(s.labelText(1));
        CHECK(f[1] == "~" && f[3] == "0");
        CHECK(s.labelCount(t0 + 4s) == 0);                       // the feed stopped: names go
        CHECK(s.apply(R"({"cmd":"labels","items":[]})", t0));
        CHECK(s.labelCount(t0) == 0);
    }
    {   // tower: rows, expiry moves the revision, an empty list hides it
        State s;
        auto f = split(s.tower(t0));
        CHECK(f.size() == 5 && f[1] == "0");
        CHECK(s.apply(R"({"cmd":"tower","ttl":5,"title":"STREET · TROLL PASS","sub":"LAP 1/1",
            "rows":[{"pos":"1","name":"D. Smith","gap":"LEADER"},{"pos":2,"name":"You","gap":"+0.8s","flag":"me"}]})", t0));
        f = split(s.tower(t0 + 1s));
        CHECK(f[1] == "1" && f[2] == "STREET · TROLL PASS" && f[4] == "2");
        const std::string rev = f[0];
        auto r = split(s.towerRow(1));
        CHECK(r.size() == 4 && r[0] == "2" && r[1] == "You" && r[2] == "+0.8s" && r[3] == "me");
        f = split(s.tower(t0 + 6s));
        CHECK(f[1] == "0" && f[0] != rev);
        CHECK(s.apply(R"({"cmd":"tower","rows":[]})", t0));
        CHECK(split(s.tower(t0))[1] == "0");
    }
    {   // calibration is clamped and versioned
        State s;
        const std::string before = split(s.view())[0];
        CHECK(s.apply(R"({"cmd":"view","range":99999,"projX":1280,"scale":0})", t0));
        auto f = split(s.view());
        CHECK(f.size() == 8 && f[0] != before && f[1] == "1000.00" && f[2] == "0.30" && f[3] == "1280.00");
        CHECK(!s.apply(R"({"cmd":"nope"})", t0));
        CHECK(!s.apply("not json", t0));
    }
    if (failures == 0) std::printf("broadcast state: all checks passed\n");
    return failures == 0 ? 0 : 1;
}
