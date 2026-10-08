// NCM Host self-test: the plugin's own Lua 5.4 + SQLite VM, the real host and the real resources, no game.
//   ncm_host_selftest <plugin-folder>        (the staged red4ext/plugins/ncm_host folder)
// Boots on a virtual clock and an in-memory database, makes a tape, enters it, runs 5 minutes, claims the Kimiko RB15,
// and fails unless every step answers ok with zero host errors.
#include "vm.hpp"

#include <cstdio>
#include <string>

static int failures = 0;
static std::string step(ncm::host::Vm& vm, const char* cmd, const std::string& payload, const char* mustContain)
{
    const std::string out = vm.call(cmd, payload);
    const bool ok = out.find("\"ok\":true") != std::string::npos && (!mustContain || out.find(mustContain) != std::string::npos);
    std::printf("%s %-10s %s\n", ok ? "  PASS" : "  FAIL", cmd, out.substr(0, 400).c_str());
    if (!ok) ++failures;
    return out;
}

// L340: the line answers redscript reads (no JSON there): pass when the expected record is present
static std::string lines(ncm::host::Vm& vm, const char* cmd, const std::string& payload, const char* mustContain)
{
    const std::string out = vm.call(cmd, payload);
    const bool ok = out.find(mustContain) != std::string::npos;
    std::string shown = out.substr(0, 300);
    for (auto& c : shown) if (c == '\n') c = '/';
    std::printf("%s %-10s %s\n", ok ? "  PASS" : "  FAIL", cmd, shown.c_str());
    if (!ok) ++failures;
    return out;
}

static std::string field(const std::string& json, const std::string& key)
{
    const auto k = json.find("\"" + key + "\":\"");
    if (k == std::string::npos) return {};
    const auto s = k + key.size() + 4;
    return json.substr(s, json.find('"', s) - s);
}

int main(int argc, char** argv)
{
    if (argc < 2) { std::printf("usage: ncm_host_selftest <plugin-folder>\n"); return 2; }
    ncm::host::Vm vm;
    std::string err;
    if (!vm.start(argv[1], err)) { std::printf("  FAIL start: %s\n", err.c_str()); return 1; }
    std::printf("  PASS start (Lua 5.4 + SQLite in-process)\n");
    step(vm, "boot", "{\"test\":true,\"virtualClock\":1791388800,\"memoryDb\":true}", "\"version\"");
    const std::string t = step(vm, "newTape", "{}", "\"id\"");
    const std::string id = field(t, "id");
    step(vm, "mount", "{\"id\":\"" + id + "\"}", nullptr);
    step(vm, "advance", "{\"seconds\":300}", nullptr);
    step(vm, "tick", "{\"player\":{\"x\":-1418,\"y\":192,\"z\":25,\"heading\":0}}", "\"hud\"");
    step(vm, "claim", "{\"record\":\"Vehicle.v_sport1_rb15_f1_kimiko\"}", nullptr);
    step(vm, "advance", "{\"seconds\":5}", nullptr);
    step(vm, "garage", "{}", "NCM #");
    step(vm, "status", "{}", "\"errors\":0");
    step(vm, "unmount", "{}", nullptr);
    // L340 phase 2: the game drives NCM -- a save loads with nothing chosen (dormant), the menu chooses the tape, frames
    // carry V in and the Race Week line out, the menu lists the tape in play, the session ends
    lines(vm, "session", "{}", "state|none");
    lines(vm, "choose", "{\"kind\":\"tape\",\"id\":\"" + id + "\"}", "state|mounted");
    lines(vm, "frame", "{\"budgetMs\":3,\"player\":{\"x\":-1418,\"y\":192,\"z\":25,\"heading\":0}}", "hud|TAPE 01");
    lines(vm, "tapes", "{}", ("mounted|" + id).c_str());
    lines(vm, "leave", "{}", "state|dormant");
    lines(vm, "session", "{}", "state|mounted");   // the choice is remembered: the next save mounts it
    // Mod Settings "Tape in play": 0 = without NCM, 1 = TAPE 01, past the last = one new tape (never two)
    lines(vm, "select", "{\"select\":0}", "state|without");
    lines(vm, "select", "{\"select\":1}", "state|mounted");
    lines(vm, "select", "{\"select\":2}", "|2");
    lines(vm, "select", "{\"select\":2}", "|2");
    lines(vm, "tapes", "{}", "tape|");
    lines(vm, "leave", "{}", "state|dormant");
    lines(vm, "session", "{\"select\":1}", "state|mounted");
    lines(vm, "leave", "{}", "state|dormant");
    std::printf("ncm_host selftest: %d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
