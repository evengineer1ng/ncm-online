-- NCM dev probe (L301): Racing Week experiments E1-E5 and E7-E8. Console only. No product behaviour.
-- Lives in prototypes/ and reaches the DEV server through a junction (tools/o77-server.ps1); it is outside the
-- `ncm/*` load glob, so it can never ship to NCM Online.
resource "ncm_dev_probe"
version "0.1.0"
auto_start true
reload_policy "reconnect"

permissions { "network.events", "world.npcs", "world.props", "world.effects", "world.population", "world.query", "world.vehicles" }

server_script "server/probe_data.lua"
server_script "server/main.lua"
