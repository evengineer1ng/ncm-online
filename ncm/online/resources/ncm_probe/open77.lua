-- NCM Online: E0 part B probe resource (throwaway; not part of the product). No permissions on purpose:
-- one probe measures what an ungated resource gets when it calls a gated native.
resource "ncm_probe"
version "0.0.1"
auto_start false   -- probes run on demand: `start ncm_probe` in the server console

server_script "server/main.lua"
