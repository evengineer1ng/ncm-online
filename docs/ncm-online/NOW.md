# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-25 - reconciliation steps 0-5 executed and pushed; KB-115 closed; owner's §AP4 is the only thing in the way.**

> **Claim before writing:** decisions through **L143**; MASTER_TEST through **2.19 / §AS**; next QA letter
> **§AT**. BACKLOG next free **IDEA-469**; known issues through **KB-120** plus the pre-existing duplicates
> **KB-87** and **L119** (both in `HEAD`, neither renumbered).
> Historical §Z collision remains: qualify by section (2.14 Machine Index vs 2.16 Help).
> *`KB-114` records why this line went stale before: the documentation gate asserts ID discipline for
> BACKLOG only. Read the last row of each ledger, not this line.*

## Next action: owner finishes §AP4 (or writes it off)

**The repository work is done.** Steps 0-5 of
[37_REPOSITORY_RECONCILIATION_SCHEDULE.md](37_REPOSITORY_RECONCILIATION_SCHEDULE.md) executed 2026-09-25:
six commits in `cyberpunk2077`, two in `ncm-wheel`, both pushed, working tree clean, no release cut, no server
changed. `KB-115` is **closed** - an aggregate SHA-256 over all 173 resource files is `a3007a11…` on both the
committed tree and `/opt/ncm/resources/ncm`, so **production is reproducible from a commit and that commit is
on the remote.** The spawn fix went first and alone as `8dc321b`.

What is left is the owner's, and it is time-sensitive:

**§AP4 — reconnect without redownload, then switch to Solo, then prove byte-exact restoration of the ten named
manual RB15/livery files.** That evidence exists only while the current packages and projection are in place,
which is why the RB15 withdrawal is ruled but parked. Either capture it, or say explicitly that it is written
off — both are fine, but the choice has to be made before anything touches Online.

Take **§AQ2** (*"did I spawn in once?"*) and **§AQ4** (log out somewhere distinctive, log back in — L110 has
still never been observed working) on the same session, and open WHEEL/PEDALS **with the companion stopped**
for §AQ3/G3 while you are there. Four gates, one join.

**Development is parked** (`IDEA-460`, done 2026-09-25). `L142` collapsed the correction: its only two declared
packages were RB15 and the liveries, so nothing was left to declare and the KB-112 URL fix became moot.
Instrumented first — `check-load-list.py` reported *40 resources, every dependency satisfied* with all four NCM
resources present — then parked with `set-mods-off.py`: `enabled=false`, `unsecured=false`, both packages still
declared, timestamped backup beside the file. **One small thing owed: restart the dev server** so the parked
flags take effect (`tools/o77-server.ps1`; `Open77.Server.exe` is currently running with the old config).
Doing this required parameterising a script hardcoded to Production — `KB-120`.

Do not implement Parts/Engineering, component rows, migration, physical effects or a control extension.

## What the owner's join proved, and what it did not

**PROVEN (L141):** public HTTPS → unsecured warning → consent UI naming all four packages, each **Not
reviewed** → Download and Join → *Preparing server mods* → *Preparing your session* → **NCM Online session
entry**. Server log corroborates: `connected` 15:38:26, `ready` 15:38:43. **No `Unverifiable`.** `KB-112` is
closed as a delivery blocker. The four `Not reviewed` verdicts match Report 35's `safety=unknown` finding
exactly.

**NOT PROVEN — do not inflate:** that ArchiveXL or TweakXL initialised (no loader log captured); that the RB15
record exists or drives; that any livery is available; that projection handled the pre-existing manual files
correctly; that reconnect reuses cache; that Solo restores every manual byte.

**Row states:** §AP1 **PASS** · §AP2 **PASS on the consent half**, journal half unevidenced · §AP3 **PARTIAL**
· §AP4-§AP7 **owed**. *A session-entry PASS is not an in-game content PASS.*

**Future sessions: do not resurrect the "RequiredMods doesn't work" narrative.** It was false, Report 35 found
the cause, the fix is deployed, and a human has walked the whole funnel.

## The owner's fall-through was KB-113, and it stopped

Resolved against the server log rather than assumed. `easporks` / driver `72519ab3` joined four times:

| Join | `ready:` | What NCM's location system did | Fix live? |
|---|---|---|---|
| 15:01:35 | x=2566.9 | restored to `0.0,3.6,0.5` — the origin | no |
| 15:04:14 | x=2566.9 | restored to `0.0,3.6,0.5` — the origin | no |
| 15:29:03 | x=2566.9 | restored to `0.0,3.6,-906.4` — **into the fall** | no |
| **15:38:26** | **x=2566.9 y=112.6 z=78.6** | **save refused with a reason; restore refused `below_world`; no teleport at all** | **yes, 15:36:15** |

**It is KB-113, it happened on the pre-fix joins, it did not recur after the fix, and it is not attributable to
RequiredMods.** §AQ1 and §AQ3 are server-side **LIVE PASSes**; §AQ2 and §AQ4 remain owed and are cheap.

## RB15: ruled, recorded, parked at the boundary

**L142 — NCM has not established sufficient redistribution permission for the exact RB15 package it was
hosting, and ceases public redistribution pending permission or provenance resolution.** The provenance is
mixed: the model-derived portions appear CC BY 4.0, while the mod author's own implementation and the complete
package carry separate restrictions requiring permission. Permission will be sought. *"Terms not established"
is superseded — this is a decision, not an open question.*

- **The NCM liveries park with it.** NCM owns the bytes, but they are ArchiveXL/TweakXL content extending the
  RB15 vehicle record; without it they extend nothing and cost every joiner 7.8 MB.
- **Preserve, do not delete.** Blobs, declarations, hashes, provenance manifest and authoring sources stay.
- **No substitute open-wheel mod.** Ruled explicitly.
- **NOT EXECUTED.** Removal needs a Production `server.jsonc` write, a restart, a digest mutation and a serving
  change — all gated, because §AP4/Case B evidence only survives while the current packages are in place.

> **The exact next authorised operation the owner must approve:** *finish §AP4 or write off that evidence;
> then run a targeted `tools/staging/` script removing the two RB15 packages from Online's
> `requiredMods.packages`, restart `ncm-server`, and confirm the new digest and master row.*

Two facts for that decision: RB15 is **38.5 of 48.4 MB**, so withdrawal cuts the first-join download by ~80%;
and with it gone, ArchiveXL and TweakXL have **no NCM content left to load**, so parking `requiredMods`
entirely may be the honest end state (`§AS4`).

## Driveability: answered by reading, not by an experiment

**L143 — research before experiment.** The owner will not flip mod environments to answer what existing mods
may already answer. Standing order: *existing-implementation research → forensic source inspection → name the
residual unknown → only then propose an experiment.* **§AR is deferred. Do not ask the owner to run it.**

Applying that order answered it the same day:

- **Surface B is SPAWN-CACHED** (`IDEA-462`). Vehicle Physics Config states it as an engine limitation and
  resummons; **Direct Wheel's contradicting CET module is absent from its own `deploy.ps1` and FOMOD
  installer** — an unshipped experiment; and the live `WheeledPhysics` instance is a per-instance copy of the
  record. So Surface B carries factory spec, Parts, setup and class/weather rules — **not** mid-stint wear or
  an expiring Chrome effect.
- **The BLOCKED list was a platform limit, not an engine limit** (`IDEA-463`, `KB-119`). `vehDriveModelData`
  carries brakes, grip, slip, suspension, weight transfer, mass and `engineMaxTorque` — which has no
  `accelerationScale ≤ 1` ceiling, so a positive part could express a real gain. **None of it is reachable
  from an OPEN//77 resource**; Report 34 §4.3 stands.
- **Surface C is the one residual unknown** (`IDEA-464`). The live instance is fully mapped in a public SDK and
  **nothing found writes it**: Direct Wheel reads five fields and writes none, LTBF writes one boolean and its
  only wheel-reinit attempt is commented out, `SetupInsert()` is named and never called. That absence is
  evidence of difficulty. **It is a code-reading question, not an owner session.**
- **Native wheel** (`IDEA-467`): every technical precondition is demonstrated in single-player; the
  OPEN//77-specific halves are not — package delivery of NCM's own executable, secured review throughput,
  **coexistence with OPEN//77's own drive-update hook (nobody has asked)**, and the RED4ext address-database
  hazard, where a lagging database means **the world cannot be entered at all**. Credible; not next.

## Repository and server state

- **Both repositories are committed, pushed and clean.** `cyberpunk2077` @ `main` = `a6f43b9`:
  `8dc321b` spawn fix (alone, first), `8d9da32` FFB panel/ladder, `b80fd82` HTTPS deployment inputs,
  `7e2c1c6` load-list guard, `aa47fd1` reports 32-37 with INDEX, `a6f43b9` ledgers.
  `ncm-wheel` @ `main` = `52dd7de`: `59eb5aa` the effect lifecycle test and its CI step, then the
  KB-103/104/106 fixes. **No release cut** — not while an owner proof window is open.
- **`ncm-wheel` is canonical and drives hardware; `tools/ncm-wheel.py` is a reference harness** that says of
  itself *"This drives no hardware."* and lacks the `KB-103`/`KB-104`/`KB-106` fixes. **Do not sync them**
  (`KB-117`). Their shared contract is `ncm/core/driver/feedback.lua`, and the Lua is authoritative. **No new
  companion release** merely because a native replacement is being investigated.
- **No deploy can be scoped to one workstream** (`KB-116`): whole-tree `rm -rf`/`mv`.
- **Development is parked** (`IDEA-460`, done): `requiredMods.enabled=false`, `unsecured=false`, both packages
  still declared, backup taken. The KB-112-broken `http://10.0.0.70:11779/` is now moot until NCM has content
  of its own to deliver. **Restart owed** for the flags to take effect.
- Caddy 2.11.4 owns public `11779` at `https://52-60-225-137.sslip.io:11779/`; OPEN//77's resource origin is
  loopback-only at `127.0.0.1:11782`; Warden loopback-only at `127.0.0.1:11780`. Certificate expires
  2026-12-24, renews automatically. `IDEA-452` tracks replacing the interim `sslip.io` name.

## Package set — as declared today, pending the L142 withdrawal

- ArchiveXL 1.27.1 — `608b7b2f…`, 1,037,774 bytes, executable, **MIT**.
- TweakXL 1.11.4 — `13033a1f…`, 1,046,349 bytes, executable, **MIT**.
- RB15 10.0.0 — `d597ceb4…`, 38,537,004 bytes, inert — **WITHDRAWAL RULED (L142), NOT YET EXECUTED**.
- NCM liveries 1.0.0 — `d1fe9bd0…`, 7,829,853 bytes, inert, NCM's own — **parks with RB15**.

## Operations and rollback

- Versioned deployment inputs `tools/staging/Caddyfile.required-mods` and
  `tools/staging/configure-required-mods-https.py` are **still untracked** — commit step 3.
- Backups: `/opt/ncm/backups/required-mods-https-20260925T145252Z/server.jsonc` and
  `…-prestage-…/Caddyfile`.
- **No Online deploy, restart or configuration change until the owner completes §AP4 or releases the gate.**
  `KB-102` measured a 90-second window in which a stopping server still admits players.

## Gate 6 and outstanding live QA

- **§AN:** setPerformance physical-effect and two-input composition proof; not run.
- **§AO:** Development-only companion brake-authority proof; KB-110/KB-111 prerequisites remain; not run.
- **§AP:** AP1 PASS, AP2 PASS (consent half), AP3 PARTIAL; **AP4-AP7 owed and time-sensitive**.
- **§AQ:** AQ1/AQ3 **LIVE PASS**; AQ2/AQ4 owed — one ordinary join and one deliberate log-out/log-in.
- **§AR:** **deferred by owner (L143)**, superseded as a method. Retained unrun; **do not schedule**.
- **§AS (new):** RB15 withdrawal proof rows. Gated behind §AP4.
- **§AM4-§AM7, §AL1-§AL2, §AK:** unchanged.
- **Rig/FFB:** IDEA-395-422, plus `KB-106`'s `ROAD_SCALE` drive — **one drive, instrumentation already ships,
  and it must not wait on any mod work.**
- Still owed: IDEA-251 full Market live PASS, §AH21 incident attribution, migration 028 fresh-world.

## Session records

- **L141** RequiredMods proven to session entry; **L142** RB15 ceases public redistribution; **L143**
  research-before-experiment and the §AR deferral.
- **IDEA-462-468** the spawn-cached finding, the wider flat inventory, Surface C, the RB15 withdrawal, the
  standing research method, the native-wheel gate, and the redistribution-terms rule.
- **KB-118** the RequiredMods pipeline has no redistribution-permission gate; **KB-119** two documents state a
  platform limit in engine-limit language. **KB-113** updated to server-side LIVE PASS.
- Reports **36** and **37** are both at **revision 2**; 37 remains the **single** execution schedule.
- **Committed and pushed this session; nothing deployed, restarted or configured.** Eight commits across two
  repositories, both remotes updated, both trees clean. Server access was read-only throughout: aggregate
  `sha256sum` over the deployed resource tree (twice, before and after), a masked configuration read, and log
  greps. **Online was not touched.**
- Two deviations from Report 37 §3.5, stated rather than buried: the ledgers went in one `docs:` commit because
  `git add -p` is interactive and unavailable here, and the reports were committed **with** INDEX because the
  docs gate requires every document to be listed and every link to resolve.
