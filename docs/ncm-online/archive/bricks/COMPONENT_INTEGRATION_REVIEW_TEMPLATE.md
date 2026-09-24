# INTEGRATION REVIEW — B-<IDEA>-<slug> v<N> — R<k>

> **STATUS: HISTORICAL** - brick template - closed experiment. A record of a moment, never architecture.
> Authority map: [INDEX.md](../../INDEX.md) - classified 2026-09-24 (L125)

*Written by the integrator after reading the brick against the live repository. One verdict, a numbered list, and
nothing the author cannot act on. The author revises from this packet alone; do not re-explain the repository.
Saved as `ncm/bricks/<id>/reviews/R<k>.md`.*

## Verdict (exactly one)
- [ ] **ACCEPTED** — admitted as delivered.
- [ ] **ACCEPTED WITH ADAPTER CHANGES** — admitted; the integrator changed only host wiring / provided modules, listed below. No author action.
- [ ] **REVISION REQUIRED** — return to author; a v<N+1> is expected. Items marked **blocking** must all be resolved.
- [ ] **REJECTED** — not proceeding; reason below; the IDEA row is updated with why.

## Offline gate result
`lua5.4`: N passed, M failed · `luajit`: N passed, M failed · `luac -p`: clean / errors
(Paste the failing test names only.)

## Findings
Each finding has a category, a severity, a location, and the exact change wanted. Categories:

`incorrect-assumption` · `interface-mismatch` · `test-failure` · `architecture-violation` ·
`semantic-drift` (sporting meaning changed) · `runtime-constraint` (something the live platform does that the
packet did not say) · `purity` · `compat` (interpreter intersection) · `style` · `docs`

| # | Category | Blocking? | Where | What is wrong | Wanted instead |
|---|---|---|---|---|---|
| 1 | interface-mismatch | yes | `evaluate()` return | returns `tags[]` of strings | `tags[]` of `{ id, label }` — host needs the stable id for the profile count |
| 2 | runtime-constraint | no | `facts.crossings` | assumed dense | live data has gaps when a client stalls; treat a missing gate as absent, not 0 |

## Packet corrections (things the assignment got wrong — the author is not at fault)
- (e.g. "packet said `state = "timed"`; live rows say `"finished"` after settlement — schema updated to v2")

## What the integrator changed (ACCEPTED WITH ADAPTER CHANGES only)
- host seam: `server/race.lua complete()` calls `M.evaluate(facts)` after progression, before announce
- provided module bump: none

## Newly discovered constraints for the gate itself
- (anything that should become a rule in `COMPONENT_GATE.md` — filed there under the next gate revision)

## Next step
- Author: deliver v<N+1> addressing #1, #2 (blocking) — optional #3.
- Integrator: on ACCEPTED, move to `ncm/core`, add MANIFEST line, run `tools\ncm-test.ps1`, wire seam, set BRICK.md
  `status: integrated`, set the IDEA row to `built`, add the live QA rows to `wp/MASTER_TEST.md`.
