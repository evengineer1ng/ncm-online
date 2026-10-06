# Racing Week site population: a seeded jigsaw over race sites

> **STATUS: RESEARCH (read-only)** - 2026-10-03. Answers the owner's "how do Minecraft villages get populated ...
> a seed system for day one, two and three ... let's look through WolvenKit". Feeds doc 45 §L
> ([45_RACING_WEEK.md](../../ncm-online/45_RACING_WEEK.md)). Nothing in production changed. Ideas IDEA-875 to IDEA-884.

## 1. How Minecraft actually does it (Java 1.14+)

Four separate mechanisms, and each one maps onto NCM:

1. **Placement from seed + salt.** Villages are one *structure set* (spacing 34 chunks, separation 8). For each
   region a candidate chunk comes from `hash(worldSeed, regionX, regionZ, salt)`, where the salt is unique to that
   structure type. Because each structure has its own salt, adding a new structure type does not move the
   existing villages. **NCM equivalent:** `Hash.key(seed, layer, ...)` with one namespace per layer (crowd, props,
   police, dialogue...). Adding a prop pool must not reshuffle the crowd.
2. **The biome picks the palette.** Plains, desert, savanna, taiga and snowy villages are the same algorithm with
   different *template pools*. **The Day is the biome:** same generator, different pools and weights.
3. **Jigsaw assembly.** A village starts from a `town_centers` pool. Every piece carries *jigsaw blocks*, named
   sockets that say which pool may attach there. The generator fills sockets recursively from weighted pools (depth
   limit, collision-checked). **Villagers are pieces too:** houses contain sockets into a `villagers` pool
   (unemployed, nitwit, baby), and there are `cats`, `animals` and `iron_golem` pools. Population is placed by
   the same grammar as buildings. *Processors* transform pieces as they are placed (mossify, crack, degrade), and
   a rare variant swaps the entire pool set (about 2% of villages are zombie villages).
4. **Then a runtime simulation takes over, keyed on anchors.** Villagers claim *POIs*: a bed (home), a job-site
   block (profession), a bell (meeting point). Breeding needs unclaimed beds. Golems and cats spawn from villager
   and bed counts. The village boundary is defined by its POIs, not by the structure. **NCM equivalent:** sockets
   are POIs; the Paddock's needs and schedule sim (`life.schedule`, `PaddockDays`) is the runtime.

Also worth copying: **generation is lazy.** A chunk generates only when a player first approaches it, and it is
still deterministic because it reads only the seed. The Paddock already materialises bodies only near players.

One honest difference: the same Minecraft seed gives a *different world in a different game version*. Seed
reproducibility is only as good as the content version pinned beside it (§5).

## 2. Runtime vs baked: what Cyberpunk and OPEN//77 actually allow

Sources: the hosted OPEN//77 MCP (**the index only answers for `2.31.13+op77.78`**; no index is published for the
running `2.31.21+op77.124`, so newer natives are unknown), the vanilla archives read with WolvenKit CLI 8.20.0, and
the code.

| Native thing | Runtime under OPEN//77? | Verdict |
|---|---|---|
| **Communities, phases, periods, AISpot markings** (`worldCompiledCommunityAreaNode`, `worldAISpotNode`) | **No.** Baked into streaming sectors; phases are switched by the quest system; no OPEN//77 native mentions communities or AISpots (search: no match). The population they produce is REDengine ambient population, which is **client-local** (CHARACTER_ARCHAEOLOGY VII.7): every player would see a different crowd, and the server has no seed control over it | **Don't use it as the controller. Harvest it as data** (§3) |
| Ambient crowd density | `Open77.world.setPopulation(bucket, { crowd 0..1, traffic, police })`, bucket-wide | A Day-level knob for anonymous filler pedestrians. Not per site and not shared identity |
| NCPD dispatch | `Open77.world.setPreventionEnabled(bucket, bool)` | A real Day-3 lever. It touches racing, so it needs a ruling |
| **Server NPCs** | `npcs.create`, `setAppearance`, `setEquipment(slot -> Items.*)`, `setBehavior`, `setDamagePolicy`, `whenReady`; replicated and the same for everyone | **This is the population** |
| **Scenarios** | `npcs.tasks.workspot(id, profile)` with 12 catalogue profiles: `smoke cigar drink phone dance handsup meditate sit clap cry think stretch`. A raw clip can go through the generic device as an escape hatch, but its animset may not load | Day 1 = clap/dance/handsup; Day 3 = think/cry/smoke. Vanilla cheer clips need experiment E2 |
| Barks | `npcs.speak(id, voContext)` from the NPC's own voiceset; no arbitrary text | Crowd murmur for free; written lines stay in the voice bank |
| **Props** | `props.create { model, appearance, light, scale, physics, streamingRadius, ttlMs }`; 8,192 registry, **2,048 per resource** | Dressing. A custom NCM banner `.ent` with appearances is *baked* (shipped via ArchiveXL, already a required mod) but *placed* at runtime |
| VFX | `effects.create/play` (server, looping or one-shot); `vfx.*` (client) | Day-1 celebration; catalogue has `q112_firework_01..04` |
| Audio | `sound.play/broadcast` (resource-shipped files, spatial); `audio.play3D` | PA, crowd beds |
| Ground | `world.groundZ` | already used by `PaddockDays` for bodies |

**The pool catalogues are already tagged.** `open77_data npc-templates` returns `categories` (crowd, police,
vendor, civilian, child...), `affiliations` (Factions.NCPD...), a `crowd` flag, `risk` (`candidate`,
`unsafe_quest_or_scene`, `restricted_child`) and appearance counts. Results: 481 match "crowd", 59 match "police".
A pool can therefore be a *filter* over the platform catalogue, for example
`crowd = true AND risk = candidate AND NOT restricted_child`. New templates join automatically, which is what the
owner's "add an archetype and every site gets it" needs. The props catalogue gives 66 banner meshes, 11 flags and
578 barrier meshes; the animations catalogue has 76 "cheer" clips.

## 3. WolvenKit findings: the game already authored our sockets, and our palette

**3,106 vanilla `.workspot` files.** By theme: cheer/crowd-wave 18 (one with flares:
`generic__stand_ground_flare__cheer__01`), **rail-lean 42** (barrier spectators: `concert\*__stand_rail_lean_*__cheer`),
argue 2 (**Claire's big race, `sq024_05_big_race\sq024__claire__stand__argue__01`**), protest 2
(`street\..._protest_sign__protest__01`), police 34 (`q005\patrol_stand_observe_crowd_cautious`), medic/trauma 14
(`sq024_05b_trauma_team\*`), phone 56, smoke 94, drink 85, sitting on the ground 78, leaning on a car 72. **The
vanilla game already contains Day 1 (cheer, flares, crowd wave), Day 2 (argue, police observing the crowd) and Day 3
(protest signs, trauma team) as authored scenarios.**

**AISpots around every race node:** `tools/harvest-site-sockets.py` reads the level-0 exterior sectors (64 m cells)
within 90 m of each of the 35 nodes in `data/nodes.lua` and records every `worldAISpotNode`: position, yaw and
the workspot it plays. **1,542 sockets** (evidence: [evidence/site_sockets.json](evidence/site_sockets.json)):

| Rich (100+) | Middling (20-100) | Bare (0-5): need authored sockets |
|---|---|---|
| Kabuki Bridge 283, Ebunike 126, Checkerboard 122, Japantown Crossway 121, Hanford Overpass 119, Parque Del Mar 118 (13 rail-lean, 2 cheer), Corpo Plaza 109 | Glenview Lofts 96, Downtown 57, Dogtown 50, Glen Straight 47, Arasaka 47, Chapel 42, Gold Niwaki 41, Pothole 31, Vista Del Drag 27, A bit 24, Deep Dive 24, Stadium 19 (7 police) | Trench, Allfoods, Hill Abode, Waterfront, Central Highway, North Tunnel, North Oak Ramp; **zero:** North Oak Tunnel, Coastview Highway, Tip, North Oak Ramp 2, Graveyard Shift, Little China Freeway, Go Smile |

Every harvested spot is a place CDPR already decided a person can stand, sit or lean, with a valid floor and a
facing direction. The markings were empty on the spots read. Classification comes from the workspot path
(`sit_chair` → seated spectator, `rail_lean` → barrier spectator, `stand`/`wall_lean` → standing spectator,
`vending` → vendor-adjacent, `police` → police). **This cuts the owner's 38-site walk roughly in half.** The walk
is still needed for what vanilla never placed: banners, PA, fireworks-safe zones, barriers, media and medical, and
the 14 bare sites. Ovals (`data/ovals.lua`) and the interior/quest sectors were not harvested in this pass.

## 4. Recommended design: the seeded jigsaw

```
socket map   (per site, authored once, versioned)   sockets { id, tags[], x, y, z, yaw, source = vanilla_aispot | walked }
palette      (per Day, the "biome")                 density ranges per tag, archetype weights, workspot weights, prop
                                                     appearance weights, VFX permissions, crowd fraction, NCPD dispatch
pools        (filters over tagged catalogues)       archetype -> npc-template filter + equipment sets + workspots + voice tags
processors   (per Day, on props)                    clean_festival -> worn -> torn; sponsor -> police_notice
generator    pure: (runSeed, day, siteId, layer, contentVersion) -> placements    (deterministic, testable offline)
materialise  near players only, under a body budget (PaddockDays presence pass pattern)
runtime      workspots, barks, voice-bank reactions (doc 45 §F), Paddock schedule for named people
```

**Rules:**
- **A palette is a distribution, never a filter to zero.** Day 3 keeps a small weight on `superfan`, so the
  contradiction happens naturally (owner, Day 3). The rare "zombie village" variant is the **Kimiko anomaly**: a
  whole Day-1 palette leaking into Day 3 at one site, with a glitch processor on its props.
- **One master seed per reconstruction**, salted per layer:
  `hash(runSeed, "DAY_n", siteId, layer)` for `layer` ∈ crowd, props, police, dialogue, ceremony, ambient.
  This is consistent with doc 45 W-1a: the historical seed (the Paddock's cast) stays fixed, and the reconstruction
  seed varies the dressing.
- **Named and anonymous are different populations.** Paddock people with schedules, rivals and contacts stay
  physical bodies from `PaddockDays`. The jigsaw fills the rest with anonymous archetypes. A site can mix both.
- **Budget first.** Today's precedent is `garageBodyCap = 18` (`ncm_paddock/server/settings.lua`). Props are capped
  at 2,048 per resource. A festival site is perhaps 15-25 bodies and 20-40 props, and only the site a player is
  near is live.
- **Pin the content version.** The archive (doc 45 §H) stores `runSeed + socketMapVersion + palette/pool table
  version`. Adding an archetype changes what a seed produces, as in Minecraft across versions. Reproduction means
  "this seed *at this content version*".

## 5. Experiments owed (dev only, in order)

| # | Question | Pass |
|---|---|---|
| E1 | 15 crowd-template NPCs at Corpo Plaza's harvested sockets running `clap/dance/drink/phone/smoke` | two clients see the same people in the same poses; client frame time recorded |
| E2 | Does a raw vanilla cheer clip play through the workspot escape hatch? | it plays, or the reason it doesn't is recorded |
| E3 | `world.getPopulation(bucket)` (owed since CHARACTER_ARCHAEOLOGY), then `crowd` at 0.3 / 1.0 | density visibly changes, and no shared-NPC regression |
| E4 | `props.create` with a vanilla banner mesh + appearance, and `effects.play` firework at a fireworks-safe socket | visible to both clients |
| E5 | Body budget: 10 / 20 / 40 bodies at one site | a defensible per-site cap |
| E6 | Re-query the MCP once a `.124` index exists (`npcs.capacity`, `npcs.presence` were unreleased at .78) | card diff recorded |

### Status 2026-10-03 (L301)

- **Probe built and loaded on dev:** `prototypes/ncm_dev_probe`. It is linked by junction from `tools/o77-server.ps1` and has an
  explicit `server.jsonc` entry, outside the `ncm/*` glob. Its data comes from `tools/gen-dev-probe-data.py`: sockets for
  Corpo Plaza, Parque Del Mar and Kabuki Bridge, plus a **626-record crowd pool**. That pool is filtered from the
  platform's `Character.*` catalogue (`https://open2077.net/data/npc-records-2.31.json`: crowd/civilian, risk
  `candidate`, no child, no vendor). Boot log `tools/open77/server/l306-restart-20261003.stdout.log`: `ready: 3 site(s), crowd pool 626`.
- Corrections from the cards: `npcs.create` takes `record = "Character.*"` (the 6,582-record catalogue), not a
  template path. `props.create` takes a raw `.mesh` path, and disabling a solid host's collision is unsupported.
  The server has no catalogue search; `Open77.data.npc` only looks one up.
- **E6 answered:** the MCP still publishes only `2.31.13+op77.78` (no `.124` index). Re-query after the next index.
- E1-E5 are console commands in Warden's live console; they await the owner in game (MASTER_TEST §RW1-§RW5).
- E7 (speed-limit margin semantics) is prepared in doc 45 §M. It needs a Pace publish with the game closed.

## 6. Unresolved

- Whether OPEN//77 lets a resource ship *its own* workspot profiles (the 12 come from `Open77RP.archive`). If
  yes, every vanilla spectator workspot becomes a clean profile.
- Community-sector harvest (`worldCompiledCommunityAreaNode` spawn sets, appearances per period). Not read;
  potentially a source of *what kinds of people* CDPR put at each place.
- The sockets' `markings` were empty in the sectors read; spots may be grouped by communities rather than
  markings. Irrelevant for harvesting, relevant if baked communities ever matter.
