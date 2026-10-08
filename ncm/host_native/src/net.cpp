#include "net.hpp"

extern "C" {
#include "lauxlib.h"
#include "lua.h"
}

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <winhttp.h>

#include <atomic>
#include <condition_variable>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

namespace ncm::host {
namespace {

std::wstring widen(const std::string& s)
{
    if (s.empty()) return {};
    const int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
    std::wstring w(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), w.data(), n);
    return w;
}

// "ws://host:port/path" or "http://host:port/path" -> parts. Loopback only by design; any host parses.
bool parseUrl(const std::string& url, bool& tls, std::string& host, int& port, std::string& path)
{
    std::string rest;
    if (url.rfind("ws://", 0) == 0) { tls = false; rest = url.substr(5); }
    else if (url.rfind("http://", 0) == 0) { tls = false; rest = url.substr(7); }
    else return false;
    const auto slash = rest.find('/');
    std::string hp = slash == std::string::npos ? rest : rest.substr(0, slash);
    path = slash == std::string::npos ? "/" : rest.substr(slash);
    const auto colon = hp.rfind(':');
    if (colon == std::string::npos) { host = hp; port = 80; }
    else { host = hp.substr(0, colon); port = std::atoi(hp.substr(colon + 1).c_str()); }
    return !host.empty() && port > 0 && port < 65536;
}

// ------------------------------------------------------------------------------------------------ websocket
struct Sock {
    std::mutex mu;
    std::condition_variable cv;
    std::deque<std::string> inbox, outbox;
    std::string state = "connecting";   // connecting | open | closed
    std::string error;
    std::atomic<bool> closing{ false };
    HINTERNET session = nullptr, connect = nullptr, ws = nullptr;
    std::thread reader, writer;
};

std::mutex g_mu;
std::map<int, std::shared_ptr<Sock>> g_socks;
int g_nextId = 1;

void setClosed(Sock& s, const std::string& why)
{
    std::lock_guard<std::mutex> lk(s.mu);
    if (s.state != "closed") { s.state = "closed"; if (s.error.empty()) s.error = why; }
    s.cv.notify_all();
}

void closeHandles(Sock& s)
{
    HINTERNET ws = nullptr, c = nullptr, se = nullptr;
    {
        std::lock_guard<std::mutex> lk(s.mu);
        ws = s.ws; c = s.connect; se = s.session;
        s.ws = s.connect = s.session = nullptr;
    }
    if (ws) { WinHttpWebSocketClose(ws, WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS, nullptr, 0); WinHttpCloseHandle(ws); }
    if (c) WinHttpCloseHandle(c);
    if (se) WinHttpCloseHandle(se);
}

void runReader(std::shared_ptr<Sock> s, std::string host, int port, std::string path)
{
    HINTERNET session = WinHttpOpen(L"NCM-Host/3.0", WINHTTP_ACCESS_TYPE_NO_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session) { setClosed(*s, "WinHttpOpen failed"); return; }
    WinHttpSetTimeouts(session, 2000, 2000, 2000, 0);   // resolve, connect, send; receive never times out (an idle socket is fine)
    HINTERNET connect = WinHttpConnect(session, widen(host).c_str(), static_cast<INTERNET_PORT>(port), 0);
    HINTERNET req = connect ? WinHttpOpenRequest(connect, L"GET", widen(path).c_str(), nullptr, WINHTTP_NO_REFERER,
                                                 WINHTTP_DEFAULT_ACCEPT_TYPES, 0) : nullptr;
    bool ok = req && WinHttpSetOption(req, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, nullptr, 0) &&
              WinHttpSendRequest(req, WINHTTP_NO_ADDITIONAL_HEADERS, 0, nullptr, 0, 0, 0) && WinHttpReceiveResponse(req, nullptr);
    HINTERNET ws = ok ? WinHttpWebSocketCompleteUpgrade(req, 0) : nullptr;
    if (req) WinHttpCloseHandle(req);
    if (!ws) {
        const DWORD e = GetLastError();
        if (connect) WinHttpCloseHandle(connect);
        WinHttpCloseHandle(session);
        setClosed(*s, "connect failed (" + std::to_string(e) + ")");
        return;
    }
    {
        std::lock_guard<std::mutex> lk(s->mu);
        s->session = session; s->connect = connect; s->ws = ws;
        if (s->closing) { /* closed while connecting */ }
        else s->state = "open";
        s->cv.notify_all();
    }
    if (s->closing) { closeHandles(*s); setClosed(*s, "closed"); return; }
    std::string msg;
    std::string buf(64 * 1024, '\0');
    for (;;) {
        DWORD got = 0;
        WINHTTP_WEB_SOCKET_BUFFER_TYPE type{};
        const DWORD rc = WinHttpWebSocketReceive(ws, buf.data(), static_cast<DWORD>(buf.size()), &got, &type);
        if (rc != NO_ERROR) { setClosed(*s, s->closing ? "closed" : ("receive error " + std::to_string(rc))); break; }
        if (type == WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE) { setClosed(*s, "socket closed"); break; }
        msg.append(buf.data(), got);
        if (type == WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE || type == WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE) {
            std::lock_guard<std::mutex> lk(s->mu);
            if (s->inbox.size() < 4096) s->inbox.push_back(std::move(msg));   // a stalled game never grows memory unbounded
            msg.clear();
        }
    }
    closeHandles(*s);
}

void runWriter(std::shared_ptr<Sock> s)
{
    for (;;) {
        std::string out;
        HINTERNET ws = nullptr;
        {
            std::unique_lock<std::mutex> lk(s->mu);
            s->cv.wait(lk, [&] { return s->state == "closed" || (s->state == "open" && !s->outbox.empty()); });
            if (s->state == "closed") return;
            out = std::move(s->outbox.front());
            s->outbox.pop_front();
            ws = s->ws;
        }
        if (ws && WinHttpWebSocketSend(ws, WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE, out.data(), static_cast<DWORD>(out.size())) != NO_ERROR) {
            setClosed(*s, "send failed");
            return;
        }
    }
}

std::shared_ptr<Sock> findSock(int id)
{
    std::lock_guard<std::mutex> lk(g_mu);
    auto it = g_socks.find(id);
    return it == g_socks.end() ? nullptr : it->second;
}

void stopSock(const std::shared_ptr<Sock>& s)
{
    s->closing = true;
    closeHandles(*s);                // unblocks a pending receive
    setClosed(*s, "closed");         // releases the writer
    if (s->reader.joinable()) s->reader.detach();
    if (s->writer.joinable()) s->writer.detach();
}

//- ws_open(url) -> id | nil, err. Connects in the background; poll for "open".
int wsOpen(lua_State* L)
{
    const std::string url = luaL_checkstring(L, 1);
    bool tls = false; std::string host, path; int port = 0;
    if (!parseUrl(url, tls, host, port, path)) { lua_pushnil(L); lua_pushstring(L, "bad url"); return 2; }
    auto s = std::make_shared<Sock>();
    int id;
    { std::lock_guard<std::mutex> lk(g_mu); id = g_nextId++; g_socks[id] = s; }
    s->reader = std::thread(runReader, s, host, port, path);
    s->writer = std::thread(runWriter, s);
    lua_pushinteger(L, id);
    return 1;
}

//- ws_send(id, text) -> bool (queued; false when the socket is closed)
int wsSend(lua_State* L)
{
    auto s = findSock(static_cast<int>(luaL_checkinteger(L, 1)));
    size_t n = 0;
    const char* p = luaL_checklstring(L, 2, &n);
    bool ok = false;
    if (s) {
        std::lock_guard<std::mutex> lk(s->mu);
        if (s->state != "closed" && s->outbox.size() < 1024) { s->outbox.emplace_back(p, n); ok = true; s->cv.notify_all(); }
    }
    lua_pushboolean(L, ok);
    return 1;
}

//- ws_poll(id) -> state, { messages... }, error
int wsPoll(lua_State* L)
{
    auto s = findSock(static_cast<int>(luaL_checkinteger(L, 1)));
    if (!s) { lua_pushstring(L, "closed"); lua_newtable(L); lua_pushstring(L, "no such socket"); return 3; }
    std::deque<std::string> got;
    std::string state, err;
    {
        std::lock_guard<std::mutex> lk(s->mu);
        got.swap(s->inbox);
        state = s->state; err = s->error;
    }
    lua_pushstring(L, state.c_str());
    lua_createtable(L, static_cast<int>(got.size()), 0);
    int i = 0;
    for (auto& m : got) { lua_pushlstring(L, m.data(), m.size()); lua_rawseti(L, -2, ++i); }
    if (err.empty()) lua_pushnil(L); else lua_pushstring(L, err.c_str());
    return 3;
}

//- ws_close(id)
int wsClose(lua_State* L)
{
    const int id = static_cast<int>(luaL_checkinteger(L, 1));
    std::shared_ptr<Sock> s;
    { std::lock_guard<std::mutex> lk(g_mu); auto it = g_socks.find(id); if (it != g_socks.end()) { s = it->second; g_socks.erase(it); } }
    if (s) stopSock(s);
    return 0;
}

// ------------------------------------------------------------------------------------------------ tcp probe
//- tcp_probe(host, port, timeoutMs = 150) -> bool: is something listening? A refused loopback connect is immediate.
int tcpProbe(lua_State* L)
{
    const std::string host = luaL_checkstring(L, 1);
    const int port = static_cast<int>(luaL_checkinteger(L, 2));
    const int timeoutMs = static_cast<int>(luaL_optinteger(L, 3, 150));
    static bool wsaUp = false;
    if (!wsaUp) { WSADATA d; wsaUp = WSAStartup(MAKEWORD(2, 2), &d) == 0; }
    bool ok = false;
    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s != INVALID_SOCKET) {
        u_long nb = 1;
        ioctlsocket(s, FIONBIO, &nb);
        sockaddr_in a{};
        a.sin_family = AF_INET;
        a.sin_port = htons(static_cast<u_short>(port));
        inet_pton(AF_INET, host == "localhost" ? "127.0.0.1" : host.c_str(), &a.sin_addr);
        connect(s, reinterpret_cast<sockaddr*>(&a), sizeof(a));
        fd_set w, e; FD_ZERO(&w); FD_ZERO(&e); FD_SET(s, &w); FD_SET(s, &e);
        timeval tv{ timeoutMs / 1000, (timeoutMs % 1000) * 1000 };
        if (select(0, nullptr, &w, &e, &tv) > 0 && FD_ISSET(s, &w) && !FD_ISSET(s, &e)) ok = true;
        closesocket(s);
    }
    lua_pushboolean(L, ok);
    return 1;
}

// ------------------------------------------------------------------------------------------------ http
struct Req {
    std::mutex mu;
    bool done = false;
    int status = 0;
    std::string body, error;
};
std::map<int, std::shared_ptr<Req>> g_reqs;
int g_nextReq = 1;

void runHttp(std::shared_ptr<Req> r, std::string method, std::string host, int port, std::string path, std::string body)
{
    HINTERNET se = WinHttpOpen(L"NCM-Host/3.0", WINHTTP_ACCESS_TYPE_NO_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    HINTERNET c = se ? WinHttpConnect(se, widen(host).c_str(), static_cast<INTERNET_PORT>(port), 0) : nullptr;
    if (se) WinHttpSetTimeouts(se, 2000, 2000, 2000, 4000);
    HINTERNET q = c ? WinHttpOpenRequest(c, widen(method).c_str(), widen(path).c_str(), nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0) : nullptr;
    const wchar_t* hdr = L"Content-Type: text/plain\r\n";
    bool ok = q && WinHttpSendRequest(q, method == "POST" ? hdr : WINHTTP_NO_ADDITIONAL_HEADERS, method == "POST" ? static_cast<DWORD>(-1L) : 0,
                                      body.empty() ? nullptr : body.data(), static_cast<DWORD>(body.size()), static_cast<DWORD>(body.size()), 0)
              && WinHttpReceiveResponse(q, nullptr);
    std::string out;
    DWORD status = 0, sz = sizeof(status);
    if (ok) {
        WinHttpQueryHeaders(q, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &status, &sz, WINHTTP_NO_HEADER_INDEX);
        for (;;) {
            DWORD avail = 0;
            if (!WinHttpQueryDataAvailable(q, &avail) || avail == 0) break;
            std::string chunk(avail, '\0');
            DWORD read = 0;
            if (!WinHttpReadData(q, chunk.data(), avail, &read)) break;
            out.append(chunk.data(), read);
        }
    }
    const DWORD e = ok ? 0 : GetLastError();
    if (q) WinHttpCloseHandle(q);
    if (c) WinHttpCloseHandle(c);
    if (se) WinHttpCloseHandle(se);
    std::lock_guard<std::mutex> lk(r->mu);
    r->done = true;
    r->status = static_cast<int>(status);
    r->body = std::move(out);
    if (!ok) r->error = "request failed (" + std::to_string(e) + ")";
}

//- http_start(method, url, body?) -> id | nil, err
int httpStart(lua_State* L)
{
    const std::string method = luaL_checkstring(L, 1);
    const std::string url = luaL_checkstring(L, 2);
    size_t n = 0;
    const char* b = luaL_optlstring(L, 3, "", &n);
    bool tls = false; std::string host, path; int port = 0;
    if (!parseUrl(url, tls, host, port, path)) { lua_pushnil(L); lua_pushstring(L, "bad url"); return 2; }
    auto r = std::make_shared<Req>();
    int id;
    { std::lock_guard<std::mutex> lk(g_mu); id = g_nextReq++; g_reqs[id] = r; }
    std::thread(runHttp, r, method, host, port, path, std::string(b, n)).detach();
    lua_pushinteger(L, id);
    return 1;
}

//- http_poll(id) -> done, status, body, error   (a finished request is forgotten after it is read)
int httpPoll(lua_State* L)
{
    const int id = static_cast<int>(luaL_checkinteger(L, 1));
    std::shared_ptr<Req> r;
    { std::lock_guard<std::mutex> lk(g_mu); auto it = g_reqs.find(id); if (it != g_reqs.end()) r = it->second; }
    if (!r) { lua_pushboolean(L, 1); lua_pushinteger(L, 0); lua_pushnil(L); lua_pushstring(L, "no such request"); return 4; }
    std::lock_guard<std::mutex> lk(r->mu);
    lua_pushboolean(L, r->done);
    lua_pushinteger(L, r->status);
    if (r->done) lua_pushlstring(L, r->body.data(), r->body.size()); else lua_pushnil(L);
    if (r->error.empty()) lua_pushnil(L); else lua_pushstring(L, r->error.c_str());
    if (r->done) { std::lock_guard<std::mutex> g(g_mu); g_reqs.erase(id); }
    return 4;
}

}  // namespace

void registerNet(lua_State* L)
{
    const luaL_Reg fns[] = { { "ws_open", wsOpen }, { "ws_send", wsSend }, { "ws_poll", wsPoll }, { "ws_close", wsClose },
        { "tcp_probe", tcpProbe }, { "http_start", httpStart }, { "http_poll", httpPoll }, { nullptr, nullptr } };
    luaL_setfuncs(L, fns, 0);
}

void netShutdown()
{
    std::map<int, std::shared_ptr<Sock>> socks;
    { std::lock_guard<std::mutex> lk(g_mu); socks.swap(g_socks); g_reqs.clear(); }
    for (auto& [id, s] : socks) stopSock(s);
}

}  // namespace ncm::host
