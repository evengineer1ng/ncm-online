-- NCM Online: NCM Sky (KB-430). Client only.
--
-- Open77 props take a position and a yaw only, so an Earth that turns under the Machine, or a sky that turns with the
-- clock, cannot be a prop. The `ncm-sky` required mod (`ncm/sky/`) draws those bodies with full orientation; this
-- resource tells it what to draw, through a hidden loopback surface to its DLL (the Scanner's pattern, its own port
-- range 38760-38763). Other resources hand it their bodies with the client export `scene`; it merges them and keeps
-- the feed alive (the DLL empties the sky 3 s after the feed stops, so nothing outlives a stopped resource).
--
-- Its own resource (feedback: new features, new mods). Its first owner is ncm_world's Deep: the NCWE space render
-- (L358) -- the star dome, the Earth and the Moon around the Machine, reached only by flying through the 12 km seam.
resource "ncm_sky"
version "0.2.0"
auto_start true

client_script "client/sky.lua"
