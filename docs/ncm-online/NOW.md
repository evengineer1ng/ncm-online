# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-26 - Parts economy/UI v1 is deployed and enabled on the private Online development
surface (`L162`, `L163`), with offline catalogue/R&D and panel coverage green. Live Parts PASSes remain owed.**

> **Claim before writing:** decisions through **L163**; MASTER_TEST through **§BF**; next QA letter **§BG**.
> BACKLOG next free **IDEA-540**; known issues through **KB-153**. Read ledger tails before allocating.

## One next action

**Deploy the `KB-153` bounded Market stream to Online, restart once empty, then open Market for the first live
25-component reassembly PASS.** After the panel draws, continue §BF1-§BF3 database audits and the first purchase.

1. Apply forward migrations 031-032 and boot twice.
2. Audit that existing vehicle identity/history is untouched.
3. Verify deterministic factory backfill: exactly 11 component assets, 19 occupied interfaces and one current
   configuration for every existing MaiMai, Galena and Hella; replay creates nothing; original exposure equals
   the Machine odometer.
4. Audit the 25 immutable launch Designs, exact prices/effects/supply and the 7/8/7 Sport fitment counts.

Online is presently the development/test surface and Parts ships enabled there (`L163`); do not create another
environment split for this work. Continue BF4-BF17 on Online after the database audits. The emergency live
tunable may park purchases/fitting, but lack of a completed QA row is recorded as awaiting evidence rather than
used to hide the deployed surface (`L69`).

## What was built this session

- Migrations 031-032 add immutable component Designs/revisions, manufacturing runs, physical assets, three
  serial histories, custody/transfers, supply/R&D state, multi-position configuration revisions and operations.
- `parts.catalogue` defines the 25 launch Designs, nineteen interfaces, exact Base Market economics and authored
  starter compatibility. Unresolved compatibility cannot enter primary distribution.
- `parts.rnd` and the server scheduler implement deterministic maker evaluations, quantized bounded effects,
  novelty/no-design outcomes, deterministic pricing and invisible undistributed specialist outcomes.
- Production mints physical assets; Market aggregates by Design and purchases claim the oldest exact unit.
- Existing supported Machines backfill deterministic factory originals without invented historical serials.
  Future manufactured Machines and all eleven factory assets/configuration commit in the same transaction.
- Base Market now has independently scrollable Machine/Component panes, a persistent detail panel and an
  on-by-default fitment overlay that keeps both compatible and incompatible cars visible.
- Machine Index has MACHINES / PARTS INVENTORY tabs, component provenance, availability/fitment projection and
  a 900 ms hold-to-fit transaction. Displaced assets return to inventory; required interfaces cannot be empty.
- Vehicle cards reserve six performance metrics and say `Not rated`. Relative part projections disclose
  DIRECT/MODELLED fidelity and limitations instead of fabricating absolute performance.
- Odometer flushes advance installed component exposure in the same durable operation. There is no wear effect.
- Market payload v2 separates vehicle/component streams; inventory has its own stream. Persistent configuration
  hydrates the existing `NcmHandling.setParts` seam on restart and world reconciliation paths.

## Offline evidence

- Core gate: **458 passed, 0 failed**, including five launch catalogue/R&D tests.
- QA observer: **17 passed, 0 failed**; vehicle access: **35 passed, 0 failed**.
- Panel render: green, including split market panes, mixed fitment overlay, exact next-unit serial, future-planning
  warning, factory-original inventory and eligible hold-to-fit.
- Nameplate/race render checks green; documentation authority reports 74 valid documents and 419 unique ledger IDs.
- Final full gate: **ALL GREEN under every interpreter** after session-close bookkeeping.

## Still live and unchanged

The previous driving work remains owed: §BA top-speed capability/read-back, §AY serialized seam equivalence,
§BB tyre window, §BC weather/time and §BE road-vs-tyre. §BF16 deliberately depends on §AY and §BA before any
paid performance claim ships. Useful commands remain:

```
/ncm.topspeed 40
/ncm.ratedtopspeed
/ncm.setup power_unit 2.0
/ncm.setup tires 1.4
/ncm.setup brakes 2.0
```

The accidental `brakeScale`/aerodynamic-drag coupling (`IDEA-538`) is still open and should be measured before
it is split. No Parts code in this session changes the carrier's proven three-lever boundary.
