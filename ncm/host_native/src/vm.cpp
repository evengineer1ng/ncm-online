#include "vm.hpp"
#include "net.hpp"

extern "C" {
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"
#include "sqlite3.h"
}

#include <cstdio>
#include <string>

namespace ncm::host {
namespace {

LogFn g_log = nullptr;
void logLine(const char* level, const std::string& msg)
{
    if (g_log) g_log(level, msg.c_str());
    else std::fprintf(stderr, "[%s] %s\n", level, msg.c_str());
}

// ------------------------------------------------------------------------------------------------ sqlite userdata
constexpr const char* kDbMeta = "ncmnative.db";
struct Db { sqlite3* h = nullptr; };

Db* checkDb(lua_State* L)
{
    auto* d = static_cast<Db*>(luaL_checkudata(L, 1, kDbMeta));
    if (!d->h) luaL_error(L, "database is closed");
    return d;
}

void pushColumn(lua_State* L, sqlite3_stmt* s, int c)
{
    switch (sqlite3_column_type(s, c)) {
    case SQLITE_INTEGER: lua_pushinteger(L, static_cast<lua_Integer>(sqlite3_column_int64(s, c))); break;
    case SQLITE_FLOAT: lua_pushnumber(L, sqlite3_column_double(s, c)); break;
    case SQLITE_NULL: lua_pushnil(L); break;
    default: {
        const auto* p = static_cast<const char*>(sqlite3_column_blob(s, c));
        lua_pushlstring(L, p ? p : "", static_cast<size_t>(sqlite3_column_bytes(s, c)));
    }
    }
}

// Run every statement in `sql`. mode 0 = exec, 1 = rows (array of name->value tables) of the last row-returning
// statement, 2 = first column of the first row. Raises a Lua error with SQLite's message on failure.
int runSql(lua_State* L, sqlite3* db, const char* sql, int mode)
{
    const char* tail = sql;
    bool havePushed = false;
    while (tail && *tail) {
        sqlite3_stmt* s = nullptr;
        if (sqlite3_prepare_v2(db, tail, -1, &s, &tail) != SQLITE_OK) {
            return luaL_error(L, "%s in: %s", sqlite3_errmsg(db), sql);
        }
        if (!s) break;   // trailing whitespace / comment
        const int ncol = sqlite3_column_count(s);
        if (mode == 1 && ncol > 0) {
            if (havePushed) lua_pop(L, 1);
            lua_newtable(L);
            havePushed = true;
        }
        int row = 0;
        bool scalarSet = false;
        int rc;
        while ((rc = sqlite3_step(s)) == SQLITE_ROW) {
            if (mode == 1 && ncol > 0) {
                lua_createtable(L, 0, ncol);
                for (int c = 0; c < ncol; ++c) {
                    pushColumn(L, s, c);
                    lua_setfield(L, -2, sqlite3_column_name(s, c));
                }
                lua_rawseti(L, -2, ++row);
            } else if (mode == 2 && ncol > 0 && !scalarSet) {
                if (havePushed) lua_pop(L, 1);
                pushColumn(L, s, 0);
                havePushed = scalarSet = true;
            }
        }
        if (rc != SQLITE_DONE) {
            // no C++ object may be alive across lua_error (it longjmps): the message goes onto the Lua stack first
            lua_pushfstring(L, "%s in: %s", sqlite3_errmsg(db), sql);
            sqlite3_finalize(s);
            return lua_error(L);
        }
        sqlite3_finalize(s);
    }
    if (mode == 0) { lua_pushboolean(L, 1); return 1; }
    if (!havePushed) { if (mode == 1) lua_newtable(L); else lua_pushnil(L); }
    return 1;
}

int dbExec(lua_State* L) { return runSql(L, checkDb(L)->h, luaL_checkstring(L, 2), 0); }
int dbQuery(lua_State* L) { return runSql(L, checkDb(L)->h, luaL_checkstring(L, 2), 1); }
int dbScalar(lua_State* L) { return runSql(L, checkDb(L)->h, luaL_checkstring(L, 2), 2); }
int dbChanges(lua_State* L) { lua_pushinteger(L, sqlite3_changes(checkDb(L)->h)); return 1; }
int dbLastId(lua_State* L) { lua_pushinteger(L, static_cast<lua_Integer>(sqlite3_last_insert_rowid(checkDb(L)->h))); return 1; }
int dbVersion(lua_State* L) { lua_pushstring(L, sqlite3_libversion()); return 1; }
int dbCheck(lua_State* L)
{
    auto* d = checkDb(L);
    sqlite3_stmt* s = nullptr;
    const int rc = sqlite3_prepare_v2(d->h, luaL_checkstring(L, 2), -1, &s, nullptr);
    if (s) sqlite3_finalize(s);
    if (rc != SQLITE_OK) { lua_pushnil(L); lua_pushstring(L, sqlite3_errmsg(d->h)); return 2; }
    lua_pushboolean(L, 1);
    return 1;
}
int dbClose(lua_State* L)
{
    auto* d = static_cast<Db*>(luaL_checkudata(L, 1, kDbMeta));
    if (d->h) { sqlite3_close_v2(d->h); d->h = nullptr; }
    return 0;
}

int openDb(lua_State* L)
{
    const char* path = luaL_checkstring(L, 1);
    auto* d = static_cast<Db*>(lua_newuserdatauv(L, sizeof(Db), 0));
    d->h = nullptr;
    luaL_setmetatable(L, kDbMeta);
    if (sqlite3_open_v2(path, &d->h, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr) != SQLITE_OK) {
        lua_pushnil(L);
        lua_pushstring(L, d->h ? sqlite3_errmsg(d->h) : "sqlite3_open_v2 failed");
        if (d->h) { sqlite3_close_v2(d->h); d->h = nullptr; }
        return 2;
    }
    // durable but not paranoid: WAL keeps a crash from tearing the file; normal sync is enough for a game save
    sqlite3_exec(d->h, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=OFF;", nullptr, nullptr, nullptr);
    return 1;
}

int nativeLog(lua_State* L)
{
    logLine(luaL_optstring(L, 2, "info"), luaL_checkstring(L, 1));
    return 0;
}

int openNative(lua_State* L)
{
    luaL_newmetatable(L, kDbMeta);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    const luaL_Reg dbm[] = { { "exec", dbExec }, { "query", dbQuery }, { "scalar", dbScalar }, { "changes", dbChanges },
        { "lastId", dbLastId }, { "version", dbVersion }, { "check", dbCheck }, { "close", dbClose }, { "__gc", dbClose },
        { nullptr, nullptr } };
    luaL_setfuncs(L, dbm, 0);
    lua_pop(L, 1);
    const luaL_Reg fns[] = { { "sqlite_open", openDb }, { "log", nativeLog }, { nullptr, nullptr } };
    luaL_newlib(L, fns);
    registerNet(L);   // loopback websockets / probe / http for the page adapters (ncm/host/webui)
    return 1;
}

int traceback(lua_State* L)
{
    const char* msg = lua_tostring(L, 1);
    luaL_traceback(L, L, msg ? msg : "(error object is not a string)", 1);
    return 1;
}

std::string jsonError(const std::string& what)
{
    std::string out = "{\"ok\":false,\"error\":\"";
    for (char c : what) {
        if (c == '"' || c == '\\') { out += '\\'; out += c; }
        else if (c == '\n') out += "\\n";
        else if (static_cast<unsigned char>(c) < 0x20) out += ' ';
        else out += c;
    }
    return out + "\"}";
}

}  // namespace

void setLogger(LogFn fn) { g_log = fn; }

bool Vm::start(const std::string& root, std::string& error)
{
    if (L_) return true;
    root_ = root;
    L_ = luaL_newstate();
    if (!L_) { error = "luaL_newstate failed"; return false; }
    luaL_openlibs(L_);
    luaL_requiref(L_, "ncmnative", openNative, 1);
    lua_pop(L_, 1);
    lua_pushstring(L_, root_.c_str());
    lua_setglobal(L_, "NCM_HOST_ROOT");

    lua_pushcfunction(L_, traceback);
    const int tb = lua_gettop(L_);
    const std::string entry = root_ + "/host/native.lua";
    if (luaL_loadfile(L_, entry.c_str()) != LUA_OK || lua_pcall(L_, 0, 1, tb) != LUA_OK) {
        error = lua_tostring(L_, -1) ? lua_tostring(L_, -1) : "host/native.lua failed";
        stop();
        return false;
    }
    if (!lua_isfunction(L_, -1)) { error = "host/native.lua must return a dispatcher function"; stop(); return false; }
    dispatcher_ = luaL_ref(L_, LUA_REGISTRYINDEX);
    lua_pop(L_, 1);   // traceback
    logLine("info", "NCM Host VM started (" LUA_RELEASE ", SQLite " SQLITE_VERSION ") at " + root_);
    return true;
}

std::string Vm::call(const std::string& cmd, const std::string& payload)
{
    if (!L_ || dispatcher_ < 0) return jsonError("host not running");
    const int top = lua_gettop(L_);
    lua_pushcfunction(L_, traceback);
    const int tb = lua_gettop(L_);
    lua_rawgeti(L_, LUA_REGISTRYINDEX, dispatcher_);
    lua_pushlstring(L_, cmd.data(), cmd.size());
    lua_pushlstring(L_, payload.data(), payload.size());
    std::string out;
    if (lua_pcall(L_, 2, 1, tb) != LUA_OK) {
        out = jsonError(lua_tostring(L_, -1) ? lua_tostring(L_, -1) : "dispatch failed");
        logLine("error", out);
    } else {
        size_t n = 0;
        const char* s = lua_tolstring(L_, -1, &n);
        out = s ? std::string(s, n) : jsonError("dispatcher returned no string");
    }
    lua_settop(L_, top);
    return out;
}

void Vm::stop()
{
    netShutdown();
    if (L_) { lua_close(L_); L_ = nullptr; }
    dispatcher_ = -1;
}

}  // namespace ncm::host
