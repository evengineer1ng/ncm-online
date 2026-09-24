-- Temporary KB-6 validation resource. No product or competitive behavior.
resource "ncm_weather_probe"
version "0.1.0"
auto_start true
reload_policy "reconnect"

permissions { "network.events", "world.environment", "players.teleport" }

server_script "server/main.lua"
client_script "client/main.lua"
