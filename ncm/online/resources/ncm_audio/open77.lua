-- NCM Online: NCM Audio (NCM FX, 2026-10-12). Client only.
--
-- The continuous sound of NCM's physics: engines whose pitch and gain follow throttle and exhaust speed, strokes and
-- hops, the roar of entry, the drives. The `ncm-audio` required mod (`ncm/audio/`, a miniaudio plugin and its
-- NCM-synthesised pack) plays it; this resource tells it what to play, through a hidden loopback surface to its DLL
-- (NCM Sky's pattern, its own port range 38800-38803). ncm_world's renderer (client/fx.lua) hands it voices with the
-- client export `voices`; a voice it stops naming fades out, and everything fades when this resource stops.
resource "ncm_audio"
version "0.1.0"
auto_start true

client_script "client/audio.lua"
