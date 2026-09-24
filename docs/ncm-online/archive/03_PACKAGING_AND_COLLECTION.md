# NCM packaging: Nexus Collection × NCM Online

> **STATUS: SUPERSEDED** by 12_CANONICAL_VEHICLE_ROSTER.md + 13_VEHICLE_COLLECTION.md - kept for history. **Do not build from it.**
> Authority map: [INDEX.md](../INDEX.md) - classified 2026-09-24 (L125)

Date: 2026-09-19. Status: **provisional (P16), pending owner review**. Inputs: owner's NCM Collection candidate matrix and Vehicle Floodgates research logs 02–06 (owner's document, 2026-09); OPEN//77 `mods` and `server-mods` guides (evidence/2026-09-19).

## Platform facts this rests on

1. **Two disjoint launcher profiles.** OPEN//77 sessions run *Stack* (platform) + *World* (server-required mods). The player's own mods live in the *Solo* profile: "The Solo profile projects the player's own set and takes Open//77's out; *browse servers* puts it back. World files never appear in Solo." A Nexus Collection therefore never loads inside an OPEN//77 session, and an online session never needs it.
2. **Content-addressed store + player-fetch.** Required mods are pinned by archive SHA-256; a redistribution-refused mod is fetched once by the player from the author's page and thereafter recognised by hash for every world. A Collection that pins the *same Nexus files* pre-satisfies that fetch (how the launcher finds a Vortex-downloaded file: E13).
3. **Secured vs unsecured servers.** Secured: unverified required mods may contain inert data only (`.archive`, `.xl`, `.tweak/.yaml`, engine INI). Unsecured (`requiredMods.unsecured = true`): executable content (CET Lua, redscript, RED4ext plugins) may be required after an explicit UNSECURED badge + consent — intended for private/trusted communities. This corrects the orientation brief's flat "cannot ship CET/reds": true for secured servers only. L1 is unaffected (CET mods are not network-aware; NCM Online is still a resource set).
4. **Client-simulated physics** means every client in a world must run identical handling configuration; the world layer guarantees that online. The Collection's handling choices only matter in Solo.

## Runtime relationship

| | SP (Collection / manual) | Online, secured | Online, unsecured (trusted) |
|---|---|---|---|
| NCM runtime | the Nexus mod (CET + redscript) | `ncm_*` resources, auto-delivered | same |
| Vehicle mod: archive + `.xl` + tweak | loads | loads (hosted / player-fetch) | loads |
| Vehicle mod's CET/redscript/DLL features (RB15 ERS runtime + native plugin, VCD hooks, Live Tuning, Vehicle Core/Garage persistence, customizers) | loads | **absent** — model/record loads, scripted feature does not | loads with consent |
| Handling (MT, NCGT, Car Profile Tuner, Vehicle Physics Config, True Grip…) | one authority chosen by the Collection | only inert tweak/INI handling + platform performance ceilings | executable allowed; identical set for all clients |
| Ownership/commerce (VCD, Vanguard, Claim, Insurance) | Collection's domain | N/A — NCM provisioning + `getProperties` garages | same |
| Traffic population (Nova Traffic, Factions Evolved) | world texture | per-client anyway (L9); flavour only, never sporting truth | flavour only |
| Cameras, IWN, wheel/FFB | free | client assists, never required (L25) | same |

**Consequence for NCX:** on a secured server the RB15 runs without its ERS runtime/native plugin — a different car from SP. Pack #2 must decide (a) accept the inert RB15, (b) reference world unsecured, or (c) pursue verification. Recorded as OPEN Q24.

## Proposed shape (P16): one catalog, two channels

**NCM Content Catalog** — a versioned data file (`ncm/catalog/*.json`) that is the single source of truth for every curated third-party mod:

```
{ id, name, author, nexusModId, nexusFileId, version, archiveSha256,
  components: { archive, xl, tweak, ini, cet, reds, dll },
  worksWithoutScripts: true|false, lostWithoutScripts: "…",
  redistribution: allowed|refused|unknown,
  eligibility: sp-only | online-inert | online-unsecured,
  handlingAuthorityConflicts: [...], ecosystem: [...], classNotes: "…", verdict: KEEP|OPTIONAL|REJECT|NEEDS_TEST }
```

From the catalog:
- **Nexus Collection** (SP): tiers *NCM Core* (NCM + loaders + inert vehicle archives + the chosen inert handling baseline), *Driving* (MT, IWN, cameras, FFB — optional), *World* (dealers, persistence, traffic — optional, SP-only). Standalone mod page remains the canonical NCM version and the manual path.
- **Online packs**: required mods declared from the `online-inert` subset (plus `online-unsecured` for the reference world if the owner chooses), same hashes as the Collection pins.

What this buys: the same car at the same version in both worlds; SP and online driving feel converge through a shared inert handling baseline; Collection players pre-satisfy online player-fetch; the Collection can keep growing without touching online, and online can pin a small subset before the Collection is final.

## Costs and cautions for the Collection as main SP download

- Vortex is mandatory for Collections; support becomes Vortex support (the dev workflow stays manual per existing records).
- A car-heavy Collection is gigabytes of textures; free-tier Nexus throttling makes the first step slow.
- Every physics/dealer/persistence/bike-ecosystem mod is a conflict surface; the research logs already show forks (VCD vs Vanguard, NCGT vs modular stack, Bikes of the Dark Future vs Bike Overhaul). Curation = authority decisions: one handling owner, one ownership/commerce owner, one bike ecosystem. NCM's own compatibility model (master plan P2.6 healthy/degraded/blocked) should detect which tier is present.
- Collection revision = SP compatibility contract; record it in bug reports the way the server digest is recorded online.

## Additions to the owner's evaluation template

`executable components (which; what they do)` · `works without CET/redscript? (+ what is lost)` · `Nexus file id/version/hash` · `redistribution permission` · `handling authority conflicts` · `eligibility class`.

## Plan impact

- Does **not** block M0.1.
- E13 gains: (i) whether the launcher recognises a Vortex/Nexus-downloaded archive for player-fetch without re-download; (ii) unsecured-mode join flow with one executable package; (iii) inert-only RB15 behaviour (archive + tweak, no ERS) on a secured dev server.
- Pack schema (M1) references catalog ids; `tools/` gains `catalog → requiredMods/preload_mod` generation when packs are built (M3/M7).
- OPEN Q24 (NCX/RB15 without ERS; secured vs unsecured reference world) and Q25 (Collection handling baseline = online inert baseline?) added to the decision record.
