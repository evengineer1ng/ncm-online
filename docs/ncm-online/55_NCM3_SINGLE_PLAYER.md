# 55 - NCM 3.0: the single-player product, Race Week tapes, the NCM Host

> **STATUS: CURRENT** - authority for: *NCM 3.0 single player -- the NCM Host runtime, Race Week tapes and offline canonical time, the front door, the seam report toward a Nexus release* - affirmed 2026-10-07 (L338); the Online port programme, §12, 2026-10-17 (L370)
> Decision: [DECISION_RECORD.md](DECISION_RECORD.md) L338. Authority map: [INDEX.md](INDEX.md).

**In one paragraph.** NCM 3.0 is a single-player Cyberpunk 2077 mod with a curated Nexus Collection around it. It is
built from what the development server runs today, minus the network: the same `ncm/online/resources/*`, unchanged,
hosted INSIDE Cyberpunk by the **NCM Host** (a CET mod) that implements the slice of the OPEN//77 API the resources use,
over SQLite instead of MariaDB. A **tape** is one NCM continuity: its own Race Week clock, seed and history, stored as
its own `server_id` in that database. Race Week keeps time while nobody plays; on return the present is
**calculated** -- every verdict missed is judged in order from the seed (`week.catchup`), never simulated second by
second. The OPEN//77 dev server is untouched in role: the laboratory and the running test universe.
**Nothing here has a live PASS yet** (L69): MASTER_TEST §TP is NOT RUN.

---

## 1. The product boundary (owner direction 2026-10-07)

| Piece | What it is | Owns |
|---|---|---|
| **NCM 3.0** | single-player mod (`dist/ncm-3.0.0-alpha.1.zip`, a CET mod folder `mods/NCM`) | the simulation: machine identity, Race Week, the clock, NPC history, engineering, knowledge, location, resources, provenance, Deep state |
| **NCM: The Collection** | a curated Nexus Collection of compatible third-party mods (vehicles, dependencies) | nothing canonical; NCM must work without any optional item |
| **OPEN//77 dev** | the laboratory and personal running universe | its own server_id world; never the single-player UX spec |
| **Cyberpunk** | the front door and home | -- |
| **AC / GTA / KSA / later hosts** | optional physicalizers of places in the same continuity | never the save, the clock or machine identity |

The question every major system now answers: **what is canonical NCM simulation, and what exists only because OPEN//77
hosts it today?** The former moves host-independent (core, or resource code that runs on both hosts unchanged).

---

## 2. What existed before this pass (audit, 2026-10-07)

### 2.1 The old single-player mod (`ncm-localized/`, "NCM 2.0", frozen by owner ruling)

Kept as published; NOT the base of 3.0 (owner: "dont mangle sp to redo sp"). What the audit found, for the record:

| Question | Finding |
|---|---|
| What it does | CET Lua (52 modules: races, AI rivals, careers, 870-driver seeded roster, championships, ambient races, heat, betting, tuning, parts) + 7 redscript files (HUD, pins, journal/SMS). `init.lua:11` says 0.1.0; README says 2.0. |
| Persistence | Global JSON under `MT_Ecosystem/save/` (`persistence.lua`; `.bak` fallback; NOT atomic: truncate-then-write). **One career shared by every Cyberpunk save**; no save-slot awareness; money and street cred live in the CP save, careers do not. |
| Time | No Race Week. Seasons count races (8). Ambient races run on GAME time; `lastClock` stored but never compared (a reloaded older CP save is not handled). Roster catch-up sim by real time (1 race / 240 s, cap 100). |
| Server assumptions | none (it predates OPEN//77) |
| Global seed | per-career seeds; `os.time()` folded into season seeds |
| Irreversible mutations | eddies (`Game.AddToInventory("Items.money")`), street-cred XP, ~30 `ncm_*` quest facts (reset on load), **TweakXL rival yaml + .xl written into the GAME folder** (`named_rivals.lua`; shipped yaml hard-coded to seed 1776881178), TweakDB drive flats (restored on vehicle exit, not on shutdown), traffic density 0 during races (restored) |
| Fixed catalogue | `data/vehicle_pool.lua` TweakDB record list; unknown records default to prestige 2; no asset_id |
| Tape support | none; no tests; no deploy script |

### 2.2 The dev stack (OPEN//77)

`Open77.Server.exe` (.NET, Lua 5.4 per-resource VMs) + MariaDB 10.11.14 + the OPEN//77 client plugin (RED4ext, CEF
WebUI) + the launcher (master tickets, requiredMods projection). NCM = 11 resources, ~37k server / ~11k client Lua,
~220 distinct `Open77.*` functions, ~600 `MySQL.*.await` calls, 70 migrations / 140 tables, everything keyed by
`server_id`. Client code reaches the game ONLY through `Open77.*` (no CET-style `Game.*`).

**Why the in-game host and not a bundled local server (owner ruling, L338):** a bundled `Open77.Server.exe` is
PolyForm-Noncommercial, gated (Developer Preview access, license key), needs the OPEN//77 client and launcher and a
MariaDB -- not a Nexus mod over a normal save. The resources themselves are almost entirely in the LuaJIT ∩ Lua 5.4
intersection (one hash fixed, KB-380; `table.unpack` supplied per VM), so CET can host them.

---

## 3. The NCM Host (built, `ncm/host/`)

```
mods/NCM/                      (CET mod; tools/ncm-host-build.ps1 stages + zips it)
  init.lua                     CET entry: deck at the main menu, mount on save load, unmount on leaving, HUD line
  host/app.lua                 tapes + one mounted world; database bring-up; the dev Time Lab
  host/runtime.lua             per-resource VMs (server/client halves isolated), scheduler with a per-frame budget,
                               events + the "network" queue, GlobalState, state bags, convars, commands, exports
  host/api/headless.lua        Open77.* over a world model (player, vehicles, NPCs, blips, environment, tunables);
                               unknown calls COUNTED (`unsupportedList`), never silent
  host/game/cet.lua            the model bound to Cyberpunk (P2: player sync, teleport, pins, waypoint, toasts)
  host/sql/translate.lua       MariaDB -> SQLite statement translation (§4), typed parameter inlining
  host/sql/schema.lua          the migrations REPLAYED into a model, emitted as SQLite, synced (create / append / rebuild)
  host/sql/mysql.lua           OPEN//77's MySQL.* (query/single/scalar/insert/update/transaction) over a driver
  host/sql/driver_cet.lua      CET `db` (the game);  driver_ffi.lua (LuaJIT FFI; tests only, not shipped)
  host/clock.lua               one clock: real (+ dev skew, + regression floor) or virtual (tests)
  host/tapes.lua               the tape index (atomic write, .bak), present-time arithmetic for the deck
  host/ui/deck.lua             the front door (§6)
  resources/<ncm_*>            ncm/online/resources/*, BYTE-IDENTICAL (build -Check verifies 1,314 Lua files)
```

**Resources shipped:** ncm_league, ncm_world, ncm_paddock, ncm_speed, ncm_broadcast, ncm_scanner, ncm_observer, ncm_aero; since L370 also ncm_universe, ncm_engineering, ncm_workshop, ncm_build, ncm_slipstream, ncm_sky, ncm_audio, ncm_radio (16; `App.RESOURCES`). The archive carriers (ncm_world_layer, ncm_race_week_map, ncm_earth_underlay, ncm_build_kit) ship as plain archives (Ch 9/10).
**Not shipped (dev only):** ncm_link, ncm_space, ncm_probe, ncm_weather_probe, prototypes. **Environment:** the host
sets the `environment` tunable to **`single_player`**, a third role beside `online` and `development`
(`calendar.lua`): no dev waivers (fuel burns, parts heat), Deep stays development-only (no single-player renderer
yet), the L330 temporal loop (`canonical.lua`) is on.

**Resource changes made for the host (all behaviour-neutral on OPEN//77 or correct for dev too):**
- `ncm_world/server/week.lua`: verdicts settle through `week.catchup` -- every possible end missed during downtime or
  an absence is judged in order (it used to judge one per 60 s step and read any run past Day 7 as unjudged; KB-381).
- `ncm_world/server/canonical.lua`: the boot waits for the world identity before loading presence (KB-379);
  `enabled()` includes `single_player`.
- `ncm_league/server/calendar.lua`: `single_player` is preserved as an environment (was collapsed to development).
- `ncm_league/server/collapse.lua`: single player keeps its money at rollover (owner ruling) -- detected through
  `Open77.runtime.host() == "ncm_sp"`, which OPEN//77 does not have.
- `ncm_league/server/components.lua`: the FNV id hash is exact in both VMs (KB-380).

---

## 4. SQL: MariaDB as the resources write it, SQLite as the host runs it

| MariaDB | SQLite (translator) |
|---|---|
| `INSERT IGNORE` | `INSERT OR IGNORE` |
| `ON DUPLICATE KEY UPDATE x = VALUES(x)` | `ON CONFLICT DO UPDATE SET x = excluded.x` (no target = any unique key = MariaDB's rule; needs SQLite >= 3.35); INSERT..SELECT gets `WHERE 1` |
| `NOW()`, `CURRENT_TIMESTAMP`, `UUID()`, `UNIX_TIMESTAMP()` | literals from the HOST clock (dev skew applies) |
| `GREATEST` / `LEAST` / `IF` / `CONCAT` / `LEFT` | `MAX` / `MIN` / `IIF` / `||` / `SUBSTR` |
| `UPDATE t a JOIN u b ON .. SET a.x = ..` | `UPDATE t AS a SET x = .. FROM u AS b WHERE ..` |
| `UPDATE/DELETE .. ORDER BY .. LIMIT n` | `.. WHERE rowid IN (SELECT rowid .. ORDER BY .. LIMIT n)` |
| `MEDIAN(x) OVER (..)` | `json_group_array(x) OVER (..)`, reduced to PERCENTILE_CONT(0.5) by the shim |
| `information_schema.COLUMNS / TABLES` | views over `sqlite_master` x `pragma_table_info` |
| DDL: ENUM, ENGINE, CHARSET, UNSIGNED, generated `AS (..) PERSISTENT`, `ALTER .. MODIFY/CHANGE` | replayed into a model; ENUM -> TEXT, generated -> STORED, keys kept, FKs/CHECKs dropped; MODIFY = SQLite table rebuild |
| TINYINT(1) results | booleans (the OPEN//77 .NET connector's behaviour) |
| a values array of the wrong length | refused (KB-168's lesson kept) |

**Gate:** `tools/test-host-sql.lua` -- 70 migrations -> 140 tables; **460 of 460 literal statements in the resources
translate AND prepare against the real schema**; a second sync is a no-op; append/rebuild keep rows. 55 statements
built dynamically are exercised by the boot gate instead.

---

## 5. Tapes, Race Week and offline canonical time

- **A tape** = `{ id, ordinal, serverId = "sp-<id>", epoch, daySeconds = 86400, boundarySod = noon ET }` + a cache of the
  last-seen timeline, the live run's standing, place/location. Index: `save/ncm_tapes.json` (tmp + rename, `.bak`).
- **One tape = one continuity = one Race Week clock** (convars `ncm_week_epoch`, `ncm_week_day_seconds`; the server id
  is the `serverId` tunable every resource reads). Two tapes are two worlds by construction: every canonical row is
  keyed by server_id, and the week seed is `Hash.key(serverId, "racing-week", n)`.
- **Duration model unchanged:** a Week can end at noon of Day 3 .. Day 7 (`week.continuation`, ~1 in 4 reach Day 4,
  ~1 in 144 Day 7). Not a fixed seven days. (L315's continuous early ending is still unbuilt: conflict C-5.)
- **The present is calculated:** `week.catchup.settle(cfg, runs, now, seedFor, standingFor)` judges every passed
  possible end in order. A run nobody lived in is judged unattended (z = 0); the run that was live is judged on the
  standing it was left with. Living through a span and catching up on it give identical timelines (core test).
- **Rollover = causal regeneration (L330/L303, as built online):** every Machine -- Deep included -- back in Night City
  (`canonical.lua`); un-anchored cars and loose parts re-keyed to the run archive, SR halves, NPC affiliations end, the
  Paddock moves to the archive and regenerates (`collapse.lua`, mode `live`); identity, knowledge, history, champions
  and anchored cars persist. **Single player keeps its money.** Only the newest finished Week collapses after a long
  absence (older ones are recorded `unwitnessed`; nothing invented).
- **Stranding is allowed.** No rescue before rollover. The deck lets the player start another tape; it never repairs
  the stranded one.
- **The clock never runs backwards for a tape:** a wall clock earlier than the tape's last-seen is held there (noted).
- **The deck and the world agree:** the deck calculates the present from the cache with the same seeds; the boot gate
  asserts the world's `GlobalState.ncmWeek.run` equals the deck's after a 19-day absence (RW 06 in the test).
- **Money (owner ruling):** eddies are the player's money; no 10k reset. NOT YET BUILT: the wallet is still NCM's
  ledger inside the tape (§8 item 5).

**Gate:** `tools/test-host-boot.lua` (37 checks): boot with zero errors and zero unsupported calls; quit; strand in
Deep at rest; 19 days with nothing running; the deck shows a later Week; remount: verdicts settled (marked
unattended), the Hella back in Night City, the collapse live, no wallet lines; TAPE 02 at RW 01 never touching TAPE 01;
a clock five days back held; a corrupt index restored from `.bak`; deck logic (first-run explanation, NEW TAPE,
WITHOUT NCM). Core `test_week_catchup` (8).

---

## 6. The front door (F: what Cyberpunk allows, stated)

- **Exact blocker for a native main-menu entry:** NCM has never hooked the game's main menu. The types exist
  (`SingleplayerMenuGameController`, `PreGameMenuGameController`, `SaveMetadataInfo` in the RED4ext SDK headers; a
  scratch rig prototype wraps `SingleplayerMenuGameController.OnInitialize`), but adding selectable entries needs
  build-specific ink widget paths and an untested load intercept. Spike: IDEA-1186.
- **What is built instead:** the deck is a CET window, on screen at the main menu (open the CET overlay to click) and
  shown again the moment a save finishes loading -- **before** any NCM world runs. NCM is dormant until a choice.
  Rows: `TAPE 01   RW 06 · D5 · 13:13   NIGHT CITY` / `<time to the next possible end> · Last active: 2 hours ago`,
  then **+ NEW TAPE** and **CYBERPUNK WITHOUT NCM**. First NEW TAPE shows the Race Week explanation (nothing about
  Deep, hosts, KSA) and **BEGIN RW 01 · D1**. Pad: D-pad + A via observed `PlayerPuppet` actions (names unverified;
  logged on the first live run). While mounted, a HUD line: `TAPE 01 · RW 06 · D5 · 13:13` + time to the next end.
- **Why choosing after the save loads is right, not a fallback:** a tape is not a Cyberpunk save.
- **Dev Time Lab** (deck checkbox "Developer mode"): +1 h, +1 day, to 60 s before the end, cross the rollover, skip
  1 / 4 Weeks, age the tape 30 days, strand the machine in Deep (tape at rest), reset the dev clock. Every use marks
  the tape DEV and is noted on it. The skew is global, so tapes stay isolated.

---

## 7. B -- what is NCM Core, what is host, what stays OPEN//77

| Layer | Contents | Runs on |
|---|---|---|
| **NCM Core** (`ncm/core`, pure) | every rule: week clock/curve/continuation/**catchup**/collapse, Moody, Paddock sim/world/tape/news, economy settlement, passport + correspondence, Deep physics, engineering, places, venues | both hosts, AC (subset), tests |
| **Resource code** (`ncm/online/resources`) | persistence (SQL), orchestration, presentation logic, per-player sessions | OPEN//77 **and** the NCM Host, unchanged |
| **NCM Host** (`ncm/host`) | VMs, scheduler, SQL translation, the headless world model, CET bindings, tapes, deck | single player |
| **OPEN//77-only** | multiplayer transport, master tickets, launcher projection, CEF WebUI, server-authoritative networked vehicles/NPCs, routing buckets, Warden, the MariaDB | dev / Online |

---

## 8. G -- the seam report: what stands between this alpha and a Nexus release

Ordered by what blocks the experience first.

1. **Vehicles / NPCs / props are headless in single player (P3).** `vehicles.create`, `vehicles.ai.*`, `npcs.*`,
   `props.*` keep state in the model but spawn nothing. Paddock live races, NPC grids, issued cars, ambient population
   need DynamicEntitySystem spawning and ncm-pace's `AIVehicleRacingCommand`. *Server-only assumption:* OPEN//77
   simulates AI on a streaming client and caps AI at 55 m/s; in single player the local game IS that client.
2. **CEF WebUI has no single-player equivalent.** The Panel (308 KB), race HUD, venue card, nameplates, observer and
   Deep (WebGL) are HTML pages. The host's `WebUI.create` records traffic for native page ADAPTERS; none is written
   yet (the deck and the HUD line are the only native surfaces). Port order: race HUD, venue card, Panel (ink or
   ImGui), Deep (needs a native renderer; WebGL in CEF has no CET path).
3. **Native plugin bridges ride WebUI loopback pages.** Carrier, ncm-vision/scanner and broadcast talk to resources
   through hidden CEF pages and loopback websockets; CET has neither. They need redscript natives (the plugins already
   register natives) called from the host's game layer.
4. **Plugin distribution.** Today NCM plugins reach the game through OPEN//77's launcher projection or hand installs.
   For Nexus each is a normal RED4ext/redscript mod listed as a requirement or a Collection item.
5. **Money (owner ruling not yet built):** the wallet is NCM's ledger inside the tape. Eddies-as-wallet needs one seam
   in `NcmEconomy` (balance and debits through a host wallet) with payouts at the online scale (`economy.settlement`).
6. **Unknown / modded vehicles:** core `machine.passport` already accepts any record (inferred, confidence 0.35), and
   machine identity is `vehicle_asset.asset_id`, never a runtime id. Missing in single player: minting an asset for a
   vehicle the player drives that the catalogue does not know (`vehicle_catalogue.resolveRecord` returns nil today),
   and the Collection's authored passports. *Third-party content assumption:* nothing in the host assumes a
   Collection item is installed; the catalogue still lists 45 vanilla machines.
7. **Persistence hazards.** One SQLite file holds every tape (a per-tape export/backup is IDEA-1183). CET's `db` API
   (exec/nrows/urows) and its SQLite version (>= 3.35 needed) are unverified (§TP0). DATETIME defaults use SQLite's
   real clock, not the dev skew. `ON UPDATE CURRENT_TIMESTAMP` is dropped (the resources write their own BIGINT
   times). FOREIGN KEY and CHECK constraints are not enforced. Upsert row counts differ from MariaDB (1, not 2).
8. **Save corruption / recovery.** Tape index: tmp + rename + `.bak` (tested). Database: SQLite is transactional; a
   crash mid-transaction rolls back. A torn `db.sqlite3` has no NCM-level recovery yet (IDEA-1183).
9. **Irreversible Cyberpunk mutations (disabling NCM):**

   | Mutation | Today in the host | Reversible? |
   |---|---|---|
   | Player position (teleport at a rollover wake, `players.teleport`) | bound | persists in the CP save if the game saves after; harmless |
   | Map pins | bound (MappinSystem, removed on unmount) | yes, runtime only |
   | Weather / time of day (`environment.set*`) | NOT bound (headless) | when bound: snapshot at mount, restore at unmount (IDEA-1184) |
   | Population density, speed limits, wanted level | NOT bound | same rule when bound |
   | Spawned vehicles / NPCs / props | NOT bound | DynamicEntitySystem entities are non-persistent |
   | Eddies, items, quest facts | none | (money ruling: eddies WILL change when built -- by design) |
   | Files in the game folder | none (the old SP wrote TweakXL yaml there; the host does not) | -- |

   Recovery path for a Nexus user: CYBERPUNK WITHOUT NCM on the deck, or delete `mods/NCM` (README in the package).
10. **Rollover semantics still missing:** the ceremony on return is a HUD line, not a ceremony; anchored-car choice
    (IDEA-910) and the witnessed-configuration rule are unbuilt online too; L315 continuous early ending (C-5).
11. **Tape isolation gaps:** everything keyed by `server_id` is isolated. Tables WITHOUT a server_id column (global
    catalogues, `ncm_driver`, `content_pack`, `schema_migrations`, `place_registry`, `machine_passport` keyed by asset)
    are shared by design or by asset id; an audit table per table is owed (IDEA-1185).
12. **Offline reconstruction gaps:** Race Week verdicts, rollover and presence settle on return. The Paddock does not
    yet resolve missed races abstractly: after an absence it resumes from its own state (no replay, no catch-up of
    individual races). Markets and production tick from their own `next_*_at` fields (they catch up by their own
    rules, measured only in the boot gate's first minutes). Ambient races and the speed-limit curve have no absence
    model beyond the Week's.
13. **Host-adapter state ownership:** AC/KSA embodiment goes through the Python host bridge (dev only). In single player
    `PerformHttpRequest` answers "no http"; no adapter can own the clock or ids (they never could: canonical.lua owns
    presence). A Nexus-shaped adapter path is P5+.
14. **Dependencies unsuitable for Nexus:** OPEN//77 (not used by the host), MariaDB (replaced), CEF (unused), the Python
    bridge (dev only), LuaJIT FFI (tests only, not shipped). Required: CET 1.37+. Optional: NCM's RED4ext plugins.
15. **UI / main menu constraints:** §6. The deck needs the CET overlay for mouse input; the pad path is unverified.
16. **The radio seam:** facts already exist -- `racing_week_event` (samples, steps, `radio:<h>` lines), verdicts,
    Moody rolls, `paddock_event` (the causal tape), `ncm:week:fact`. A radio consumer reads those rows per tape; no new
    server-only channel was added. A canonical fact feed across hosts is IDEA-1187.

**Next build order (P3+):** (1) eddies wallet seam + payout scale; (2) spawned vehicles + Paddock live races;
(3) race HUD + venue card native adapters; (4) plugin bridges as natives; (5) unknown-vehicle minting; (6) Panel;
(7) environment bindings with snapshot/restore; (8) Deep renderer.

---

## 9. How to run it

- Gate: `tools/ncm-build.ps1 -Check`, then `tools/ncm-test.ps1` (host SQL + host boot run under LuaJIT; SQLite via
  `NCM_SQLITE_DLL` or Python's `sqlite3.dll`).
- Package: `tools/ncm-host-build.ps1` -> `dist/ncm-3.0.0-alpha.1.zip` (not installed by the script). Back up CP saves,
  extract into the game folder, launch: MASTER_TEST §TP.
- The old single-player mod (`MT_Ecosystem`) and NCM 3.0 should not both be installed: they are different products.

---

## 10. The first Collection car: the Kimiko RB15 (L338 addendum)

- **Model / appearance / machine:** `ncx_rb15` / one of ten liveries (`data.liveries`: kimiko, archer, herrera, mizutani,
  quadra, raven, rayfield, spunky_monkey, thorton, yorinobu) / a claimed asset with its own serial.
- **Claim** (`NcmOwnership.claim`, the deck's GARAGE): a known model is manufactured with a birth certificate and handed
  to the player; an unknown record becomes a machine of its own without a serial; the car goes into V's garage
  (`EnablePlayerVehicle` -- a deliberate save mutation, reversible with `EnablePlayerVehicle(record, false)`).
- **Install:** `tools/install-ncm3-kimiko.ps1` (RB15 from the owner's own download + NCM's livery archive + NCM 3.0;
  recorded, backed up, `-Uninstall`). The RB15's files are never shipped by NCM; the Collection points at Nexus 31543.
- **Next:** observed performance per asset (IDEA-1198); AC by correspondence and KSA by reconstruction (IDEA-1199).

---

## 11. The native host (L338 addendum, KB-385)

CET's sandbox cannot run the resources (no coroutines, no load, no setfenv, no _G). The simulation therefore runs in the
`ncm_host` RED4ext plugin (`ncm/host_native`): Lua 5.4.7 + SQLite 3.49.1 in-process, the host Lua of §3 and the resources
unchanged, the database at `red4ext/plugins/ncm_host/ncm.sqlite3`, the tape index at `red4ext/plugins/ncm_host/save/`.
CET is the front end: the deck (§6) through a port, the Race Week line, and the game bindings, over one native,
`NcmHost_Call(cmd, json) -> json`, once per frame (`tick` sends V's position and car; the answer carries the game
commands -- pins, toasts, teleports, a car into V's garage). §3's in-CET layout is superseded by this one.

---

## 12. The Online port programme (L370, 2026-10-17)

Online is frozen (fixes only). Every Online system reaches single player through this host, one chapter at a time.
**Each chapter:** an audit table (feature -> resource files -> Open77 calls -> host status), the owner's review of every
multiplayer-only reinterpretation, the build (game bindings + ink screens + host tests), `ncm-test` ALL GREEN, an alpha
package installed over backed-up saves, a live §SP PASS in MASTER_TEST, then the owner's sign-off before the next.

**Screens:** native ink only (L370). A WebUI page becomes an ink renderer over a host **page adapter**
(`ncm/host/webui/`): the resource still calls `WebUI.create/send`; the adapter turns messages into lines for redscript
and ink actions back into the resource's own page callbacks. The ink kit `NcmInk` is built once in Ch 1 (IDEA-1318):
docked, cursor-only focus like F9 (L353), never a modal layer (KB-389), its key and Esc always close it.

| Ch | Scope | State |
|---|---|---|
| 0 | Freeze, catch the host up to the current tree, measure the binding backlog, frame-time baseline live | **offline done 2026-10-17; §SP0 live NOT RUN** |
| 1 | Front door + tapes (non-modal), Race Week line, `NcmInk` proven on the How to Play screen (L354) | not started |
| 2 | The map: blips/markers/anchors -> MappinSystem under a pin budget (KB-387/388), GPS, Route Me There | not started |
| 3 | Your machines and money: garage cars as Machines, `vehicles.create` spawning (paint/damage re-applied), claim + unknown-vehicle minting, the eddies wallet seam, fuel; Machine Index (F10) in ink | not started |
| 4 | The F6 hub in ink, view by view: Race Guide + Race Graph (F8), Messages (quest graph), Market + parts + Parts Inventory, Exchange (NPC traders), weather ribbon, Help | not started |
| 5 | Racing: venue rings + card, race HUD, race flow, Street Call (F5), ghosts/PB, Safety Rating, grids; AI opponents through NCM Pace on the local game (one opponent first) | not started |
| 6 | The living league: Paddock (live races, off-screen sim, scouting, My Org, the queue), calendar, Moody, verdicts/rollover/collapse (money kept), ambient population; Observer (F3) on NPC races; the Paddock's absence catch-up (§8.12) designed | not started |
| 7 | Engineering: F9 (Service/Parts/Build/Workshop), Carrier force channel, wear/damage, stacked gearboxes, Slipstream SL-1 + HUD, Build attachments, quickhacks | not started |
| 8 | Plugins and devices: Rig Bridge + DEVICES/WHEEL/PAD, Vision/Scanner key, radial menu, Broadcast nameplates (NPC racers), NCM Audio/FX, NCM Radio played locally per tape | not started |
| 9 | Flight and Deep: AV, propulsion, snowglobe/seam, NCM Sky + an ink instrument panel in place of `deep.html`, presence/stranding, `ncm_aero` | not started |
| 10 | Release shape: Nexus requirements, the Collection, per-tape backup (IDEA-1183), mutation restore (IDEA-1184), coexistence with NCM 2.0 | not started |

**Multiplayer-only things (the owner rules on each in its chapter):** other players on the map, their nameplates and
chat -> gone (NPC racers keep nameplates); the player Exchange -> NPC traders only; human team managers -> the player
is the only one; Observer of players -> of NPC races; launcher requiredMods, master tickets, Warden, Lightsail -> Nexus
requirements, nothing hosted; `ncm_link`, the dev probes, the KSA rehearsal -> out; the server radio render loop ->
a pre-rendered corpus played locally.

### 12.1 Ch 0 audit: what the 16 shipped resources call, and what reaches the game (2026-10-17)

Measured by grep over the shipped resources' `server/` and `client/` Lua (call sites in parentheses where it matters)
and by the boot gate. **Bound** = reaches Cyberpunk today through the native frame (`ncm/host/native.lua` ->
`NcmHostRuntime.reds`, which draws only `toast`, `teleport`, `waypoint`, `givecar` and the Race Week `hud`/`state`
line; the frame's `chat` and `pin` lines are sent and dropped: pins left with CET in L340 phase 2). **Headless** = a working model, nothing in the game.
**Missing** = not modelled; a call returns nil (KB-481: the boot run never reached these).

| Open77 namespace | Side | Host today | Chapter |
|---|---|---|---|
| notifications.send (41), hud.notify | both | **bound** (toast) | 1 |
| chat.send (45) | both | sent, dropped by redscript (no chat in single player; owner rules in Ch 1 whether any line becomes a toast) | 1 |
| players.teleport (12), travel.teleport* | both | **bound** | 1 |
| blips.* (44), markers.*, anchors.* | client | GPS waypoint **bound**; blips sent as `pin` lines and dropped; markers, anchors headless | 2 |
| map.open, camera.project (4), world.raycast | client | headless | 2 / 5 |
| vehicles.create (9) / remove (17) / setTransform / setPaint / setDamage / getDamage / doors | server | headless (setDamage, getDamage, doors, freeSeats, seatFree, openDoor **missing**) | 3 |
| vehicles.get / getPosition / getPlayerSeat / owner / requestAuthority, players.getVehicleSeat / warpIntoVehicle | both | headless (fed by the frame's V position + car) | 3 |
| vehicles.setPerformance / ratedTopSpeed / setEngine / setFrozen | both | headless; the real channel is the Carrier adapter (§PB1) | 7 |
| vehicles.ai.* (40), npcs.* (~70), world.setPopulation / clearArea / groundZ | server | headless (clearArea **missing**); NCM Pace adapter built but no spawn | 5 / 6 |
| webui.create (4 resources' pages + plugin pages) | client | plugin pages -> native adapters (§PB); player pages recorded only | 1, 4-9 |
| input.isDown (14) / isCaptured (10) / axis / registerKeyMapping / devices | client | headless (nothing pressed) | 1 / 8 |
| camera.*, screen.fade*, hud.setVisible / setCinematic | client | headless | 5 / 6 |
| vfx.play / update / stop, props.create / attach / setTransform | both | props headless; vfx and props.attach **missing** | 7 / 9 |
| nameplates.stream, inspector.outline, hacking.*, combat.*, cyberware.*, effects.screen | both | headless (cyberware.install, hacking.start refuse) | 7 / 8 |
| environment.* (weather/time), world.setTimeScale | server | headless (a CET-era setWeather/setTime hook exists, unbound natively) | 6 |
| io.read / write / makeDirectory, resource.readFile, kvp.* | both | **host-complete** (L370: io per tape in `_ncm_host_files`) | 0 |
| tunables, state bags, exports, routingBuckets, ready, players.positions, time, runtime | both | **host-complete** (single player has one bucket, one player) | 0 |
| network.status, players.kick, routingBuckets (multiplayer) | both | answered as single player | -- |

**Ch 0 still owed (live):** §SP0 below: install the current build, boot, choose a tape, read the slow-frame log.
