#pragma once
// NCM Host plugin: the one Lua 5.4 VM that runs the NCM Host (ncm/host/*.lua) and, inside it, the NCM resources --
// the same language and the same coroutines OPEN//77 gives them (L338, KB-383/KB-385: CET's sandbox has neither).
// Single-threaded by contract: every call arrives on the game's script thread (CET -> NcmHost_Call).
#include <string>

struct lua_State;

namespace ncm::host {

class Vm {
public:
    // `root` = the plugin folder (holds host/, resources/, compiled/ is not needed here, save/, ncm.sqlite3)
    bool start(const std::string& root, std::string& error);
    // Dispatch one command to host/native.lua's dispatcher. Never throws; errors come back as {"ok":false,...} JSON.
    std::string call(const std::string& cmd, const std::string& payload);
    bool running() const { return L_ != nullptr; }
    void stop();
    ~Vm() { stop(); }

private:
    lua_State* L_ = nullptr;
    int dispatcher_ = -1;   // registry ref
    std::string root_;
};

using LogFn = void (*)(const char* level, const char* message);
void setLogger(LogFn fn);

}  // namespace ncm::host
