# NOW — the single next-action index

> **STATUS: LEDGER** — living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) — classified 2026-09-24 (L125).

Last rewritten: **2026-09-24 — Market nullable-binding hotfix promoted through Development to Online.**
Commit `0406562` is on `origin/main`, and its resource file is running in the persistent world.

> **Claim before writing:** decisions through **L130**; MASTER_TEST through **2.18 / §AL**; next QA letter
> **§AM**. BACKLOG next free **IDEA-415**; known issues through **KB-99** plus the existing duplicate KB-87.
> Historical §Z collision remains: qualify by section (2.14 Machine Index vs 2.16 Help).

## Next action: visually confirm the recovered Market

The first post-fix request already passed the server path: `base_market / universal / NULL / open` was written,
the panel reported healthy in 13 ms and no old failure recurred. Confirm that the page visibly showed all three
authored offerings and the current balance, then open it once more. Re-query the row to prove the second open did
not duplicate it or rewrite `first_known_at`; record those last observations in MASTER_TEST §AL.

## Market recovery

The first live Market open after IDEA-251 failed in `NcmMarketKnowledge.ensureUniversal`, before any payload
reached WebUI. A universal market legitimately has no `source_ref`, but the adapter put Lua `nil` at position 6
of a seven-value SQL array. OPEN//77 rejected the shortened/holed parameter sequence as `invalid_parameters`.
Inventory, balance and the Market renderer were not the cause.

The fix uses the repository's established nullable-value contract: send a dense empty-string sentinel and let
`NULLIF(?, '')` restore database `NULL`. `tools/test-market-knowledge.lua` executes the real host adapter and
asserts seven non-nil positional parameters, the sentinel position and SQL conversion under Lua 5.4 and LuaJIT.
The full gate is green: **285 core tests per interpreter**, 41 cross-scope checks, the new 6-assertion Market
adapter check, 17 QA checks, 35 vehicle-access checks, **165 resource Lua files**, five WebUI scripts, 96 panel
assertions, 26 Driver Card assertions and documentation authority.

Development restarted at **21:29 EDT** with schema 30 / `pending=[]`, Market ready, HTTP 200 and empty stderr.
Commit `0406562` was pushed before production promotion. Fresh Online rollback artifacts were taken at
`20260925-013053`: a 230 KB database dump containing 63 tables and a 494 KB resource-tree archive. The named
`deploy-staging.ps1 -Target online` pipeline restarted Online at **01:32 UTC**. Service is active, health is 200,
schema remains 30, and the deployed fix hash `0453300b…` exactly matches local. There are no post-restart error
matches. Canonical counts remain 13 drivers, 13 bindings, 19 assets, 29 results, 23 ledger rows, 14 evidence and
14 discoveries; the sole server identity remains `ncm-dev`. At 01:34 UTC the first live Market request created
the intended knowledge row with a real SQL `NULL`, logged a healthy 13 ms panel open and produced no error. The
visual content confirmation and repeated-open idempotency check are the only §AL items still owed.

## Driver Card and rig work remain intact

The Driver Card distance correction remains deployed. MASTER_TEST §AK6 still needs a WebUI-capable observing
client to verify proportional scaling; the second local process cannot provide that proof while KB-4 leaves its
WebUI host disconnected. The owner's `ncm_default` banner state was already present and published.

The rig/FFB line through commit `3737a69` remains intact: generic wheel input, axis-level device detection,
panel arming, bounded feedback and cleanup. Its live calibration and owed checks remain in BACKLOG IDEA-395–412.

## Live QA still owed

- **§AL1–§AL2:** visual confirmation of three offerings and one repeated-open idempotency check. §AL3 passed.
- **§AK:** two-client Driver Card renderer handoff, presentation lifecycle and corrected distance scaling.
- **Rig/FFB:** the outstanding physical/in-game checks already named in BACKLOG and MASTER_TEST.
