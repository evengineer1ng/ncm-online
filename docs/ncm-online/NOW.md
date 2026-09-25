# NOW — the single next-action index

> **STATUS: LEDGER** — living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) — classified 2026-09-24 (L125).

Last rewritten: **2026-09-25 — full platform-freeroam eviction verified in Development; Online activation pending.**

> **Claim before writing:** decisions through **L132**; MASTER_TEST through **2.18 / §AM**; next QA letter
> **§AN**. BACKLOG next free **IDEA-420**; known issues through **KB-102** plus the existing duplicate KB-87.
> Historical §Z collision remains: qualify by section (2.14 Machine Index vs 2.16 Help).

## Next action: promote the verified eviction without repeating the Kazami restart race

Development now excludes both `freeroam` and `open77_freeroam` from `resources.load` and no longer carries the
`freeroam` discovery tag. The independent `open77_animations` resource remains. A clean Development restart at
00:55 EDT proved: dependency audit green (36 explicit resources), neither freeroam resource discovered or
started, animations and both NCM resources started, schema 30 / `pending=[]`, health 200, empty stderr and zero
boot errors. The repository gate is green after the idempotency repair to the vendor-tree script.

The same change still needs to be staged and activated on Online. Before any restart: push the commit, take a
fresh database/resource/config rollback set, verify the effective config, and query current players. Re-check
immediately before restart. That narrows but does not close KB-102: the prior restart entered `Stopping` at
04:39:23 UTC, accepted Kazami at 04:39:29, and kept the listener alive until systemd killed it at 04:40:53.
There is no proven admission-drain mechanism yet; do not describe an empty preflight as a lock.

## What changed (L132 / IDEA-416)

`tools/staging/close-freeroam-sandbox.py` now enforces the whole boundary:

- remove `freeroam` and `open77_freeroam` from the load list;
- remove the `freeroam` server tag;
- keep `open77_animations` loaded;
- retain the earlier restricted-command, PvP-off and race/PvP manifest edits as defence in depth;
- print and validate the resulting load state; and
- remain reversible and idempotent across upgrades.

This removes the platform vehicle/weapon menu, `/freeroam`, `/car`, platform `/race`/`/footrace`, `/pvp`/`/dm`,
the separate freeroam persistence/wallet resource and the forced kill-respawn on every join. `/anim <profile>`,
`list`, `info` and `stop` remain. The no-argument animation picker leaves with freeroam.

## Honest lifecycle gap

NCM does not yet own respawn-after-death. `open77_death` observes life state but does not respawn, and no NCM
handler replaces freeroam's `/revive`/auto-respawn. Until that is built and tested, reconnecting is the honest
workaround after death. This gap no longer vetoes the authority boundary.

KB-101 also remains: NCM can save a not-yet-incarnated player's origin placeholder and later restore it. That
is independent of freeroam and still needs the readiness/origin guards already recorded.

## Live QA still owed

- **§AM3–§AM7:** activate Online, verify boot, then use a real client to prove no join death, no sandbox
  commands, animations still work, and record current death behavior.
- **§AL1–§AL2:** visually confirm the three Market offerings and repeated-open idempotency. §AL3 passed.
- **§AK:** two-client Driver Card renderer handoff, presentation lifecycle and corrected distance scaling.
- **Rig/FFB:** the outstanding physical/in-game checks named in BACKLOG IDEA-395–412.
- Still owed from earlier: IDEA-251 full Market live PASS, §AH21 incident attribution, migration 028 fresh-world.
