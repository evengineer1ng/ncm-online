#pragma once

#include <cstdint>
#include <string>
#include <vector>

// The programme item the server is airing, and where in it a listener is (doc 59 §6). Pure: no audio, no clock.
//
// The server owns the broadcast's time. An item is a sequence of clips, each followed by a gap; the client is told
// how far into the item the broadcast already is, so tuning in lands mid-sentence the way a real radio does
// (bible §148: "the player has joined an already-running broadcast").
namespace ncm::radio {

struct Clip {
    std::string key;     // render key, e.g. "FINISH-NORMAL-A#01~1" or "lex/MARA/four-tenths-of-a-second"
    int32_t ms = 0;      // its length, from the pack manifest
    int32_t gapMs = 0;   // silence after it
};

struct Item {
    uint64_t seq = 0;
    std::string beat;
    std::vector<Clip> clips;

    int64_t totalMs() const
    {
        int64_t t = 0;
        for (const auto& c : clips) t += c.ms + c.gapMs;
        return t;
    }
};

struct Position {
    int index = -1;          // the clip sounding at `elapsed`, or -1 in a gap / past the end
    int32_t intoClipMs = 0;  // how far into that clip
    bool ended = false;
};

inline Position locate(const Item& item, int64_t elapsedMs)
{
    Position p;
    if (elapsedMs < 0) elapsedMs = 0;
    int64_t t = 0;
    for (size_t i = 0; i < item.clips.size(); ++i) {
        const auto& c = item.clips[i];
        if (elapsedMs < t + c.ms) {
            p.index = static_cast<int>(i);
            p.intoClipMs = static_cast<int32_t>(elapsedMs - t);
            return p;
        }
        t += c.ms;
        if (elapsedMs < t + c.gapMs) return p;   // in the gap after clip i
        t += c.gapMs;
    }
    p.ended = true;
    return p;
}

// A render key -> the clip's path under the pack, the same mapping `ncm/radio/voice/render.py` writes.
inline std::wstring clipPath(const std::wstring& packDir, const std::string& key)
{
    std::wstring out = packDir + L"\\clips\\";
    for (const char ch : key) {
        if (ch == '#') out.push_back(L'_');
        else if (ch == '~') out.push_back(L'-');
        else if (ch == '/') out.push_back(L'\\');
        else out.push_back(static_cast<wchar_t>(static_cast<unsigned char>(ch)));
    }
    out += L".ogg";
    return out;
}
}
