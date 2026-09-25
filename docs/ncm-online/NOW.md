# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-25 - the carrier is built, hosted and live on Development; server upgraded to op77.102.**

> **Claim before writing:** decisions through **L146**; MASTER_TEST through **§AT**; next QA letter **§AU**.
> BACKLOG next free **IDEA-479**; known issues through **KB-121** plus the pre-existing duplicates **KB-87**
> and **L119**. Read the last row of each ledger, not this line (`KB-114`).

## Next action: join Development.

**Everything is in place.** The carrier is imported, declared and served; both causes of the two dead joins
are fixed.

Development: manifest digest `1e4f80c0...`, `enabled: true`, one package **`ncm-carrier-0-1-0` v1.0.0**,
868,069 bytes, blob `7febfa6e...`, advertised over loopback. No script errors.

Expect on the join: a consent prompt naming **NCM Carrier** as executable content, `modstack: ... N added`
in `%LOCALAPPDATA%/Open77/launcher.log`, `ncm_carrier` in `<game>/red4ext/logs/`, and a
`red4ext/plugins/ncm_carrier/ncm_carrier.log` naming its version, whether the bridge is listening and what
device it found. **A declined hook is still a PASS** -- effects and force feedback do not depend on it.

That is **AT1**. If the game does not launch: `publish-carrier.py tools/open77/server --remove`, restart,
rejoin -- and read `ncm_carrier.log`.

**Why the first two joins delivered nothing** -- neither cause was the plugin, and nothing NCM wrote ran:

- **`KB-125`**: the server advertised its blob URL as `http://10.0.0.70:11779/`, private-LAN plain HTTP,
  which launchers `.89`/`.100` null out before download, cache or hash. That is **`KB-112`**, which named
  Development as the remaining offender and was never acted on. Result: `OP77_WORLD_MODS_DIGEST=-`,
  `0 added`, no consent prompt, **no error anywhere**. Now loopback; `set-download-url.py` refuses a
  non-loopback HTTP value rather than letting it be set again.
- **`KB-124`**: a hand-written store entry vanished on restart. **Cause never established** -- the claim
  that only Warden may fill the store was wrong, since Production's loaders went in without it. The likely
  companion fault is `IDEA-483`: Warden derives its own id (`ncm-carrier-0-1-0`, not `ncm-carrier`), so a
  declaration that restates an assumed id can never resolve. `publish-carrier.py` now reads the store and
  declares exactly what it finds.

**What the dead joins showed about inputs** (`IDEA-482`): the launcher **removed 44 files and added none**
-- ArchiveXL's and TweakXL's DLLs -- and RED4ext loaded exactly **one** plugin, Open77. The player was in the
world with their RED4ext stack absent; that is what changed the feel. A join that delivers nothing is
indistinguishable from one that delivers everything, and the cheapest fix is to compare what the launcher
projected against what the server declared and show it in the panel.

## Ownership identifiers -- observing, not migrating

op77.102 added `Open77.players.identifiers()` with `license`, `steam` and `gog`. **NCM has not changed its
binding key** (`IDEA-479`). `ncm_driver_binding.user_id` has been `GetPlayerIdentifier()` since M2.1 and
every driver, profile, SR row and machine hangs off it; if `license` is a different string, switching would
orphan every existing driver silently -- a missing binding just mints a new one and the player finds an empty
garage. `identity.lua` now logs, once per player, whether `license` matches the key already in use, and
shouts if it diverges. **Your next join answers it.** If they diverge, the migration is a backfilled second
column, never an in-place key change.

## What was built this session

**`ncm/carrier/`** - a RED4ext plugin. Loopback WebSocket bridge on 38480 serving the same page the Python
companion served, so `carrier_bridge.lua` generalises rather than being replaced. TweakDB flat application
with an originals ledger. SDL force feedback with `CEILING`/`clamp`/`slew`/rung transcribed verbatim (`L133`)
and KB-103, KB-104 and IDEA-412 carried across. Final-command authority behind RTTI resolution that declines
rather than guessing. **No ViGEm, no virtual gamepad** - the companion needed one because nothing in the game
could read a wheel; this writes the final command directly.

**`machine.flats` and `machine.projection`** - the one calculation, in pure Lua, 20 tests. Parts, wear,
weather, chrome and class rules in; one versioned envelope out, with a trace naming every movement of every
number. The plugin applies triples and interprets nothing (`L135`).

**`server/machine.lua`** publishes projections through `GlobalState.ncmProjections`, the same path the class
ceilings already use. **Rain is grip now, not a lowered speed limit** (`IDEA-476`) - but it must not go live
before `KB-6`, because unsynced weather plus grip effects means two drivers racing under different rules
without knowing it.

Offline gate green, **and it is now compiled, packaged, declared and serving on Development.** Two defects
the offline gate could never have caught surfaced on the first live run and are fixed: `KB-122` (a
`capability` field in the declaration stops the server booting) and `KB-123` (`os.time()` does not exist in
the server Lua sandbox, so the projection publisher was dead and silent). `IDEA-481` records the gap:
**the gate proves the calculation, and only a running server proves the wiring.**

## Live state

- **Production:** untouched this session. ArchiveXL 1.27.1 + TweakXL 1.11.4, digest `67ad384b...`. The
  `requiredMods.note` still names RB15 and is stale - fix on the next config touch, not with its own restart.
- **Development:** **op77.102** (upgraded 2026-09-25; load-list guard clean, freeroam sandbox re-closed per
  `L131`). requiredMods **enabled and unsecured**, one package: `ncm-carrier 0.1.0`, digest `78c37893...`.
  RB15 and the liveries dropped from the declaration (`L142`).
- **Repos:** `cyberpunk2077` has a new submodule (`RED4ext.SDK`, MIT). `ncm-wheel` @ `52dd7de`, now reference
  material rather than a shipping dependency.

## What is settled, so nobody re-opens it

- **NCM owns native code** (`L146`). `L138`'s three questions are answered: mod-required world, yes; native
  ownership, yes; companion as device layer, no. `L139` is **discharged** - but its naming discipline is not:
  the command surface is `brake_command_authority`, never `native_brake_force`.
- **Delivery works; NCM's packages are unwritten** (`L145`, `IDEA-471`). The carrier is the first one.
- **Spawn-cached** (`L143`). Record effects reach a car at its next spawn, never mid-stint. Parts, weather and
  class rules fit that honestly. Wear and expiring chrome do not - do not design them against the hope it
  changes.
- **Two drivers of the same model still share one record.** Report 36's hardest constraint, untouched by any
  of this, and it sits directly across the premise of a parts economy.
- **Four of the twelve families cannot be felt at all** (`IDEA-474`): cooling, transmission, electrical,
  chassis. Enforced in code, refused by name.
- **No test may require Solo** (`L144`). **Nobody is to be asked to drive an RB15** (`L145`).
- **Surface C remains the one open capability question** (`IDEA-464`). A code-reading task, not an owner
  session.

## Outstanding live QA

- **§AT:** the carrier. **AT0 PASS**; **AT1 FAIL then re-armed** -- the package was never offered
  (`KB-125`/`KB-124`), both causes fixed, imported and declared. AT1-AT7 need one join.
- **§AQ:** AQ1/AQ3 **LIVE PASS**; AQ2 and AQ4 cheap and owed.
- **`KB-106`'s `ROAD_SCALE`** is now folded into **§AT6** - the carrier prints the measured peaks on shutdown,
  so one drive closes it.
- **AN / AO:** Gate 6 setPerformance and brake-authority proofs; not run.
- **AM4-AM7, AL1-AL2, AK** unchanged. Still owed: IDEA-251 Market live PASS, AH21 incident attribution,
  migration 028 fresh-world.

## Engineering, parked mid-track

`engineering.competency` is built and green; next is `IDEA-470` - migration 031, `engineer_skill` and
`engineer_family`, same shape as `driver_sr` - then one bench inspection operation. Untouched this session
and blocked by nothing.

## Session records

- **L146** NCM owns native code; the carrier is one mod; the companion retires. `L50`/`L1` amended, `L139`
  discharged, **KB-117 closed by retirement**.
- **IDEA-479** ownership identifiers, observed not migrated; **480** the build needs no package manager;
  **481** offline-green does not mean it runs. **KB-122**, **KB-123** found by running it.
- **IDEA-472** the carrier; **473** NCM had already written these flats itself and nobody checked; **474** four
  families cannot be felt; **475** one fact, one carrier; **476** rain as grip; **477** how a flat is actually
  written; **478** superseded -- the manual pre-flight was extra QA on top of the path that actually ships,
  and the hosted path is the more recoverable one.
- Online untouched. No deploy, no restart, no config change.
