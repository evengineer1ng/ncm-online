# Night City Motorsports workspace

NCM is an existing, publicly released single-player Cyberpunk 2077 racing and career framework. Preserve its working release and solo roadmap. This workspace also contains release snapshots, recovered assets and personal mod tooling; it is not all one runtime package.

## Start here

- Working payload: `ncm-localized/`.
- CET entry: `ncm-localized/bin/x64/plugins/cyber_engine_tweaks/mods/MT_Ecosystem/init.lua`.
- Lua systems: the adjacent `modules/` directory. `racing.lua` orchestrates races/results, `ai_vehicles.lua` owns native physical AI, `roster.lua`/`championships.lua`/`ambient_races.lua` own much of the persistent racing world. Phone commands pass through `phone_bridge.lua` and `race_commands.lua`.
- Native presentation/assets: `ncm-localized/r6/scripts/` and other payload directories; recovered authoring sources under `wolvenkit-projects/mt_ecosystem/`.
- Existing product work: `NCM_MASTER_PLAN.md`, `NCM_PHASE1_PLAYTEST.md`, `NCM_QUEST_SPIKE.md`. Continue the existing onboarding plan rather than starting a competing redesign.
- `staging/checkpoint-03/extracted/28713/release2.0` is a snapshot, not the editing target.

## Session memory (read this before anything else)

`docs/ncm-online/NOW.md` says where the project is and what the one next action is; it is **rewritten** at the end
of every working session. `docs/ncm-online/BACKLOG.md` is the **append-only** idea ledger — every idea, feature,
concern and fix, with a permanent ID, captured when it is spoken rather than when it is scheduled (L68). Rows
change state; they are never deleted.

At the end of every session: append any new ideas to `BACKLOG.md`, record any decisions in `DECISION_RECORD.md`
(never a new document), log any defects in `KNOWN_BUGS.md`, rewrite `NOW.md`, and keep `INDEX.md` accurate if any
document changed status. `tools/ncm-test.ps1` asserts the documentation invariants, so a lapse fails the gate. Do not hand-write a fresh
catch-up brief — `NOW.md` plus `BACKLOG.md` is the catch-up brief.

Nothing is *done* because it is built. It is done when a live PASS sits beside it in `wp/MASTER_TEST.md` (L69).

## OPEN//77 work

Read [docs/research/open77/README.md](docs/research/open77/README.md) and its seven assessment documents before implementation. **The entry point for NCM Online documentation is [docs/ncm-online/INDEX.md](docs/ncm-online/INDEX.md)** — the authority map. It says which document currently governs which topic, and lists known conflicts rather than resolving them silently. Every document carries a STATUS banner (CURRENT / SPEC / PROPOSAL / SUPERSEDED / HISTORICAL / LEDGER); superseded and historical material lives in `docs/ncm-online/archive/`, preserved but no longer equally discoverable (L125). **Document number and date confer no authority.** The living decision record (LOCKED / PROVISIONAL / OPEN / EXPERIMENTS) is `docs/ncm-online/DECISION_RECORD.md`; update it, not a new document, when a decision changes. Reconnaissance dated 2026-09-18 is static analysis plus primary-source/MCP research; no multiplayer experiments passed. Major OPEN//77 implementation must wait until the reconnaissance is reviewed. Documentation corrections and further read-only research may continue.

Do not assume native CET spawning, mutable single-player globals, TweakDB tuning or JSON saves are network-safe. Platform AI needs a simulating client; off-screen statistical racing is separate. Query current build-pinned official API cards before using methods; preview docs conflict in places. Preserve observed/simulated result provenance.

Published NCM permissions require attribution and restrict reupload of original files; see the architecture document. Official Freeroam/Race source is noncommercial-licensed; the official devkit is MIT. Do not assume their licenses or third-party asset rights are interchangeable.

Keep discoveries and experiment outcomes in the research folder, with completed work, unresolved questions and next action. No production behavior was changed by this reconnaissance. Use isolated prototypes and back up saves before later implementation/testing.
