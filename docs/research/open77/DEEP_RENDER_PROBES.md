# NCM Deep renderer: geographic LOD + spatial upscaling, probes (L332)

> **STATUS: RESEARCH (built on dev, headless-verified; live probes pending)** - 2026-10-06. Owner brief: "more actual
> geography underneath, fewer pixels spent rendering it, smarter reconstruction on top, and never upscale the HUD."
> Decision: [DECISION_RECORD L332](../../ncm-online/DECISION_RECORD.md). Ideas IDEA-1164 to IDEA-1167.

## What was built

- **The plan:** `ncm/core/space/geolod.lua` decides the geography. It is a clipmap: one 4x4-tile window per zoom 5..16,
  centred on the camera's ground point. It also produces the prefetch list along the predicted path and at the
  Guidance destination.
- **The bridge:** `tools/ncm-host-bridge.py` serves `/tiles/<layer>/<z>/<x>/<y>.jpg` and `/tiles/prefetch` from a disk
  cache at `%LOCALAPPDATA%\NCM\tiles`, capped at 4 GB.
- **Cyberpunk Deep:** `ncm_world/web/deep.html`:
  - The planet is ray-traced instead of the faceted mesh.
  - The world is drawn at an internal resolution and reconstructed with EASU + RCAS (a GLSL ES port of AMD
    FidelityFX FSR 1, MIT).
  - Stars and the HUD are drawn natively.
- **AC Deep:** `ncm/assetto/apps/lua/NCM/ncm_world.lua` does the same with CSP canvases and HLSL.

## Sources (public domain only, owner ruling)

| layer | source | zoom | measured |
|---|---|---|---|
| `bmng` | NASA Blue Marble NG via GIBS WMS (EPSG:4326) | 0-8 | ~0.5 s per tile |
| `weld` | NASA/USGS Landsat WELD true colour, annual, via GIBS | 9-12 | ~0.5 s. Only `TIME=2000-12-01` has data (2005 and 2010 are blank). Covers the US and Monza. |
| `naip` | USGS The National Map *USGSImageryOnly* MapServer `export` (NAIP-based) | 11-16 | ~0.45 s. The NAIP Plus ImageServer answered in **~17 s** per tile, so it was rejected. |

Blank answers are treated as no data (the coarser level shows):
- GIBS returns a ~668-byte flat JPEG where it has no data.
- USGS returns a white ~2.4 KB tile over the sea.

The bridge therefore treats < 3 KB, or a uniform image (Pillow, when present), as no data.

## Verified (headless, 2026-10-06 23:00-23:25)

The real `deep.html` ran in Chrome on SwiftShader with a fake Open77 bridge and the real `space.geolod` plan; tiles
came through the bridge's own code. The harness is in the session scratchpad and is not shipped.

- **WebGL1:** the FBO is complete; MAX_TEXTURE_SIZE is 8192; there are 32 texture units and 4096 fragment uniform
  vectors; highp is 23 bits. The 4096x3072 atlas is OK.
- **3 km over Laguna Seca:**
  - Ground at 2.4 m per texel (z15, USGS imagery): roads and the Monterey coast are visible.
  - The HUD is sharp while the world runs at 50% (the controller stepped down on the slow software renderer).
  - The imagery credit is on screen.
- **30 km:** Monterey Bay, Monterey and Salinas are recognisable (z11, 38 m per texel).
- **A seam bug was found and fixed:** a placeholder drawn before its parent tile arrived was never redrawn, leaving a
  hard straight edge in the ocean.
- **No bridge:** only the global image is used, and the readout says "(no tile bridge: global image)".
- **A latent bug was caught before it shipped:** the star loop relied on a `var i` from the removed sphere mesh. In
  strict mode that threw and stopped the page.
- **AC:**
  - All three HLSL shaders (world, EASU, final RCAS + stars) compile with the Windows SDK `fxc` (ps_5_0) inside a
    CSP-style wrapper.
  - The CSP stand-in ran the full AC path through the world layer: 4 canvases, a world and an EASU pass every frame,
    and 192 tiles fetched and drawn.

## Not yet known (the live probes answer these; each reports itself)

- **Cyberpunk WebUI:** can the page load `http://127.0.0.1:47710` images with CORS, and POST the prefetch list? The
  server log shows `RENDER PROBE ... "what":"tiles","ok":true|false`.
- **The game GPU's real numbers:** the server log shows `RENDER PROBE ... "what":"render"`.
- **CSP:**
  - Does `ui.ExtraCanvas:updateWithShader` work at a reduced size and sample inside `render.fullscreenPass`?
  - Does `ui.isImageReady` work on the bridge's local tile files?
  - The bridge log shows `AC probe {"what":"render","ok":...}`. Any refusal turns the layer off and the old pass draws.
- **The frame-time controller in the game:** a WebUI page's rAF interval may be the game's own frame time.

## Next action

The owner flies the California descent (MASTER_TEST §RD1-§RD6) after the bridge restarts. It was not restarted at
23:29 because AC was running and the bridge holds that session's checkpoint relay. Then read both probes.
