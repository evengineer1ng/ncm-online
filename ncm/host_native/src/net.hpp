#pragma once
// NCM Host plugin: loopback networking for the page adapters (plan "dev-server parity", phase 1).
//
// On the dev server every NCM plugin (Carrier, Rig Bridge, Vision, Broadcast, Pace) is reached through a hidden CEF page
// it serves itself; the page's few lines of JavaScript relay named events to the plugin's websocket. Single player has
// no CEF, so the NCM Host speaks those websockets itself (ncm/host/webui). Everything here is non-blocking for the
// game's script thread: each socket has a reader and a writer thread; Lua polls.
struct lua_State;

namespace ncm::host {

// Registers ws_open / ws_send / ws_poll / ws_close, tcp_probe, http_start / http_poll into the table on top of the stack.
void registerNet(lua_State* L);
// Closes every socket and request (the VM is stopping).
void netShutdown();

}  // namespace ncm::host
