// NCM Sky state: the scene Lua sends, what redscript reads, and the rules that keep a dead feed from leaving anything
// in the sky.
#include "state.hpp"

#include <cstdio>
#include <cstdlib>
#include <string>

using namespace ncm::sky;
using Clock = State::Clock;

static int passed = 0;
static void check(const char* label, bool ok)
{
    if (!ok) { std::printf("  FAIL %s\n", label); std::exit(1); }
    ++passed;
    std::printf("  PASS %s\n", label);
}

static std::string revOf(const std::string& scene) { return scene.substr(0, scene.find('|')); }

int main()
{
    const auto t0 = Clock::now();
    State s;
    const std::string earth = R"({"cmd":"scene","bodies":[{"id":"earth","kind":1,"app":"default","p":[-12000,12000,6300],"q":[0,0,0,1]}]})";
    check("a scene is accepted", s.apply(earth, t0));
    const std::string first = s.scene(t0);
    check("the body is written for redscript", first.find("|earth`1`default`-12000.000`12000.000`6300.000`0.0000000`0.0000000`0.0000000`1.0000000") != std::string::npos);
    check("a quaternion that is not a rotation is refused", !s.apply(R"({"cmd":"scene","bodies":[{"id":"e","kind":1,"p":[0,0,0],"q":[0,0,0,0]}]})", t0));
    check("an old Euler body is refused (the protocol is quaternions)", !s.apply(R"({"cmd":"scene","bodies":[{"id":"e","kind":1,"p":[0,0,0],"r":[0,0,0]}]})", t0));
    s.apply(R"({"cmd":"scene","bodies":[{"id":"n","kind":1,"p":[0,0,0],"q":[0,0,0,1.2]}]})", t0);
    check("a drifted quaternion is normalised", s.scene(t0).find("|n`1`~`0.000`0.000`0.000`0.0000000`0.0000000`0.0000000`1.0000000") != std::string::npos);
    s.apply(earth, t0);
    const std::string settled = s.scene(t0);
    check("the same scene again keeps its revision", s.apply(earth, t0) && revOf(s.scene(t0)) == revOf(settled));
    const std::string turned = R"({"cmd":"scene","bodies":[{"id":"earth","kind":1,"app":"default","p":[-12000,12000,6300],"q":[0,0,0.7071068,0.7071068]}]})";
    s.apply(turned, t0);
    check("a turned body is a new revision", revOf(s.scene(t0)) != revOf(settled));

    check("an unknown command is refused", !s.apply(R"({"cmd":"nope"})", t0));
    check("a bad id is refused", !s.apply(R"({"cmd":"scene","bodies":[{"id":"Earth!","kind":1,"p":[0,0,0],"q":[0,0,0,1]}]})", t0));
    check("kind 0 is refused", !s.apply(R"({"cmd":"scene","bodies":[{"id":"e","kind":0,"p":[0,0,0],"q":[0,0,0,1]}]})", t0));
    check("outside the world box is refused (KB-411)", !s.apply(R"({"cmd":"scene","bodies":[{"id":"e","kind":1,"p":[-25000,0,0],"q":[0,0,0,1]}]})", t0));
    check("a duplicate id is refused", !s.apply(R"({"cmd":"scene","bodies":[{"id":"e","kind":1,"p":[0,0,0],"q":[0,0,0,1]},{"id":"e","kind":1,"p":[0,0,0],"q":[0,0,0,1]}]})", t0));
    check("a refused message changes nothing", s.scene(t0).find("earth`1") != std::string::npos);

    // a stale feed empties the sky
    const std::string before = s.scene(t0);
    const std::string later = s.scene(t0 + std::chrono::milliseconds(kStaleMs + 10));
    check("a stale feed empties the scene", later == revOf(later) + "|" && revOf(later) != revOf(before));
    check("health says it was cleared", s.health().find("\"staleCleared\":true") != std::string::npos);

    // a dropped socket empties it too
    s.apply(earth, t0);
    s.disconnect();
    const std::string gone = s.scene(t0);
    check("a dropped socket empties the scene", gone == revOf(gone) + "|");

    // an empty Lua table ({}) clears the sky like []
    s.apply(earth, t0);
    check("an empty object is accepted as an empty scene", s.apply(R"({"cmd":"scene","bodies":{}})", t0));
    const std::string cleared = s.scene(t0);
    check("...and empties it", cleared == revOf(cleared) + "|");

    // reports travel back to Lua
    s.report("earth", 1, 12345, "");
    check("a spawn is reported to Lua", s.statusJson().find("\"earth\":{\"entity\":\"12345\"") != std::string::npos);
    s.report("earth", 4, 0, "");
    check("a despawn removes the report", s.statusJson().find("earth") == std::string::npos);
    std::printf("sky state: %d passed, 0 failed\n", passed);
    return 0;
}
