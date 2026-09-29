// The parts of the wheel that can be wrong without a game running: the wire format redscript splits on '|', and
// the two rules that close a wheel nobody is driving any more.
#include "state.hpp"

#include <cstdio>
#include <string>

using ncm::radial::State;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

int main()
{
    const auto t0 = State::Clock::now();

    {   // A layout with a separator in a label cannot shift every later field.
        State s;
        CHECK(s.apply(R"({"cmd":"layout","title":"NCM","hint":"release to open",
            "slots":[{"label":"H|UB","key":"F6","detail":"Everything"},null,{"label":"Call","state":2}]})", t0));
        const std::string l = s.layout();
        CHECK(l.rfind("1|NCM|release to open|1|HUB|F6|Everything|0|~|~|~", 0) == 0);
        CHECK(l.find("|2|Call|~|~") != std::string::npos);
        int fields = 1;
        for (char c : l) fields += c == '|';
        CHECK(fields == 3 + 8 * 4);
        CHECK(l.find("||") == std::string::npos);        // no empty field can ever reach StrSplit
    }
    {   // A slot with no label is an open slot, whatever state it claims.
        State s;
        CHECK(s.apply(R"({"cmd":"layout","slots":[{"state":1,"label":""}]})", t0));
        CHECK(s.layout().rfind("1|~|~|0|~|~|~", 0) == 0);
    }
    {   // Frames: selection bounds, pointer normalisation.
        State s;
        CHECK(s.apply(R"({"cmd":"frame","open":true,"sel":9,"pointer":450})", t0));
        CHECK(s.frame(t0) == "1|-1|90.0|0");
        CHECK(s.apply(R"({"cmd":"frame","open":true,"sel":2,"pointer":-5})", t0));
        CHECK(s.frame(t0) == "1|2|-1.0|0");
    }
    {   // A dropped socket closes the wheel.
        State s;
        s.apply(R"({"cmd":"frame","open":true,"sel":3,"pointer":135})", t0);
        s.disconnect();
        CHECK(s.frame(t0) == "0|-1|-1.0|0");
    }
    {   // A stalled feed closes the wheel, and says so in health.
        State s;
        s.apply(R"({"cmd":"frame","open":true,"sel":1,"pointer":45})", t0);
        CHECK(s.frame(t0 + std::chrono::milliseconds(1000)).rfind("1|1|", 0) == 0);
        CHECK(s.frame(t0 + std::chrono::milliseconds(2000)) == "0|-1|-1.0|0");
        CHECK(s.health().find("\"staleClosed\":true") != std::string::npos);
    }
    {   // A label cannot smuggle in the sentinel.
        State s;
        s.apply(R"({"cmd":"layout","slots":[{"label":"~"}]})", t0);
        CHECK(s.layout().rfind("1|~|~|0|", 0) == 0);    // "~" alone cleans to empty, so the slot is open
    }
    {   // Garbage changes nothing.
        State s;
        CHECK(!s.apply("not json", t0));
        CHECK(!s.apply(R"({"cmd":"explode"})", t0));
        CHECK(!s.apply(R"({"cmd":"layout","slots":"nope"})", t0));
        CHECK(s.layout().rfind("0|NCM|~|", 0) == 0);
    }

    if (failures == 0) std::printf("ncm_radial state: all checks passed\n");
    return failures == 0 ? 0 : 1;
}
