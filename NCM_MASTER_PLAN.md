# Night City Motorsports 2.0 — Master Development Plan

Last updated: 2026-09-03  
Implementation target: `ncm-localized` 2.0 payload  
Product direction: native quest-led discovery; preserve the existing SMS/contact system; CET for advanced tools and recovery

Terminology note (2026-09-22): this single-player plan's “season” and eight-event season refer to a player-driven
career competition. The global NCM competitive calendar uses UTC quarter identities (`YYYY-S1`…`YYYY-S4`) per
Online decision L100. Neither meaning implies a world-state reset; do not silently substitute one for the other.

## How to use this document

- `[ ]` not started; `[~]` active; `[x]` verified; `[!]` blocked; `[-]` deferred.
- A work package is complete only when its acceptance gate passes.
- Future prompts should name task IDs, for example: `Plan and implement P1.3`.
- Add discovered defects beneath the responsible task. Do not hide them in unrelated work.
- Update the decision log, evidence, and checkboxes after every implementation/testing prompt.
- Public Nexus changes require explicit approval after the local draft is reviewed.
- Planning and test artifacts at the workspace root must never enter the release archive.

## Current status

| Package | Status | Depends on | Next action |
| --- | --- | --- | --- |
| P0.1 Master plan | `[x]` | — | Keep current after every prompt |
| P0.2 Baseline | `[x]` | P0.1 | Re-capture before release candidate |
| P0.3 Validation commands | `[~]` | P0.2 | Add gameplay/content validator |
| P1.1 Product contract | `[x]` | P0 | Apply terminology to runtime copy |
| P1.2 Nexus/install communication | `[~]` | P1.1 | Review draft; verify dependency versions |
| P1.3 Persistent onboarding | `[~]` | P1.1 | Add fixtures and exercise runtime migrations |
| P1.4 Native quest onboarding | `[~]` | P1.3, recovered WolvenKit source | Prove one static quest entry, then implement `Contact Dex` |
| P1.5 SMS/contact redesign | `[-]` | — | Existing system is frozen; test it for regressions only |
| P1.6 Guided staging | `[ ]` | P1.4 | Rewrite HUD/readiness copy |
| P1.7 First result | `[ ]` | P1.3–P1.4 | Add idempotent result card |
| P1.8 CET repositioning | `[ ]` | P1.4, P1.6 | Replace Overview information hierarchy |
| P1.9 Automated checks | `[ ]` | P1.3–P1.8 | Build continuously with each package |
| P1.10 Manual validation | `[ ]` | P1.2–P1.9 | Execute `NCM_PHASE1_PLAYTEST.md` |

## Product contract

**Promise:** Build a racing career, meet persistent rivals, tune your car, and change Night City's underground motorsport scene.

**Normal player loop:** Receive the NCM onboarding quest → contact Dex through the existing phone entry → use Dex and the existing specialist contacts → accept and route to a race → stage and race → pursue consequences through the existing systems.

**Terminology:**

| Player-facing | Meaning |
| --- | --- |
| Career | Persistent progression, rivals, seasons, rewards, and consequences |
| Quick Race | Consequence-free sandbox race |
| Race Control | Staging, active-race actions, and recovery |
| Reputation | Career progress within the named prestige tier |
| Grid | The starting lineup |

`roots`, `nodes`, `solver`, raw `metrics`, internal race-state names, spawn paths, and fallback codes are Advanced/author terminology. They must not be required to complete the normal loop.

Every first-session message must answer: **what can I do, why should I care, and what do I do next?**

## Baseline evidence

- Release payload: 76 runtime files before audit documents; 1.83 contained 58.
- Approximate Lua size: 53,741 lines.
- Highest-risk modules: `racing.lua` 7,644 lines; `ai_vehicles.lua` 6,600; `race_commands.lua` 3,882; `ui_racing.lua` 2,265; `parts.lua` 2,054.
- Content snapshot: 39 named route pairs, 11 factions, 36 part IDs, approximately 66 inline vehicle-pool records, 11 contact-event archetypes, and one explicit checkpoint circuit.
- Localization: strict validation passes with 1,307/1,307 English keys present and no obsolete keys.
- Existing saves/configuration include `careers.json`, roster files, race telemetry/state, roots/routes, records, heat, safety rating, tuning profiles, settings, and versioned ambient-race state.
- Required runtime ecosystem evidenced by staged dependencies/package: Cyber Engine Tweaks, RED4ext, redscript, ArchiveXL, TweakXL, Codeware, Native Settings, Input Loader, and Custom Map Markers. Exact supported versions still require release-page verification.
- Known limitations: first launch points to CET; legacy quest/SMS probe is disabled; ambient observation/promotion settings are partly reserved; live promoted knockout is unsupported; management has one driver slot; authored circuit coverage is thin; no gameplay regression harness is present.
- Historical quest failure: earlier builds repeatedly surfaced an `NCPD: Assault in Progress` activity. Current evidence shows the NCM journal archive contains contacts only, `MTERaceQuestEvent` merely changes facts, and race markers use an orphaned `QuestStaticMappinDefinition/DefaultQuestVariant`. Treat that combination as contaminated legacy plumbing, not as a foundation for the new quest.
- Nexus baseline on 2026-09-02: header still reports 1.84; 2.0 is described as beta; description leads with framework/features; normal onboarding ends with “check CET.”

## Phase 0 — Program control

- [x] **P0.1 — Create master plan**
  - [x] Stable IDs, statuses, dependencies, gates, decisions, evidence, and deferrals recorded.
- [x] **P0.2 — Capture untouched baseline**
  - [x] Package size, module sizes, content counts, localization, saves, dependencies, and limitations recorded.
- [~] **P0.3 — Establish validation commands**
  - [x] Localization command documented.
  - [x] Read-only inventory commands documented.
  - [x] WolvenKit CLI 8.20.0 installed locally, checksum verified, and archive inspection documented.
  - [ ] Add a single gameplay/content validation runner during P1.9.
- [x] **P0 gate:** status and next safe task are recoverable from this document.

### Baseline validation commands

Run from the workspace root:

```powershell
$env:UV_CACHE_DIR="$PWD\.uv-cache"
uv run --no-project python tools/ncm_i18n.py validate --strict
```

```powershell
Get-ChildItem ncm-localized -Recurse -File | Measure-Object Length -Sum
Get-ChildItem ncm-localized\bin\x64\plugins\cyber_engine_tweaks\mods\MT_Ecosystem\modules -File |
  Sort-Object Length -Descending | Select-Object Name,Length
```

```powershell
rg -n -i "TODO|FIXME|HACK|stub|placeholder|reserved|not implemented|deprecated" ncm-localized
rg --files . | rg -i "(test|spec|lint|ci)"
```

WolvenKit CLI is pinned locally at `tools/WolvenKit.Console-8.20.0/WolvenKit.CLI.exe`.
Inspect the cooked NCM archive without extracting or changing it:

```powershell
& ".\tools\WolvenKit.Console-8.20.0\WolvenKit.CLI.exe" `
  archive ".\ncm-localized\archive\pc\mod\mt_ecosystem.archive" `
  --list --verbosity Minimal
```

Expected archive members:

```text
mt_ecosystem\journal\mt_ecosystem.journal
mt_ecosystem\localization\en-us\onscreens\mt_ecosystem.json
```

Do not use `build` as a release gate until the canonical `.cpmodproj` and raw project
sources are restored. The current workspace contains only the cooked `.archive`.

## Phase 1 — Complete first player journey

### P1.1 — Product contract

- [x] Define the one-sentence promise and normal player loop.
- [~] Standardize Career, Quick Race, Race Control, Reputation, prestige tier, Grid, and native quest-onboarding terminology.
- [x] Classify internal route/spawn terminology as Advanced.
- [x] Create a shared glossary.
- [ ] Validate every runtime first-session surface against the three-question copy rule during P1.4–P1.8.
- [x] **Artifact gate:** contract and glossary are recorded above and used in the Nexus/README drafts.

### P1.2 — Nexus and installation communication

- [x] Draft fantasy-first Nexus summary and description.
- [x] Position 2.0 as public beta and 1.84 as stable fallback.
- [x] Cover activity, first five minutes, features, requirements, installation, updating, limitations, troubleshooting, integrations, and bug reports.
- [x] Explain phone-first normal play and CET advanced/recovery role.
- [x] Add screenshot/video shot list.
- [x] Add a player-first guide to the packaged README while preserving technical tuning reference.
- [ ] Verify exact supported dependency/game versions and all outbound links.
- [ ] Review `NCM_NEXUS_2_0_DRAFT.md` with the author.
- [!] Live publication is blocked pending explicit author approval.
- [ ] **Acceptance gate:** an external reader answers compatibility, installation, first action, core loop, beta status, and recovery path using the draft alone.

### P1.3 — Persistent onboarding state

- [x] Add focused `modules/onboarding.lua`; do not expand `race_commands.lua` with persistence policy.
- [x] Persist versioned `save/onboarding.json` with per-career milestones and specialist unlocks.
- [x] Migrate `phoneIntroPingSent`; infer established careers from history without replaying tutorials.
- [x] Implement idempotent `getState`, `mark`, `shouldPrompt`, `unlockContact`, and `reset` methods.
- [x] Fall back to session-only state if persistence fails; racing must remain available.
- [ ] Test clean, upgraded, corrupt, deleted-career, and switched-career cases.
- [ ] **Acceptance gate:** prompts neither disappear early nor repeat after completion/reload.

### P1.4 — Native quest onboarding

- [-] Rejected prototype: `Tonight's Race` command/card/dispatcher. Removed completely on 2026-09-03.
- [x] Restore Quinn's `Quick Race` label, `ncm_route_quickie` routing, command table, REDscript mapping, and original cooked archive byte-for-byte.
- [ ] Freeze the existing SMS/contact architecture: no renamed routes, replacement menus, consolidated dispatcher, or contact-role redesign in this phase.
- [x] Reject the physical signup location and persistent pre-activation mappin; they add travel and authoring work without solving the core discovery problem.
- [~] Show one native HUD toast per loaded gameplay session: `NCM network online. Check your Journal or Messages.` Implementation is complete; in-game timing/readability still requires validation.
- [~] **P1.4a — Static quest proof:** add the minimum valid `quest → phase → objective` hierarchy to the cooked journal and prove it can be activated, displayed, tracked, completed, and reloaded without phantom entries.
- [x] Offline resource half: added the mapless hierarchy at `quests/ncm/ncm_onboarding/contact_dex/contact_dex`, compiled localization, packed exactly two resources, and verified the re-extracted CR2W structure.
- [x] Add a standalone, manually operated, default-inert REDscript spike controller and CET helpers. It has no load/update activation path and no dependency on race/SMS state.
- [x] Deploy the inert spike and pass REDscript compilation; runtime quest activation remains deliberately manual and unverified.
- [ ] Keep this first proof deliberately static: one quest, one objective, no race mutation, no SMS changes, and no dependency on CET career creation.
- [ ] Implement the proof through a new isolated quest controller and new namespaced journal paths. Do not reuse `MTERaceQuestEvent`, `ncm_race_active`, the legacy track-mappin callbacks, or an orphaned `QuestStaticMappinDefinition`.
- [ ] Before enabling the proof, obtain a known-good quest resource hierarchy and activation sequence from shipped game data or another verifiable working resource; do not guess journal field structure.
- [ ] Add a hard edge-trigger/dedup guard: state changes only when the desired quest state differs from the last applied state; never toggle Inactive → Active from an update loop to force a notification.
- [ ] Add a kill switch enabled by default during the spike. One setting/fact must immediately prevent further quest activation without disabling the existing phone or race-state bridge.
- [ ] Record the exact journal paths, entry classes, state-transition order, tracking behavior, and REDscript compile/runtime evidence before generalizing it.
- [ ] Explicitly regression-test for the historical looping `NCPD: Assault in Progress` notification at first activation, after five minutes, after save/reload, after fast travel, and after returning from menus.
- [ ] **P1.4a gate:** `Contact Dex` appears once in the native Journal/quest tracker, survives save/reload, can be completed cleanly, and produces zero NCPD activity notifications.
- [ ] **P1.4b — Contact Dex onboarding:** surface the quest after the player reaches a normal playable state and the NCM journal resource is ready.
- [ ] Use a concise NCM-flavored quest title and the objective `Contact Dex`; do not add a new dispatcher, card, or explanatory SMS layer.
- [ ] Activate Dex through the existing journal/contact path. Complete the objective when the player opens or meaningfully interacts with Dex's existing NCM conversation.
- [ ] Create/select `NCM Rookie` only at the first existing Dex action that requires a career, or at another explicit existing action; merely loading the mod must not silently create a career.
- [ ] Complete/retire the onboarding quest after Dex contact and mark the persisted onboarding milestone idempotently.
- [ ] Established 2.0 careers infer onboarding completion and retain every existing contact and conversation unchanged.
- [ ] Allow the tutorial to be skipped without disabling NCM and provide concise recovery instructions in CET.
- [x] Restore the WolvenKit 8.20.0 authoring environment on the new Windows installation.
  - Portable build installed at `tools/WolvenKit-8.20.0`; official GitHub SHA-256 verified.
  - Cyberpunk executable detected at `C:/Program Files (x86)/Steam/steamapps/common/Cyberpunk 2077/bin/x64/Cyberpunk2077.exe` for first-run configuration.
- [x] Recover and verify the canonical WolvenKit project source for `mt_ecosystem.journal`.
  - Project: `wolvenkit-projects/mt_ecosystem/mt_ecosystem.cpmodproj`.
  - Editable source: `source/raw/mt_ecosystem/journal/mt_ecosystem.journal.json`.
  - JSON-to-CR2W round trip is byte-identical to the shipped journal.
  - Direct CLI packing of `source/archive` reproduces both shipped archive members byte-for-byte.
  - WolvenKit CLI 8.20.0 `build` incorrectly packs the project root in this environment; use the proven direct `pack --path source/archive` validation until GUI project building is separately verified.
- [ ] **P1.4c — Per-race quest shell:** only after P1.4a/b pass, add one reusable race quest whose title/objective state follows accepted → travel → stage → race → result.
- [ ] Keep the current proven `CustomPositionVariant` waypoint for automatic GPS; the old REDscript track-mappin path remains disabled unless a verified engine API replaces it.
- [ ] Refresh race text and location without creating unbounded journal entries or relying on dynamic cooked IDs.
- [ ] Abort, DNF, completion, restart, and save/reload must leave exactly one coherent quest state and no stale tracked objective.
- [ ] **Acceptance gate:** on a clean install, a player sees `Contact Dex`, reaches Dex's existing NCM conversation, accepts an existing race, receives native quest guidance and automatic GPS, and completes the race without CET, console use, or author coaching; Quinn and every existing SMS route behave exactly as before.

### P1.5 — SMS/contact architecture freeze

- [-] Progressive contact reveal and contact-role redesign are removed from Phase 1 scope.
- [ ] Regression-test Dex, Quinn, Rico, Stu, Foreman, Billie, and #1 Fan after signup activation.
- [ ] Confirm Quick Race remains owned by Quinn and all existing routes, branches, replies, and dynamic text remain intact.
- [ ] Limit contact changes to the minimum activation gate required by signup.
- [ ] **Acceptance gate:** signup adds discoverability without changing how any existing SMS feature works.

### P1.6 — Guided staging

- [ ] Explain eligible vehicle, route, start-area entry/alignment, grid formation, and recovery after offer acceptance.
- [ ] Translate blockers into actions; hide detailed diagnostics unless debug mode is enabled.
- [ ] Native sequence: route → approach → align/hold → forming → ready → countdown → race → classification → result.
- [ ] Grid failure provides one recommended recovery action and Race Control route.
- [ ] Manual-grid/ghost fallback is candid but calm.
- [ ] **Acceptance gate:** first-time tester stages/starts without console, coaching, or debug telemetry.

### P1.7 — First result

- [ ] Present position/time, money, reputation/tier, season movement, rival/faction effect, opportunity, and next action.
- [ ] Choose only the highest-value consequence per category; retain detail in specialist/CET surfaces.
- [ ] Separate result acknowledgement from settlement; message retries may never re-award anything.
- [ ] Send one next-race prompt after acknowledgement or close.
- [ ] **Acceptance gate:** player can explain what changed, why it matters, and what to pursue.

### P1.8 — CET repositioning

- [ ] Overview shows signup/tutorial status, active objective, career progress, pressure/rival, vehicle readiness, health, and Dex recovery guidance.
- [ ] Mark Routes, Metrics, raw Telemetry, pool overrides, and detailed tuning Advanced.
- [ ] Preserve all power-user tools.
- [ ] Add confirmed onboarding reset and compatibility diagnostics in Settings.
- [ ] **Acceptance gate:** CET is a useful dashboard/recovery tool without being required for normal play.

### P1.9 — Automated checks

- [ ] Onboarding transition and migration fixtures.
- [ ] Quest-state transitions, established-career inference, interrupted Dex contact, and explicit career creation tests.
- [ ] Contact unlock predicate tests.
- [ ] Result-card purity/idempotency tests.
- [ ] Lua/REDscript phone ID consistency and uniqueness test.
- [ ] Localization and placeholder validation.
- [ ] Release-exclusion validation for saves/tests/planning files.
- [ ] One documented command, non-zero on failure.

### P1.10 — Manual validation

- [ ] Execute and record `NCM_PHASE1_PLAYTEST.md`.
- [ ] Clean install; 1.84 upgrade; early-2.0 upgrade; missing eligible vehicle; missing phone bridge.
- [ ] Grid success/delay/failure/fallback; win/mid/last/DNF/abort/restart.
- [ ] Reload during offer/prerace/race/classification/results.
- [ ] 16:9, ultrawide, controller, keyboard/mouse.
- [ ] Record first-race journey and full eight-event season.
- [ ] **Phase 1 gate:** independent newcomer completes the journey and no settlement applies twice.

## Phase 2 — Consolidate the core loop

- [ ] **P2.1** Unified post-race fallout for every race.
- [ ] **P2.2** Rival arcs: encounter, escalation, counter-build, rematch, resolution.
- [ ] **P2.3** Heat-driven event mutations and visible consequences.
- [ ] **P2.4** Telemetry coaching with Safe, Street, and Qualifying recommendations.
- [ ] **P2.5** Atomic economy service for stakes, bets, management, and rewards.
- [ ] **P2.6** Compatibility model: healthy, degraded, blocked.
- [ ] **P2.7** Split race configuration, state, progression, classification, settlement, and world adapter.
- [ ] **Phase 2 gate:** existing modes retain behavior and players understand consequence/recovery.

## Phase 3 — Progression and authored content

- [ ] **P3.1** Five to eight validated multi-checkpoint circuits.
- [ ] **P3.2** District mini-series with distinctive rules/finales.
- [ ] **P3.3** Gameplay-distinct faction identities.
- [ ] **P3.4** Prestige ceremonies and meaningful unlock packages.
- [ ] **P3.5** One authored rival storyline per prestige tier.
- [ ] **P3.6** Vehicle-class and bike championships.
- [ ] **P3.7** Choose polished single-driver contracts or full team management.
- [ ] **Phase 3 gate:** seasons, opponents, and goals are recognizable without reading raw numbers.

## Phase 4 — Night City world presence

- [ ] **P4.1** Visible promoted ambient-race preparations.
- [ ] **P4.2** Invitations, racers in transit, aftermath, and faction starts.
- [ ] **P4.3** Police disruption/escape event.
- [ ] **P4.4** Selective authored voice for milestones/rivals.
- [ ] **P4.5** Optional, non-blocking Radio integration.
- [ ] **P4.6** Community route-pack schema, validator, and guide.
- [ ] **Phase 4 gate:** players encounter the ecosystem naturally in Night City.

## Deferred until earlier gates pass

- [-] Multi-driver team management.
- [-] Sponsor simulation.
- [-] Additional currencies.
- [-] More raw tuning parameters.
- [-] Large generic vehicle-pool expansion.
- [-] Procedural voice for routine messages.
- [-] Multiplayer/online leaderboards.
- [-] Full pit and repair simulation.

## Decision log

| Date | Decision | Reason |
| --- | --- | --- |
| 2026-09-02 | Player experience is the primary lens | Systems exist but their meaning is poorly surfaced |
| 2026-09-02 | Phone-first normal journey | Superseded on 2026-09-03 by native quest discovery leading into the unchanged phone network |
| 2026-09-02 | Complete first journey is Phase 1 | Fix the whole promise from download through next reason to race |
| 2026-09-02 | Progressive contact reveal | Rejected on 2026-09-03; existing contact architecture is intentionally preserved |
| 2026-09-02 | Auto-create `NCM Rookie` on Tonight | Rejected on 2026-09-03; signup must be an explicit in-world player action |
| 2026-09-02 | Market 2.0 as public beta | Fresh-install and upgrade matrices are not yet proven |
| 2026-09-02 | Draft Nexus copy locally before publication | Separates reviewable content from external mutation |
| 2026-09-02 | Use WolvenKit 8.20.0 stable for journal work | Current official stable release; installer digest verified against GitHub |
| 2026-09-02 | Treat recovered journal JSON as canonical source | WolvenKit 8.20.0 converts it back to a byte-identical CR2W resource |
| 2026-09-02 | Gate archive changes with direct CLI packing | CLI `build` 8.20.0 packed project-root paths; direct `pack source/archive` produced the correct two-member archive |
| 2026-09-03 | Preserve the existing SMS system | Quinn, Rico, Dex, and the other contacts already cover the intended roles; the actual gap is discovery and tutorialization |
| 2026-09-03 | Use an in-world signup location | Superseded the same day: it adds friction where a native `Contact Dex` quest is sufficient |
| 2026-09-03 | Replace the signup location with a native quest | `Contact Dex` directly solves discovery with less friction and preserves the existing phone design; a per-session HUD toast points players to Journal/Messages |
| 2026-09-03 | Show the NCM-online toast every gameplay load | Returning players may have forgotten the mod; suppress repetition only within the same uninterrupted session, never permanently |
| 2026-09-03 | Quarantine the legacy quest plumbing | Earlier attempts looped `NCPD: Assault in Progress`; the archive has no real quest hierarchy and its orphaned quest-variant mappins are the leading fallback trigger |

## Playtest evidence

No Phase 1 in-game run has been recorded yet. Use `NCM_PHASE1_PLAYTEST.md`; link logs, screenshots, video timestamps, save fixture, game version, dependency versions, and result here after each run.
