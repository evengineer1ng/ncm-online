# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-25 - RB15 withdrawn and verified; repos clean and pushed; Engineering's first slice built.**

> **Claim before writing:** decisions through **L145**; MASTER_TEST through **2.19 / §AS**; next QA letter
> **§AT**. BACKLOG next free **IDEA-472**; known issues through **KB-121** plus the pre-existing duplicates
> **KB-87** and **L119**. Read the last row of each ledger, not this line (`KB-114`).

## Next action: build. Two tracks, both unblocked.

**Engineering - next step is migration 031.** `engineering.competency` is built and green
(`ncm/core/engineering/competency.lua`, 15 tests): 15 skills, 12 families, the reducer, headroom, difficulty,
relevance and the both-halves gating rule. Pure, not yet persisted or wired. Next is `IDEA-470` -
`engineer_skill` and `engineer_family`, same shape as `driver_sr`, at most 27 rows per engineer ever - then one
bench inspection operation and a command to run it.

**Wheel - next step is NCM's first own package.** The delivery pipeline is proven and currently carries two
loaders and nothing else, which makes this the moment to ship NCM content through it. Start with a **CET Lua
package**: executable class, so it exercises the real consent path, and it needs no C++ toolchain. Prove NCM
ships its own content end to end; *then* add the RED4ext plugin, which is the only demonstrated path to HID,
FFB and final-command interception (Report 36 3.2, 6.7). **Packaging first, wheel code second.**

**Independent, whenever the wheel is on:** `KB-106`'s `ROAD_SCALE` drive. One drive, instrumentation already
ships, blocked by nothing, and the last thing between the FFB work and an honest "done".

## Live state

- **Production:** RB15 and the NCM liveries **deleted from Warden by the owner** (`L145`). Public manifest
  declares ArchiveXL 1.27.1 and TweakXL 1.11.4 only, digest `67ad384b...` (was `06ab5485...`). The loaders stay
  staged so the pipeline is already correct the day NCM's first package exists. The `requiredMods.note` still
  names RB15 and is stale - fix on the next config touch, not with a restart of its own.
- **Development:** parked and restarted. `enabled=false`, `mods:[]`, empty-set digest, 40 resources, all four
  NCM resources present.
- **Repos:** both clean and pushed. `cyberpunk2077` @ `ef448fd`, `ncm-wheel` @ `52dd7de`. No release cut.
  Production is reproducible from a commit (`KB-115` closed).

## What is settled, so nobody re-opens it

- **Delivery works; NCM's packages are unwritten.** Different problems (`L145`, `IDEA-471`). Transport,
  consent, executable roots, projection, loader init and archive load all passed with real packages, evidenced
  from the client's own logs. Do not resurrect "RequiredMods doesn't work", and do not call NCM's own hosted
  delivery unproven.
- **The AP section is closed.** AP1-AP4 pass; AP5/AP6 retired with their subject. **Nobody is to be asked to
  drive an RB15.**
- **No test may require Solo** (`L144`). A row that needs it is unrunnable as written, not "owed".
- **Research before experiment** (`L143`). The AR probe is deferred and its question answered: the drive model
  is **spawn-cached**.
- **Surface C is the one open capability question** (`IDEA-464`): the live `WheeledPhysics` instance is a
  per-instance copy of the drive-model record, fully mapped, and nothing found writes it. A code-reading task,
  not an owner session.

## Outstanding live QA

- **AQ:** AQ1/AQ3 **LIVE PASS**. AQ2 (spawned in once?) and AQ4 (log out somewhere distinctive, log back in -
  `L110` has never been observed working) are cheap and owed.
- **AN / AO:** Gate 6 setPerformance and companion brake-authority proofs; not run.
- **AM4-AM7, AL1-AL2, AK:** unchanged.
- Still owed: IDEA-251 full Market live PASS, AH21 incident attribution, migration 028 fresh-world.

## Session records

- **L144** no test may require Solo; **L145** RB15 removed and verified, Case B closed as moot.
- **KB-120** the mod-flag scripts could only address Production; **KB-121** most of the AP evidence was already
  on disk and the test design asked a human for it instead.
- **IDEA-469** the competency slice, **IDEA-470** its two tables, **IDEA-471** pipeline versus packages.
- Dev server restarted; both repos pushed; Online untouched by this session beyond read-only checks.
