# 37 - the Online / Development reconciliation schedule

> **STATUS: PROPOSAL** - an ordered schedule awaiting the owner's approval to execute. Nothing in it has been
> done. It authorises no commit, no push, no deploy, no restart and no configuration change.
> **Revision 2, 2026-09-25** - reconciled against the owner's completed RequiredMods join, the RB15 withdrawal
> ruling (L142) and the §AR deferral (L143). This remains the single execution schedule; see section 1.1.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125). Environments and promotion discipline
> remain governed by [16_ENVIRONMENTS.md](16_ENVIRONMENTS.md); live operation by
> [OPS_STAGING.md](OPS_STAGING.md).

**Written 2026-09-25, revised the same day.** Two repositories are fully uncommitted, two servers have diverged
in opposite directions, one owner-run proof is half-captured, and one owner ruling is waiting for a safe slot.
This document says in what order to untangle that, and what must not move until the owner releases the gate.
**It is the single execution schedule. Do not create a second one beside it.**

---

## 1. Answer first — and one finding that changes the priority

The brief said *"Online has mods + the spawn fix and is mid-proof; Development has untested FFB."* A read-only
hash comparison run while writing this says something sharper:

> **Online is byte-identical to the uncommitted working tree, and differs from every commit.**

| File | Online (`/opt/ncm/resources/ncm/…`) | Working tree | Committed `HEAD` |
|---|---|---|---|
| `ncm_world/web/panel.html` | `36ddb90f…` | `36ddb90f…` | `4480ea5a…` |
| `ncm_world/shared/core/world/location.lua` | `299c868b…` | `299c868b…` | `94347abf…` |
| `ncm_world/server/main.lua` | `b95e45fd…` | `b95e45fd…` | `43f29d93…` |
| `ncm_league/shared/core/driver/feedback.lua` | `b6a8aff1…` | `b6a8aff1…` | *(vendored, generated)* |

Three consequences, all of them new:

1. **The untested FFB panel work is already on Online.** It is not a Development-only risk. `deploy-staging.ps1`
   tars the whole of `ncm\online\resources` and does `rm -rf /opt/ncm/resources/ncm && mv ncm.new ncm` — a
   **whole-tree replace**. The 15:36 UTC KB-113 deploy therefore carried `panel.html`, `panel-render-check.js`'s
   subject, and the L133 ceiling/slider change with it. No deploy in this repository can ever be scoped to one
   workstream. Logged as **`KB-116`**.
2. **The exact bytes running in production exist in no commit**, on one developer machine, with no push. A disk
   failure, a `git stash`, a `git checkout --` or a fresh clone loses the ability to reconstruct what Online is
   running. Logged as **`KB-115`**.
3. **The KB-113 regression is one routine git command away.** `HEAD`'s `location.lua` is `94347abf…` — the
   version with no readiness gate, no vertical band and no `alreadyThere` check, i.e. the one that teleported
   the owner into the world origin and then followed them down to z = −906.4.

**Therefore the order below starts with committing, not with deploying.** Committing changes no server, is
reversible, and is the only thing that makes the rest of the schedule safe. Everything that touches a server
waits behind the owner's §AP Case A.

### 1.1 Revision 2 - what the owner's evidence and rulings changed

Four inputs arrived after revision 1. **None of them weakens §1, §3 or §4** - the uncommitted-production
exposure is unchanged and is still the first thing to close.

| Input | Effect on this schedule |
|---|---|
| **The owner completed the RequiredMods join.** Unsecured warning → consent UI naming all four packages, each **Not reviewed** → **Download and Join** → *Preparing server mods* → *Preparing your session* → **entered NCM Online**. Server log: `connected` 15:38:26, `ready` 15:38:43. | **G1 is no longer "in flight"**, so §6's hard block is now a *decision* rather than a *wait*. §AP2 is a PASS on its consent half, §AP3 PARTIAL. See §5 and §6.1. |
| **RB15 must cease public redistribution (L142).** | A new step enters the sequence at **step 8a**, after the commits and after the owner releases the Case A gate. It is a Production config write, so it does **not** jump the queue. See §6.2. |
| **§AR is deferred by the owner (L143)**, and superseded as a method by existing-implementation research. | §10's line that §AR *"can happen at any point"* was read as scheduling permission. **Corrected below.** |
| **The owner's fall-through was KB-113 on the pre-fix joins**, and did not recur after the 15:36 deploy. | Strengthens the case for step 2: the fix demonstrably works and exists in no commit. §AQ1/§AQ3 are now server-side PASSes. |

**What did not change:** Online is still byte-identical to an uncommitted tree; `HEAD` still carries the
KB-113-broken `location.lua`; the deploy is still a whole-tree replace; `ncm-wheel` is still canonical and
`tools/ncm-wheel.py` still a reference harness. **Steps 0-5 remain first and remain available now.**

---

## 2. The three-way inventory, per resource

This is **Phase 0** and it is entirely read-only. Do it before any git command. Four of its twelve rows are
already filled in above; the rest are the same method.

### 2.1 What the three sides actually are

| Side | What it physically is | How to read it |
|---|---|---|
| **Tree** | `C:\Users\eveng\Documents\cyberpunk2077`, `main`, level with `origin/main`, ~22 modified + 6 untracked | `git status`, `sha256` per file |
| **Development** | **the same bytes.** `tools/open77/server/resources/ncm` is a directory junction to `ncm/online/resources` (16_ENVIRONMENTS). Development has no separate copy of NCM code at all. | nothing to compare — it *is* the tree |
| **Online** | `/opt/ncm/resources/ncm` on `52.60.225.137`, symlinked into `/opt/ncm/server/resources/ncm`, last replaced 15:36 UTC | `ssh … sha256sum <path>` — read-only, no restart |

**The junction is the most important line in that table and it is easy to miss.** There is no "push from
Development to Online" — `deploy-staging.ps1 -Target dev` prints *"the resources junction means local edits are
already live, so there is nothing to upload"* and **exits**. Development is the working tree, live, with no
build step. So a git operation on the tree changes the running Development server **instantly**, and stages
whatever it produced for the next Online deploy. That single mechanism is the whole of the risk in §4.

### 2.2 The inventory procedure

1. `git status --short` and `git diff --stat` — the tree's delta against `HEAD`. Already captured.
2. For every file under `ncm/online/resources` that `git status` lists, plus every file `ncm-build.ps1`
   generates, compute the local SHA-256.
3. One `ssh … sha256sum` batch against the same paths under `/opt/ncm/resources/ncm`. **Read-only. No restart,
   no `systemctl`, no config write, no `server.jsonc` read.**
4. Classify each row into exactly one of four states:

| State | Meaning | Action |
|---|---|---|
| `tree == online != HEAD` | deployed but uncommitted — **the current state of everything in §1** | commit it; this is `KB-115` |
| `tree == online == HEAD` | clean | nothing |
| `tree != online` | a tree change never deployed, **or** an Online change never made here | investigate before anything else — an Online-only change is an out-of-band edit and must be recovered into the tree, not overwritten |
| untracked | new file | decide: commit, ignore, or scratch |

5. Repeat steps 1–2 for `C:\Users\eveng\Documents\ncm-wheel` (there is no server side; its third side is the
   GitHub release artifact).

**Record the result in this document's §8 before proceeding.** An inventory that lives only in a terminal is
the thing that let §1 go unnoticed for nine hours.

### 2.3 What the inventory already says about configuration

Read through `tools/o77-config-show.ps1` (the masking tool — `server.jsonc` is never read any other way):

| | Online | Development |
|---|---|---|
| Mod base URL | `https://52-60-225-137.sslip.io:11779/` (Caddy → loopback `11782`) | **`http://10.0.0.70:11779/` — KB-112-broken** |
| `requiredMods.enabled` | `true` | `true` |
| `requiredMods.unsecured` | `true` | **`false`** |
| Declared packages | **four** — ArchiveXL 1.27.1, TweakXL 1.11.4, RB15 10.0.0, NCM liveries 1.0.0 | **two** — RB15 10.0.0, NCM liveries 1.0.0 only |

So Development is behind Online on **three** axes, not one. Report 35 named the URL. The other two matter:

- **The two loaders are missing from Development entirely.** RB15 and the liveries are `archive/pc/mod` content
  that ArchiveXL/TweakXL exist to load. Correcting only the URL would give Development a world layer that
  projects two archives with nothing to load them — a resolver PASS and an in-game FAIL, which is precisely the
  confusion §AP was written to prevent.
- **`unsecured=false` is currently correct for Development's two packages** (both inert; unverified inert is
  warned, not blocked) and becomes **wrong the moment the loaders are added**, because executable packages on a
  secured world need a `verified` verdict for those exact bytes. Adding the loaders and leaving `unsecured` at
  `false` produces a refusal that looks like KB-112 and is not.

---

## 3. Phase 1 — commit `cyberpunk2077`, by workstream

**Trigger: now. Blocks on nothing. Touches no server.** Do this before any other step in this document.

The brief said two workstreams. The tree holds **four**, plus documentation. They separate cleanly by file —
verified by reading every hunk — with one exception noted in §3.5.

### 3.1 Commit 1 — the location/spawn fix (`KB-113`, `KB-101`, `L110`)

```
ncm/core/world/location.lua                                   (+27)   SOURCE
ncm/core/tests/test_persistence.lua                           (+43)   3 regression tests
ncm/online/resources/ncm_world/server/main.lua                (+68)   8 hunks, all location
ncm/online/resources/ncm_world/shared/core/world/location.lua  (+27)  GENERATED
ncm/online/resources/ncm_league/shared/core/world/location.lua (+27)  GENERATED
```

**This commit is the one that matters.** Once it exists, `HEAD` contains the fix and no ordinary git operation
can reintroduce `94347abf…`. Commit it first, alone, and **push it** before touching anything else.

Memory rule `ncm-core-is-vendored` applies and is visible right here: `ncm/core/world/location.lua` is the
source; the two `resources/*/shared/core/world/location.lua` files are **output of `tools/ncm-build.ps1`** and
must never be hand-edited. They belong in the *same* commit as their source — a commit containing only the
source leaves the tree in a state where a deploy would regenerate them anyway, and a commit containing only the
generated copies is a lie about where the change was made.

### 3.2 Commit 2 — the FFB panel and ladder (`KB-105`, `KB-107`, `L133`)

```
ncm/online/resources/ncm_world/web/panel.html                  (+149)
tools/panel-render-check.js                                    (+57)  one appended block, 5 payload shapes
ncm/core/driver/feedback.lua                                   (+1/-1) comment: belt -> gear G29
ncm/online/resources/ncm_world/shared/core/driver/feedback.lua (+1/-1) GENERATED
ncm/online/resources/ncm_league/shared/core/driver/feedback.lua(+1/-1) GENERATED
tools/ncm-wheel.py                                             (+1/-1) comment only, same correction
```

The three `feedback.lua` hunks and the `ncm-wheel.py` hunk are the **same one-word correction** — a G29 is
gear-drive, not belt-drive — applied to the authority, its two generated copies and the reference harness. They
belong together and they belong here, because the device-class vocabulary is what L133 rules on.

### 3.3 Commit 3 — the RequiredMods HTTPS deployment inputs (`KB-112`, `L137`)

```
tools/staging/Caddyfile.required-mods            NEW, untracked
tools/staging/configure-required-mods-https.py   NEW, untracked
```

These are the versioned inputs NOW.md already names as the deployment record for the live Online change. They
are currently **untracked**, which means the only record of how production's TLS termination was configured is
an unversioned file on one machine. Commit them with the OPS_STAGING hunk that documents them (§3.5).

### 3.4 Commit 4 — the load-list guard (`KB-108`)

```
tools/staging/check-load-list.py                 (+25)
```

Independent of everything else: the guard that could not match `"ncm/*"` and therefore reported `load list OK`
while Development ran with no NCM at all. One file, one concern, one commit.

### 3.5 Commits 5+ — documentation and ledgers

The ten `docs/ncm-online/*.md` modifications and the five untracked reports (32, 33, 34, 35, and this session's
36/37) are **not** separable by file, because `BACKLOG.md`, `DECISION_RECORD.md`, `KNOWN_BUGS.md`,
`MASTER_TEST.md`, `INDEX.md` and `NOW.md` each carry rows from several workstreams at once. That is inherent to
append-only ledgers and is not a problem to solve.

Two options, and the first is recommended:

- **Recommended — one documentation commit per workstream, staged by hunk** (`git add -p` on the six ledgers),
  ordered so each code commit above is immediately followed by the ledger rows that describe it. Cost: six
  interactive stagings. Benefit: `git log -- docs/` reads as the project's history rather than as six bulk
  dumps, and a bisect over a ledger row lands on the code it describes.
- **Acceptable — one `docs:` commit for the whole session**, if the hunk-staging is judged not worth the time.
  Say so in the message rather than letting it look accidental.

**Whichever is chosen, the reports are separate commits from the ledgers.** 32–35 are finished artifacts from
earlier sessions that were never committed; 36/37 are this session's. Committing five multi-hundred-line reports
inside a ledger commit buries them.

### 3.6 Push

Push after commit 1, and again at the end. `main` is currently level with `origin/main`, so there is no rebase
question. **`KB-115` is not closed by committing — it is closed by pushing**, because the defect is that
production's bytes exist on exactly one disk.

---

## 4. The specific risk: how a tree operation silently reverts `KB-113`, and what prevents it

### 4.1 The mechanism, stated exactly

There is no "dev → online push". The chain is:

```
git checkout -- ncm/   (or stash, reset, clean, a branch switch, a fresh clone on another machine,
                        or anyone promoting origin/main as it stands today)
  -> ncm/core/world/location.lua and its two vendored copies return to HEAD (94347abf…)
  -> NCM Development changes INSTANTLY and LIVE, because the junction has no copy step
  -> the next deploy-staging.ps1 run calls ncm-build.ps1, tars the whole tree, and on the server does
         rm -rf /opt/ncm/resources/ncm && mv ncm.new ncm
  -> Online silently returns to the KB-113 code: no readiness gate on saveLocation, no vertical band on
     Location.valid, no same_session refusal, no alreadyThere check
  -> the next joiner is teleported to the world origin, falls, and the fall is stored for the next join
```

Nothing in that chain prints a warning. `deploy-staging.ps1` has no diff, no dry run and no per-file
confirmation; its whole-tree replace is what makes it reliable and also what makes it indiscriminate.

### 4.2 What the sequence does about it

| Order | Why it prevents the revert |
|---|---|
| **Commit 1 first, alone, pushed** | After this, `HEAD` *contains* the fix. Every command in the list above becomes harmless — there is no longer a committed state that lacks it. **This is the entire mitigation, and it costs one commit.** |
| **No deploy until after Case A** (§5) | Removes the second half of the chain for the whole window the owner is testing in. |
| **Re-run the §2.2 inventory immediately before the first post-Case-A deploy** | Catches the case where something changed between now and then, including an out-of-band edit made directly on Online. |
| **Re-run it immediately after** | `deploy-staging.ps1` prints boot lines but never asserts that what landed is what was sent. A post-deploy hash comparison is the only actual proof of the promotion. |
| **`tools/ncm-test.ps1` green before every commit that touches Lua or panel JS** | `test_persistence.lua`'s three regression tests are the thing that would notice a location regression offline. |

### 4.3 What it does *not* prevent

Committing does not make the deploy selective. `KB-116` stands: the next Online deploy for any reason ships
every uncommitted and committed change in `ncm/online/resources` together. Plan promotions as *tree states*,
never as *changes*, until that is addressed — and it is not worth addressing before the reconciliation is done.

---

## 5. Where owner verification gates sit

| Gate | What it is | Who | Blocks |
|---|---|---|---|
| **G1 — §AP2-§AP4, Case A** | **PARTLY DISCHARGED 2026-09-25.** Consent without `Unverifiable` and session entry: **PASS** (§AP2, §AP3-partial). Still owed: loader logs, the real RB15 and liveries **in game**, collision/journal handling of the manual files, reconnect and byte-exact Solo restoration (§AP4). | **Owner**, personally (L137) | Any Online restart, deploy or configuration change — **until the owner releases it**. See §6.1. |
| **G2 — §AQ** | The live join/spawn PASS owed for the deployed `KB-113` fix: one join, no double spawn, no origin teleport, no fall; `location:` lines show a refusal reason rather than silence. | **Owner**, in game | Nothing — but see below. |
| **G3 — FFB panel live check** | The WHEEL/PEDALS panel opens for a player with **no companion running** (the `KB-107` state every new tester meets first), the STRENGTH slider commits without snapping back (`KB-105`), and the MEASURED block renders. | **Owner**, in game | Calling the FFB panel work done (L69). |
| **G4 — the `ROAD_SCALE` drive** | One drive with the shipped `Mixer._observe` instrumentation, to set `ROAD_SCALE` from data rather than from a desk (`KB-106`). | **Owner**, with hardware | Any claim that road feel works. |
| **G5 — Development correction** | After §7, Development resolves its packages over loopback and boots with them. | Owner or operator | Any later Development-first proof. |
| **G6 — RB15 withdrawal (§AS)** | The two packages leave the public declaration, the digest changes, the blobs stop serving, and every local artifact is preserved byte-identical. | Operator, after the owner releases G1 | Nothing downstream — but it is a Production write, so it sits behind G1. |

**G2 largely discharged itself, from the server side.** The 15:38 join produced
`location: not saving ... ncm-ready=NO in-world=NO platform-stage=none` and
`location: NOT restoring driver=72519ab3 (below_world) -- default spawn`, with `ready:` at a real position.
§AQ1 and §AQ3 are **LIVE PASSes**. What is left is cheap and visual: one join confirming *"I spawned in once"*
(§AQ2), and one deliberate log-out-somewhere-distinctive / log-back-in to prove L110 has ever worked (§AQ4).
The 15:38 session lasted two minutes, so §AQ4 was never reachable.

**G3 still composes with any join** — the panel is already live on Online (§1), so opening WHEEL/PEDALS during
a session is evidence. It does not cover the no-companion path unless the owner deliberately opens the panel
with the companion stopped, which is one extra step and worth asking for explicitly.

---

## 6. What is blocked, and by what, now that Case A has partly discharged

### 6.1 The gate is now a decision, not a wait

Revision 1 wrote this section while Case A was in flight. It no longer is: the owner has consented, downloaded,
projected, booted and entered the world (§1.1). **But the gate does not lift automatically**, because the parts
of Case A a restart would destroy are exactly the parts still owed:

- **§AP4 needs the *current* client state.** Reconnect without redownload, then switch to Solo and prove every
  manual RB15/livery byte is restored exactly. A digest change invalidates the cache the reconnect half tests.
- **§AP2's journal half is unevidenced.** How the projection handled the pre-existing manual files was never
  captured, and that evidence only exists while those files and that projection are in place.
- **§AP5-§AP7 (Case B) have not started.** They need the same packages present to isolate.

**So the ruling stands with a changed reason.** Revision 1 blocked these operations because the proof had not
run. Revision 2 blocks them because **the proof is half-captured and a Production write discards the half that
is left**. Either the owner finishes §AP4 (and, if wanted, Case B) first, or the owner explicitly writes off
that evidence. **That is now a call the owner can make, and this document should not make it for them.**

**Hard-blocked** — do none of these until the owner either completes §AP4 or explicitly releases the gate:

- Any `deploy-staging.ps1` run against Online, with or without `-NoRestart`.
- Any `systemctl restart ncm-server`, any Caddy reload, any `server.jsonc` write, any Warden change.
- `set-mods-off.py`, `set-mods-on.py`, `set-unsecured.py` against Online.
- Any change to the four declared packages, their hashes, the digest or the `publicBaseUrl`.
- Moving or isolating the manual RB15/livery game files — NOW.md is explicit: *"Do not isolate the manual files
  until Case A and its backup/receipts are complete."* Case B (§AP5-§AP7) owns that.

**Why a restart is not a small thing here:** `KB-102` measured a 90-second SIGTERM window during which the
listener still admitted a player, and OPS_STAGING puts a full restart at ~100 s end to end. A restart also
changes the world digest handling and would invalidate a Case A run in progress.

**Not blocked** — all of Phase 1 and Phase 2, the inventory, the gate, and every documentation change. Nothing
in those touches a server.

**Development is not blocked by Case A**, but it *is* blocked by the standing rule: **Windows dev is
instrumented before any Lightsail change.** That ordering is why §7 comes before §8 even though §7 is the less
urgent repair.

### 6.2 RB15 withdrawal — the exact operation, and the boundary it stops at

**The ruling (L142) is recorded and is not in doubt.** What follows is where it safely executes, and what it
costs to execute it. **It is not executed here.**

Removing RB15 from public redistribution requires, at minimum:

| Operation | Class | Currently gated by |
|---|---|---|
| Remove `rb15-f1-inert-v10` and `ncm-rb15-liveries` from `requiredMods.packages` on Online | **Production `server.jsonc` write** | §6.1 |
| Restart `ncm-server` so the declaration and digest change | **Production restart** — ~100 s, and `KB-102`'s 90-second admit window | §6.1 |
| Accept the resulting **digest mutation** from `06ab5485…` to a new value | changes every client's world layer on next Connect | §6.1, and it destroys §AP4's cache-reuse test |
| Stop serving the two blobs over public HTTPS | resource-origin or Caddy change | §6.1 |
| Reduce Development's intended package set | Development config write | §7 — instrument first |
| Update OPS_STAGING, NOW.md and the package tables | documentation | nothing |

**Therefore: STOP AT THE BOUNDARY.** The documentation, the ruling, the ledger entries and the §AS proof rows
are all written now. The Production operations are not performed, and this document does not broaden the
owner's authorisation to perform them.

> **The exact next authorised operation the owner must approve, in one sentence:**
> *"Complete §AP4 (reconnect + Solo restoration) or write off that evidence; then run a targeted
> `tools/staging/` script that removes the two RB15 packages from Online's `requiredMods.packages`, restart
> `ncm-server`, and confirm the new digest and master row."*

Two things worth the owner knowing before deciding:

1. **The download cost mostly disappears with RB15.** It is 38,537,004 of 48.4 MB. Withdrawal cuts the
   first-join download by roughly 80%, which materially improves the funnel arithmetic in `IDEA-461`.
2. **With RB15 and the liveries gone, ArchiveXL and TweakXL have nothing of NCM's to load.** A required set
   that exists to deliver two loaders and no content still costs every joiner the red `UNSECURED` badge and the
   consent gate. **Parking `requiredMods` entirely may be the honest end state** until NCM has content of its
   own to deliver. That is `§AS4` and it is a decision, not a cleanup.

---

## 7. Phase 4 — the Development correction

**Trigger: after Phase 1 and Phase 2. Independent of Case A.** Report 35 §F names the smallest same-PC
correction; §2.3 above says it is necessary and not sufficient.

1. **Instrument first.** Confirm `tools/staging/check-load-list.py` (commit 4) reports `ncm/*` present and both
   `ncm_*` resources in the expanded set. This is the guard that was blind through the whole `KB-108` episode;
   run it before changing anything, not after.
2. **Correct the URL** to `http://127.0.0.1:11779/`, which `.89` and `.100` explicitly permit, through a
   targeted script in `tools/staging/` in the style of `configure-required-mods-https.py`. Do not hand-edit
   `server.jsonc`; do not read it except through `o77-config-show.ps1`. Back up the file first, as the Online
   change did (`/opt/ncm/backups/required-mods-https-…`).
3. **Decide the package set.** Two inert packages with no loader is not a testable configuration (§2.3). Either
   add ArchiveXL 1.27.1 and TweakXL 1.11.4 with Online's exact hashes **and set `unsecured=true`** (they are
   executable; a secured world needs a `verified` verdict), or park `requiredMods` on Development until the
   loaders are added. **Do not leave it enabled with an incomplete set** — that produces an in-game failure
   that looks like a transport failure.
4. **Record which transport was exercised.** §AP's contract requires the evidence to say loopback-HTTP-same-PC
   or public-HTTPS, and never to conflate them. A loopback PASS proves the resolver and projection on one
   machine and proves nothing about a remote player.
5. **Do not sync Development's configuration from Online's.** They are deliberately different worlds with
   different `serverId`s; 16_ENVIRONMENTS is explicit that promotion moves code, resources, config touches and
   migrations, never data, and never identity.

---

## 8. Phase 2 — commit `ncm-wheel`, and the relationship between the two companions

**Confirm the relationship before touching either. It is now confirmed, and it is not symmetric.**

| | `C:\Users\eveng\Documents\ncm-wheel\ncm-wheel.py` | `cyberpunk2077\tools\ncm-wheel.py` |
|---|---|---|
| Remote | `github.com/evengineer1ng/ncm-wheel`, separate repo | inside `ncm-online` |
| Status | **CANONICAL. Drives real hardware.** Built and released by `.github/workflows/release.yml`. | **Reference harness.** Its own header: *"**This drives no hardware.** It is the shape JoyMoCo's side should take, and a harness for watching the telemetry arrive before any force is applied to a real wheel."* |
| Has `KB-103` `_resume()` | **yes** | no |
| Has `KB-104` relative threshold | **yes** | no |
| Has `KB-106` `ROAD_SCALE` / `Mixer._observe` | **yes** | no |
| Uncommitted | `ncm-wheel.py` (+122/−8), `release.yml` (+9), `test_resume.py` untracked | one comment line (in commit 2 above) |

**Do not sync them.** They are not two copies of one file; they are a product and a specification sketch that
happen to share ancestry and a filename. Merging the canonical fixes back into the harness would make the
harness claim capabilities it does not have, and the harness's `ladder()`-only comment (*"the ladder is the
safety property"*) is the exact claim L133 ruled false.

**What they genuinely share, and what must stay in step**, is `ncm/core/driver/feedback.lua` — both files say
*"The Lua is authoritative"*. That is the real contract, and it is the one Report 36 §6.4 says to preserve
through any future migration.

Logged as **`KB-117`**: neither file names the other, and nothing in either states which is canonical. A reader
who opens `tools/ncm-wheel.py` first — the one in the repository they are working in — finds a complete-looking
companion with three known defects and no indication that a fixed version exists elsewhere.

### 8.1 Commits in `ncm-wheel`

1. **`test_resume.py`** (untracked) + the `release.yml` hunk that runs it. The test *"drives a fake haptic
   device, counts SDL calls and **fails against the pre-fix source**"* — it is the regression proof for
   `KB-103` and it currently exists nowhere but this disk. Commit it first and alone, for the same reason
   Commit 1 goes first in the other repository.
2. **The `ncm-wheel.py` fixes** — `KB-103` `_resume()`, `KB-104` relative threshold, `KB-106` `ROAD_SCALE` +
   `Mixer._observe`, `engine_period_ms`, the `Output.write` engine channel. These are one coherent
   "monki's six symptoms" session and may be one commit; splitting `KB-103`/`KB-104`/`KB-106` into three is
   better if the hunks separate cleanly, because all three are cited independently in `KNOWN_BUGS.md`.

**Do not cut a release.** `release.yml` builds an artifact testers install; a new binary during an owner-run
proof window adds a variable to a session that already has enough. Commit and push; release after G3/G4.

---

## 9. The ordered schedule

| # | Step | Blocks on | Touches a server? |
|---|---|---|---|
| 0 | Three-way inventory (§2.2), both repositories. Record it in §2 of this document. | — | read-only ssh + masked config read |
| 1 | `tools/ncm-test.ps1` — must be green. | 0 | no |
| 2 | **Commit 1: the location/spawn fix, alone. Push.** (§3.1) | 1 | no |
| 3 | Commits 2–4: FFB panel, HTTPS deployment inputs, load-list guard. (§3.2–§3.4) | 2 | no |
| 4 | Documentation and ledger commits, per §3.5. Push. | 3 | no |
| 5 | `ncm-wheel`: commit `test_resume.py` + `release.yml`, then the fixes. Push. No release. (§8.1) | — (independent) | no |
| 6 | **OWNER GATE G1 — finish §AP4** (reconnect without redownload, then Solo, then byte-exact restoration of the ten named manual files), with **§AQ2/§AQ4** taken on the same session and G3 opportunistically. **Or** explicitly write off that evidence. | 2 | owner's client only |
| 7 | Development correction: instrument, fix URL, decide the package set — **without reintroducing RB15**. (§7) | 4, 5 | Development only |
| 8a | **RB15 withdrawal (§AS, L142):** capture the pre-state, remove both packages from Online's declaration through a targeted script, restart, confirm the new digest and master row, stop serving the blobs, verify local preservation. | **6** | **Online** |
| 8b | Re-run the §2.2 inventory. Then, and only then, the first post-Case-A Online *code* deploy — if there is a reason for one. Combine with 8a if both are due, since the deploy is whole-tree anyway (`KB-116`). | 6, 7, 8a | **Online** |
| 9 | Re-run the inventory immediately after any deploy; confirm Online matches the tree byte for byte. | 8b | read-only ssh |
| 10 | G4: the `ROAD_SCALE` measurement drive. Then a companion release if wanted — **not before**. | 6 | no |
| 11 | Driveability follow-up, research only: read Whip Wizard's source if obtainable; look for any plugin calling `WheeledPhysics::SetupInsert()`; investigate native/OPEN//77 hook coexistence. **No experiment, no owner session.** (Report 36 §11) | — (independent) | no |

**Steps 0–5 are available now and account for every risk in §1.** Steps 6–10 are the owner's; 8a and 8b are the
only ones that change Online. **Step 11 is the only driveability work authorised, and it is reading.**

---

## 10. What this schedule does not cover

- It does not decide whether the FFB panel work should have gone to Online in the same deploy as the spawn fix.
  It went; `KB-116` records why that was structurally inevitable rather than a mistake of judgement.
- It does not address making `deploy-staging.ps1` selective, or adding a dry run. Both are worth doing and
  neither should be attempted during a reconciliation.
- It does not touch the OPEN//77 server tree, the freeroam eviction (`close-freeroam-sandbox.py` must still be
  re-run after every upgrade, L131), or any database work.
- **It no longer offers §AR as available work. Revision 1 said the probe *"can happen at any point"*, which
  was a statement about dependencies and was readable as scheduling permission. It was not.** The owner has
  deferred it (**L143**): they are committed to NCM Online, will not flip mod environments or profiles to
  answer something existing mods may already have answered, and have set a standing order —
  **existing-implementation research → forensic source inspection → identify the residual unknown → only then
  propose an experiment.** Applying that order already answered §AR's question (Report 36 §4: **spawn-cached**).
  The residual unknown is a different question about *writing* the live physics instance, and it is a
  code-reading task, not an owner session. **Do not ask the owner to run the single-player probe.**
- It does not authorise the RB15 withdrawal operations. §6.2 names them and stops at the boundary.
