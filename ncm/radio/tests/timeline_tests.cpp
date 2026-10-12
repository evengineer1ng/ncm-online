// Where in the broadcast a listener lands, and where a clip lives on disk (doc 59 §6).
#include "timeline.hpp"

#include <cstdio>
#include <cstdlib>

using namespace ncm::radio;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

int main()
{
    Item item;
    item.clips = {{"A#01", 1000, 200}, {"A#02~1", 500, 0}, {"lex/MARA/four", 300, 260}};
    CHECK(item.totalMs() == 2260);

    auto p = locate(item, 0);
    CHECK(p.index == 0 && p.intoClipMs == 0 && !p.ended);
    p = locate(item, 999);
    CHECK(p.index == 0 && p.intoClipMs == 999);
    p = locate(item, 1100);                 // in the gap after the first clip
    CHECK(p.index == -1 && !p.ended);
    p = locate(item, 1200);                 // the second clip starts after the gap
    CHECK(p.index == 1 && p.intoClipMs == 0);
    p = locate(item, 1700);                 // no gap after clip 2: the lexicon clip follows at once
    CHECK(p.index == 2 && p.intoClipMs == 0);
    p = locate(item, 2100);
    CHECK(p.index == -1 && !p.ended);
    p = locate(item, 2260);
    CHECK(p.ended);
    p = locate(item, -50);                  // a clock skew never seeks before the start
    CHECK(p.index == 0 && p.intoClipMs == 0);

    CHECK(clipPath(L"C:\\pack", "FINISH-NORMAL-A#01~2") == L"C:\\pack\\clips\\FINISH-NORMAL-A_01-2.ogg");
    CHECK(clipPath(L"C:\\pack", "lex/MARA/four-tenths-of-a-second") == L"C:\\pack\\clips\\lex\\MARA\\four-tenths-of-a-second.ogg");
    CHECK(clipPath(L"C:\\pack", "sting/news") == L"C:\\pack\\clips\\sting\\news.ogg");

    if (failures) { std::printf("%d failure(s)\n", failures); return EXIT_FAILURE; }
    std::printf("timeline: all checks passed\n");
    return EXIT_SUCCESS;
}
