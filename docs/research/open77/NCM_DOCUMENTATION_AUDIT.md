# NCM documentation audit

Date: 2026-09-18. Static code/document audit; no player usability test performed.

Existing work to preserve: root `NCM_MASTER_PLAN.md`, `NCM_PHASE1_PLAYTEST.md`, `NCM_QUEST_SPIKE.md`, `NCM_NEXUS_2_0_DRAFT.md`; payload README, NCM_2_0_SYSTEMS, VOICE_GUIDE and localization docs. The master plan already prioritizes a phone/quest-led first journey and preserves the current contacts. Do not start another competing onboarding redesign.

| Priority | Gap / evidence | Deliverable and acceptance criterion |
|---|---|---|
| P0 | README intended phone loop differs from unfinished native quest onboarding | Version-specific first-race guide: exact career creation, Dex entry, accept/route/stage/countdown/result actions; fresh install and upgrade playtests both reach a result |
| P0 | Quick Race described as consequence-free but finalizer writes money/heat/records outside career guard | Resolve product contract through playtest and owner review; publish accurate consequence table before release |
| P0 | Published permissions not captured locally | Link and preserve exact dated author permission/license text with attribution and asset/dependency exclusions; do not assign an invented SPDX license |
| P0 | Deep features scattered across SMS/CET and systems reference | One feature-to-contact/control map with prerequisites, unlocks, next action and fallback for each workflow |
| P1 | Career, prestige tier, reputation, championship points and faction standing overlap | Illustrated progression glossary and one worked race/result example showing separate ledgers |
| P1 | Live AI, estimated results, ghost fallback and ambient simulation can look equivalent | Explain modes and result provenance, grid delays and recovery; expose finishMode in diagnostics/result details |
| P1 | Parts, tuning sliders, rival hardware, shop offers and vehicle profiles overlap | Build workflow: acquire, install, inspect fit, tune, save/revert; distinguish inventory/build effects from TweakDB sliders |
| P1 | Ambient races, managed driver entry and box scores easily missed | Demonstrate hiring one driver, queueing an event, simulating or spectating, and finding the resulting box score; state live-format limits |
| P1 | Route/root/node terminology and per-root overrides are technical | Player-facing course names; separate author guide with IDs, directionality, units, checkpoint/lap rules and override precedence |
| P1 | Qualifying, standing/rolling starts and race readiness unclear | State-specific HUD/action reference; explain how qualifying affects grid and what blocks countdown |
| P1 | Betting includes winner picks and streaks, beyond a simple stake | Explain escrow, placement deadline, cancellation/refund, payout and reputation effects with examples |
| P1 | Installation dependency list lacks pinned supported versions | Tested compatibility table including game patch and optional integrations; isolate NCM from workspace MT hotfixes |
| P2 | Telemetry/records/history/box score views lack a data dictionary | Define route identity, sectors, estimated versus observed data, retention, safety incidents, DNF and filters |
| P2 | Developers must discover MTE coupling and cross-module side effects | Maintain architecture map, event/payload catalogue, storage schemas/migrations and lifecycle contract |
| P2 | Extension points exist but are informal | Document route packs, nodes/circuits, vehicle pool overrides, parts/slot profiles, factions, contact archetypes, translations and rulesets; validate examples |
| P2 | Version labels differ and public draft may lag runtime | Release checklist reconciles internal/build/public versions and marks planned/beta/reserved features |

Discoverability candidates: scouting persistent rivals; discipline/hardware fit advice; recurring contact offers; faction championships; ambient results and one-driver management; safety rating; root-specific settings overriding globals; telemetry route history; quick-race compatibility warnings; optional radio integration. Presence in source is not evidence users can reliably find these.

Recommended sequence: finish P0 contract and existing Phase 1 acceptance gates; publish concise user workflow maps; then produce author/developer references. Keep advanced solver/log terminology out of the first-race flow. Public-page editing is outside this task; retain local drafts only.

The public-page and permissions cross-check below completes the documentation audit; proposed workflow changes still need gameplay/usability validation.

## Current public-page cross-check

The [published NCM page](https://www.nexusmods.com/cyberpunk2077/mods/28713), checked 2026-09-18, still presents 1.84 as stable while describing 2.0 beta. It documents seven SMS contacts and warns that Foreman is slow, recommending CET for career/custom setup. Its requirement panel is shorter than the payload README. Public feature coverage is substantial; the larger gap is a clear, version-accurate workflow and reliable discovery, not simply listing more features.

Licensing verification is complete in NCM_ARCHITECTURE.md; the remaining P0 action is preserving a release-owned permission document and resolving server redistribution scope. No public text was changed.

Status: local and public documentation audit complete. Next action: review P0 items alongside the existing master plan, then execute fresh-install first-race acceptance tests before rewriting user guidance.
