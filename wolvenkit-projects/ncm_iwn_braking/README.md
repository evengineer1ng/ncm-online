# NCM braking-zone racing line (In-World Navigation add-on)

Base mod: In-World Navigation 0.1.20 (Nexus 4583, jackhumbert, MIT) — installed via `tools/deploy-checkpoint-07.ps1`.

Files installed on top of it (2026-09-19):
- `red4ext/plugins/in_world_navigation/packed.reds` — patched by `apply_braking_patch.py` (original kept next to it
  as `packed.reds.orig`; a copy of both is in `source/` and `payload/`).
- `archive/pc/mod/ncm_iwn_braking.archive` — four red arrow variants (`user\ncm\effects\world_navigation_red_1..4`),
  clones of the mod's yellow particle/effect with the material colour changed (255,150,20 / 255,90,10 / 255,30,10 /
  200,0,10). Sources in `source/archive-tree/` (CR2W) — rebuild with WolvenKit CLI `pack`.

Behaviour (all in Mod Settings > In-World Navigation):
- **Render distance (m)** (default 150): only this much route ahead of the player is spawned as arrows; the rest is
  never created, whatever "Max number of arrows" says — nothing extends into de-streamed parts of the city.
- **Braking zones (red arrows)** toggle, **Braking zone lookahead (m)** (40) and **Braking zone sensitivity (deg)**
  (75): every arrow sums the heading change of the route within the lookahead ahead of it; that total is mapped to a
  tier (orange -> red -> deep red) so the colour builds into a corner and eases out after the apex. Straights keep
  the mod's own colour.
- Arrow instances are only respawned when their colour tier changes; otherwise they are transform-updated as before.

After a mod update: re-run `python apply_braking_patch.py "<game>\red4ext\plugins\in_world_navigation\packed.reds"`
(idempotent), keep the archive. Verified to compile offline with `engine/tools/scc.exe` against the full script set.
