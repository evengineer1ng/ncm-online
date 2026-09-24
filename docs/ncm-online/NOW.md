# NOW — the single next-action index

**Rewritten at the end of every working session.** Read this first, then BACKLOG.md, KNOWN_BUGS.md,
DECISION_RECORD.md and the referenced QA rows.

Last rewritten: **2026-09-24 — version control, and NCM Development is standing (L121).** Earlier: the
engineering/wear proposals accepted with one reconciliation (L120); before that KB-87 incident detection, built
locally and still not deployed.

> **Claim before writing:** decisions through **L124**; MASTER_TEST through **2.18** / **§AG**; next QA
> letter **§AH**. BACKLOG next free **IDEA-295**; known issues through **KB-93**.
> *(This block was stale until 2026-09-24 — it still claimed L119 / IDEA-241 / KB-87 while 172 BACKLOG rows,
> L120 and KB-91 already existed. It is the only guard against reusing an ID, so correct it every session.)*
> Historical §Z collision remains: qualify it by section (2.14 Machine Index vs 2.16 Help).
> `KB-87` is used **twice** (incident detection, and the odometer forensic) — an existing collision, not a typo.
> L106 is the Market/access meaning (acquisition vs access); the probe-evidence corollary is **L109**.
> Do not reuse IDs or rewrite another session's authored history.

## The work now has a repository, and a workshop to happen in

**`github.com/evengineer1ng/ncm-online` — private, 644 files, ~11 MB.** Everything we wrote; ~1.9 GB of
runtimes, snapshots and third-party assets excluded with a stated reason per rule. Verified private. No secret
was ever in the tracked set (DPAPI, outside the workspace) — which is the only reason this was a same-day job.
**One gap, recorded not hidden: the RB15 livery artwork (353 MB) is still backed up nowhere (`IDEA-293`).**

**NCM Development is running on the Windows box.** `.87` (704 files verified), production's exact 39-entry load
list, `serverId = ncm-devbox`, `environment = development`, database migrated 005 → 023 cleanly.

**NCM Online was not touched.** Still `ncm-dev`, unrenamed, `deploy-staging.ps1` still defaults to
`-Target online`. Those are L112 cutover steps 3-6 and remain the owner's call.

### The box found three things before it finished booting

All three are **invisible in production**, which is always already migrated and long-running:

- **KB-51 reproduced and stopped.** `.87` makes `freeroam` depend on `open77_cyberware_lab`, which the local
  load list lacked — the fault that aborted the whole start set and took NCM offline for an hour. The guard
  caught it on the candidate tree *before* the swap. `check-load-list.py` now runs on both sides.
- **KB-93** — `022_supply_dynamics.lua` was listed twice in the manifest. Fixed.
- **KB-92** — a `SQL 1146` that only fires when the schema is behind the code, i.e. on every fresh install.

**Standing rule (L121): Lightsail changes are instrumented on Windows first.**

## Awaiting two rulings; two proposals up for review (L124)

**A2 LOCKED** -- team machines use the same serial sequences; exclusivity moves upstream into market/distribution
access (`IDEA-298`). **A5 LOCKED** -- interim visible conditions are fine, effects stay gated, and the interim
must never become the product model.

**A1 awaiting ruling.** Measured: `origin` is `production` on all 19 live assets, `grant` has never been used,
**nothing in the codebase branches on it**, and `consumesOrdinals()` is never called outside tests. It is a
write-only restatement of what `production_ordinal` already records. My earlier "two unrelated jobs" framing was
wrong and is corrected in L124.

**A4 awaiting ruling.** Evidence gathered. Exactly one ownership transfer has ever occurred; 8 of 27 results fall
after it, all non-team; the MaiMai is the only asset in the world with odometer distance. **But NCM never
verified the fielded vehicle at the grid**, so attribution is strong inference, not record. Recommendation: leave
unknown, or adopt `IDEA-300` (`attribution_basis`) so a derived attribution stays legible as derived.

**Up for review:** `25_MACHINE_ARCHITECTURE_PROFILE.md` (Q18/Q19) and `26_DOCUMENT_AUTHORITY.md` (the
documentation pass, `IDEA-299`). Both PROPOSAL; nothing moved or rewritten.

## Earlier: STOPPED FOR REVIEW -- reconciliation delivered, nothing implemented (L123)

All 70 questions answered by the owner 2026-09-24. `24_FOUNDATION_RECONCILIATION.md` reconciles them against the
schema, code, production data and the full 297-row ledger.

**Headline: most of this is already designed and blocked on one missing primitive.** NCM has no principal that can
hold title, money or custody -- everything is keyed to a driver. `14_TEAM_ORGANIZATIONS.md` (L92/L93) and
`IDEA-139/142/157/162/168` already specify what the Q4/Q6/Q15/Q45/Q46/Q48/Q50 answers describe, and migration 015
even named the ALTER. **`IDEA-297` (owner principal) is the highest-leverage row in the ledger.**

**Bleeding now, measured against production:** 29 unattributable results (+1 per finisher per race), 9
driver-only incident rows, `player_market_knowledge` empty since migration 017. **Stage 0 -- `asset_id` on
`session_result` and `incident` -- is the only thing recommended for early promotion to Online.**

**Five answers needed before Stage 1:** A1 `origin` semantics, A2 serial allocator for team machines, A4 whether
ownership-at-the-time is authoritative attribution, A5 visible conditions without effects, Q18/Q19 profile shape.

## The ledger is classified now — and one foundation is already leaking (L122)

All 177 BACKLOG rows carry a **`Class`**: F0 / F1 / INV / GATE / SYS / UI / OPS / UP / DSN, with `·LIVE` where
production already stores that shape. Nothing pruned; the 14 done rows moved to `## Completed` at the bottom under
their original headings. Read the **foundation register** at the top of `BACKLOG.md` before scheduling anything.

Of 163 open rows: **35 data-model/schema**, **14 invariants**, **6 gates**, **28 UI that can wait indefinitely**.

**`IDEA-236` is P0 and is a present loss, not a future risk.** Production holds **29 completed results, none
attributable to a machine, and not reconstructible** — `session_result`, `entry` and `seat` all lack any vehicle
reference, so the car fielded was never written down. Every further race adds another anonymous result. Forward-only
and cheap; impossible to backfill. Two owner decisions sit beside it: `IDEA-233` (do admin grants carry serials?)
and `IDEA-238` (are NCX team cars assets?) — both hold open holes in the serial space.

## Owner's one-pass answer is the next input (IDEA-295)

**`23_OPEN_QUESTIONS.md` — 70 numbered structural questions**, raised against the classified ledger and held
deliberately in one document so they can be answered together and cross-referenced. Tagged **BLOCKING / SHAPES /
LATER**, each with a recommendation where one exists, so "Q14 agree" is a complete answer. Numbering is permanent.

The four that most change the schema: **Q20/Q21** (do the 19 existing vehicles get factory components, and do
those components inherit the machine's distance), **Q16** (do installed parts transfer with a sold car), **Q2**
(what `asset_id` holds when the car raced is not an asset), and **Q48** (design the trade envelope before parts
exist, since per-asset transfer cannot express atomic multi-item trade).

**Nothing in §A-§K gets inferred.** An unanswered structural question stays open.

### Next, in order

1. ~~`IDEA-292`~~ **done** — 110 legacy rows relabelled `ncm-devbox-legacy`. Nothing on the dev box wears
   production's identity any more. Relabel beat deletion because 69 child rows hang off those events through
   tables with no `server_id` column of their own (L121 addendum).
2. **The owed live QA is now the blocker it was always going to be.** §AD1–AD7, §AE8–AE13, §AF4–AF6, §AG5–AG8
   are all NOT RUN, and `IDEA-287` already promoted §AG5/§AG6 to a **prerequisite** for wear carrying any
   economic weight. The dev box can now run the console-driven and destructive half of these without touching
   the world — which is exactly what it is for.
3. **KB-86 live re-check** on Online: Guide loads, correct date, PAST RESULTS shows the two finished runs.
4. Then the parts work (`18`/`19`/`20`, proposals `21`/`22`, L120), which is why the workshop was wanted.
> Historical §Z collision remains: qualify it by section (2.14 Machine Index vs 2.16 Help).
> L106 is the Market/access meaning (acquisition vs access); the probe-evidence corollary is **L109**.
> Do not reuse IDs or rewrite another session's authored history.

## KB-87 — obvious environmental crashes were missed (local fix, live matrix owed)

Tip-to-Trench live evidence showed two sign strikes and a substantial barrier collision could still yield Clean
Race. The old detector inferred object contact from adjacent 200 ms speed samples or vehicle health, but sample
interpolation discarded health and the speed path never used its intended 600 ms window. Locally fixed: health
survives interpolation, motion uses the full window, canonical `onVehicleDamageChanged` feeds the same ledger,
and object evidence within 3 s / 15 m coalesces as one crash episode. Clean Race already consumes the canonical
classified `incidentCount`; the false badge was detector failure, not a separate counter. Full gate green: 263
core tests per interpreter, 35 access, 17 observer, 150 Lua parses, 94 render assertions. Not deployed or live
proven. A harmless sign knockdown remains invisible without a platform collision/destructible-object callback.

## Spec batch captured 2026-09-23 — capture only, nothing authorised

Three specs plus two addenda, recorded as `IDEA-239` … `IDEA-288` (50 rows) and three documents:

- **`18_PARTS_ECOSYSTEM.md`** — procedural component ecosystem + the markets/distribution/discovery addendum.
- **`19_ENGINEERING.md`** — engineering career + the "every intervention has an outcome roll" addendum.
- **`20_WEAR_LIFECYCLE.md`** — wear/tear as odometer-driven component lifecycle. *This is the spec that
  explains why the other two exist.*

**Both owed proposals are delivered** (batch closed 2026-09-23): `21_ENGINEERING_PROPOSAL.md` answers
`IDEA-269`, `22_WEAR_PROPOSAL.md` answers `IDEA-288`. They are decision documents, not implementations —
each states a recommendation, the reasoning, and where I am guessing. **Nothing is built and nothing is
authorised.**

**Accepted and locked as L120** (2026-09-23), including one reconciliation the owner caught. The two
structural claims:

1. **The time regime belongs to the OPERATION, not the discipline** — because Diagnostics contains both the
   fastest operation (inspect) and one of the slowest (reverse-engineer). Splitting per discipline breaks
   there.
2. **Wear is a pure function, not a process**: `conditions = f(profile, seed, exposure) − serviced`. Nothing
   rolls, nothing accumulates but exposure, so determinism, idempotence and restart-safety become structural
   rather than disciplined.

Two first slices accepted: **Diagnostics-only** for engineering (needs no components — the 19 live vehicle
assets are enough), and **exposure accrual with no conditions** for wear, shipped *in the same release as
component assets* because a kilometre not recorded is a kilometre that never happened.

**The reconciliation (IDEA-289 / L120):** the first draft subtracted serviced conditions as a set, which
would have made a botched repair and a master's repair identical. Fixed — a repair now *advances a
condition's threshold* by a workmanship-derived `relief_m`, so a weak repair leaves the condition at reduced
severity and an excellent one buys real distance. Exposure still never moves. **That single number is the
entire interface between the engineering and wear systems.**

Three things already true that the batch leans on:

- The odometer→car-death design is **struck** (L119 amended). Wear now lives at component level instead.
- **`IDEA-287` promotes §AG5/§AG6 to a prerequisite.** Spec 3 names our own KB-88 jitter finding and says
  distance must be proven robust *before* wear has economic consequences. Owed QA is now blocking work.
- Market discovery is **half-built** (`IDEA-251`): `player_market_knowledge` and `markets.known()` both
  exist, neither is wired. Cheaper to finish before parts exist than after.

## KB-87 / KB-88 — the odometer investigation

**The ~20% "overcount" is mostly not one.** The 6.6 km figure for Tip->Trench is a **straight line between
two nodes**, not a road distance: `routes.resolve` only sums legs when a route authors intermediate points,
and that one authors none. Recomputed exactly: **6,630 m**, planar, ignoring the climb and the tunnel.
7,900 m of road over a 6,630 m straight line is a circuity factor of **1.19** -- normal-to-low for a city.

**Stationary jitter was real, though** (KB-88). The only guard was a 0.25 m floor per 1 Hz sample = 0.9 km/h,
so a squirming parked car banked ~1.9 km/hour. Speed is now an independent witness: under 0.2 m/s the delta
is rejected; above it, a delta beyond what the speed could cover is capped rather than discarded. Creeping at
3-8 km/h is untouched.

**Existing mileage was not altered** -- MaiMai #0000001 reads 11,903 m before and after the deploy, and no
migration recomputes anything.

## KB-86 — the Race Guide broke, and it was mine (fixed, live re-check owed)

Adding PAST RESULTS to the Guide payload pushed it from ~17.9 KB to ~22.5 KB and it stopped arriving:
no races, 1969 date (a missing `serverNow` renders as epoch 0). Results are now fetched **on demand** when
that tab opens, which is where they belonged anyway -- the Guide payload is rebuilt for every player on every
calendar tick, while a driver's history changes once per finished race.

**Worth carrying forward: the headroom is thin.** ~17.9 KB arrives, ~22.5 KB does not, and the Guide is at
~17.9 KB with 17 rows right now. A larger calendar will hit this again. `PAYLOAD_WARN_BYTES` was 24 KB --
above the size that actually broke -- and is now 18 KB so it warns first.

## Two defects the live capture caught after deploy (fixed 23:30 UTC)

Worth reading before trusting the supply engine, because neither was visible offline:

1. **A TINYINT(1) flag reads back as a Lua boolean**, and `tonumber(true)` is nil — so `initial_done = 1`
   was read as 0 and a MaiMai event ran as an INITIAL allocation on a line that launched days earlier. It
   minted nothing only because the shelf was full; with capacity it would have re-dropped the launch
   allocation. Flag columns now go through `truthy()`.
2. **A "decrease" that did not decrease.** The ladder kept every equal-rate (batch, interval) pair as a
   separate rung, so a step could change the shape and leave the rate alone — seen live as
   `decrease -> 6x/60min` from `4x/30min`. One rung per distinct rate now, with `grain` deciding how a
   manufacturer expresses it. That exposed a follow-on: a *hold* was snapping an authored schedule to the
   ladder's preferred expression of the same rate. A hold now returns the current schedule verbatim.

## Individual Machine Profile — specification recorded, NOT built

`docs/ncm-online/17_MACHINE_PROFILE.md` (IDEA-237). Three layers kept apart: the Machine Index knows the
model, the asset ledger knows what happened, the profile is how the owner presents it. Facts authoritative,
presentation curated, history follows the machine.

**One real gap in the foundations, found while writing it up:** race results are recorded against the
DRIVER, not the machine — `session_result` has no `asset_id`. So "486 starts, 37 wins" for a specific car
cannot be answered at all today. Small and forward-only to fix (**IDEA-236**), but it compounds: results not
attributed to a machine from the start are results that machine's biography will never contain. Worth doing
before much more racing happens.

## Vehicle identity, provenance and the odometer (L119 / IDEA-226..230)

Every manufactured machine now has a birth certificate: three independent append-only sequences (NCM's whole
production history, its manufacturer's, its model's) attached to the permanent `assetId`. Backfilled live
across all 19 existing assets with **0 skipped** — and **MaiMai `10000000-...-0001` is NCM #0000001 /
makigai #0001 / makigai_maimai #0001**, still owned, identity untouched.

One thing the audit caught and had to work around: **`vehicle_asset.acquired_at` is rewritten on purchase**,
so it means "when the current owner got it", not "when it was made". Ordering by it put the first persistent
asset NCM ever had in third place. The backfill orders by `vehicle_asset_transfer.kind = 'production'`
instead, which is written once at manufacture and never touched.

Mileage is measured server-side from the **vehicle's** position at 1 Hz while occupied — not from the client
(a figure that may one day cost someone their property must not be client-editable) and not from the driver
(that would count walking around a parked car). Reconstruction never invents kilometres.

Mileage accrues for **any car that is a persistent asset**, whatever materialised it: the odometer takes the
CALL/access map plus registrations from any resource (`ncm:odometer.track`). What cannot accrue is a vehicle
that is not an asset — NCX team cars are issued equipment with no assetId (IDEA-238, owner decision).

**No vehicle dies.** The lifecycle state exists so retirement will never need a `DELETE`, and
`TERMINAL_FAILURE_ENABLED = false` with a test asserting it stays off.

## Dynamic manufacturer supply (L118 / IDEA-220)

Cadence and batch are no longer fixed forever. A manufacturer now chooses its **next** schedule from real
market history, inside an authored envelope, and has authority over exactly two numbers — next batch and next
interval. Price, shelf capacity, identity, ownership and provenance are outside its reach by construction.

It reacts to demand and **never to a buyer**: the fact bundle it consumes has no field capable of carrying an
identity, so ten sales to one player and ten to ten players are literally the same input. Three personalities
(`steady_hand`, `volume_responsive`, `scarcity_keeper`) share one mechanism and differ only in numbers.

Live: all three alpha lines resumed mid-life at their next index with **no launch replay**, profiles composed
from the catalogue (Makigai → volume, Thorton → steady, Archer → scarcity), and a restart left the committed
plan byte-identical. The first real evaluation is due at 23:10 UTC (§AF4).

**The simulations changed the design twice, which is the main reason to trust them.** A raw sales-velocity
signal made a market in perfect equilibrium read as maximum demand and raise production forever; and an
unweighted imbalance ratio let a single purchase move a schedule, because a ratio is most sensitive when the
numbers are smallest. Both were caught by §27 scenario tests, not by inspection.

## The one next action

**Open F6 → MARKET on a live client and run §AE8–AE13.** The supply engine is proven against the live world;
the player-facing half has not been seen by anybody. The first thing to confirm is simply that **the MaiMai is
back on the shelf at 8/8** — that is the whole of the owner's original report.

Still owed from earlier today and not superseded: **§AD1–AD7** (race navigation, withdraw, forfeit, Past
Results, node markers). §AD2 remains the single most valuable row in the file.

## Where we are

### Base Market (KB-85 / L117)

The audit answer was blunter than expected: **there was no supply system at all.** The three launch assets
came from a one-time `alpha_launch` seed, and no code path existed that could ever mint primary stock again.
Buying MaiMai #0000001 did not sell the MaiMai out — it removed the MaiMai from NCM permanently, because the
payload listed available *assets* and an offering with no asset has no row.

Two things were already right and were preserved: stock was derived from real unsold assets rather than a
counter, and **nothing enforced one-per-player**. The "Real stock. One machine per listing." subtitle was
inherited *description* of a three-asset bootstrap, not a rule — multiple purchases were always legal and
merely impossible for want of supply.

What exists now:

- `economy.production` — authored `ceiling` / `batch` / `cadence` per offering, and
  `mint = min(batch, max(0, ceiling - available))`. Ceiling-**seeking**, so a skipped or partial tick is
  corrected by the next one and no sequence can overshoot.
- Ticks are **indexed and the index is claimed**. The host writes `market_production_run` before minting and
  verifies the claim by reading its own nonce back — deliberately not by trusting an affected-rows count,
  because whether a driver reports `INSERT IGNORE` as 0 or an insert id is not something vehicle manufacture
  may rest on. (The original epoch-derived index, `epoch + n × cadence`, was superseded by L118: it only made
  sense while cadence was fixed forever. The guarantee never lived in that arithmetic.)
- Offerings are persistent. `0 / 8` is a thing a market says, not a thing that makes a market disappear.
- Discovery moved from payload-build to **player-facing inspection**, so it works at zero stock and does not
  hand over the whole shelf for opening a panel.

Alpha levers (tune freely, they are data). Shelf / starting batch / starting cadence / launch drop, and the
envelope the manufacturer may move inside:
MaiMai 8 · 4 per 30 min · launch 6 · envelope 1–6 every 15 min–8 h ·
Galena 6 · 3 per 60 min · launch 4 · envelope 1–4 every 30 min–24 h ·
Hella 4 · 2 per 120 min · launch 2 · envelope 1–2 every 60 min–72 h.

**Live evidence, not inference** (§AE1–AE7): first pass took MaiMai 0→4, Galena 1→4, Hella 1→3; the next tick
took all three to their ceilings. Partial-capacity capping was observed twice in the production ledger (Hella
batch 2 into 1 slot minted 1; Galena batch 3 into 2 slots minted 2). A restart at the ceiling produced **zero**
production lines — which proves the tick *claim*, not merely the ceiling, because a failed claim would have
logged "no capacity". Bootstrap MaiMai #0000001 keeps its identity, owner and `purchase` provenance.

### Race graph (IDEA-216)

Reworked as asked: vertical, finish at the top, at most four drivers, `152 px` on the left edge instead of a
`1240 px` bar across the bottom that sat on the speedometer. `session.standings.focus` slides a four-wide
window — one ahead and two behind in midfield, three behind when leading, three ahead when last — and never
fabricates a competitor to fill a slot.

## Blocked on the platform, with the check actually done

**Throttle / brake / STEERING meters are not feasible (IDEA-231, supersedes IDEA-218).** Checked twice now,
the second time including steering. `Open77.input` exposes only digital key state (`isDown`, `isCaptured`,
`keyFor`, `setNativeActionBlocked`); `Open77.vehicles` has no pedal or steering accessor among its ~40
functions. `GetAxis`, `Steering` and `AccelerationScale` appear only as internal symbols inside the server
binaries, in no scripted resource. Reproducing the single-player meters would require REDscript/DLL client
dependencies, which the owner's own brief forbids. **The odometer was built instead and stands on its own.**
Worth asking the OPEN//77 developers for an analog input surface, alongside the paint replication question.

## Verification

**249 core tests** under both interpreters (+14 supply-profile scenario simulations, +7 production,
+5 standings), cross-scope 34 / 0 bad, 35 access, 17 observer, **145 resource Lua files**, 3 inline scripts,
**91 panel render assertions**. Migrations 021 and 022 applied cleanly; the database was backed up before each
(`/opt/ncm/backups/supply-20260923T220955Z`, `.../supply-dynamics-20260923T223843Z`). Clean boot, no script
errors.

Reminder that cost a false-green gate earlier today: **`ncm/core/` is the source and
`resources/*/shared/core/` is build output.** The vendored files carry no banner and the test run reads the
source tree, so editing a copy passes the gate and ships nothing. Edit, then `ncm-build.ps1`, then
`ncm-test.ps1`.

## Still open, untouched

Race-purse / economic settlement (deliberately out of scope; the acquisition side had to be sound first).
KB-76 slow venue panel. KB-68 purchased-vehicle delivery. Vehicle paint replication (`pass1 ret=true`,
`pass2 ret=true`, still visually wrong — platform-side). §Z/§S/§U/§V/§W QA debt. Environment split cutover
(`16_ENVIRONMENTS.md`) remains operator-owned and not active.
