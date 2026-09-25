#include "bridge/server.hpp"

#include "log.hpp"

#include <nlohmann/json.hpp>

#include <winsock2.h>
#include <ws2tcpip.h>

#include <array>
#include <cstring>

using json = nlohmann::json;

namespace ncm::bridge {

// The page. Behaviourally identical to the companion's `BRIDGE_HTML` -- it owns no policy and makes no
// decisions -- with two channels added: projections down from NCM, health up from the carrier.
const char* kBridgeHtml = R"HTML(<!doctype html>
<html><head><meta charset="utf-8"><title>NCM carrier bridge</title></head>
<body style="margin:0;background:transparent">
<script>
(function () {
  var ws = null, ready = false;
  var tell = function (event, detail) {
    try { if (window.Open77 && Open77.emit) Open77.emit(event, { detail: String(detail) }); } catch (e) {}
  };
  var connect = function () {
    try {
      ws = new WebSocket("ws://" + location.host + "/telemetry");
    } catch (e) { tell("ncm:ffb.closed", "construct failed: " + e); return; }
    ws.onopen = function () { ready = true; tell("ncm:ffb.ready", location.origin); };
    ws.onmessage = function (ev) {
      try {
        var msg = JSON.parse(ev.data);
        if (!msg || !window.Open77 || !Open77.emit) return;
        if (msg.device) Open77.emit("ncm:ffb.device", msg.device);
        if (msg.health) Open77.emit("ncm:carrier.health", msg.health);
      } catch (e) {}
    };
    ws.onclose = function () { ready = false; tell("ncm:ffb.closed", "socket closed"); setTimeout(connect, 2000); };
    ws.onerror = function () { ready = false; };
  };
  var relay = function (payload) {
    if (!ready || !ws) return;
    try { ws.send(JSON.stringify(payload)); } catch (e) {}
  };
  if (window.Open77 && Open77.on) {
    Open77.on("ncm:ffb.frame", relay);
    Open77.on("ncm:ffb.idle", function (p) { relay({ v: (p && p.v) || 1, idle: true }); });
    Open77.on("ncm:ffb.settings", function (p) { relay({ cmd: "settings", settings: p || {} }); });
    Open77.on("ncm:ffb.test", function (p) { relay({ cmd: "test", test: p || {} }); });
    // The carrier channel. One transport for telemetry and effects, so the two sides cannot disagree about
    // which is authoritative, and so an effect cannot arrive while the socket that reports feel is down.
    Open77.on("ncm:machine.projection", function (p) { relay({ cmd: "projection", projection: p || {} }); });
  }
  connect();
})();
</script>
</body></html>
)HTML";

namespace {

constexpr const char* kGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

// ---------------------------------------------------------------------------------------------------- sha1
// RFC 3174. Needed only for the WebSocket handshake accept key.
struct Sha1 {
    uint32_t h[5] = { 0x67452301u, 0xEFCDAB89u, 0x98BADCFEu, 0x10325476u, 0xC3D2E1F0u };

    static uint32_t rol(uint32_t v, int n) { return (v << n) | (v >> (32 - n)); }

    std::array<uint8_t, 20> operator()(const std::string& input)
    {
        std::string msg = input;
        const uint64_t bitLength = static_cast<uint64_t>(msg.size()) * 8;
        msg.push_back(static_cast<char>(0x80));
        while (msg.size() % 64 != 56) msg.push_back('\0');
        for (int i = 7; i >= 0; --i) msg.push_back(static_cast<char>((bitLength >> (i * 8)) & 0xFF));

        for (size_t chunk = 0; chunk < msg.size(); chunk += 64) {
            uint32_t w[80] = {};
            for (int i = 0; i < 16; ++i) {
                w[i] = (static_cast<uint8_t>(msg[chunk + i * 4]) << 24) |
                       (static_cast<uint8_t>(msg[chunk + i * 4 + 1]) << 16) |
                       (static_cast<uint8_t>(msg[chunk + i * 4 + 2]) << 8) |
                       (static_cast<uint8_t>(msg[chunk + i * 4 + 3]));
            }
            for (int i = 16; i < 80; ++i) w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);

            uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
            for (int i = 0; i < 80; ++i) {
                uint32_t f, k;
                if (i < 20)      { f = (b & c) | (~b & d);            k = 0x5A827999u; }
                else if (i < 40) { f = b ^ c ^ d;                     k = 0x6ED9EBA1u; }
                else if (i < 60) { f = (b & c) | (b & d) | (c & d);   k = 0x8F1BBCDCu; }
                else             { f = b ^ c ^ d;                     k = 0xCA62C1D6u; }
                const uint32_t temp = rol(a, 5) + f + e + k + w[i];
                e = d; d = c; c = rol(b, 30); b = a; a = temp;
            }
            h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e;
        }

        std::array<uint8_t, 20> out{};
        for (int i = 0; i < 5; ++i)
            for (int j = 0; j < 4; ++j) out[i * 4 + j] = static_cast<uint8_t>((h[i] >> (24 - j * 8)) & 0xFF);
        return out;
    }
};

std::string base64(const uint8_t* data, size_t length)
{
    static const char* table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    for (size_t i = 0; i < length; i += 3) {
        const uint32_t n = (data[i] << 16) | ((i + 1 < length ? data[i + 1] : 0) << 8) |
                           (i + 2 < length ? data[i + 2] : 0);
        out.push_back(table[(n >> 18) & 63]);
        out.push_back(table[(n >> 12) & 63]);
        out.push_back(i + 1 < length ? table[(n >> 6) & 63] : '=');
        out.push_back(i + 2 < length ? table[n & 63] : '=');
    }
    return out;
}

std::string acceptKey(const std::string& key)
{
    Sha1 sha;
    const auto digest = sha(key + kGuid);
    return base64(digest.data(), digest.size());
}

std::string headerValue(const std::string& request, const std::string& name)
{
    // Case-insensitive header lookup; browsers do not agree on capitalisation.
    std::string lowered;
    lowered.reserve(request.size());
    for (char c : request) lowered.push_back(static_cast<char>(::tolower(static_cast<unsigned char>(c))));
    const auto at = lowered.find(name);
    if (at == std::string::npos) return {};
    const auto colon = lowered.find(':', at);
    if (colon == std::string::npos) return {};
    auto end = lowered.find("\r\n", colon);
    if (end == std::string::npos) end = lowered.size();
    std::string value = request.substr(colon + 1, end - colon - 1);
    while (!value.empty() && (value.front() == ' ' || value.front() == '\t')) value.erase(value.begin());
    while (!value.empty() && (value.back() == ' ' || value.back() == '\r')) value.pop_back();
    return value;
}

bool sendAll(SOCKET s, const char* data, size_t length)
{
    size_t sent = 0;
    while (sent < length) {
        const int n = ::send(s, data + sent, static_cast<int>(length - sent), 0);
        if (n <= 0) return false;
        sent += static_cast<size_t>(n);
    }
    return true;
}

/// One text frame, server->client, unmasked as the RFC requires for a server.
bool sendText(SOCKET s, const std::string& payload)
{
    std::string header;
    header.push_back(static_cast<char>(0x81));  // FIN + text
    if (payload.size() < 126) {
        header.push_back(static_cast<char>(payload.size()));
    } else if (payload.size() <= 0xFFFF) {
        header.push_back(126);
        header.push_back(static_cast<char>((payload.size() >> 8) & 0xFF));
        header.push_back(static_cast<char>(payload.size() & 0xFF));
    } else {
        header.push_back(127);
        for (int i = 7; i >= 0; --i)
            header.push_back(static_cast<char>((static_cast<uint64_t>(payload.size()) >> (i * 8)) & 0xFF));
    }
    return sendAll(s, header.data(), header.size()) && sendAll(s, payload.data(), payload.size());
}

bool recvExactly(SOCKET s, char* into, size_t length)
{
    size_t got = 0;
    while (got < length) {
        const int n = ::recv(s, into + got, static_cast<int>(length - got), 0);
        if (n <= 0) return false;
        got += static_cast<size_t>(n);
    }
    return true;
}

/// Returns false when the socket is done. `opcode` 8 is close.
bool readFrame(SOCKET s, int& opcode, std::string& payload)
{
    char head[2];
    if (!recvExactly(s, head, 2)) return false;
    opcode = head[0] & 0x0F;
    const bool masked = (head[1] & 0x80) != 0;
    uint64_t length = static_cast<uint64_t>(head[1] & 0x7F);

    if (length == 126) {
        char ext[2];
        if (!recvExactly(s, ext, 2)) return false;
        length = (static_cast<uint8_t>(ext[0]) << 8) | static_cast<uint8_t>(ext[1]);
    } else if (length == 127) {
        char ext[8];
        if (!recvExactly(s, ext, 8)) return false;
        length = 0;
        for (int i = 0; i < 8; ++i) length = (length << 8) | static_cast<uint8_t>(ext[i]);
    }
    // A frame larger than any projection or telemetry frame could be is a bug or an attack; drop the socket.
    if (length > (1u << 20)) return false;

    char mask[4] = {};
    if (masked && !recvExactly(s, mask, 4)) return false;

    payload.assign(static_cast<size_t>(length), '\0');
    if (length > 0 && !recvExactly(s, payload.data(), static_cast<size_t>(length))) return false;
    if (masked) {
        for (size_t i = 0; i < payload.size(); ++i) payload[i] ^= mask[i % 4];
    }
    return true;
}

double num(const json& obj, const char* key, bool& has)
{
    auto it = obj.find(key);
    if (it == obj.end() || !it->is_number()) { has = false; return 0.0; }
    has = true;
    return it->get<double>();
}

}  // namespace

// ---------------------------------------------------------------------------------------------------------

Server::Server(uint16_t port) : port_(port) {}

Server::~Server() { stop(); }

void Server::start()
{
    if (running_.exchange(true)) return;
    thread_ = std::thread([this] { run(); });
}

void Server::stop()
{
    if (!running_.exchange(false)) return;
    // Closing the sockets is what wakes the blocking accept/recv.
    if (auto s = client_.exchange(0)) ::closesocket(static_cast<SOCKET>(s));
    if (auto s = socket_.exchange(0)) ::closesocket(static_cast<SOCKET>(s));
    if (thread_.joinable()) thread_.join();
    listening_ = false;
    connected_ = false;
}

void Server::run()
{
    WSADATA wsa{};
    if (::WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        NCM_ERR("winsock unavailable -- the bridge cannot listen");
        return;
    }

    SOCKET listener = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listener == INVALID_SOCKET) {
        NCM_ERR("could not create the listening socket");
        ::WSACleanup();
        return;
    }

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = ::htons(port_);
    // **Loopback only.** Not a hardening afterthought: this socket carries a player's vehicle telemetry and
    // accepts instructions that change their handling. It has no business being reachable from a network.
    ::inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (::bind(listener, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == SOCKET_ERROR ||
        ::listen(listener, 1) == SOCKET_ERROR) {
        // The overwhelmingly likely cause is the old Python companion still running on this port. Say so,
        // because "address in use" sends someone hunting for the wrong thing.
        NCM_ERR("port %u is unavailable -- is the old NCM Wheel Support companion still running?", port_);
        ::closesocket(listener);
        ::WSACleanup();
        return;
    }

    socket_ = static_cast<uintptr_t>(listener);
    listening_ = true;
    NCM_INFO("bridge listening on 127.0.0.1:%u", port_);

    while (running_.load()) {
        SOCKET client = ::accept(listener, nullptr, nullptr);
        if (client == INVALID_SOCKET) break;
        client_ = static_cast<uintptr_t>(client);

        std::string request(4096, '\0');
        const int got = ::recv(client, request.data(), static_cast<int>(request.size()) - 1, 0);
        if (got <= 0) {
            ::closesocket(client);
            client_ = 0;
            continue;
        }
        request.resize(static_cast<size_t>(got));

        const std::string key = headerValue(request, "sec-websocket-key");
        if (key.empty()) {
            serveHttp(static_cast<uintptr_t>(client), request);
        } else {
            serveWebSocket(static_cast<uintptr_t>(client), key);
        }

        ::closesocket(client);
        client_ = 0;
    }

    listening_ = false;
    ::closesocket(listener);
    socket_ = 0;
    ::WSACleanup();
}

void Server::serveHttp(uintptr_t clientHandle, const std::string&)
{
    const SOCKET client = static_cast<SOCKET>(clientHandle);
    const std::string body = kBridgeHtml;
    const std::string response =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/html; charset=utf-8\r\n"
        "Content-Length: " + std::to_string(body.size()) + "\r\n"
        "Cache-Control: no-store\r\n"
        "Connection: close\r\n\r\n" + body;
    sendAll(client, response.data(), response.size());
}

void Server::serveWebSocket(uintptr_t clientHandle, const std::string& key)
{
    const SOCKET client = static_cast<SOCKET>(clientHandle);
    const std::string response =
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Accept: " + acceptKey(key) + "\r\n\r\n";
    if (!sendAll(client, response.data(), response.size())) return;

    connected_ = true;
    NCM_INFO("NCM connected to the bridge");

    int opcode = 0;
    std::string payload;
    while (running_.load() && readFrame(client, opcode, payload)) {
        if (opcode == 0x8) break;          // close
        if (opcode == 0x9) continue;       // ping; the browser does not send these, but be correct anyway
        if (opcode != 0x1) continue;       // text only
        try {
            dispatch(payload);
        } catch (const std::exception& e) {
            NCM_WARN("unreadable message dropped: %s", e.what());
        }
    }

    connected_ = false;
    NCM_INFO("NCM disconnected from the bridge");
    // The world is gone. Whoever is listening gets to put things back; see `main.cpp`.
    if (onDisconnect_) onDisconnect_();
}

void Server::dispatch(const std::string& payload)
{
    const json msg = json::parse(payload);
    if (!msg.is_object()) return;

    const auto cmd = msg.value("cmd", std::string());

    if (cmd == "projection") {
        if (!onProjection_) return;
        const auto& p = msg["projection"];
        if (!p.is_object()) return;

        Projection out;
        out.version = p.value("v", 1);
        const auto& record = p.contains("record") ? p["record"] : json::object();
        out.record = record.value("path", std::string());
        out.restore = record.value("restore", false);
        if (out.record.empty()) return;

        if (record.contains("flats") && record["flats"].is_array()) {
            for (const auto& f : record["flats"]) {
                effects::FlatChange change;
                change.id = f.value("id", std::string());
                change.suffix = f.value("suffix", std::string());
                change.multiplier = f.value("multiplier", 1.0);
                if (!change.suffix.empty()) out.flats.push_back(std::move(change));
            }
        }
        onProjection_(out);
        return;
    }

    if (cmd == "settings" || cmd == "test") {
        // Handled by the mixer through the same path the companion used; deliberately unchanged.
        return;
    }

    // No `cmd` means a telemetry frame, which is the hot path and therefore the cheapest branch to reach.
    if (!onFrame_) return;

    Frame frame;
    frame.idle = msg.value("idle", false);
    bool has = false;
    frame.at = num(msg, "t", has);
    frame.engine = num(msg, "engine", frame.hasEngine);
    frame.speed = num(msg, "speed", frame.hasSpeed);
    frame.steering = num(msg, "steering", frame.hasSteering);
    frame.slipLong = num(msg, "slipLong", frame.hasSlipLong);
    frame.slipLat = num(msg, "slipLat", frame.hasSlipLat);
    frame.slipTotal = num(msg, "slipTotal", frame.hasSlipTotal);
    frame.suspLong = num(msg, "suspLong", frame.hasSuspLong);
    frame.suspLat = num(msg, "suspLat", frame.hasSuspLat);
    onFrame_(frame);
}

void Server::sendDevice(const std::string& payload)
{
    const auto client = client_.load();
    if (!client || !connected_.load()) return;
    sendText(static_cast<SOCKET>(client), payload);
}

}  // namespace ncm::bridge
