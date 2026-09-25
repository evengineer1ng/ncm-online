# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-25 - AP1-AP4 pass after reading the client's own logs; no test may require Solo (L144); Case B must be decided before RB15 leaves.**

> **Claim before writing:** decisions through **L144**; MASTER_TEST through **2.19 / §AS**; next QA letter
> **§AT**. BACKLOG next free **IDEA-469**; known issues through **KB-121** plus the pre-existing duplicates
> **KB-87** and **L119** (both in `HEAD`, neither renumbered).
> Historical §Z collision remains: qualify by section (2.14 Machine Index vs 2.16 Help).
> *`KB-114` records why this line went stale before: the documentation gate asserts ID discipline for
> BACKLOG only. Read the last row of each ledger, not this line.*

## Next action: two looks in Online, then decide Case B before RB15 leaves

**§AP4 as written is gone.** It asked the owner to switch to Solo, two messages after `L143` recorded that they
do not leave NCM Online. `L144` now rules that **no MASTER_TEST row may require Solo, single-player or another
profile**, and §AP was re-scoped rather than re-asked.

Re-scoping found that **most of §AP was already on disk** (`KB-121`) — in `launcher.log`, `red4ext/logs/` and
ArchiveXL's own log — at higher precision than a human could report. Reading it closed §AP2's journal half,
most of §AP3, and all of the runnable part of §AP4 in one pass. **§AP1-§AP4 now PASS.**

**What is genuinely left, and it is short:**

1. **Two looks, in Online, no Solo:** does the **RB15 exist and drive**, and do the **NCM liveries look right**.
   These are the only §AP items with no artifact behind them. Take `§AQ2` ("did I spawn in once?") and `§AQ4`
   (log out somewhere distinctive, log back in — `L110` has still never been seen working) on the same session,
   and open WHEEL/PEDALS with the companion stopped for `§AQ3`/G3.
2. **A decision, and it has a deadline of your own making.** Case A proved the content loads. It **cannot**
   prove the hosted packages supplied it, because the launcher said outright *"kept the copy of
   `archive/pc/mod/ncm_rb15_liveries.archive` that was already there"*. Only **Case B (§AP5)** settles that —
   and `L142` withdraws both packages, after which there is nothing left to run it against. So: **run Case B
   before §AS, or record deliberately that NCM chose withdrawal over the proof** and that hosted delivery of
   NCM's *own* content stays unproven until the first package NCM actually ships. Case B needs no Solo — it is
   a file-isolation operation. **Do not let this lapse silently.**

**Then, on your word:** §AS — the RB15 withdrawal. §AP6 is largely the same removal, so run them together.

**Small and owed:** restart the dev server so the parked `requiredMods` flags take effect.

Do not implement Parts/Engineering, component rows, migration, physical effects or a control extension.

## What the owner's join proved, and what it did not

**PROVEN (L141):** public HTTPS → unsecured warning → consent UI naming all four packages, each **Not
reviewed** → Download and Join → *Preparing server mods* → *Preparing your session* → **NCM Online session
entry**. Server log corroborates: `connected` 15:38:26, `ready` 15:38:43. **No `Unverifiable`.** `KB-112` is
closed as a delivery blocker. The four `Not reviewed` verdicts match Report 35's `safety=unknown` finding
exactly.

**ALSO PROVEN, from on-disk artifacts read 2026-09-25** (`KB-121` — this was available all along):

- **Executable-root delivery.** `unsecured world: accepting unreviewed executable content in 'tweakxl'
  ('red4ext/plugins/TweakXL/TweakXL.dll')`, same for ArchiveXL.
- **The overlap was named and handled, not silently overwritten.** `modstack: replacing an unmanaged copy of
  archive/pc/mod/ncm_rb15_liveries.archive` → `kept the copy that was already there (705a3c2207b0)`.
  Receipt: `projected 387 file(s) — 2 added, 1 repaired, 0 removed`.
- **The declared loaders initialised.** RED4ext log: `ArchiveXL (version: 1.27.1…) has been loaded`,
  `TweakXL (version: 1.11.4…) has been loaded`, `3 plugin(s) loaded`, clean unload at disconnect.
- **Both archives loaded.** ArchiveXL log: `Loading "fable5.archive.xl"`, `Loading "ncm_rb15_liveries.archive.xl"`,
  RB15 localization merged. No errors.
- **Reconnect reuses cache.** Three later Connects each logged `projected 0 file(s), removed 0, kept 387 in place`.
- **The manual files were not touched.** All ten destinations present; mtimes 2026-08-14 / 08-30 / 09-19 / 09-20,
  all weeks before the join.

**STILL NOT PROVEN:** that the RB15 record exists and drives; that the liveries look right; and — the important
one — **that the hosted packages supplied any of it**, since the launcher kept the manual copies. The on-disk
livery archive is **8,003,584 bytes** against the declared package's **7,829,853**: a different artifact
(`IDEA-451`).

**Row states:** §AP1-§AP4 **PASS** · §AP4b **blocked by owner choice** (`L144`) · §AP5 Case B **the only
remaining proof of hosted delivery** · §AP6 folds into §AS · §AP7 log review largely done.
*Timestamps: launcher and game logs are local (UTC-4), the NCM server log is UTC; the join is 11:38 = 15:38.*

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
  change. **§AP4 no longer gates it** — that evidence is captured. **Case B (§AP5) is now the only thing the
  withdrawal would destroy**, and it is the sole proof that hosted delivery of NCM's own content works. Decide
  it deliberately, in either direction, before §AS runs.

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
