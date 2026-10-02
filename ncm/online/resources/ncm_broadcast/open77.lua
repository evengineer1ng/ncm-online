-- NCM Online: Broadcast (L235). Race presentation drawn natively by the `ncm-broadcast` required mod.
--
--   * names over race cars that are not players (Paddock drivers), so a spectator can tell who is who;
--   * an opt-in timing tower (`/ncm.tower`) for the Paddock race around you, or the multiplayer session you are in,
--     with usernames.
--
-- A resource of its own (owner rule: new features, new mods) and so a WebUI budget of its own: two surfaces, the
-- hidden 16x16 loopback page to the plugin (the L129 pattern, for the tower) and, only while Paddock cars are near,
-- web/names.html -- the car names, placed by `Open77.anchors` (0.1.1, KB-223: the plugin's own plates piled up in one
-- spot). `kMaximumWebSurfaces` is eight PER RESOURCE (open77_media: "a resource may hold eight").
--
-- vehicles.read: `Open77.vehicles.get(id).entity`, what an anchor is attached to.
resource "ncm_broadcast"
version "0.1.2"
auto_start true

permissions { "network.events", "vehicles.read" }
dependency "open77_notifications"

web_files { "web/**" }

server_script "server/main.lua"
client_script "client/main.lua"
