# NCM Driver Identity / Nameplate Recovery Audit

> **STATUS: HISTORICAL / RESEARCH** — recovery and feasibility audit, not implementation authority.
> Current authority remains [docs/ncm-online/INDEX.md](../../ncm-online/INDEX.md), its linked documents,
> the decision record and runtime code. Audited 2026-09-24. No runtime, schema, configuration, deployment,
> save, API or gameplay behaviour changed.

## Executive conclusion

Phase 2 is technically buildable after a small owner review and the missing art is supplied. The original
concept survives clearly enough to recover the product shape:

1. a compact floating Driver Card;
2. platform-verified readable identity;
3. an accomplishment-unlocked, player-curated banner and a **few** featured badges;
4. a tiny, immutable radar/spider **Driver Fingerprint** derived from actual behavioural history;
5. a full Driver Profile containing the labelled version and the receipts behind the compact card.

The recovered design does **not** establish a maximum of three badges, a standardized far-right Fingerprint
region, exact final dimensions, or final Fingerprint calculations. The only surviving axis set is explicitly
marked **candidate placeholders, not locked**: Competition, Street, Craft, Chrome, Contact/aggression and
Experience. No normalization, sample window, insufficient-data rule, update cadence or anti-gaming formula
survives. Those are real design decisions still owed; filling them in during implementation would be invention,
not recovery.

OPEN//77 has the necessary presentation primitives now. The smallest honest first release can show verified
username, a fallback/selected banner, a bounded set of selected earned badges, and an explicit
**insufficient data / Fingerprint unavailable** state until the Fingerprint definition is ruled. There is no
need to block the entire card on invented zero-valued axes.

## Evidence labels used here

- **RECOVERED HISTORICAL DESIGN** — preserved intent, usually in the append-only idea ledger; not promoted to
  current authority by this audit.
- **CURRENT AUTHORITATIVE DESIGN** — a CURRENT document or locked decision in the authority map.
- **CURRENT IMPLEMENTATION** — verified in present code/schema/assets. Static inspection is not a live PASS.
- **MISSING / UNRESOLVED** — no surviving answer or implementation found.
- **RECOMMENDATION** — the smallest proposed bridge to a buildable Phase 2; not a decision.

## Recovery map

| Subject | Strongest surviving source | What it establishes |
|---|---|---|
| Driver Card / Fingerprint | [`BACKLOG.md`, IDEA-069–071](../../ncm-online/BACKLOG.md) | Three layers, behavioural not moral/skill, candidate axes, compact/full-profile split |
| Nameplate use case | [`BACKLOG.md`, IDEA-063](../../ncm-online/BACKLOG.md) | Inspecting a nearby driver before accepting a challenge |
| Chrome relationship | [`06_CHROME_ROSTER.md`, “Driver Fingerprint relationship”](../../ncm-online/06_CHROME_ROSTER.md) | Chrome records usage history, not competence |
| Notoriety badge | [`BACKLOG.md`, IDEA-078](../../ncm-online/BACKLOG.md) | Permanent historical fact can coexist with curated display |
| Asset/layout contract | [`BACKLOG.md`, IDEA-080 and IDEA-085](../../ncm-online/BACKLOG.md) | ~240×80 concept, no blur, banner masters/crops, SVG/font rules, no baked text/rules |
| Banner/badge progression | [`BACKLOG.md`, IDEA-082](../../ncm-online/BACKLOG.md); [`DECISION_RECORD.md`, L74–L75](../../ncm-online/DECISION_RECORD.md) | Prestige ladder and permanent aggregate invariants |
| Driver number | [`DECISION_RECORD.md`, L73](../../ncm-online/DECISION_RECORD.md) | Preferred racing number is part of Driver Card identity |
| Machine presentation | [`17_MACHINE_PROFILE.md`](../../ncm-online/17_MACHINE_PROFILE.md) | Model knowledge vs asset history vs owner-curated profile |
| Vehicle art sourcing | [`15_GENERATION_1_VEHICLE_ARTWORK_MANIFEST.md`](../../ncm-online/15_GENERATION_1_VEHICLE_ARTWORK_MANIFEST.md) | 27-model source mapping and licensing/provenance cautions |
| Public/private replication | [`29_STATE_BAG_AUDIENCE_AUDIT.md`](../../ncm-online/29_STATE_BAG_AUDIENCE_AUDIT.md) | `player(id)` bags are bucket-public, not private |
| Current telemetry | [`31_CAPABILITY_AUDIT.md`](../../ncm-online/31_CAPABILITY_AUDIT.md) | Server/client evidence split and fields now exposed |
| Old API capture | [`evidence/ns-nameplates.txt`](evidence/ns-nameplates.txt) | Build-pinned `.78` nameplate namespace, including historical `setTalking` |
| Current shipped renderer | [`open77_nameplates/client/main.lua`](../../../tools/open77/server/resources/system/open77_nameplates/client/main.lua) and [`policy.lua`](../../../tools/open77/server/resources/system/open77_nameplates/client/policy.lua) | Native-first renderer, fallback WebUI stream, distance/policy and through-wall risk |

Git contains no pre-initial-import recovery layer: the relevant ledger material first appears in repository
commit `010f65f`, and no older branch or hidden commit contains the missing mockups/catalogues. Repository-wide
asset searches found only the current system glyph sheet and unrelated RB15 livery badge textures.

## Original Driver Card / nameplate design

### RECOVERED HISTORICAL DESIGN

IDEA-070 specifies a compact floating identity card replacing the plain username above a remote player or
their vehicle, in three layers:

1. **Authoritative identity.** The platform-sourced name remains readable. Harsh truncation that makes names
   ambiguous was rejected; a slow horizontal pan inside the name region was preferred, with exact UX still TBD.
2. **Curated expression.** Accomplishment-unlocked banners, stickers, badges, emblems, titles and decorations.
   The driver chooses one banner and a **few** featured badges. Curating the visible story is allowed; changing
   the historical record is not.
3. **Immutable Fingerprint.** A tiny, non-editable radar/spider polygon showing actual behavioural history.
   Labels and numbers do not belong on the floating card; the full labelled form belongs in the profile.

IDEA-080 records a working target of approximately **240×80 pixels**, at a fixed 1920×1080 WebUI canvas,
without blur. It is an asset/performance contract rather than a final signed-off layout. Banner art was to be
crop-tested at 4:1 and 6:1 on the card; IDEA-085 therefore prohibits baked-in wordmarks that the crop would cut.

### MISSING / UNRESOLVED

- The remembered **three-badge maximum** is not recovered. The source says only “few.”
- The remembered fixed, high-contrast **far-right Fingerprint region** is not recovered in text or assets.
  It is compatible with the legibility/comparability goal, but remains owner memory until the external mockup
  confirms it.
- Exact internal regions, sizes, badge placement, long-name timing and vehicle-versus-character anchoring are
  not locked.
- No original card mockup or banner concept file exists in the repository.

### RECOMMENDATION

Treat the three-layer composition as recovered, the ~240×80 size as a starting constraint, and the badge count
and right-side standardized region as two explicit owner confirmations against the external artwork. Do not let
banner artwork overlap the eventual Fingerprint rectangle; that is a sound implementation constraint, but it
must be recorded as a new ruling rather than mislabelled as recovered fact.

## Driver Fingerprint recovery

### RECOVERED HISTORICAL DESIGN

The Fingerprint is public social evidence, not progression:

- server-measured/retained behavioural history;
- immutable and non-editable by the player;
- descriptive, not a morality judgement;
- activity/tendency, not skill, power or competence;
- compact unlabeled silhouette on the card, full labelled form in the Driver Profile;
- deliberately able to contradict curated cosmetics (for example, an innocent banner with a large Chrome /
  contact history).

The only surviving axis list is exactly six **candidate placeholders, not locked**:

| Candidate axis | Recovered historical meaning |
|---|---|
| Competition | Participation in sanctioned/competition activity, not success or skill |
| Street | Participation in street activity, not notoriety or morality |
| Craft | Tuning/building/garage involvement, not tuning competence |
| Chrome | Frequency of vehicle-hacking/cyberware engagement, not hacking skill |
| Contact/aggression | A contact-heavy/aggressive history, not ability; the combined label itself was provisional |
| Experience | General NCM/driving experience, not driver rating |

IDEA-069 also names clean driving as recorded history, but it was not made a seventh candidate axis. The Chrome
spec reiterates that a large Chrome axis means frequent use, never expertise. IDEA-078’s destruction/skull badge
is a separate earned historical artifact, not a Fingerprint formula.

### MISSING / UNRESOLVED

No surviving source defines:

- whether the six candidates became final, or even whether the final graph has six axes;
- formulas, weights, denominators or normalization;
- lifetime versus rolling/recent/event-specific windows;
- minimum sample size and the visual treatment of insufficient evidence;
- update cadence;
- how race type, distance/time exposure, DNF/DNS or free-roam activity affect a value;
- anti-farming/anti-gaming rules;
- whether Contact and aggression are one dimension or two ideas accidentally sharing one placeholder;
- how clean driving contributes;
- a version identifier for the definition.

The word “immutable” means the player cannot edit the result; it does not prove values never evolve as history
accumulates. “Behavioural history” and the later durable-aggregate badge rule suggest cumulative settlement
facts, but that is an inference, not a recovered window definition.

## Can today’s NCM compute the candidate Fingerprint?

It can compute useful ingredients for three candidates, cannot compute two, and cannot honestly compute
aggression. Because all six labels are provisional and the maths is absent, **none of the six can yet be called
the recovered Fingerprint**.

| Candidate axis | Required evidence | Evidence today | Authority / persistence | Derivable now? | Missing substrate |
|---|---|---|---|---|---|
| Competition | Settled sanctioned participation plus a stable activity classification | Events, sessions and results exist; disciplines/series carry tier intent in definitions | Server settlement is authoritative; result rows persist. `event` does **not** persist `tier` | **Ingredient only** | Lock meaning/formula/window; persist the event’s street/sanctioned classification at settlement so history does not depend on today’s catalogue |
| Street | Settled street participation plus stable classification | Same as Competition | Same; current definitions can classify today, but old rows are not self-describing | **Ingredient only** | Same, including mixed/`both` rules |
| Craft | Tuning/building/garage actions | Engineering/components/crafting are specs, not live systems; no activity ledger | None | **No** | A future authoritative engineering/action ledger; do not proxy this with ownership |
| Chrome | Eligible hacking attempts/outcomes/usage | Platform capability is researched, but NCM hacking is not loaded or implemented and no transition ledger exists | None | **No** | Implemented Chrome mechanics and durable server-side transition aggregates |
| Contact/aggression | Contact events, exposure denominator, and—if “aggression” is retained—an honest intent/blame signal | `incident` persists kind, band, delta-v, other driver, time/position and machine attribution; sessions/results provide denominators | Server-derived and persistent, though fed partly by client-attested samples | **Contact tendency: ingredient only. Aggression: no** | Formula/window/minimum sample. Current zero-fault incident policy explicitly records both cars and does not infer blame or intent; it cannot support “aggression” |
| Experience | Defined unit of experience | Starts/finishes/results, DNF/DNS, licences, ratings and accomplishments persist | Server-settled and persistent | **Race experience ingredient only** | Define the unit/window. General motoring experience needs the unbuilt always-on driving ledger (IDEA-081) |

### Important evidence limits

- Client race telemetry persists at 5 Hz as position, speed, gear, on-ground and health chunks. The new
  throttle/brake/steering HUD reads richer client fields, but those inputs are **not** in persisted telemetry.
- The server has velocity/angular velocity; the client has drivetrain/input fields. The split is relevant to
  future driving analysis, not a reason to invent Fingerprint axes.
- Incidents use a deliberately zero-fault rule: both cars carry a car-to-car event. Frequency/severity can
  describe contact exposure; it cannot prove aggression.
- The `clean_race` accomplishment still exists in current progression code even though the Race Tags spec wants
  that concept moved to an ephemeral post-event descriptor. It is not a safe long-term Fingerprint source until
  that authority/build discrepancy is resolved.
- Use settled facts or durable derived aggregates for a public Fingerprint. Do not publish raw telemetry or
  client inputs merely because they are available.

### RECOMMENDATION

Before writing the first real Fingerprint value, rule and version a compact definition containing: ordered axes,
meaning, evidence source, normalization/window, minimum sample, missing-data representation and update point.
Persist the activity/tier facts that calculations depend on at settlement. Never render “unknown” as zero. A
`definitionVersion` is cheap now and prevents silently comparing polygons calculated under different rules.

## Banners

### RECOVERED HISTORICAL DESIGN

- Main visual treatment of the Driver Card and part of profile presentation.
- Unlocked by accomplishments, with a deliberately dull default and 12 launch banners proposed.
- Master format: 3:1 at 1536×512; ship no larger than 768×256; keep masters outside `web/`.
- Crop-test at 4:1 and 6:1; do not bake wordmarks/rules/key bindings into art.
- A later Machine Profile spec also permits an owner-curated machine banner.

### CURRENT IMPLEMENTATION

No banner catalogue, IDs, names, categories, entitlement rows, selected/current field, fallback asset or banner
files exist. The historical concept did not collapse definition, entitlement and selection into one record, but
it never specified their storage.

### MISSING / UNRESOLVED

The external concept artwork, stable IDs, launch catalogue, acquisition rules and default banner identity are
missing. Machine banners are later SPEC intent, not evidence that the old driver banner catalogue was shared.

## Badges

### RECOVERED HISTORICAL DESIGN

- Earned historical collection and displayed selection are distinct. Hiding a badge never deletes it.
- Prestige ladder: Bronze → Silver → Gold → Diamond → Purple; cumulative behaviour; never downgrades.
- One badge SVG plus five frame overlays; tier frames are not baked into art.
- Prestige counters are durable settlement aggregates, not recomputed from retained raw telemetry.
- Badges never revoke once beta permanence begins; alpha data remains disposable under L75.
- Unlock reveals queue for a safe menu moment, never over the race HUD.
- Unique/non-prestige examples: First Race, First Win, All Regions, Rare Find, Secret family, dated Special Event,
  True Driver. The skull badge records eligible Chrome destruction.
- IDEA-082 claims roughly 40 marks, five frames and per-tier flavour text, but none of that catalogue/copy/art is
  present on disk. Its “derivable today” examples are design claims, not implemented badge rules.

### CURRENT IMPLEMENTATION

The generic `accomplishment` table and driver progression can persist one-time driver facts (`first_finish`,
`first_win`, `first_time_trial`, `clean_race`). This is useful award substrate, but it is not a badge catalogue,
prestige counter, entitlement model or displayed selection. The WebUI glyph sheet contains system/race glyphs,
not badge artwork.

### CURRENT AUTHORITATIVE MACHINE DIRECTION

The Machine Profile SPEC agrees with the old driver split: complete earned distinctions follow the serialized
machine, while the current owner may feature a few without editing history. It extends the old material; it does
not conflict with it. Machine-earned accomplishments, presentation selection and transfer/edit handling are not
built. Current migrations now attribute new results and incidents to `asset_id`, so future machine competition
history is possible for post-migration records; 29 earlier completed results remain unattributable.

### MISSING / UNRESOLVED

Badge catalogue, art, category IDs, tier thresholds, flavour copy, entitlement/counters, displayed selection,
machine award ledger, profile/nameplate selection-sharing rule and the maximum displayed count. “Three” is not
recovered.

## Driver Profile

### RECOVERED HISTORICAL DESIGN

The profile is the “back of the trading card”: all earned badges, racing history, sanctioned and street history,
records, driving and behavioural statistics, a full labelled Fingerprint, and vehicle/career information. It is
the receipts behind the curated card. No biography, teams panel or global searchable directory was specified in
the recovered Driver Profile item.

### CURRENT IMPLEMENTATION

- Durable NCM Driver UUID bound per server to OPEN//77 `userId`.
- Stored display, preferred racing number, dimensions and safety document in `driver_profile`.
- Licences, class ratings, safety aggregates, accomplishments, results and incidents.
- `/ncm.profile` is a chat summary of progression, not the recovered visual profile.
- The onboarding questionnaire document is explicitly “never shown”; it is not a personality/profile biography
  and must not be repurposed as one.

OPEN//77’s current identity contract distinguishes durable `userId`, session `playerId`, and editable but
Master-verified `displayName`. NCM binds the durable identifier correctly. Existing profiles retain their stored
`display` on reconnect rather than refreshing it after a platform rename, so the nameplate should use the current
platform-verified stream/player name for presentation unless NCM deliberately adds a rename-sync policy.

## Machine Profile and machine biography

### CURRENT AUTHORITATIVE DESIGN

[`17_MACHINE_PROFILE.md`](../../ncm-online/17_MACHINE_PROFILE.md) is SPEC, not implementation authority. It
separates:

- Machine Index: knowledge about a model;
- authoritative asset history: facts about one serialized machine;
- Machine Profile: how the current owner presents that machine.

Authoritative material includes model/manufacturer, three production ordinals, odometer, production date,
lifecycle, owner count and eventual race history. Owner-curated biography, banner and featured distinctions are
unbuilt. The profile follows the car; owners cannot edit facts; all earned versus featured distinctions remain
separate; stored data is not automatically public.

The newer request that biography passes with the machine and may be edited by the new legitimate owner is a
reasonable extension, but that exact transfer/edit rule is not recovered from the existing SPEC. It requires a
future explicit ruling and moderation/length/escaping limits.

## Vehicle/model artwork and glyphs

### CURRENT AUTHORITATIVE DESIGN / RESEARCH

The vehicle artwork manifest maps all 27 Generation 1 conceptual machines to preferred Cyberpunk Wiki vehicle
icons/database art, with a Wikimedia exception for the RB15 and explicit mapping/licensing cautions. It is source
research, not a shipped asset pack. No normalized `collection/<vehicleKey>/...` files were found.

### CURRENT IMPLEMENTATION

`ncm_world/web/glyphs.js` and `glyphs.manifest.json` contain the first live-bound 24-grid system glyph tranche:
street/sanctioned, route/race states, actions and several deliberately unbound future glyphs. The stable
`currentColor`/controlled-palette contract exists. It contains no Driver Card badge catalogue, banners, NCM/NCX
marks, team badges or bundled webfont. RB15 `rb15_badges_*.png` files are vehicle livery textures, not player
badges.

## Current nameplate readiness

| Need | Current surface | Finding |
|---|---|---|
| Nearby/streamed players | `Open77.players.all({streamed=true})`, `nearby`, `closest` | Supported; client view is streaming-scoped, not a server roster |
| Player-to-NCM Driver association | Public `ncm` key on `Open77.state.player(playerId)` | Already exists: `driverId`, display, number, reputation, SR |
| Verified username | Nameplate stream label / `Open77.players` name; server `GetPlayerName` | Supported and Master-verified; use current presentation name, not session id |
| Frame-tight world attachment | `Open77.nameplates.stream(page)` | Supported; emits `{id,label,color,x,y,distance}` to an owned page every frame without Lua on projection path |
| Rich card rendering | Transparent NCM WebUI page | Supported; native `render(true)` is text-only and cannot draw banners/badges/radar |
| Public presentation state | Server-written player state bag | Supported, but visible to everyone in the same routing bucket; publish only intentional public projection |
| Join/leave/body transitions | Nameplate/player stream plus bag lifecycle | Supported; key by session `playerId`, re-resolve bodies, remove DOM rows when absent |
| Distance/visibility | Native nameplate projection and overrides | Supported. Current default is 35 m; shipped policy warns it has no geometry occlusion and can draw through walls |
| Existing NCM WebUI | Race/panel/venue pages and shared glyph helper | Rendering techniques reusable; no existing page is an always-on nameplate surface |
| NCM manifest permission | None for nameplates | `ncm_world` currently lacks `ui.nameplates` and an `open77_nameplates` dependency |

Current official platform evidence:

- [Player identity](https://open2077.net/docs/identity) — durable `userId`, session `playerId`, editable verified
  `displayName`.
- [Players around you](https://open2077.net/docs/client-players) — streaming-scoped players, bodies, positions,
  distances and names.
- [Drawing in the world](https://open2077.net/docs/world-drawing) and
  [`Open77.nameplates`](https://open2077.net/docs/api/client/open77-nameplates) — native rendering or per-frame
  streaming to an owned WebUI page.
- [Replicated state bags](https://open2077.net/docs/state-bags) — player bags are bucket-wide, server-authored,
  snapshotted on join/bucket change and delta-updated thereafter.

### The renderer coexistence issue

The shipped `.87` `open77_nameplates` resource now calls `Open77.nameplates.render(true)` first and creates no
WebUI page when native drawing succeeds. A rich NCM card therefore cannot merely style that resource’s current
page; NCM needs its own page and must suppress the native text drawer to avoid duplicates. The system resource
exports `setEnabled`, but a bounded live/reload probe must prove the ownership/coexistence sequence:

1. disable the shipped native drawer;
2. start NCM’s owned stream/page;
3. preserve its policy overrides and visibility rules;
4. restore the native drawer if NCM stops or page creation/streaming fails.

This is an integration proof, not an architectural blocker. The old `.78` capture lists `setTalking`; the current
public generated reference lists seven functions and omits it, while the shipped `.87` voice resource still calls
it and the fallback page still consumes a `talking` flag. Voice indication should therefore be treated as a
build-pinned probe, not promised from the stale capture.

### Privacy and visibility boundary

A nameplate presentation projection is intentionally public within proximity/bucket. It may contain only what
the card needs, for example:

```text
schemaVersion
bannerId
displayedBadgeIds[]
fingerprint { definitionVersion, values[], sampleState }
```

The verified name and transient player id already come from the platform; `driverId`/number already exist in the
small public NCM view. Do **not** add the earned badge collection, detailed history, telemetry, machines, Machine
Knowledge, onboarding answers, biography drafts, eligibility, market knowledge or private profile data. Selection
requests, if later allowed from clients, require server validation against earned entitlements; the public bag is
the server-authored result, never the request channel.

## Smallest Phase 2 implementation plan — recommendation only

No step below was implemented by this audit.

1. **Owner recovery checkpoint.** Supply the original card/banner concepts and any badge/Fingerprint material.
   Explicitly rule only what recovery cannot: badge display limit, fixed Fingerprint region/layout, and whether
   the six candidate axes remain candidates or become the version-1 definition.
2. **Tiny asset definition layer.** Stable banner/badge IDs with assets and a default fallback. Keep definition,
   earned entitlement and selected display state separate. Do not build the whole prestige system to show a
   baseline banner.
3. **Presentation state.** Store selected banner and bounded badge IDs separately from earned facts. Server
   validates selections; publish one versioned, compact, intentionally public projection.
4. **Fingerprint only after definition.** Derive versioned values from durable settled aggregates, with explicit
   insufficient-data state. Until then publish `sampleState = unavailable` and render the designed fallback,
   never six zeros.
5. **Dedicated nameplate page.** Add an NCM-owned transparent always-on WebUI surface, using the platform stream
   for screen coordinates and the public projection keyed by session `playerId`. Reuse NCM typography/glyph
   conventions, not the race page’s lifecycle.
6. **Preserve platform policy.** Keep the existing default distance and visibility/policy behavior; do not widen
   the through-wall exposure. Disable the native renderer only after the custom page is ready; restore it on
   teardown/failure.
7. **Bounded proof.** Test two clients: join/leave, stream-in/out, body recreation, bucket transition, reload,
   long and non-ASCII names, missing/invalid assets, insufficient Fingerprint data, distance/behind-camera cull,
   duplicate suppression, and native fallback restoration.

## Genuine blockers and owner-supplied material

There is **no OPEN//77 capability blocker** to a first working card.

Full fidelity needs the following external/recovered inputs:

- original Driver Card/nameplate mockup, especially any fixed right-hand Fingerprint region and badge count;
- banner concept masters plus intended IDs/names/default, if those existed;
- badge masters, five prestige frames, catalogue, thresholds and flavour copy, if authored externally;
- any annotated Fingerprint source or notes containing final axes/formulas/window/insufficient-data rules;
- canonical NCM/NCX/RC marks and the intended bundled OFL font if not yet in the repository.

Vehicle artwork is not required for Driver Nameplate Phase 2. Its source manifest survives, but normalized art
files do not.

## Conflicts and stale assumptions

- The six Fingerprint labels are placeholders, not final axes. Treating them as locked would overstate history.
- “Three badges” and the fixed far-right region are owner recollection, not recovered repository authority.
- The historical mechanism note assumed the WebUI stream was the primary renderer. Current shipped OPEN//77
  prefers native text rendering; rich cards require a deliberate handoff.
- The historical `setTalking` reference is not in the current public generated namespace despite current shipped
  resource usage; probe it on the pinned build.
- The Machine Profile document’s statement that results lack asset attribution is stale relative to migrations
  024/026 and current settlement code. Attribution is now forward-looking; historical unattributed results remain
  unknown.
- Current NCM’s stored display may lag a platform rename. Platform identity remains the presentation authority.
- Current incident data measures contact without fault. Calling it aggression would contradict the zero-fault
  sporting invariant.
- A player state bag is public to the bucket, not personal. It is suitable for a deliberately narrow nameplate
  projection and unsuitable for the full Driver Profile.

## Starting-line verdict

After owner review, Phase 2 needs one art handoff, three narrow design rulings, a small presentation-selection
model and one renderer-coexistence probe. It does **not** need another general platform audit, a global directory,
the full Driver Profile, Machine Profile, prestige economy, driving ledger, Chrome implementation or a completed
Fingerprint before the first honest nameplate can exist.
