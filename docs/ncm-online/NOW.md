# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-27 - The broad Economy v1 vertical is built locally and offline-green (`L169`,
`IDEA-564`-`IDEA-567`), not deployed.** It includes migration 035; authored Street/GT/Hypercar/NCX economics;
one centralized host money service; paid event check-in; atomic solo/contested settlement and refunds; itemized
statements; Race Tag evaluation and capped clean-driving bounties; explicit personal-first Research submissions;
and once-only rewards for the three existing unique accomplishments. Fuel, generalized player trade, Research
contracts/world-first calls and tiered Badges remain unbuilt. Lap ghosts, Parts and Machine Knowledge remain on
the previously deployed Online tree with their live test sections still owed.

> **Claim before writing:** decisions through **L169**; MASTER_TEST through **§BJ**; next QA letter **§BK**.
> BACKLOG next free **IDEA-568**; known issues through **KB-155**. Read ledger tails before allocating.
>
> The next-free guard matters: overlapping 2026-09-26/27 sessions previously made this block stale several
> times (`IDEA-380`). The docs gate asserts ID uniqueness and the BACKLOG next-free line.

## One next action

**Run a time trial twice, then run MASTER_TEST §BJ.**

**Ghosts first, because the last attempt found a defect rather than a result.** The owner ran a time trial on
the cut at 16:41 UTC and saw nothing (`KB-156`): a race session record carried `routeName` but never `routeId`,
so every time trial was unkeyable -- the client refused the session, recorded no poses, and prefetched nothing,
while the host claimed with an empty route. `ghost_lap` was confirmed empty, so nothing was mis-stored. Fixed
and redeployed 16:55 UTC; both ends now name the missing key instead of failing silently. Read the server line
first: `time trial ghost invited ... route=<a real id>`, never `route=nil`. **Two runs are needed** -- the first
stores the ghost, the second is the first one that can show it. Then §BI2: find out whether it draws as a car.

**Economy v1 is ON ONLINE, not only local.** Migration 035 applied at 16:55 UTC in the same deploy that carried
the `KB-156` fix, because `deploy-staging.ps1` ships the working tree rather than a selected change. The owner
accepted that promotion. So §BJ runs against Online: confirm boot, then starter balance, paid/denied/duplicate
check-in, solo and contested settlement, qualifying-without-payout, clean and dirty Tags, repeat floor,
abort/restart refunds, unique-Badge rewards and explicit Research submissions, reconciling receipts, typed
ledger rows and balances in SQL.

The rest of the live queue is not displaced: §BH for Machine Knowledge, §AZ for Parts, plus twice-applied
migration dry-runs for 033-035 when `NCM_DB_ROOT` is available.

## Economy v1 - deployed to Online 2026-09-27 16:55 UTC (`L168`, `L169`, document 40)

- Launch now has a genuine one-human income loop. A scheduled field of one uses time-trial completion/target
  economics and never receives P1; fields of two or more use contested completion, placement and field bonuses.
- Free practice and qualifying mint nothing. Scheduled paid events freeze their authored economics, charge at
  check-in, and settle through one idempotent transactional service with itemized receipts.
- Street begins at €$50 entry, €$250 solo completion and €$300 contested completion. GT and Hypercar use authored
  10× and 100× scales; NCX is sponsor-funded with free entry. All numbers remain observable tuning data.
- Repeating the same route/economy opportunity in its window receives the authored repeat floor instead of an
  unlimited first-completion payment. DNF/DNS/DSQ receive no purse.
- Race Tags are factual first: the runtime evaluator emits all qualified facts separately from its capped display
  set. Settlement consumes only an authored allow-list and cap; initial money rewards clean driving, not negative,
  contact, penalty, placement-duplicate or position-manipulation Tags.
- `/ncm.research` lists and submits finite personal-first physical identity and server-measured capability
  evidence. Catalogue exposure and incremental maxima/configuration revisions cannot farm money.
- Existing first-finish, first-time-trial and first-win accomplishments pay €$100 / €$100 / €$300 exactly once,
  after progression persists. The five-tier Badge reducer is not built.
- Cars and serialized Parts remain the principal progression sinks. Player trade will redistribute existing
  assets/value; fuel should follow measured event economics and retain a bankruptcy road back.

## Offline evidence

- Core: **504 passed, 0 failed** under Lua 5.4 and LuaJIT.
- Cross-scope: **51 checked, 0 bad**; QA observer **17 / 0**; vehicle access **35 / 0**.
- `luac -p`: **217 resource files, 0 bad**.
- Render checks: panel **129**, nameplate **26**, race **46**, all green.
- Documentation authority: **76 valid documents, 446 unique ledger IDs**. The final complete repository gate is
  **ALL GREEN under every interpreter** after session-close bookkeeping.

## Still live and unchanged

- Ghosts are deployed PERSONAL BEST only under `L166`; §BI remains awaiting live driving proof, including the
  exact vehicle visual, non-collision, heading seam, penalty time and both practice/time-trial claim paths.
- Machine Knowledge migration 033 and the first typed observation vocabulary are deployed under `L164`; §BH and
  the twice-applied dry-run remain owed. No estimator, envelopes or confidence were added.
- Parts economy/UI v1 is deployed under `L162`-`L163`; §AZ and later performance work remain owed. Economy v1 did
  not change the Carrier's proven three-lever boundary or resolve the brakeScale/drag coupling (`IDEA-538`).
- Useful live commands remain `/ncm.topspeed 40`, `/ncm.ratedtopspeed`, `/ncm.setup power_unit 2.0`,
  `/ncm.setup tires 1.4` and `/ncm.setup brakes 2.0`.
