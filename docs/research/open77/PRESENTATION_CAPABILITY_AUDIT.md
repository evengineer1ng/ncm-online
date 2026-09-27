# NCM Online — presentation capability audit (visual, spatial, motion, audio)

Date: **2026-09-27**. Status: **reconnaissance complete for the categories asked; no production behaviour changed.**
Scope: *what NCM can paint with*, not *what NCM should say*. The companion player-visibility/comprehension audit owns
the second question; §20 is the handoff.

Answered for: **OPEN//77 server package `2.31.13+op77.102`** (the build staging runs), against a devkit index published
for **op77.78** — so every `since` here is a **lower bound**, exactly as `CAPABILITY_PALETTE.md` records.

## Method, and what "proven" is allowed to mean

Three independent sources, in descending order of authority:

1. **The shipped OPEN//77 resources** in `tools/open77/server/resources/`. This is implementation source, not
   marketing: 34 system resources plus the freeroam/race/pvp gamemodes. Where a doc and the code disagree, the code
   wins and the disagreement is recorded here.
2. **The hosted devkit MCP** (`https://mcp.open2077.net/mcp?build=…`), via `query_open77.ps1` — 1,644 API cards,
   94 guides, 445 events, 135 permissions. It returned **502 for the first part of this session** and then recovered.
   If it is down, the shipped resources still answer most questions.
3. **NCM's own resources** in `ncm/online/resources/`, and the existing research in this folder.

**I could not run the game.** So the proof ladder is deliberately stricter than "I read that it works":

| Grade | Means |
|---|---|
| **PROVEN** | NCM or an official OPEN//77 resource **already ships code that does this**, in-tree, and the surrounding comments describe it working. File named where it matters. |
| **AVAILABLE** | The stack plainly exposes it — an official API card, a declared permission, a shipped service export — but no in-tree caller exercises the specific thing NCM would want. |
| **PLAUSIBLE** | A viable path exists and rests on one unverified assumption, which is named. |
| **BLOCKED / UNSUITABLE** | Cyberpunk or CEF can do it elsewhere; OPEN//77, the surface budget, the delivery model or replication prevents or strongly discourages it here. |

The platform runs the same taxonomy on its own *assets*, and it is worth adopting verbatim because it is about asset
safety rather than API safety: **Open77-supported** → **Runtime-validated** → **Extracted candidate**
(`guide-data-reference`). A 17,586-row SFX CSV is the third kind. `ui_menu_onpress` is the first.

---

## 1. The ten findings that change plans

1. **NCM is not on the platform design system, and did not know it.** OPEN//77 ships `web/open77-ui.css` — a
   documented token layer with measured contrast ratios, a HUD type scale, motion tokens and a reduced-motion block —
   **byte-identical in 11 resources** (verified: every copy hashes `7481e7a15e043bb301d589212189de35`). NCM ships
   **no copy**. It re-derived a smaller, divergent subset inline. Highest-leverage fix in the audit.
2. **Two different typefaces are rendering inside NCM right now.** The platform states plainly that no font is
   bundled and there is no network, so `"Rajdhani"`, `"Saira"` and `"IBM Plex Mono"` **never resolve in-game**; what
   renders is the next name in the stack. `panel.html` falls to **Bahnschrift Condensed**. `nameplates.css` declares
   `"Rajdhani", "Arial Narrow", Arial` and therefore falls to **Arial Narrow**. Logged as `KB-157`.
3. **The hard ceiling is eight CEF surfaces per resource** (`kMaximumWebSurfaces`, stated in
   `open77_admin/open77.lua:69` and in `open77_media`). All NCM presentation lives in one resource, `ncm_world`, and
   NCM can already have **seven** alive at once. **NCM has one spare surface.** Every future surface must reuse a page
   or displace one. This is the central architectural constraint of the audit.
4. **Native per-frame world→screen projection into a WebUI page is proven, and NCM already ships it.**
   `Open77.nameplates.stream(page)` hands native projection to a page at frame rate while Lua publishes only
   slow-changing content (`ncm_world/client/nameplates.lua`). The same split exists as a **general** primitive in
   `Open77.anchors` (`create/update/frame/list/clear/remove`), which `open77_interactions` uses for its cards. The
   hybrid mechanism the brief hoped for is not speculative.
5. **NCM's own icon language can be drawn by the engine, inside the vanilla map.** `Open77.blips.create` accepts
   `icon = { asset = "icons/x.svg", size = 48 }`, **rendered as native Ink geometry**, while the mappin keeps vanilla
   selection, tracking and tooltips. NCM already owns 33 semantic SVG glyphs with a binding manifest. Zero client mods.
6. **NCM is completely silent.** No `Open77.sfx`, no `Open77.vfx`, no `Open77.effects`, no music call anywhere in
   `ncm/`. The platform's race gamemode meanwhile proves the exact vanilla race cues *by name*. Cheapest large win.
7. **NCM has no motion language at all.** Zero `@keyframes` in every NCM page; 10 `transition` declarations in total.
   The platform proves 38 distinct keyframe animations in-engine plus `backdrop-filter`, `mix-blend-mode`,
   `conic-gradient`, `mask-image` and `:has()`. CEF is modern; the gap is authored, not technical.
8. **World-space UX is real, shipped, and richer than expected.** Three separate mechanisms — native ground markers
   as actual REDengine worldEffects; **live web pages on world televisions** (a 38-record screen catalogue that
   includes `cinema.100ft` and `cinema.150ft`); and camera feeds on world surfaces. NCM already uses the first.
9. **A curated racing asset kit already exists.** VFX `race.firework.burst`, `race.flare.smoke`; props
   `race.checkpoint`, `race.route_arrow`, `street.traffic_light`, `light.spotlight`, the whole `barrier.*` family
   (`barrier.road.jersey`, `barrier.tire_blocker`, `barrier.concrete`), `market.kiosk`, `recreation.tent`. Grids,
   pit lanes, paddocks and closed-street courses are dressable from supported records.
10. **Client-mod delivery is not the wall it was believed to be.** `35_REQUIREDMODS_FORENSIC_AUDIT.md` established
    that `Unverifiable` meant *the launcher discarded a non-loopback plain-`http:` URL*, not "awaiting review".
    **HTTPS is the fix.** Every "additional client component" technique below is reachable engineering rather than
    fantasy, which materially changes §16 and the ceiling.

---

## 2. Current presentation inventory

### 2.1 What NCM presents today

| Surface | Entry | Layer / z / fps | What it carries |
|---|---|---|---|
| Career panel | `web/panel.html` (131 KB) | `menu` / **900** / 30 | The large multi-section interface; the only NCM page that takes focus |
| Race HUD | `web/race.html` (38 KB) | `hud` / **730** / 30 | Light tree (`#tree`, `.lamp`), banner, strip, board, progress graph with finish flag, driver inputs (throttle/brake pedals + %, steering + G, speed), tyre gauge with needle and state, odometer, ghost delta block |
| Driver cards | `web/nameplates.html` | `hud` / **650** / 60 | World-projected identity cards: banner art, name, voice dot, up to 3 badges, Fingerprint panel |
| Venue card | `web/venue.html` (12 KB) | `hud` / **720** / 20 | Venue/entry surface, created on demand |
| Carrier bridge | `http://127.0.0.1:<port>` | `hud` / 1 / — | **16×16, invisible.** Not presentation — a localhost data channel to the NCM Carrier |
| Carrier machine channel | second localhost port | `hud` / 1 / — | Second invisible 16×16 channel |
| Race bridge probe | remote entry | `hud` / 1 / — | Invisible diagnostic |

Worth naming explicitly because it is a genuinely clever, non-obvious use of the stack: **NCM uses invisible 16×16
WebUI pages as network transport**, reaching a local companion process Lua cannot reach directly. Three of the eight
surfaces are spent on things that draw nothing.

Shared NCM assets: `glyphs.js` (33 semantic SVG symbols on a 24-grid, with a palette token list) and
`glyphs.manifest.json`, which binds glyph ids to semantic events — `race.state.live`, `event.state.registered`,
`guide.route.point_to_point`, and a deliberate note that the weather marks are **families** (dry/wet/obscured/
hazardous) rather than the eight presets, so the vocabulary survives the presets changing. Plus
`assets/banners/{ncm-default,ncm-development}.svg`.

**That manifest is the most design-system-shaped thing NCM owns**, and it already does the hardest part: it names
meanings instead of pictures.

### 2.2 What OPEN//77 presents underneath NCM

`open77_nameplates` (z640, native text plates, with a `setEnabled` export so a resource can take over — NCM does),
`open77_interactions` (z660, camera-projected action cards; motifs `dot ring diamond arrow chevron exclamation info
vehicle person door shop`), `open77_chat` (z700, fps **240**), `open77_notifications` (z720),
`open77_contextmenu` (z750), `open77_watermark` (z900 on `hud`), `open77_blips` (layer `system`, z**−100**, a trusted
compositor for custom blip textures), `open77_shell`/`open77_pause` (layer `system`, fps 144), `open77_worldui`
(no page of its own — it composes marker + prompt), `open77_media` (world televisions).

**Not shipped in our package, and it matters: `open77_uikit`** — progress bars, hints (`textUI`, four slots per
resource), confirmations, input forms, context and keyboard menus, radial wheels, **`drawText3D` world text** and
letterboxing, all sharing **one** WebUI surface across every resource. NCM's manifest records that declaring it on
`.82` stopped every resource; it is absent from the current tree too (checked). Future ceiling, high value, because
it would cost NCM **zero** surfaces and it is the only documented path to world text.

---

## 3. Presentation capability matrix

Client-mod column: **NONE** = works on a stock launcher-provisioned client; **COMPONENT** = needs a delivered
package; **VALIDATE** = uncertain.

| Capability | Mechanism | Proof | Client mod | Cost | Best use | Limitations |
|---|---|---|---|---|---|---|
| Transparent HUD overlay page | `WebUI.create{layer="hud", transparent=true}` | **PROVEN** (4 NCM pages) | NONE | 1 surface + its fps | anything screen-space | 8 surfaces/resource total |
| Click-through overlay | `pointer-events:none` on root | **PROVEN** (`race-ui`, `nameplates.css`) | NONE | free | all passive HUD | — |
| Modal/interactive panel | `pointer-events:auto` + `page:setFocus` | **PROVEN** (`panel.html`, freeroam `control-panel`) | NONE | focus claim | career, markets | focus is a soft-lock risk; see §7 |
| Selective key capture | `page:setConsumedKeys{…}` + `webui.keep_input` | **AVAILABLE** | NONE | — | Escape/arrows in a HUD menu without losing movement | ≤32 keys, navigation keys only; no mouse/pad buttons |
| World→screen projection into a page | `Open77.nameplates.stream(page)` | **PROVEN** (NCM driver cards) | NONE | per-frame native, Lua idle | driver cards | nameplate-shaped payload |
| General world anchors → page | `Open77.anchors.create/update/frame` | **PROVEN** (`open77_interactions`) | NONE | ~2.1 ms/s measured at RP scale | any world-anchored label | **32 anchors/resource**; out-of-slot entries are not drawn |
| Native 3D ground marker | `Open77.markers.create` (real worldEffect) | **PROVEN** (NCM via `open77_worldui`) | NONE | native | grid boxes, checkpoints, venues | **64/resource**; radius 0.1–50 m; maxDistance 1–500 m; **must be lifted ~0.06 m or it renders invisible inside the floor** |
| POI = marker + prompt card | `open77_worldui` `create` | **PROVEN** (NCM race + venue) | NONE | as above | interactable places | facade always draws its own E card (`KB-3`, `KB-16`) |
| Vanilla map/minimap pin | `Open77.blips.create` | **PROVEN** (NCM landmarks, ~30 pins) | NONE | cheap | named places | **128/resource, 512/client**; HUD-only sprites can be absent from the fullscreen map |
| **Custom SVG map icon** | `blips.create{icon={asset,size}}` → native Ink | **AVAILABLE** | NONE | cheap | NCM's own venue/market/paddock icons | resource-relative SVG only; **URLs and raster rejected**; size 16–128 Ink units |
| Blip colour override | `blips.setColor("#RRGGBBAA")` | **AVAILABLE** | NONE | cheap | tier/state colouring | replaces RGB, multiplies source alpha |
| Native GPS route line | `blips.create{routable=true}` + `blips.track(id)` | **PROVEN** (`ncm_world/client/nav.lua`) | NONE | native | "drive there" | GPS snapshots pedestrian/vehicle context at track time — **must re-track on seat change** |
| Blip attached to entity | `blips.create{entity, slot="poi_mappin", offset}` | **AVAILABLE** | NONE | cheap | rival/teammate markers | — |
| Toasts | `open77_notifications` `show`/`update` | **PROVEN** (NCM landmarks) | NONE | shared surface, 20 Hz | transient messages | 4 types; **7** positions; 32 total, 8/position; `durationMs` 0 or 750–120000; **icon is text, ≤16 chars, no images** |
| Native HUD module hiding | `Open77.hud.setVisible(component,false)` | **AVAILABLE** | NONE | free | reclaim speedometer/minimap space | needs `ui.vanilla.hud`, **which NCM does not declare**; claim-based |
| Letterbox / cinematic | `Open77.hud.setCinematic(true[,h])` | **AVAILABLE** | NONE | free | race intro, podium | hides resource WebUIs and world labels too |
| Native screen fade | `Open77.screen.transition("fade",…)` / `fadeOut`/`fadeIn` | **AVAILABLE** | NONE | native | session start/end, teleport cover | `screen.effects`; **`fade` is the only preset — `glitch` returns `unsupported_screen_preset`**; colour fades allowed (white flash), no strobe by design |
| Full-screen post-process | `Open77.vfx.screen(alias)` | **AVAILABLE** | NONE | native | incident/impact feedback | `vfx.screen`; 16 aliases, all **semantically loaded** (drunk, drugged, bleeding); `blackout`/`health.critical` obscure vision |
| World VFX (curated) | `Open77.vfx.play(alias)` client / `Open77.effects.play` server | **AVAILABLE** (`race.firework.burst` used by platform race) | NONE | native | starts, finishes, incidents | **60 aliases / 16 families**; client-local and server-replicated are **different surfaces that do not talk** |
| VFX attached to entity/slot | `Open77.vfx.attach(handle, entity, slot)` | **AVAILABLE** | NONE | native | car-mounted effects | slot names are engine names |
| Base-game UI sound (2D) | `Open77.sfx.play2d("ui_menu_onpress")` | **AVAILABLE** (platform race uses these events) | NONE | **no quota, no handle** | confirm/deny/countdown/reward | **no volume and no pitch — the engine's event carries neither**; cannot duck or fade |
| Base-game spatial sound | `Open77.sfx.play(event,{entity})` | **AVAILABLE** | NONE | quota'd handle | world audio | needs an entity |
| Open-world music state | `mus_ow_generic_START_silent` / `_combat` / `_silent` | **AVAILABLE** (freeroam pvp) | NONE | native | race tension | **open a container, never close one** — closing the engine's takes district music away |
| Custom audio file | `Play2DSound` / `Play3DSound` (bundled mp3/PCM wav) | **AVAILABLE** | NONE | **no WebUI surface** | NCM's own stings | `audio.play`(+`audio.network`); async decode; not sample-accurate |
| Custom audio with gain/pitch/loop | `open77_sound` exports | **AVAILABLE** | NONE | surface is **open77_sound's**, not NCM's | fades, ambient, radios | mp3/ogg/opus/wav/flac/m4a/aac |
| World props as set dressing | `Open77.props.create/setTransform` | **PROVEN** (NCM ghost car) | NONE | replicated | grids, paddocks, markets | `world.props`; catalogue-bound |
| **Web page on a world screen** | `open77_media` (spawn record + URL) | **PROVEN** (shipped service) | NONE | media's own surfaces | paddock timing screen, big screen | **http/https only — a local page will not load**; 38 records inc. `cinema.150ft`; 6 materialised within 90 m; server may hold 64 |
| Camera feed on a world surface | remote-camera world screens | **AVAILABLE**, marked **experimental** | NONE | each capture is an extra scene render | trackside big screen of the leader | fixed **640×360**, 8 capture slots, depth-tested overlay, occluded by geometry |
| Pause-menu branding | `Open77.pauseMenu` accent + logo | **AVAILABLE** | NONE | free | NCM identity in the Escape menu | — |
| Local slow motion | `Open77.world.setTimeScale` | **AVAILABLE** | NONE | client | photo finish beat | replicated per bucket if set server-side |
| Sky hologram branding | `preload_mod` XBM pack | **PLAUSIBLE** (documented pipeline) | **COMPONENT** | boot-time | NCM in the Night City skyline | 128×2048, four bands, WolvenKit CLI; **cannot swap at runtime**; needs HTTPS hosting per finding 10 |
| Bundled webfont | `@font-face` + `web_files` | **PLAUSIBLE** | NONE | page weight | one real typeface everywhere | **no font is bundled anywhere today**; the token file is written expecting this |
| World text (`drawText3D`), hints, radial menus | `open77_uikit` | **BLOCKED — not shipped** | — | would cost **0** NCM surfaces | labels in the world | absent from the package; declaring it on `.82` stopped every resource |
| Native `glitch` transition | `Open77.screen.transition("glitch")` | **BLOCKED** | — | — | — | returns `unsupported_screen_preset`; not isolated safely upstream |
| UI on vehicle part/bone | — | **BLOCKED** | — | — | — | Cyberpunk authors slot names per entity, no Lua binding lists them; `open77_interactions` offers a `part` state selector instead |
| Replacing a prop's material/UVs | — | **BLOCKED** | — | — | — | remote-camera world screens are a depth-tested overlay, explicitly *not* a material replacement |
| Remote assets for gameplay UI | CDN fonts/icons/images | **BLOCKED by policy** | — | — | — | both platform design systems state no gameplay surface reaches the network to render; `Open77.webui.blocklist` lets a host block hosts/tokens |

---

## 4. Base-asset inventory (what exists, and how sure we are)

| Class | Count | Where | Accessibility |
|---|---:|---|---|
| Blip sprites | **147** validated variants + ~25 stable aliases | `guide-blips` | **Open77-supported.** `race`, `objective`, `quest`, `important`, `danger`, `vehicle`, `fast_travel`, `tech`, `vendor`, service points… Names are case/space/hyphen/underscore-insensitive |
| VFX aliases (curated) | **60 in 16 families** | `Open77.vfx.catalog()`; mirrored in `open77_admin/shared/config.lua` | **Open77-supported** |
| VFX raw paths | 1,070 | `docs/generated/vfx-assets-2.31.csv` | **Extracted candidate** — archive-discovered, "advanced and build-dependent" |
| Screen post-process | 16 aliases | `Open77.vfx.screenCatalog()` | **Open77-supported**, semantically loaded |
| SFX events (named, proven in-tree) | 13 | platform race/pvp configs | **Open77-supported** |
| SFX event seed | **17,586** | `docs/generated/sfx-events-wolvenkit-seed.csv` | **Extracted candidate** — WolvenKit 1.6 seed, explicitly requires runtime validation |
| Props | ~250 aliases across 30 families | `Open77.props.catalog()` / admin config | **Open77-supported** |
| World screen records | **38** | `open77_media/shared/records.lua` | **Open77-supported**, geometry measured per record |
| Animations | 23,044 names / 4,690 sets | `docs/data/emote-*` | **Extracted candidate** |
| Vehicle records | 1,372 (89 player/garage) | `docs/vehicle-models.md` | mixed |
| Fonts | **0 bundled** | — | Windows faces only: Bahnschrift (Condensed/SemiCondensed), Cascadia Mono, Segoe UI, Arial Narrow |

### The racing subset, extracted

Audio: `sq024_race_countdown_start`, `sq024_race_countdown`, `sq024_race_start`, `sq024_race_finish`,
`sq024_race_start_fireworks`, `ui_jingle_quest_new` / `_success` / `_update`, `ui_menu_onpress`, `ui_unavailable`,
`mus_ow_generic_START_silent` / `_combat` / `_silent`. The platform's own comment is worth quoting: *"The sq024 layers
are the exact vanilla race cues."*

VFX: `race.firework.burst`, `race.flare.smoke`, `vehicle.skid`, `vehicle.skid.mark`, `vehicle.skid.smoke`,
`vehicle.exhaust`, `neon.holo_zone`, `weather.rain`, `weather.dust`, `sparks.burst.large`, `smoke.column.black`,
`steam.column`, `glass.shatter`, `impact.metal`.

Props: `race.checkpoint`, `race.route_arrow`, `street.traffic_light`, `light.spotlight`, `barrier.road.jersey`,
`barrier.tire_blocker`, `barrier.concrete`, `barrier.pedestrian`, `barrier.blockade.mechanical`, `sign.arrow.left`,
`sign.rect.blank`, `sign.kiosk_frame`, `market.kiosk`, `market.stand`, `recreation.tent`, `debris.*`.

Map sprites: `race` (`Zzz18_RacingVariant`), `Zzz01_CarForPurchaseVariant`, `Zzz02_MotorcycleForPurchaseVariant`,
`Zzz14_ServicePointBlackMarketVariant`, `ServicePointTechVariant`, `FastTravelVariant`, `CustomPositionVariant`,
`HazardWarningVariant`, `DynamicEventVariant`, `ConvoyVariant`, `OutpostVariant`.

One curiosity worth recording: the sprite enum contains **`CPO_*` variants from a dormant multiplayer HUD**
(`CPO_PingDoorVariant`, `CPO_PingGoHereVariant`, `CPO_PingLootVariant`, `CPO_RemotePlayerVariant`), aliased as
`ping_door`, `ping_go_here`, `ping_loot`, `remote_player`. The guide warns they must be checked visually. A
multiplayer *ping* sprite is exactly the thing a racing server wants for "rival here" / "go here", so this is worth
one look in-game.

### Licensing, which is not uniform

Per `AGENTS.md` and `NCM_SERVER_MOD_LICENSING_CATALOG.md`: the **official devkit is MIT**, but the
**Freeroam/Race source is noncommercial-licensed**. That matters directly here, because `gamemodes/freeroam/web/race/`
(33 KB `theme.css`, 53 KB `app.js`) is the most directly reusable racing UI in the tree. **Read it for patterns;
do not copy it into NCM without settling the licence.** `open77-ui.css` and `design-system.css` are the safer
reference: they are token layers whose *values* come from the OPEN//77 public design system, and adopting a token
contract is not the same act as copying a gamemode's stylesheet. Confirm before shipping either way.

---

## 5. WebUI capability audit

**Proven in-engine CEF**, by count of uses across the platform's shipped pages: `box-shadow` 112, `clip-path` 71,
`linear-gradient` 44, `filter` 38, `text-shadow` 18, **`backdrop-filter` 9**, `mix-blend-mode` 6, `radial-gradient` 5,
`will-change` 1, `mask-image` 1, `conic-gradient` 1, `:has()` 1. Plus 38 distinct `@keyframes`. So blur, blend modes,
conic gradients, masks and modern selectors all work; NCM simply is not using them.

**Page configuration** (`WebUI.create`): `entry`, `layer`, `width`, `height`, `fps`, `zIndex`, `transparent`,
`visible`. Three layers exist — `hud`, `menu`, `system`. `fps` is a **real per-page budget knob** and the platform
uses the whole range: 10 (watermark, freeroam ambient), 15, 20, 30, 60, **144** (pause, shell), **240** (chat).

**Entry may be a URL.** NCM's own carrier bridge proves it with `http://127.0.0.1:<port>`, and `open77_media` loads
arbitrary `http`/`https` pages onto world televisions with an ad-block blocklist (`Open77.webui.blocklist`) behind it.
So "no network" is a **reliability policy both design systems chose**, not an engine limitation — a distinction worth
holding precisely, because it means a *served* NCM page on a world screen is possible while a *CDN font* in a gameplay
HUD remains a bad idea.

**Interaction:** `pointer-events:none` root for click-through (proven), `pointer-events:auto` on a panel plus
`setFocus` for modal (proven), `page:setConsumedKeys` for navigation keys without losing movement (available),
`focus-visible` outlines already used by the platform.

**Cost model, and where the real limits are.** The enforced limit is surfaces, not pixels: **8 per resource**, and
NCM can reach 7. Update cadence is the second lever and the platform separates rates deliberately — smooth things go
through native projection at frame rate, decisions go on a Lua tick (`open77_interactions` runs positioning through
`Open77.anchors` per frame and content on a 500 ms tick; `open77_media` reselects screens on a 1 s thread; NCM's
nameplates publish presentation every 250 ms only when a signature changes). **Adopt that pattern rather than
measuring animation counts**: the thing that actually costs is asking Lua or the host for something every frame.

`open77_interactions` is also the one component that ships a **measured** budget line — `work=2.10 ms/s` at RP scale
with per-phase microsecond averages, plus `tests/budget.test.lua` and a host-side `InteractionsBudgetTests.cpp`. That
is the model for how NCM should instrument any new surface, and it is better than anything I could measure from here.

**Honest gap:** NCM's three render harnesses (`tools/{panel,race,nameplate}-render-check.js`) stub a minimal DOM in
Node's `vm` and assert *that a render did not throw*. They prove **logic**, not appearance, layout or CSS — and they
cannot measure frame cost. There is currently **no** offline visual or performance verification for NCM UI, and §17
does not pretend otherwise.

---

## 6. Native, hybrid and world-space audits

### 6.1 The hybrid pattern, stated generally

The platform's architecture is consistently **native owns position, WebUI owns content**:

- `Open77.anchors` — register an anchor (fixed point or entity-attached); the plugin projects it every rendered frame
  straight to your page over `open77:anchors`. 32 anchors per resource, against 256 possible definitions, so the tick
  spends the budget on what could matter this instant.
- `Open77.nameplates.stream(page)` — the same thing specialised for players; NCM ships it.
- `Open77.camera.project` / `screenRaycast` — direct world↔screen conversion, plus screen picking.
- `Open77.blips` — *inverted*: your **asset** goes native (SVG → Ink geometry, or a texture through the
  `open77_blips` trusted compositor at z−100) while the engine owns projection and tooltips entirely.

So "NCM feels embedded rather than floating above the game" has four separate, shipped mechanisms behind it. The
strongest available-but-unused one is the blip SVG path, because it puts NCM's *own* glyph language inside the
player's vanilla map with vanilla selection behaviour.

### 6.2 A worked hybrid NCM could build on one spare surface

Native ring + prompt (`open77_worldui`) marks a grid box; the **same** NCM page that already draws the race HUD adds
an anchored label per box via `Open77.anchors`; `Open77.sfx.play2d("sq024_race_countdown_start")` carries the
countdown; `Open77.vfx.play("race.firework.burst")` marks the finish; `Open77.blips` with an NCM SVG icon puts the
venue on the map with an NCM tooltip. **Zero new surfaces, zero client mods, five subsystems.**

### 6.3 World-space, ranked by readiness

1. **Ground markers + prompts** — PROVEN, already in use. 64/resource. Remember the 0.06 m lift.
2. **Props as set dressing** — PROVEN (ghost car). Barriers, traffic lights, spotlights, kiosks, tents.
3. **Web page on a world television** — shipped service, needs NCM to *serve* the page over http/https. 38 records
   from a desk monitor to `cinema.150ft`. The obvious use is a paddock/venue timing screen that is simply a URL.
4. **Anchored labels** — AVAILABLE via `Open77.anchors` on an existing page; 32 at a time.
5. **Camera feeds on surfaces** — AVAILABLE but **experimental**, 640×360, 8 slots, each an extra scene render.
6. **`drawText3D`** — BLOCKED until `open77_uikit` ships.
7. **Sky holograms** — COMPONENT, boot-time only, needs HTTPS delivery.

Synchronisation note for all of it: markers, prompts, anchors, blips, client VFX and `sfx.play2d` are
**client-local presentation**; props, server effects and vehicles are **replicated server state**. The split is the
whole of §15.

---

## 7. Screen real estate

### 7.1 Layer and z-index map, with two real collisions

`system` (below/around everything: `open77_blips` z−100, `open77_shell` z10) · `hud` · `menu`.

| z | Owner |
|---:|---|
| 620 | freeroam |
| 640 | `open77_nameplates` (native plates) |
| **650** | **NCM driver cards** — deliberately above the native plate, below interaction prompts |
| 660 | `open77_interactions` |
| 700 | `open77_chat` |
| 710 | `open77_wardrobe_ui` (`menu`) |
| 720 | `open77_notifications` (`hud`) · `open77_admin` (`menu`) · **NCM venue (`hud`)** ← **collision** |
| 725 | `open77_cyberware_lab` (`menu`) |
| **730** | `open77_admin` (`hud`) · **NCM race HUD (`hud`)** ← **collision** |
| 750 | `open77_contextmenu` |
| 760 | `open77_remote_camera` |
| 780, 800 | freeroam |
| 900 | `open77_watermark` (`hud`) · **NCM panel (`menu`)** |

NCM's venue card shares `hud` z720 with the notification toasts, and NCM's race HUD shares `hud` z730 with
`open77_admin`'s HUD page. Same layer, same z = undefined ordering. **I have not observed a symptom**, so this is
logged as a latent risk (`KB-158`), not a confirmed bug. The nameplate choice at 650 is, by contrast, exactly right
and worth preserving as the documented rationale.

### 7.2 Regions, and what already owns them

The authoritative answer is the list of vanilla modules a resource may claim with `Open77.hud.setVisible` — 13 of
them, each individually hideable, claim-refcounted so two resources cannot fight:

`minimap` (map panel, geometry, player marker, mappins, **GPS lines**, frame, location label) · `compass` ·
`clock` · `health` · `stamina` · `weapon` · `speedometer` · `questTracker` (**and its yellow GPS route**) · `phone` ·
`scanner` · `vanillaNotifications` · `crosshair` · `hubMenu`.

**NCM does not declare `ui.vanilla.hud`**, so none of this is currently reachable — a one-line manifest change.

Already cleared for us, free: during an authenticated OPEN//77 session the platform **permanently** removes
solo-game input hints, the phone/radio/quick-slot cluster and the lower-right standing/crouching silhouette. So
`hubMenu`, `phone` and `scanner` are already gone and **a claim will not bring them back** — and `isVisible()`
reports *claims*, not what is on screen, so it can read "visible" while the session keeps it hidden.

| Zone | Occupied by | Verdict for NCM |
|---|---|---|
| Upper left | — | **low conflict.** Best home for a timing tower / classification |
| Upper centre | — | **low conflict.** freeroam/race puts navigation here |
| Upper right | `compass`, `clock` | conflict unless claimed |
| Centre | crosshair; native fades | **keep clear.** No toast position exists here anyway |
| Middle left | `open77_notifications` **default** | conflict — toasts land here by default |
| Lower left | `hubMenu` (already removed) | **low conflict, and freed for us** |
| Lower centre | — | low conflict |
| Lower right | silhouette (already removed); freeroam race puts timing here | **low conflict, and freed** |
| Minimap region | `minimap` | claimable |
| Vehicle HUD | `speedometer` | claimable — NCM already draws its own speed |

Note the notification service offers **seven** positions, not the six its README claims: `top_left`, `top_center`,
`top_right`, `middle_left`, `bottom_left`, `bottom_center`, `bottom_right`. There is **no `middle_center` and no
`middle_right`** — so a centre-screen toast is not available, and a centre-screen announcement must be NCM's own page.

---

## 8. Motion and audio vocabulary

**Motion, all CSS, all proven in-engine by the platform:** slide (`ds-slide-left/right`), rise (`ds-rise`), fade,
pop/`chip-in`, `signal-in`, `sweep`, `spin`, pulse (`rx-pulse`, `pvp-boost-pulse`), flash (`range-flash`),
`marker-float`, `hit-pop`, `damage-fade`, `curtain-flare`/`curtain-beat`, `race-impact`, `race-vote-tick`,
`notification-progress`, `capture`, `arrive`. Timing tokens are already authored for us: `--op77-dur-fast 90ms`
(colour/border), `--op77-dur 150ms` (enter/leave/hover), `--op77-dur-slow 220ms` (a whole panel), easing
`cubic-bezier(0.2,0,0,1)`; the second system adds `--dur-4 340ms` and `--ease-out`.

The platform's own stated rule is worth inheriting wholesale: *"Functional and fast. No glitch loops, no parallax,
no idle animation."* And `prefers-reduced-motion` is already handled in `open77-ui.css` — which NCM does not ship, so
NCM currently honours nothing.

**Native motion beyond CSS:** `Open77.screen` fade/hold/return (colour-tintable, no strobe by design),
`Open77.hud.setCinematic` letterbox, `Open77.world.setTimeScale` local slow motion, `Open77.vfx.screen` post-process.

**Audio vocabulary, mapped to the jobs NCM actually has:**

| Job | Mechanism |
|---|---|
| Confirm | `sfx.play2d("ui_menu_onpress")` |
| Deny / error | `sfx.play2d("ui_unavailable")` |
| New event / objective | `ui_jingle_quest_new` |
| Reward / accomplishment | `ui_jingle_quest_success` |
| State changed | `ui_jingle_quest_update` |
| Countdown | `sq024_race_countdown_start`, `sq024_race_countdown` |
| Green | `sq024_race_start`, `sq024_race_start_fireworks` |
| Finish | `sq024_race_finish` |
| Tension / calm | `mus_ow_generic_combat` / `_silent` (open a container, never close one) |
| Anything needing a fade, duck or pitch | **must be an NCM file** — `Play2DSound`/`Play3DSound` or `open77_sound` |

That last row is the important constraint: `gameaudioeventsPlaySound` carries only
`soundName, emitterName, audioTag, seekTime, playUnique`. **There is no gain and no pitch field in the engine event
at all**, so base-game audio is take-it-or-leave-it. A volume slider for NCM's own cues requires NCM's own files.

---

## 9. Visual directions (five, plus one that emerged)

Not a recommendation. Each is scored on what it costs *in this stack*.

**A · Cyberpunk-native / platform-native.** Adopt `open77-ui.css` wholesale. *Strength:* free coherence with chat,
toasts, prompts, pause; reduced-motion and contrast already solved; a documented reason behind every token.
*Weakness:* NCM looks like the platform, not like NCM. *Cost:* lowest of all five. *Fit:* perfect.

**B · Motorsport broadcast.** Timing tower, sectors, classification rows, session clock, flags, dense mono figures.
*Strength:* it is what the product *is*, and the type scale already tops out at `--op77-fs-hero 40px` for
"countdowns, verdicts". *Weakness:* density is the enemy of a windscreen; broadcast graphics assume a viewer, not a
driver. *Cost:* medium; mostly layout and a number-roll. *Fit:* good — upper-left and lower-right are the free zones
and they are exactly where a tower and a timing block belong.

**C · Paddock / engineering.** Technical clarity for parts, setup, temperatures, compatibility, wear.
*Strength:* matches the Parts/Engineering/Machine Knowledge systems already built; `--font-mono` and the
`--size-data` scale exist for it. *Weakness:* wrong register for reward moments. *Cost:* medium. *Fit:* good, and
this is the one direction whose natural home is a **world screen in a paddock** rather than the HUD.

**D · Night City motorsport culture.** An original identity from NCM's own organisations, manufacturers, venues and
markets. *Strength:* the only direction that builds an asset rather than borrowing one; NCM already has the fiction
(`14_TEAM_ORGANIZATIONS`, `17_MARKET_NETWORK`, banners, Driver Cards). *Weakness:* needs authored art, and the
**no-bundled-font** reality caps typographic personality until a webfont ships. *Cost:* highest. *Fit:* medium now,
high after a font.

**E · Diegetic corporate.** Different presenters look different — a market unlike a manufacturer unlike an organiser.
*Strength:* `blips.setColor` per blip, per-notification `color`, and CSS custom properties scoped to a container make
this genuinely cheap to *implement*. *Weakness:* it multiplies the design surface and fights legibility; and it only
reads as intentional once the base system is coherent — which it is not yet. *Cost:* low to build, high to author.
*Fit:* good later, wrong first.

**F · The one that emerged from the audit: layered by mechanism, not by theme.** The stack already sorts
presentation into native / anchored / world / screen tiers with different owners and update rates. A visual system
that maps *tier* to *voice* — engine-drawn things speak vanilla (map icons, markers, fades, jingles), NCM's own
surfaces speak NCM, world screens speak in-fiction broadcast — would be honest about the machinery instead of
fighting it, and it is the only direction that needs no new capability at all.

**On not making everything a neon red rectangle:** the platform has already done this thinking and written it down —
*"Blue-gray hairlines, never cyan. Depth comes from borders, not shadows."* · *"if a viewport shows more than ~3 cyan
elements, remove some"* · *"6px is the maximum radius anywhere"* · coral is *"semantic only, never a CTA"* · and one
single permitted shadow, *"a separation device, not a depth ramp: there are no levels."* That is a visual system.
Inheriting it is the fastest way to stop being a costume.

---

## 10. Component library and tokens

**Yes, and most of it already exists — it is just not shared.** Recommended shape:

1. **`ncm/online/resources/ncm_world/web/ncm-ui.css`** — one token file, `@import`-free (CEF pages load only files
   their own manifest declares, and `web_files { "web/**" }` already covers it). Layer it: platform tokens
   (`--op77-*`, copied byte-identical so the mirror check stays meaningful) + an NCM block that *aliases* them, so
   NCM's existing `--accent` / `--ncm-cyan` keep working while resolving to one value. This alone fixes findings 1
   and 2 and costs no surfaces.
2. **Fix the font stacks to match reality.** Name Bahnschrift Condensed / Bahnschrift / Cascadia Mono as the
   *intended* faces with Rajdhani-family names kept first, exactly as the platform does, so a future bundled webfont
   takes over with no edit. Delete `"Arial Narrow"` from the nameplate stack.
3. **Promote the glyph manifest to the icon contract** and give it a second output: an `icons/*.svg` build for
   `blips.create{icon=…}`. Same ids, two renderers — CEF and native Ink.
4. **Primitives NCM's shipped systems actually need** (not the brief's full list): `timing-row`/`classification-row`,
   `timer`/`countdown`, `delta` (signed, mono, colour-coded — ghosts already need it), `status-chip`,
   `progress`/`fill`, `toast` (defer to `open77_notifications` rather than rebuild), `banner`, `card`
   (vehicle/part — Parts UI exists), `compatibility-indicator`, `weather-indicator` (four families, glyphs exist),
   `tyre-indicator` (race HUD has one), `reward-reveal`, `transaction`/`receipt` (Economy v1 emits itemised
   statements today with no component to show them), `event-banner`, `location-banner`, `map-legend`.
5. **Do not build:** modal, tooltip, nav bar, radial — `open77_uikit` would supply the first three for free if it
   ever ships, and `panel.html` already has its own navigation.

Token axes the stack proves are worth centralising: colour (field/line/ink/signal), transparency floors (the
platform's rule that **0.94 is the floor for any surface carrying words over gameplay** is a measured HUD-specific
decision worth copying exactly), type roles + the 9-step HUD scale, tracking, base-4 space, viewport insets
(`--op77-inset-x/y`, so surfaces line up instead of each picking its own vw), chamfer/notch clip-paths, the single
shadow, durations/easings, and **z-index conventions** — which §7.1 shows is the one axis NCM is currently getting
wrong.

---

## 11. Resolution, accessibility, legibility

- Every NCM page is authored at a fixed **1920×1080** and scaled by the compositor. The platform's own race theme
  instead uses `clamp(20px, 2.2vw, 40px)` for its inset, which survives ultrawide honestly. NCM's fixed-pixel cards
  are why `nameplates.js` has to compute `cardScale()` by distance at all.
- Contrast is already measured for us against `--op77-surface`: text 16.2:1, dim 6.2:1 (AA at any size), faint 3.6:1
  — **decoration and disabled only, never body copy**. NCM's `--dim: #8d99a8` is the same value; its many
  `rgba(223,250,255,0.42)` and `0.12`-alpha decorations in `nameplates.css` are below the floor and are, correctly,
  decoration — but `.ncm-card__fingerprint-note` at **5px** and eyebrows at **6–7px** carry words.
- The HUD type scale exists precisely because of this: `--op77-fs-micro` bottoms out at **9px**, *"read at arm's
  length over a moving image, not on a document."* NCM has type well below its own platform's floor.
- `prefers-reduced-motion` is handled in `open77-ui.css`; NCM ships no copy, so NCM honours nothing today.
- Colour dependence: the four notification types differ by colour **and** a `kind` label, which is the right pattern.
  NCM's badge tiers in `nameplates.css` differ by `:nth-child()` border colour **only** — position-dependent and
  colour-dependent at once.
- Controller: `KB-3` already records that `open77_interactions` is keyboard-only and cannot show a pad glyph, so NCM
  writes "hold E or X" as text. `setConsumedKeys` explicitly rejects mouse and controller buttons. **Pad players are
  a standing presentation gap, not a solved problem.**
- Driving readability is the binding constraint: a racing surface is read in fractions of a second, which argues for
  the top-left/lower-right free zones, the larger end of the type scale, and the 0.94 opacity floor.

---

## 12. Client / server responsibility

| Presentation class | Authority | Notes |
|---|---|---|
| Race state, classification, timing, penalties | **server** | NCM race kernel; the HUD renders a published view |
| Money, receipts, ledger | **server** | Economy v1 settles atomically; UI must never compute a balance |
| Ghost laps | server-stored, **client-rendered** | Client replays poses; `KB-156` is exactly what happens when the key is missing |
| Driver Card identity/badges | **server** state bag, sanitised | `driver.presentation.sanitizePublicProjection` already exists — deliberately public data only |
| Projection, anchors, markers, blips, client VFX, `sfx.play2d` | **client** | Pure presentation; never authoritative |
| Props, server effects, vehicles | **server** | Replicated |

Two traps the platform documents and NCM should inherit as rules: **client-local `Open77.vfx.play` is never
replicated and server `Open77.effects.play` is not a broadcast of a client call** — picking the wrong one produces a
feature that works perfectly for the person testing it and does not exist for anyone else. And the interactions
service warns that `groups`, `canInteract`, distance and vehicle state in a prompt payload are **all read on a
machine the player owns** — a client can always claim it pressed the button.

---

## 13. Mod-delivery reality

Techniques needing **no additional client component** (the overwhelming majority): every WebUI page, all toasts,
markers, POIs, blips including custom SVG icons, GPS routing, anchors, native projection, HUD module claims,
letterbox, native fades, screen post-process, curated VFX, all base-game audio, bundled audio files, props, world
televisions, camera feeds, pause-menu branding, time scale.

Techniques needing a **client component**: sky hologram replacement (`preload_mod` XBM pack) and any custom
mesh/texture/archive asset — liveries included.

**Uncertain / validate:** a bundled webfont (nothing bundles one today, and the design systems assume it will
eventually work); the `CPO_*` ping sprites; remote-camera world screens while they are marked experimental; Unicode
glyph coverage in a notification `icon`, which depends on which Windows symbol/emoji faces the client has.

And the correction that matters most: delivery previously looked blocked and was not. `Unverifiable` meant the
launcher's `CatalogUrls.ModBlob` **discards every non-loopback plain-`http:` URL** before resolution. HTTPS hosting
is the fix. So the ceiling is nearer than the record suggested.

---

## 14. Prototypes

Built, isolated under `docs/research/open77/prototypes/`, touching no shipped resource:

- **`ncm-ui.css`** — the missing token layer: platform tokens verbatim, NCM aliases over them, corrected font stacks.
- **`gallery.html`** — a self-contained CEF-safe capability gallery: no network, no webfonts, system faces only. It
  renders the token ramps, the corrected typography, a native-style notification, an animated progress/fill, a race
  banner and countdown, a timing-tower row set, a delta readout, status chips, the weather-family glyphs, and one
  motion strip using the platform's own duration tokens. Open it in a browser to look at it.

These validate *authoring* — the same thing `race-render-check.js` validates for logic. **Neither validates
in-engine appearance or frame cost.** Doing that needs a client, and it is the first item in §16.

---

## 15. Recommended near-term toolkit

Given only what is proven or plainly available today, and only one spare surface:

1. **Ship the token file and fix the fonts.** Zero surfaces, zero permissions, fixes findings 1–2.
2. **Give NCM a voice.** `Open77.sfx.play2d` for confirm / deny / countdown / green / finish / reward. No quota, no
   handle, no surface. Largest perceived change per line of code in the whole audit.
3. **Separate the two colliding z-indices** and write the allocation down next to the nameplate rationale.
4. **Declare `ui.vanilla.hud`** and claim `speedometer` where NCM already draws speed.
5. **Export the glyphs as SVG and put NCM's own icons on the vanilla map** via `blips.create{icon=…}`.
6. **Add motion from the platform's tokens** — enter/leave on the banner and toasts, a progress fill, a number roll
   on deltas — and inherit the reduced-motion block with it.
7. **Use `Open77.anchors` on an existing page** for the first world-anchored NCM label, rather than creating a surface.
8. **`race.firework.burst` at the finish line**, which the platform's own race gamemode already does.

Everything above is additive, reversible, and needs no client component.

## 16. Future ceiling

- **A bundled webfont** — the one change that unlocks real typographic identity (direction D).
- **`open77_uikit`** if it ships: world text, hints, radial menus, progress, letterbox, at **zero** surface cost.
- **World screens as a first-class NCM surface**: a served timing page on `cinema.150ft` at a venue.
- **Sky holograms**, once packages are served over HTTPS.
- **Remote-camera big screen** once it leaves experimental.
- **A ninth surface** is not coming — so the real ceiling-raiser is reclaiming the three invisible bridge surfaces,
  or splitting NCM's presentation into a second resource with its own budget of eight.

## 17. What this audit did not establish

Stated plainly, because negative clarity is the point:

- **Nothing here was measured in-engine by me.** No frame cost, no visual confirmation, no CEF font-fallback proof.
  The typeface finding is derived from source and the platform's own explicit statement, not from a screenshot.
- The z-index collisions are **latent**, not observed.
- The devkit index answers for **op77.78** while staging runs **.102**: `since` values are lower bounds and anything
  added in between is invisible to this audit.
- I did not enumerate the 17,586-row SFX seed, the 1,070 VFX paths or the 23,044 animations. They are
  **extracted candidates** and each needs the platform's own six-step promotion checklist before use.
- Licensing of `gamemodes/freeroam/web/race/` for reuse is **unresolved** and needs an owner decision.
- Whether a notification `icon` can carry a Unicode symbol depends on client font coverage — untested.

## 18. Handoff to the player-visibility audit

That audit answers *what must be said, when*. This one answers *with what*. The join is the glyph manifest: it
already binds meanings (`race.state.live`, `event.state.registered`, `race.penalty`) to marks. Extend **that** file
with the events the visibility audit finds NCM is silent about, and each one arrives with a mark, a toast type, a
position, a sound and a motion already chosen — instead of a new box invented per feature.

The four questions worth bringing back from that audit: which messages must survive being read in half a second at
speed; which must persist versus flash; which need to exist in the **world** rather than on the HUD; and which need a
sound, because sound is the channel NCM currently does not use at all.

---

# Addendum A · Market visual identity

Added 2026-09-27 at owner request, as a concrete design study for the broader audit. Placeholder names in the
request (Watson dealership, Pacifica engineering market) are **not** adopted as market or organisation names.

## A.1 The timing is unusually good, and the existing plan already argues for this

There is exactly **one** market in the code today — `ncm/core/economy/markets.lua` defines
`{ marketId = "base_market", displayName = "Base Market", universallyKnown = true, kind = "primary" }` — plus a
`M.discovery(fact)` validator, `DISCOVERY_SOURCES`, `ACCESS_STATES` and `M.purchaseDecision`. So the theming
question arrives **before** the second market exists, which is the cheapest possible moment to answer it.

More usefully, `17_MARKET_NETWORK.md` (STATUS: CURRENT) has already settled the principle this study needs, for
its own reasons:

- it explicitly rejects **name as identity**, because *"one manufacturer may operate several surfaces and one
  supplier may carry several manufacturers"*;
- `market_id` is *"stable opaque identity"* while `display_name` is *"presentation, independently mutable"*;
- and *"`marketId`, manufacturer identity, allocation identity, `vehicleKey` and `assetId` are never collapsed."*

A market theme is therefore **another independently mutable presentation attribute resolved from the opaque
`marketId`** — exactly the shape the document already blesses. This study extends the existing plan rather than
competing with it, and it satisfies the owner's constraint directly: because identity is resolved per market
rather than derived from geography, **two markets in one district can differ**, and one operator can carry the
same identity across districts.

## A.2 The mechanism: a theme is a token override block, not an interface

This is the whole technical answer, and it is cheap because CSS custom properties cascade.

NCM's panel already resolves every colour, face, size and timing through custom properties. A theme is therefore
a scoped redefinition of a **small, closed subset** of those properties:

```css
/* Base — the neutral NCM commercial environment, and the fallback for any unknown theme. */
[data-market-theme] { /* inherits every :root token unchanged */ }

/* An authored identity overrides only what it is allowed to override. */
[data-market-theme="forge"] {
  --mk-accent:      #ff8a3c;                 /* the operator's signal */
  --mk-plate:       rgba(24, 16, 10, 0.94);  /* still at or above the 0.94 words floor */
  --mk-frame:       var(--op77-line-hud);
  --mk-display:     var(--op77-font-mono);   /* a *role reassignment*, not a new font */
  --mk-texture:     repeating-linear-gradient(135deg, transparent 0 6px, rgba(255,138,60,.05) 6px 7px);
  --mk-cut:         var(--op77-notch-clip);
  --mk-dur:         var(--op77-dur-fast);    /* this operator is brisk */
  --mk-voice:       "technical";             /* read by JS to pick a copy register */
}
```

One stylesheet, N identities, **zero new WebUI surfaces** — which matters more than usual here, because §1 finding
3 says NCM has one spare surface in its budget of eight. A per-market interface is not merely expensive to build;
it is *unaffordable* in surfaces. A per-market `data-market-theme` attribute costs nothing.

The identity is applied by setting one attribute when the player selects a market in the existing left-hand list.
The F6 → Markets shell, its navigation and its transaction affordances do not move.

## A.3 What is allowed to vary, and what must never

The failure mode of diegetic theming is that the player loses their bearings — or worse, misreads a price. So the
surface is split in two, and the split is not negotiable:

| Layer | Owner | May a theme change it? |
|---|---|---|
| Shell chrome: the six-tab nav, panel frame, back affordance, focus outlines | **NCM, always** | **No.** The player must always know whose software they are in. |
| Identity plate: header, operator mark, background texture, eyebrow copy, accent, frame motif, entrance motion | the market | **Yes** — this is the whole point |
| Stock rows: item name, provenance, compatibility state | shared components | Accent and frame only |
| The money figure and the commit affordance | **NCM, always** | **No.** Price and "you are about to spend" never take on a local dialect. |
| Legibility floors: 9px type minimum, 0.94 opacity under words, contrast ratios, tabular numerals | **NCM, always** | **No.** A theme may not opt out of being readable. |

That last row is what keeps this from becoming a costume. An identity gets a palette, a texture, a type *role*
assignment, a motion character and a voice — it does not get permission to be dim, tiny or ambiguous about money.

## A.4 Identity inputs, resolved rather than derived

The owner's list is the right list, and none of it should be read straight from geography. Proposed resolution
order, most specific first — the first hit wins, so an authored exception never fights a rule:

1. **explicit `themeId` authored on the market** (always wins; how a one-off gets its identity)
2. **operator / organisation** — the strongest input, because an operator is what a player actually recognises
3. **specialisation** (machines vs components vs a specific discipline)
4. **relationship** — corporate, manufacturer, gang, team, where one legitimately exists
5. **supply / price tier**
6. **clientele**
7. **district / subdistrict** — a *flavour* modifier, never the primary key
8. **fallback: base**

Resolution belongs in core as a pure function over authored facts —
`markets.theme(market) -> themeId` — so it is testable offline and identical on client and host. The **theme
descriptor** (what a themeId means visually) is authored presentation data; the **resolution** is domain logic.
Keeping those apart is the same separation `driver.presentation` already draws between definition, entitlement and
selection, and it is why that module is easy to reason about.

## A.5 Scale, and honest costs

- **Assets must be CSS geometry or a bundled SVG.** Both platform design systems state that no gameplay surface
  reaches the network to render, so a themed market cannot pull art. Textures should be gradients and repeating
  patterns; an operator mark can be an inline SVG in the glyph set.
- **Cost per identity is one CSS block plus one descriptor row.** No new page, no new resource, no client mod.
- **The fallback must be total.** An unknown `themeId` renders base and logs once — a market must never fail to
  open because its art is missing.
- **Ten identities is plausible; fifty is a content problem, not a code problem.** That is the correct place for
  the limit to sit.
- **Not free:** every theme is a legibility regression risk, so the render harness should assert the floors
  (contrast, minimum size, that the money figure keeps the NCM treatment) **per theme**, not once.

---

# Addendum B · Player Banners

## B.1 The strongest finding: this system already exists, minus one substrate

Banners are not a new concept to build. `ncm/core/driver/presentation.lua` already ships:

| Piece | Status |
|---|---|
| A banner registry with stable ids | **built** — `M.BANNERS`, two rows |
| A **`theme`** field per banner | **built**, and already used: `nameplates.css` keys `.ncm-card--banner-development` off it |
| An **`entitlement` reason** string per banner | **built** — `"baseline"`, `"development_fixture"` |
| Art + focal point per banner | **built** — `image`, `crop` |
| Entitlement computation | **built** — `M.entitlements(accomplishmentKinds, opts)` |
| Selection validated against entitlement, with typed issues | **built** — `unknown_banner`, `banner_not_entitled` |
| Persistence of the equipped banner | **built** — `driver_presentation.banner_id` |
| A safe public projection | **built** — `sanitizePublicProjection` |
| A renderer | **built** — the Driver Card's `banner-art` layer |
| An asset catalogue for the client | **built** — `M.assets()` |
| **An earning path** | **MISSING — and it is the only missing piece** |

The precise gap: `M.entitlements()` takes *only accomplishment kinds*, and every badge binds to an
`accomplishment`. Banners have **no** earning input at all — the sole non-baseline grant is the `developmentOnly`
flag. So the architecture is complete and the substrate that would feed it does not exist.

That is a very different piece of work from "design a banner system", and much smaller.

## B.2 Badge versus Banner, stated so the distinction survives contact

The owner's distinction is sound, and it maps cleanly onto two substrates NCM already keeps apart:

| | BADGE | BANNER |
|---|---|---|
| Sentence | *"I did this."* | *"I was there."* |
| Grammar | a **verb** | a **noun / place** |
| Source | an **accomplishment** (`first_win`) | an **encounter** (discovered a market, ran a venue, represented a team) |
| Scarcity | earned, meaningful, finite | **generous by design** |
| Mechanical effect | none | none, ever |
| On the card | up to **3** marks | exactly **1** field, behind them |

The visual relationship falls out of the existing card geometry and is genuinely elegant: **the banner is the
ground, the badges are the marks on it.** One says where you have been, three say what you did there.

## B.3 Format — the renderer has already decided most of this

Measured from `nameplates.css`, not proposed: the card is `288×84` with `grid-template-columns: minmax(0,1fr) 82px`,
so the banner art area is **206×84 ≈ 2.45:1**, drawn `background-size: cover` from a `crop` focal point at
**opacity 0.72**, with the driver's name, eyebrow and badge row composited on top.

The consequences are strict and useful:

- **A banner is a background wash, not a picture.** It must read at 72% opacity under text. High-contrast art with
  a focal subject will fight the name and lose.
- **Author at 2.45:1** (e.g. 412×168 for 2×), and rely on `crop` for framing rather than re-cropping the asset.
- **SVG is the right format** — it is what both existing banners use, it scales with `cardScale()`, it costs no
  asset delivery, and it can be recoloured from tokens.
- **The bottom-left 8px is clipped** (`clip-path: polygon(... 8px 100%, 0 calc(100% - 8px))`), so nothing load-
  bearing goes in that corner.

**Static versus animated:** the card page runs at **fps 60** and draws one card *per streamed remote player*, so
an animated worn banner multiplies by the field size. Recommendation: **worn banners are static**; animation is
reserved for the **unlock moment**, which happens once, on a different surface, for one player. That is a
performance argument, not an aesthetic one, and it also happens to be better design — the unlock is the event, the
worn banner is the memory.

## B.4 The substrate to add, and nothing more

A banner grant is a **provenance fact**, which is the same shape NCM already uses for market discovery
(`first_known_at` written once, never updated) and vehicle discovery (`first_discovered_at`):

```
banner_grant
  ncm_driver_id, server_id, banner_id      -- PK
  source_kind                              -- market | venue | district | championship |
                                           -- manufacturer | team | organisation | event | milestone
  source_ref                               -- the opaque id it came from, nullable for baseline
  first_granted_at                         -- write-once, like every other first-sight fact
```

Then `M.entitlements(accomplishmentKinds, opts)` gains a second input — `grantedBannerIds` — and the existing
selection/validation/projection path needs **no change at all**. That is the whole code delta on the core side.

`source_kind` is deliberately an open vocabulary covering the owner's list, so markets, venues, championships,
manufacturers, teams, organisations, events and milestones can all feed it later. **Only `market` should be
implemented now.** The others are proven possible by the column existing, which is the point.

## B.5 Market discovery as the first case

Discovery currently risks landing as *"another inventory source became available"*. With a banner it becomes a
thing the player keeps. The moment has two halves, and they belong on different surfaces:

- **The event** — one message through the communication layer that now exists
  (`NcmComms.send`, priority `informative`, `repeatPolicy.mode = "once"`), carrying the market's *themed* identity
  plate so the player sees whose door they just opened; plus `ui_jingle_quest_success` via
  `Open77.sfx.play2d`, which costs no quota and which NCM currently never plays.
- **The memory** — the banner appears in the Driver File, already built by the visibility pass, which is the
  natural home for *"where can I find this again?"*.

On the copy: the request's own draft reads *"Supply chain unlocked."* That is the corporate register, and the
established NCM voice is better than it — `visibility.lua` already says **"THE ROAD IS OPEN"**,
**"ENTERED · THE FIELD KNOWS YOUR NAME"** and **"The city remembers what you do."** A discovery in that voice is
closer to:

> **A DOOR IN WATSON OPENS**
> *Kiroshi-lit, smells of brake dust.* You know where this one is now.
> **BANNER EARNED · their colours are yours to fly**

Register, not decoration: it is specific, it is short, it names a *place* rather than a *feature*, and it does not
congratulate the player for existing. §B.7 makes that rule explicit.

## B.6 Where an equipped banner can appear

Every one of these surfaces exists today:

1. **The Driver Card**, world-projected over the player — already renders it (`PROVEN`).
2. **The Driver File header** — the new persistent surface; the banner is its natural crest.
3. **Classification and results rows** — as a 3–4px accent edge drawn from the banner's `theme`, not the art.
4. **A themed market's greeting**, when the player is flying that market's own banner. Cheap, and the kind of
   detail that makes a world feel like it noticed.
5. **A collection surface** — the one piece with no existing home. It belongs in the Driver File as a grid of
   earned banners with source and date, *not* as a new panel: `SHELL_TABS` is already six entries wide.

## B.7 Anti-goals, kept explicit

- **Never statistical.** No banner grants money, grip, access, price movement or standing. The instant one does,
  players optimise collection instead of enjoying it, and every future banner becomes a balance argument.
- **Not achievement confetti.** Generous does not mean constant. A banner marks an *encounter with a place or an
  organisation* — a finite set that grows as Night City's map does, not a counter.
- **No new notification convention.** Unlocks route through the communication layer with its pacing policy, or
  they will drift into their own dialect within two features.
- **No banner that cannot be re-found.** If it cannot be inspected later, it is a toast, not a collectible.

---

# Addendum C · The voice — what "joy" means as an engineering constraint

Requested explicitly, and it is a real specification rather than a mood, because an audit that produces correct
but lifeless copy has failed at the thing NCM is for.

**The register already exists in this repo and should be codified rather than invented.** `visibility.lua` writes
"THE ROAD IS OPEN" and "The city remembers what you do."; `panel.html` writes "Night City Motorsports · Persistent
Driver Record". That is the voice: *energised, specific, slightly documentary, never bubbly and never corporate.*

Six rules that make it reproducible:

1. **Name the place, not the feature.** "A door in Watson opens" beats "Market discovered". The player is in a
   city, not a menu tree.
2. **One concrete sensory detail earns more than three adjectives.** "smells of brake dust" does work that
   "exciting new vendor" cannot.
3. **Be exact where it costs money, atmospheric where it does not.** €$2,500 is never "a tidy sum". The audit's
   own token split enforces this: the money figure keeps the NCM treatment under every theme.
4. **Energy comes from verbs and rhythm, not exclamation marks.** "The field knows your name" has no punctuation
   tricks in it.
5. **Never congratulate a player for pressing a button.** Confirm the consequence instead: "Your venue is marked
   and practice is open" tells them something; "Great choice!" tells them nothing.
6. **Escalating clarity must not escalate volume.** The communication layer escalates *priority*, which changes
   duration and weight — the wording should get **plainer**, not louder. A player who is stuck needs
   "Open the map with M and follow the NCM marker", not a bigger font on a poem.

And the structural half, which is where joy actually comes from in a game: **the surfaces have different jobs, so
they should have different voices.** The audit's direction F (§9) argued for exactly this by mechanism — engine-drawn
things speak vanilla, NCM's own surfaces speak NCM, world screens speak in-fiction broadcast. Markets add a fourth:
an operator speaks in its own accent. A player who can *hear* four distinct voices in one product is in a world.
A player who hears one is in an application.

---

# Addendum D · Input accessibility and the Session Landing Panel

Added 2026-09-27. **This one is implemented, not only audited** — the recon is here, the code shipped into the
working tree, and §D.7 says exactly what was and was not tested.

Answered against the **installed client**, not the docs index. That distinction turned out to matter: see D.1.

## D.1 A correction about which build answers

The devkit MCP publishes cards up to **op77.78**. Staging runs **op77.102**. So the MCP answers `.78` and
labels anything newer *"NOT AVAILABLE on 2.31.13+op77.78: this native is not in any published build"* — which
is a statement about the **index**, not about our client.

`WebUI.Page.setConsumedKeys` is exactly such a native. Rather than guess, the installed plugin was read
directly: `red4ext/plugins/Open77/Open77.dll`, 11,139,584 bytes, modified **2026-09-25**. It contains
`setConsumedKeys`, `hasFocus`, `webui_key_capture_unavailable`, `gamepad_not_connected`, `control_is_an_axis`
and the complete pad vocabulary. **So `setConsumedKeys` is present on our client.**

The general lesson is worth keeping: *when the index is behind the deployed build, grep the binary.* It is
cheap, it is definitive, and it beats both guessing and waiting.

## D.2 Input capability findings

| Need | What the stack gives us | Verdict |
|---|---|---|
| Gamepad buttons | `Open77.input.isDown(control)` — `padA/B/X/Y`, `padUp/Down/Left/Right`, `padStart`, `padBack`, `padLeftShoulder`(`padLB`), `padRightShoulder`(`padRB`), `padLeftThumb`, `padRightThumb` | **AVAILABLE** (`input.actions`, which NCM already declares) |
| Analogue sticks / triggers | `Open77.input.axis` — `padLeftStickX/Y`, `padRightStickX/Y` (−1..1, XInput dead zone already removed, **Y positive UP**), `padLeftTrigger`/`padRightTrigger` (0..1) | **AVAILABLE** |
| Device detection | `Open77.input.devices()` — per-control `{name, device, kind, available, reason}`; an unplugged pad is present and `available=false` with `gamepad_not_connected`, never omitted | **AVAILABLE** |
| Controller **brand** | Nothing. `devices()` reports device/kind/availability only, and the underlying API is XInput (Xbox-shaped) | **BLOCKED** — see D.5 |
| Keyboard in a page | Ordinary CEF `keydown`/`keyup` once the page holds keyboard focus | **PROVEN** |
| Reserving nav keys from the game | `page:setConsumedKeys` (≤32 names, navigation keys only) | **AVAILABLE** on our client, but needs `webui.keep_input`, which NCM does **not** declare — and does not need (D.4) |
| Focus | `page:setFocus(keyboard, cursor, keepInput)` — the first argument is keyboard, the second the cursor; `page:hasFocus()` reads it back | **PROVEN** (NCM uses it) |
| Mouse wheel | `Open77.input.axis("mouseWheel")` — a **cumulative counter**, not consumed on read, so two samples must be differenced | **AVAILABLE** |
| Pointer | `Open77.input.pointer()` (0..1 across the rendered image), `Open77.input.cursor()` | **AVAILABLE** |
| Blocking gameplay actions | `setActionBlocked` / `blockAll{except}` / `blockableActions()` (with mechanism *and confidence*) / `blocks()` | **AVAILABLE** |

Three facts from the cards that shaped the implementation:

- **These are physical reads.** They do not know the player's bindings and do not know whether the game is
  currently consuming the control — the `GetDisabledControlNormal` flavour. The API's own advice is followed:
  *"Prefer a press edge or a hold timer over firing every frame."*
- **A missing device is named, never answered zero**, *"because a zero cannot be told from a stick held at
  centre."* That is why `nav_input.lua` reports its probe result out loud.
- **Gamepad reads are zero while the game window is not in the foreground**, which is correct behaviour and
  needs no handling.

## D.3 The one architectural fact

**A CEF page cannot see the gamepad.** There is no bridge from XInput into the page's `navigator`. So:

> The pad is read in Lua, translated into **semantic actions** there, and sent to the page as ordinary events.
> `web/ncm-nav.js` never mentions a button. It receives "up", "activate", "back".

That is not a workaround, it is the safe design, and `KB-61` is why. The panel took keyboard *and* cursor
focus, and **both** ways out ran through the page; when the page broke, the player could not move, could not
open the pause menu, and had to kill Cyberpunk. The rule that came out of it — *nothing about releasing focus
may depend on the page being healthy* — extends to the pad:

> **Pad BACK is resolved in Lua and is authoritative there.** `client/nav_input.lua` calls the surface's own
> `onBack` directly, then tells the page for the sake of a smooth close. It does not wait for an answer. A dead
> page is still escapable with the controller alone.

## D.4 What was built

| Piece | File | What it does |
|---|---|---|
| Pad driver | `ncm_world/client/nav_input.lua` | Polls buttons and sticks on a 60 ms tick, press edges + repeat (340 ms then 130 ms), **stick hysteresis** (latch at 0.55, release below 0.32), probes `devices()` once and re-probes every 5 s until a pad appears, owns BACK, and ships `/ncm.input` as a diagnostic that prints every control and axis |
| Navigation layer | `ncm_world/web/ncm-nav.js` | Stacked focus scopes (a modal genuinely traps), spatial navigation with a directional cone, a focus ring, scroll-into-view, activation, linear Tab stepping, input-family detection, prompt painting |
| Landing data model | `ncm/core/player/landing.lua` | The alpha contract, capability states, changelog validation and ordering, "new since you left", a forward-only seen watermark |
| Authored content | `ncm_world/client/landing_content.lua` | The capability list and changelog as **data**, so a release never touches markup |
| The panel | `panel.html` (`#landing`) + `client/panel.lua` | A new **mode** of the existing page |

Two decisions worth stating because they were close calls:

**The landing panel is a mode, not a new surface.** A resource may hold eight CEF surfaces
(`kMaximumWebSurfaces`) and NCM already holds seven (§1 finding 3). A new page would have spent the last one on
a screen shown once per session. As a mode it also inherits the KB-61 focus handshake for free.

**The "already seen" watermark is a client KVP, not a schema column.** `Open77.kvp` is isolated by connection
address, resource and key, which is the right scope for a presentation preference — and it avoids stacking a
migration on top of **036**, whose twice-applied dry-run is still owed. The cost is honest: a player on a second
machine sees the same releases marked NEW once more. That is the correct trade for a landing panel.

**`webui.keep_input` is not needed and was not added.** NCM's panel already takes full focus
(`setFocus(true, true)`), so the game is not receiving input anyway and there is nothing to reserve keys *from*.
`setConsumedKeys` would only matter for a surface that wants navigation keys **while gameplay keeps running** —
worth knowing we can, not worth a permission today.

## D.5 Glyphs, honestly

Controller brand is **not detectable**. So the default pad prompt is **layout-neutral position words** —
`CONFIRM` / `BACK` / arrows — which are true on every pad. `xbox` (`A`/`B`) and `playstation` (`✕`/`○`) styles
exist and are honoured, but only when set **explicitly**: `NcmNav.setPadStyle(style)`, ultimately a player
setting. Nothing infers a layout, because a wrong `PRESS B` on a DualSense is worse than a correct `BACK`.

This is the graceful fallback the brief asked for rather than a blocker: accessibility shipped, glyph polish can
follow a settings row.

## D.6 Existing interactive surface audit

Every interactive NCM surface is a mode of the one `panel.html` page, so wiring the nav scope into `show()`
migrated all of them at once rather than one at a time.

| Surface | Mouse | Keyboard | Gamepad | Focus visible | Scroll w/o mouse | Back/close |
|---|---|---|---|---|---|---|
| Landing (new) | yes | yes | yes | yes | yes — scroller registered | ESC · pad BACK · CONTINUE, all three |
| Race Guide | yes | **now** | **now** | **now** | list is focus-scrolled | ESC · pad BACK |
| Market | yes | **now** | **now** | **now** | focus-scrolled | ESC · pad BACK |
| Machine Index | yes | **now** | **now** | **now** | focus-scrolled | ESC · pad BACK |
| Driver File | yes | **now** | **now** | **now** | focus-scrolled | ESC · pad BACK |
| Help | yes | **now** | **now** | **now** | yes — `helpScroll` registered | ESC · pad BACK |
| Wheel/Pedals | yes | partial — **sliders keep their own key handling**, which is correct | directional nav reaches them; a slider still needs left/right, which the nav layer passes through | **now** | n/a | ESC · pad BACK |
| Questionnaire | yes | **now** | **now** | **now** | n/a | by design has no escape until answered |
| Messages/Inbox | yes | **now** | **now** | **now** | focus-scrolled | ESC · pad BACK |
| Race HUD | n/a | n/a | n/a | n/a | n/a | passive — correctly takes no focus at all |
| Driver Cards | n/a | n/a | n/a | n/a | n/a | passive |

The race HUD and Driver Cards are in the table to make a point the brief asks for: **gamepad accessibility does
not mean everything becomes modal.** Passive presentation stays passive, takes no focus, and polls no pad.

Remaining honest gap: the **hold-to-confirm** controls (`hold-btn`) accept `Enter`/`Space` keydown/keyup, so a
keyboard can hold them — a pad CONFIRM arrives as a synthetic click with no hold, so a pad player cannot
currently complete a hold-to-confirm action. That needs a pad hold timer feeding a press/release pair. Logged.

## D.7 Validation — what was actually tested

**Tested, and green:**

- `tools/nav-render-check.js` — **33 assertions**, new. Stubs a DOM with real `getBoundingClientRect` values and
  drives the layer as Lua and the keyboard do: focusable filtering (disabled, `aria-hidden`, `display:none`,
  zero-size all correctly refused), spatial navigation, list walking, Tab clamping, scroll-into-view, modal
  trapping and focus restoration, single activation, Enter left alone inside a text field, Escape left to the
  host, family switching without losing focus, and prompt painting.
- `tools/panel-render-check.js` — **148 assertions** (was 131). The landing panel's contract, capability states
  including a `partial` that must state its limit, the collapsed/expanded changelog, NEW marking, focusable
  changelog headers, and that an **unconfigured** panel still draws and still carries the contract.
- `ncm/core/tests/test_landing.lua` — **12 assertions** under Lua 5.4 and LuaJIT.
- Whole gate: **ALL GREEN**, 522 core tests, 226 resource files, 76 documents.

**It caught a real bug on its first run.** Spatial navigation used a bare half-plane test, so from a control at
the top of the screen, pressing **right** selected one 700 px *below* and 20 px across — because it was, technically,
to the right. A directional cone (`across > along * 2 + 40` unless the cross-axis bands overlap) fixed it. That
is precisely the failure the brief describes, and it would not have been found by reading the code.

**NOT tested, and this is the honest limit:**

- **No gamepad has touched this.** I cannot run the game. Every pad path — `isDown` edges, stick hysteresis,
  repeat feel, the BACK escape, family switching mid-panel — is **unvalidated in engine**. The harness proves
  the *translation* is right, not that the pad reads as expected.
- No mouse-only / keyboard-only / gamepad-only session was run; §31's matrix is owed in full.
- Repeat timings (340/130 ms) and the stick thresholds (0.55/0.32) are **reasoned, not tuned**. They will
  probably need adjusting the first time somebody holds a stick.
- The focus ring's position under CEF at non-1080p is unverified — the layer repaints on `resize`, but that is
  an untested mitigation for a named failure condition.
- `/ncm.input` exists precisely so the first live session can answer these in one command.

## D.8 A blocking defect found while integrating

Not mine and worth recording: `ncm/core/player/communication.lua` had been added to `MANIFEST.lua` but
**never vendored** — `tools/ncm-build.ps1` had not been run, so the file was absent from every resource's
`shared/core/` and absent from the `shared_script` list. `ncm_league/server/communication.lua` calls
`NcmCore.get("player.communication")` at file scope, and `NcmCore.get` **raises** on an unknown module, so
`ncm_league` would have failed to start on deploy. Fixed by running the build (`KB-159`). The build is
idempotent and a `-Check` run now reports no drift.
