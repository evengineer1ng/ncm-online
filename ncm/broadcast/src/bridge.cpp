#include "bridge.hpp"

#include "log.hpp"
#include "state.hpp"

#include <nlohmann/json.hpp>

#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <tlhelp32.h>

#include <array>
#include <cctype>
#include <string>
#include <utility>
#include <vector>

namespace ncm::broadcast {
namespace {
constexpr const char* kWebSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

// The page the resource's hidden surface loads. It relays in both directions and holds no state of its own.
const char* kPage = R"HTML(<!doctype html><html><head><meta charset="utf-8"><title>NCM Broadcast</title></head>
<body style="margin:0;background:transparent"><script>(function(){
var ws=null,ready=false;
function emit(e,d){try{if(window.Open77&&Open77.emit)Open77.emit(e,d||{});}catch(x){}}
function connect(){
  try{ws=new WebSocket("ws://"+location.host+"/broadcast");}catch(x){emit("ncm:bcast.closed",{detail:String(x)});return;}
  ws.onopen=function(){ready=true;emit("ncm:bcast.ready",{detail:location.origin});};
  ws.onmessage=function(e){try{emit("ncm:bcast.msg",JSON.parse(e.data));}catch(x){}};
  ws.onclose=function(){ready=false;emit("ncm:bcast.closed",{detail:"socket closed"});setTimeout(connect,2000);};
  ws.onerror=function(){ready=false;};
}
if(window.Open77&&Open77.on){Open77.on("ncm:bcast.send",function(p){if(ready&&ws){try{ws.send(JSON.stringify(p||{}));}catch(x){}}});}
connect();})();
</script></body></html>)HTML";

// ---- peer check: the socket must belong to this game (or a child of it, e.g. its CEF helper) --------------

bool inProcessTree(uint32_t peer, uint32_t self)
{
    if (peer == 0 || peer == self) return true;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return true;
    std::vector<std::pair<uint32_t, uint32_t>> parents;
    PROCESSENTRY32W item{};
    item.dwSize = sizeof(item);
    if (Process32FirstW(snapshot, &item)) {
        do { parents.emplace_back(item.th32ProcessID, item.th32ParentProcessID); } while (Process32NextW(snapshot, &item));
    }
    CloseHandle(snapshot);
    uint32_t current = peer;
    for (int depth = 0; depth < 8; ++depth) {
        uint32_t parent = 0;
        for (const auto& [pid, ppid] : parents) {
            if (pid == current) { parent = ppid; break; }
        }
        if (parent == 0) return false;
        if (parent == self) return true;
        current = parent;
    }
    return false;
}

uint32_t peerPid(SOCKET client)
{
    sockaddr_in peer{}, local{};
    int peerSize = sizeof(peer), localSize = sizeof(local);
    if (getpeername(client, reinterpret_cast<sockaddr*>(&peer), &peerSize) == SOCKET_ERROR ||
        getsockname(client, reinterpret_cast<sockaddr*>(&local), &localSize) == SOCKET_ERROR) return 0;
    DWORD size = 0;
    if (GetExtendedTcpTable(nullptr, &size, FALSE, AF_INET, TCP_TABLE_OWNER_PID_CONNECTIONS, 0) != ERROR_INSUFFICIENT_BUFFER) return 0;
    std::vector<uint8_t> bytes(size);
    if (GetExtendedTcpTable(bytes.data(), &size, FALSE, AF_INET, TCP_TABLE_OWNER_PID_CONNECTIONS, 0) != NO_ERROR) return 0;
    const auto* table = reinterpret_cast<const MIB_TCPTABLE_OWNER_PID*>(bytes.data());
    for (DWORD i = 0; i < table->dwNumEntries; ++i) {
        const auto& row = table->table[i];
        if (row.dwLocalPort == static_cast<DWORD>(peer.sin_port) &&
            row.dwRemotePort == static_cast<DWORD>(local.sin_port) && row.dwState == MIB_TCP_STATE_ESTAB)
            return row.dwOwningPid;
    }
    return 0;
}

// ---- WebSocket handshake ------------------------------------------------------------------------------------

std::array<uint8_t, 20> sha1(const std::string& input)
{
    uint32_t h[5] = {0x67452301u, 0xEFCDAB89u, 0x98BADCFEu, 0x10325476u, 0xC3D2E1F0u};
    auto rol = [](uint32_t v, int n) { return (v << n) | (v >> (32 - n)); };
    std::string msg = input;
    const uint64_t bits = static_cast<uint64_t>(msg.size()) * 8;
    msg.push_back(static_cast<char>(0x80));
    while (msg.size() % 64 != 56) msg.push_back('\0');
    for (int i = 7; i >= 0; --i) msg.push_back(static_cast<char>((bits >> (i * 8)) & 0xff));
    for (size_t chunk = 0; chunk < msg.size(); chunk += 64) {
        uint32_t w[80]{};
        for (int i = 0; i < 16; ++i) {
            w[i] = (uint32_t(uint8_t(msg[chunk + i * 4])) << 24) | (uint32_t(uint8_t(msg[chunk + i * 4 + 1])) << 16) |
                   (uint32_t(uint8_t(msg[chunk + i * 4 + 2])) << 8) | uint32_t(uint8_t(msg[chunk + i * 4 + 3]));
        }
        for (int i = 16; i < 80; ++i) w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
        for (int i = 0; i < 80; ++i) {
            uint32_t f, k;
            if (i < 20)      { f = (b & c) | (~b & d);          k = 0x5A827999u; }
            else if (i < 40) { f = b ^ c ^ d;                   k = 0x6ED9EBA1u; }
            else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDCu; }
            else             { f = b ^ c ^ d;                   k = 0xCA62C1D6u; }
            const uint32_t t = rol(a, 5) + f + e + k + w[i];
            e = d; d = c; c = rol(b, 30); b = a; a = t;
        }
        h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e;
    }
    std::array<uint8_t, 20> out{};
    for (int i = 0; i < 5; ++i)
        for (int j = 0; j < 4; ++j) out[i * 4 + j] = static_cast<uint8_t>((h[i] >> (24 - j * 8)) & 0xff);
    return out;
}

std::string base64(const uint8_t* data, size_t length)
{
    static const char* table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    for (size_t i = 0; i < length; i += 3) {
        const uint32_t n = (uint32_t(data[i]) << 16) | (uint32_t(i + 1 < length ? data[i + 1] : 0) << 8) |
                           uint32_t(i + 2 < length ? data[i + 2] : 0);
        out.push_back(table[(n >> 18) & 63]);
        out.push_back(table[(n >> 12) & 63]);
        out.push_back(i + 1 < length ? table[(n >> 6) & 63] : '=');
        out.push_back(i + 2 < length ? table[n & 63] : '=');
    }
    return out;
}

std::string header(const std::string& request, const std::string& wanted)
{
    std::string low;
    for (const char c : request) low.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    const auto at = low.find(wanted);
    if (at == std::string::npos) return {};
    const auto colon = low.find(':', at);
    if (colon == std::string::npos) return {};
    const auto end = low.find("\r\n", colon);
    std::string value = request.substr(colon + 1, end - colon - 1);
    while (!value.empty() && (value.front() == ' ' || value.front() == '\t')) value.erase(value.begin());
    while (!value.empty() && (value.back() == ' ' || value.back() == '\r')) value.pop_back();
    return value;
}

// ---- framing ------------------------------------------------------------------------------------------------

bool sendAll(SOCKET s, const char* p, size_t n)
{
    size_t done = 0;
    while (done < n) {
        const int sent = send(s, p + done, static_cast<int>(n - done), 0);
        if (sent <= 0) return false;
        done += static_cast<size_t>(sent);
    }
    return true;
}

bool sendText(SOCKET s, const std::string& payload)
{
    std::string h;
    h.push_back(static_cast<char>(0x81));
    if (payload.size() < 126) {
        h.push_back(static_cast<char>(payload.size()));
    } else {
        h.push_back(126);
        h.push_back(static_cast<char>((payload.size() >> 8) & 0xff));
        h.push_back(static_cast<char>(payload.size() & 0xff));
    }
    return sendAll(s, h.data(), h.size()) && sendAll(s, payload.data(), payload.size());
}

bool recvExact(SOCKET s, char* p, size_t n)
{
    size_t got = 0;
    while (got < n) {
        const int r = recv(s, p + got, static_cast<int>(n - got), 0);
        if (r <= 0) return false;
        got += static_cast<size_t>(r);
    }
    return true;
}

bool readFrame(SOCKET s, int& opcode, std::string& payload)
{
    char h[2];
    if (!recvExact(s, h, 2)) return false;
    opcode = h[0] & 15;
    const bool masked = (h[1] & 0x80) != 0;
    uint64_t n = h[1] & 0x7f;
    if (n == 126) {
        char e[2];
        if (!recvExact(s, e, 2)) return false;
        n = (uint64_t(uint8_t(e[0])) << 8) | uint8_t(e[1]);
    } else if (n == 127) {
        return false;                       // nothing this page sends is that large
    }
    if (n > 60 * 1024) return false;
    char mask[4]{};
    if (masked && !recvExact(s, mask, 4)) return false;
    payload.assign(static_cast<size_t>(n), '\0');
    if (n && !recvExact(s, payload.data(), static_cast<size_t>(n))) return false;
    if (masked) for (size_t i = 0; i < payload.size(); ++i) payload[i] ^= mask[i % 4];
    return true;
}
}

Bridge::~Bridge() { stop(); }

void Bridge::start()
{
    if (running_.exchange(true)) return;
    thread_ = std::thread([this] { run(); });
}

void Bridge::stop()
{
    if (!running_.exchange(false)) return;
    if (auto s = client_.exchange(0)) closesocket(static_cast<SOCKET>(s));
    if (auto s = listener_.exchange(0)) closesocket(static_cast<SOCKET>(s));
    if (thread_.joinable()) thread_.join();
    state().disconnect();
}

void Bridge::run()
{
    WSADATA data{};
    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) { BCAST_ERR("Winsock unavailable"); return; }

    // Two game instances on one PC share this DLL's folder, so the second walks up the range.
    SOCKET listener = INVALID_SOCKET;
    for (uint16_t candidate = kPortBase; candidate < kPortBase + kPortSpan; ++candidate) {
        SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if (s == INVALID_SOCKET) continue;
        BOOL exclusive = TRUE;
        setsockopt(s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, reinterpret_cast<const char*>(&exclusive), sizeof(exclusive));
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_port = htons(candidate);
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
        if (bind(s, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != SOCKET_ERROR && listen(s, 2) != SOCKET_ERROR) {
            listener = s;
            port_ = candidate;
            break;
        }
        closesocket(s);
    }
    if (listener == INVALID_SOCKET) {
        BCAST_ERR("no free port in %u-%u", kPortBase, kPortBase + kPortSpan - 1);
        WSACleanup();
        return;
    }
    listener_ = static_cast<uintptr_t>(listener);
    BCAST_INFO("listening on http://127.0.0.1:%u/broadcast.html", port_.load());

    while (running_.load()) {
        SOCKET client = accept(listener, nullptr, nullptr);
        if (client == INVALID_SOCKET) break;
        const uint32_t peer = peerPid(client);
        if (!inProcessTree(peer, GetCurrentProcessId())) {
            BCAST_WARN("refused peer pid=%u outside this game's process tree", peer);
            closesocket(client);
            continue;
        }
        client_ = static_cast<uintptr_t>(client);
        serve(client_);
        closesocket(client);
        client_ = 0;
    }
    closesocket(listener);
    listener_ = 0;
    WSACleanup();
}

void Bridge::serve(uintptr_t value)
{
    const SOCKET s = static_cast<SOCKET>(value);
    std::string request(4096, '\0');
    const int got = recv(s, request.data(), 4095, 0);
    if (got <= 0) return;
    request.resize(static_cast<size_t>(got));

    const std::string key = header(request, "sec-websocket-key");
    if (key.empty()) {
        const std::string body = kPage;
        const std::string response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\n"
            "Content-Length: " + std::to_string(body.size()) + "\r\nConnection: close\r\n\r\n" + body;
        sendAll(s, response.data(), response.size());
        return;
    }

    const auto digest = sha1(key + kWebSocketGuid);
    const std::string response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        "Sec-WebSocket-Accept: " + base64(digest.data(), digest.size()) + "\r\n\r\n";
    if (!sendAll(s, response.data(), response.size())) return;

    BCAST_INFO("resource connected");
    sendText(s, state().health());
    int opcode = 0;
    std::string payload;
    int refused = 0;
    // Unlike the Scanner, the plugin speaks first: gate reports cannot wait for the resource's next message. The
    // loop waits up to 50 ms for a frame, then pushes whatever the game thread queued. One writer (this thread).
    while (running_.load()) {
        fd_set readable;
        FD_ZERO(&readable);
        FD_SET(s, &readable);
        timeval wait{0, 50 * 1000};
        const int ready = select(0, &readable, nullptr, nullptr, &wait);
        if (ready == SOCKET_ERROR) break;
        if (ready > 0) {
            if (!readFrame(s, opcode, payload)) break;
            if (opcode == 8) break;
            if (opcode == 1) {
                const auto parsed = nlohmann::json::parse(payload, nullptr, false);
                const auto cmd = parsed.is_object() ? parsed.value("cmd", std::string()) : std::string();
                if (cmd == "hello" || cmd == "health") {
                    if (!sendText(s, state().health())) break;
                } else if (!state().apply(payload)) {
                    if (++refused <= 5) BCAST_WARN("message not understood (%zu bytes)", payload.size());
                }
            }
        }
        bool ok = true;
        for (const auto& message : state().outbox()) {
            if (!sendText(s, message)) { ok = false; break; }
        }
        if (!ok) break;
    }
    // Whoever planned the race is gone: stop every car rather than let a plan nobody watches keep driving.
    state().disconnect();
    BCAST_INFO("resource disconnected");
}
}
