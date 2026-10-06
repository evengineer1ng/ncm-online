-- ncm_deep -- L326 probe 0 (DEV ONLY, outside the ncm/* load glob; started only by its own server.jsonc entry).
--
-- The owner's direction (2026-10-06): no second program. The universe beyond Night City is simulated by NCM "just
-- slightly out of reach of REDengine", reached by hitting the vertical bounds and a loading screen into our space.
-- The candidate renderer is an OPEN//77 WebUI surface (CEF inside the game process) drawing with WebGL. This probe asks
-- the one question that decides it: does WebGL run in that surface, on which GPU, at what frame rate?
--
-- `/ncm.deep` opens a full-screen surface for 20 s (it never takes input focus), draws a lit Earth sphere, stars and
-- the Machine's sprite, and reports renderer + fps to the server log ([ncm_deep] lines).
resource "ncm_deep"
version "0.0.1"
auto_start true

permissions { "network.events" }

web_files { "web/**" }

server_script "server/deep.lua"
client_script "client/deep.lua"
