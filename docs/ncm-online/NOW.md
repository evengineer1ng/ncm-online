# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-25 - the NCM Carrier built: one native mod for parts, chrome, weather and the wheel.**

> **Claim before writing:** decisions through **L146**; MASTER_TEST through **§AT**; next QA letter **§AU**.
> BACKLOG next free **IDEA-479**; known issues through **KB-121** plus the pre-existing duplicates **KB-87**
> and **L119**. Read the last row of each ledger, not this line (`KB-114`).

## Next action: build it and host it on Development.

```
git submodule update --init --recursive
$env:VCPKG_ROOT = "<your vcpkg>"
.\tools\build-carrier.ps1 -PublishDev
```

That builds the DLL, stores the blob on Development, declares it, drops RB15 and the liveries from the
declaration (`L142`), un-parks requiredMods and restarts the server. Then launch the game and join: the
launcher names **NCM Carrier** as executable content, you accept it, and it installs. That is MASTER_TEST
**AT0 and AT1**, and together they are NCM's first own package through NCM's own pipeline.

**If the game will not launch**, the fix is server-side and there is nothing to hunt for on disk:

```
python tools/staging/publish-carrier.py tools/open77/server --remove
.\tools\build-carrier.ps1 -RestartDevOnly
```

Read `red4ext/plugins/ncm_carrier/ncm_carrier.log` for why -- it is the only diagnostic that survives a
failed load.

Expect to debug the flat write first (`IDEA-477`) and OPEN//77 coexistence second: OPEN//77 is itself a
RED4ext plugin with its own vehicle adapter, and nobody has asked whether a second one sharing the drive
path is fine.

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

Offline gate green. Nothing is compiled, packaged, declared or deployed.

## Live state

- **Production:** untouched this session. ArchiveXL 1.27.1 + TweakXL 1.11.4, digest `67ad384b...`. The
  `requiredMods.note` still names RB15 and is stale - fix on the next config touch, not with its own restart.
- **Development:** parked, `enabled=false`, empty-set digest. Unchanged this session.
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

- **§AT:** the carrier, AT0-AT7. Nothing run. AT0 publishes, AT1 is the join.
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
- **IDEA-472** the carrier; **473** NCM had already written these flats itself and nobody checked; **474** four
  families cannot be felt; **475** one fact, one carrier; **476** rain as grip; **477** how a flat is actually
  written; **478** superseded -- the manual pre-flight was extra QA on top of the path that actually ships,
  and the hosted path is the more recoverable one.
- Online untouched. No deploy, no restart, no config change.
