-- NCM Online: the quick menu (radial). Client only.
--
-- A resource of its own for one reason: its transport to the native wheel is a hidden loopback WebUI surface,
-- and `ncm_world` is at 8 of 8 (`IDEA-570`). The wheel is DRAWN natively by the `ncm-radial` required mod
-- (`ncm/radial/`); this resource reads the pad and keyboard, decides what is highlighted, and asks `ncm_world`
-- to run the chosen action through its `quickAction` export. Without the required mod nothing is drawn and
-- `/ncm.radial` says so; every action keeps its hotkey and chat command regardless.
--
-- input.actions: `Open77.input.isDown` / `axis` / `keyFor` physical reads, and blocking on-foot movement and
--   firing while the wheel is up so a direction key does not also walk the driver off.
resource "ncm_radial"
version "0.1.0"
auto_start true

permissions { "input.actions" }

client_script "client/radial.lua"
