# NCM 2.0 Phase 1 Playtest Protocol

Use one copy of the result table per run. Do not mark a master-plan task complete from author-only testing when its gate requires a newcomer.

## Run metadata

- Date/time:
- Tester:
- NCM build/hash:
- Cyberpunk version:
- CET / RED4ext / redscript / ArchiveXL / TweakXL / Codeware versions:
- Input: controller / keyboard and mouse / wheel:
- Resolution/aspect ratio:
- Save type: clean / 1.84 upgrade / early-2.0 upgrade:
- Other vehicle/gameplay mods:
- Video/log/save-fixture paths:

## Severity

- **S0 Blocker:** cannot install, load, create/restore career, or race.
- **S1 Critical:** progression/economy duplication, save loss, crash, unrecoverable race.
- **S2 Major:** phone/HUD route fails, misleading instruction, grid/finish failure with recovery.
- **S3 Minor:** copy, layout, timing, cosmetic, or low-impact inconsistency.

## First journey

- [ ] Install instructions are complete and unambiguous.
- [ ] On entering a playable session, one readable HUD toast says NCM is online and directs the player to Journal or Messages; it does not repeat during that session.
- [ ] First message appears once and identifies Night City Motorsports.
- [ ] NCM and Quickie are initially visible; specialist contacts are not unexplained clutter.
- [ ] A native NCM quest appears once in a normal playable state and its first objective is **Contact Dex**.
- [ ] The quest is visible in the Journal and quest tracker, remains coherent after save/reload, and does not create phantom duplicate entries.
- [ ] No `NCPD: Assault in Progress` or other vanilla activity notification appears at activation, over five idle minutes, after menus/fast travel, or after save/reload.
- [ ] Contacting Dex through **Phone → Messages → Dex - NCM Dispatch** completes the onboarding objective without adding a replacement SMS flow.
- [ ] Quinn's existing Quick Race route and all existing specialist conversations remain unchanged.
- [ ] No-career flow creates and selects `NCM Rookie` exactly once.
- [ ] Offer identifies event type, district, distance, field, pressure, requirement, reward, and consequence.
- [ ] Player can accept, route, approach, align, wait for grid, and start without CET or console.
- [ ] HUD instruction at each stage is actionable and readable at speed.
- [ ] Result explains sporting, money, reputation/season, rival/faction, opportunity, and next action.
- [ ] Result acknowledgement cannot duplicate settlement.
- [ ] Next-race prompt appears once.

## State interruption matrix

For each row: exit to menu/reload the save, then confirm recovery, messaging, and settlement count.

| State | Resume expectation | Pass | Evidence/defect |
| --- | --- | --- | --- |
| Offer displayed | Offer resumes or safely regenerates | [ ] | |
| Contact Dex objective active | Same objective returns without duplication | [ ] | |
| Offer accepted | Same staged objective remains | [ ] | |
| Traveling to start | Route/instruction returns | [ ] | |
| Grid forming | Clean recovery or explicit restage | [ ] | |
| Countdown | No duplicate stake; clean recovery/forfeit | [ ] | |
| Racing | Defined recovery/forfeit; no duplicate entry | [ ] | |
| Classification | Result completes exactly once | [ ] | |
| Results unacknowledged | Message retries; settlement does not | [ ] | |
| Results acknowledged | Next prompt does not repeat endlessly | [ ] | |

## Race and recovery matrix

- [ ] Grid forms normally.
- [ ] Delayed grid tells player to hold.
- [ ] Failed grid gives one recommended action and Race Control path.
- [ ] Manual-grid fallback is understandable.
- [ ] Ghost/simulated fallback is disclosed calmly.
- [ ] No eligible vehicle produces a useful instruction.
- [ ] Phone bridge unavailable leaves a documented CET recovery path.
- [ ] Win, middle, last, and DNF each settle correctly.
- [ ] Abort before staging is consequence-free.
- [ ] Abort during qualifying/countdown/race applies the documented forfeit once.
- [ ] Restart does not duplicate payout, reputation, part, contact event, or championship result.
- [ ] Visible, stuck, despawned, and untracked AI produce a coherent official classification.

## Upgrade and contacts

- [ ] 1.84 career loads without replaying beginner onboarding.
- [ ] Early-2.0 career loads without losing contact access.
- [ ] Clean career unlocks Race Control on first staging.
- [ ] Ledger unlocks after first completion.
- [ ] Bookie unlocks after first completion only when stakes are enabled.
- [ ] Setup Stu unlocks on first part, first DNF, or third completion.
- [ ] Scout unlocks on first named-rival/bounty encounter.
- [ ] Each introduction is delivered once.
- [ ] Corrupt onboarding state falls back without blocking racing.
- [ ] Deleted/switched careers do not leak incorrect prompts or unlock state.

## Long-session and display checks

- [ ] Complete an eight-event season and record route/rival repetition.
- [ ] Record earnings, expenses, parts, rep, heat, hype, fan, and contact frequency.
- [ ] Confirm the SP career championship closes and begins its next career competition without erasing persistent
      history/state. This is the legacy player-driven eight-race cycle, not the UTC calendar-quarter NCM Season (L100).
- [ ] Test 16:9 and ultrawide HUD safe areas.
- [ ] Test controller-only and keyboard/mouse phone flow.
- [ ] Review message volume for spam and stale advice.

## Result log

| ID | Step/state | Expected | Actual | Severity | Repro | Evidence | Owner/task |
| --- | --- | --- | --- | --- | --- | --- | --- |
| — | — | — | — | — | — | — | — |

## Run verdict

- [ ] Pass: no S0/S1, all first-journey items pass, settlement is idempotent.
- [ ] Conditional: no S0/S1 but one or more S2 defects need a recorded follow-up.
- [ ] Fail: any S0/S1 or player cannot complete the phone-first journey.
