-- NCM Online: Broadcast (L235). Race presentation drawn natively by the `ncm-broadcast` required mod.
--
--   * names over race cars that are not players (Paddock drivers), so a spectator can tell who is who;
--   * an opt-in timing tower (`/ncm.tower`) for the Paddock race around you, or the multiplayer session you are in,
--     with usernames.
--
-- A resource of its own (owner rule: new features, new mods) and so a WebUI budget of its own: its only surface is
-- the hidden 16x16 loopback page to the plugin (the L129 pattern). `kMaximumWebSurfaces` is eight PER RESOURCE
-- (open77_media: "a resource may hold eight"); ncm_world holds up to seven of its own.
--
-- vehicles.read: `Open77.vehicles.get(id).engineEntity`, the hash redscript finds a car by.
resource "ncm_broadcast"
version "0.1.0"
auto_start true

permissions { "network.events", "vehicles.read" }
dependency "open77_notifications"

server_script "server/main.lua"
client_script "client/main.lua"
