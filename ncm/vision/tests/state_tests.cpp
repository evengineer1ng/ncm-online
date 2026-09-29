// The parts of the scanner that can be wrong without a game running: the reticle wire redscript splits on '|',
// the record key that must match `TDBID.ToNumber`, and the rules that clear a reticle nobody is feeding.
#include "state.hpp"

#include <cstdio>
#include <string>

using ncm::vision::State;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

static int fields(const std::string& s)
{
    int n = 1;
    for (char c : s) n += c == '|';
    return n;
}

int main()
{
    const auto t0 = State::Clock::now();

    // CRC32-B check value, and the TweakDBID identity layout (hash | length << 32).
    CHECK(ncm::vision::crc32("123456789") == 0xCBF43926u);
    CHECK(ncm::vision::recordKey("123456789") == (0xCBF43926ull | (9ull << 32)));

    {   // Separators and control characters cannot shift a field; empties are '~'.
        State s;
        CHECK(s.apply(R"({"cmd":"frame","state":4,"progress":0.5,"title":"Maki|gai","detail":""})", t0));
        const auto r = s.reticle(t0);
        CHECK(fields(r) == 5);
        CHECK(r == "1|4|0.500|Makigai|~");
        CHECK(r.find("||") == std::string::npos);
    }
    {   // Out-of-range state and progress are clamped, not trusted.
        State s;
        CHECK(s.apply(R"({"cmd":"frame","state":99,"progress":7})", t0));
        CHECK(s.reticle(t0) == "1|0|1.000|~|~");
    }
    {   // A dropped socket clears the text.
        State s;
        s.apply(R"({"cmd":"frame","state":3,"title":"Known"})", t0);
        s.disconnect();
        CHECK(s.reticle(t0).find("|0|0.000|~|~") != std::string::npos);
    }
    {   // A stalled feed clears the text, and health says so.
        State s;
        s.apply(R"({"cmd":"frame","state":2,"title":"Unknown"})", t0);
        CHECK(s.reticle(t0 + std::chrono::milliseconds(1000)).find("|2|") != std::string::npos);
        CHECK(s.reticle(t0 + std::chrono::milliseconds(ncm::vision::kStaleMs + 1)).find("|0|") != std::string::npos);
        CHECK(s.health().find("\"staleCleared\":true") != std::string::npos);
    }
    {   // A reported TweakDBID travels as its identity key, whatever its offset bytes say.
        State s;
        const uint64_t id = ncm::vision::recordKey("Vehicle.v_sport2_quadra_type66") | (0xABCDEFull << 40);
        s.report(true, 1234567890123ull, id, 1, 22.0f);
        const auto j = s.targetJson();
        CHECK(j.find("\"recordKey\":\"" + std::to_string(ncm::vision::recordKey("Vehicle.v_sport2_quadra_type66")) + "\"") != std::string::npos);
        CHECK(j.find("\"entity\":\"1234567890123\"") != std::string::npos);
        CHECK(j.find("\"kind\":\"vehicle\"") != std::string::npos);
        CHECK(!s.apply(R"({"cmd":"records","list":["x"]})", t0));
    }
    {   // Vision off reports nothing, and an unchanged report does not bump seq.
        State s;
        s.report(true, 5, 0, 2, 3.0f);
        const auto a = s.targetJson();
        s.report(true, 5, 0, 2, 3.1f);
        CHECK(s.targetJson() == a);
        s.report(false, 5, 0, 2, 3.0f);
        CHECK(s.targetJson().find("\"entity\":\"\"") != std::string::npos);
        CHECK(s.targetJson().find("\"active\":false") != std::string::npos);
    }
    {   // The panel wire: six fields, rows and info joined with their own separators that text cannot forge.
        State s;
        CHECK(s.apply(R"({"cmd":"frame","state":3,"title":"x","selected":1,
            "hacks":[{"s":0,"l":"LIMITER","r":"2.0s"},{"s":4,"l":"ENGINE^CUT","r":"COOL`ING"}],
            "infoTitle":"Thorton Galena","infoSub":"STREET",
            "info":[{"k":"OPERATOR","v":"NCM TRAFFIC"},{"k":"RANGE","v":"12|m"}]})", t0));
        s.reticle(t0);
        const auto p = s.panel();
        CHECK(fields(p) == 6);
        CHECK(p == "1|1|0`LIMITER`2.0s^4`ENGINECUT`COOLING|Thorton Galena|STREET|OPERATOR`NCM TRAFFIC^RANGE`12m");
    }
    {   // No list is selected -1; a stale feed clears the panels with the reticle.
        State s;
        s.apply(R"({"cmd":"frame","state":1,"selected":7,"hacks":[{"s":9,"l":"A"}]})", t0);
        CHECK(s.panel() == "1|-1|0`A`|~|~|~");
        s.reticle(t0 + std::chrono::milliseconds(ncm::vision::kStaleMs + 1));
        CHECK(s.panel().find("|-1|~|~|~|~") != std::string::npos);
    }
    {   // The looked-at point travels with the report; moving it half a metre is a new report.
        State s;
        s.report(true, 9, 0, 1, 10.0f, 100.0f, -200.0f, 30.0f);
        const auto a = s.targetJson();
        CHECK(a.find("\"pos\":{\"x\":100.0,\"y\":-200.0,\"z\":30.0}") != std::string::npos);
        s.report(true, 9, 0, 1, 10.0f, 101.0f, -200.0f, 30.0f);
        CHECK(s.targetJson() != a);
    }
    {   // Garbage is refused and changes nothing.
        State s;
        CHECK(!s.apply("not json", t0));
        CHECK(!s.apply(R"({"cmd":"explode"})", t0));
        CHECK(s.apply(R"({"cmd":"ping"})", t0));
        CHECK(s.reticle(t0) == "0|0|0.000|~|~");
    }

    if (failures) { std::printf("%d failure(s)\n", failures); return 1; }
    std::printf("ncm_vision state tests: all passed\n");
    return 0;
}
