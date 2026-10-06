-- NCM Online: the cross-server link, Night City's side (L323; doc 52 §2, doc 54 §S). Server only. DEV ONLY until
-- the owner rules otherwise: it calls the Snowglobe hub on the Los Santos FiveM server over LOOPBACK
-- (`ncm_link_hub` convar, default http://127.0.0.1:30120/ncm_ls_space), which needs the server's outbound HTTP enabled
-- with 127.0.0.1 allow-listed (server.jsonc `http`). Online has no Los Santos server: there it logs once and idles.
--
-- What it carries: `/ncm.link` (a link code for this driver, claimed in Los Santos with `/ncm.link CODE`); Night
-- City's Race Week facts (`ncm:week:fact`, hidden, both ways); and every finished human race (`ncm:paddock.human.result`)
-- as a candidate leg of the Three Cities event. It edits no other resource: it only listens to their server events.
--
-- network.events: the server-local events above. database.access: the NCM driver binding. http.request: the hub.
resource "ncm_link"
version "0.1.0"
auto_start true

permissions { "network.events", "database.access", "http.request" }

server_script "server/link.lua"
