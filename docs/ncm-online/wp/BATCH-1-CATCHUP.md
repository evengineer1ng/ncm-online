> **SUPERSEDED 2026-09-21.** Catch-up now lives in `docs/ncm-online/NOW.md` + `BACKLOG.md` (L68), which are
> kept current instead of hand-written per session. This file is kept as the record of where Batch 1 stopped.
> Note: Messages moved **F7 → F9** in the Batch 2 fix pass.

# Catch-up brief — paste this into a fresh session opened from C:\Users\eveng\Documents\cyberpunk2077

You are continuing NCM Online (the Cyberpunk 2077 motorsport mod "NCM" ported to the OPEN//77 multiplayer platform).
The previous session ended right after **deploying Batch 1 to the staging server without running its live validation**.
Your first job is to run that validation with me, one step at a time, exactly as written in
`docs/ncm-online/wp/BATCH-1.md` (Session A solo → Session B two clients → Session C regression), logging PASS/FAIL in
its Results table, fixing only what blocks everything, and leaving the rest for a fix pass afterwards.

## Read first (in this order)
1. `docs/ncm-online/wp/BATCH-1.md` — what was built, per-feature live scripts with exact commands and pass lines, the runbook.
2. `docs/ncm-online/KNOWN_BUGS.md` — KB-1..KB-11 (KB-4 second local client has no WebUI; KB-5 never restart with clients in;
   KB-8 hosted mods blocked upstream; KB-10 no headless vehicle physics; KB-11 bad intersection for the chauffeur).
3. `docs/ncm-online/OPS_STAGING.md` — staging server recipe (ssh, Warden tunnel, deploy script, flag scripts).
4. `docs/ncm-online/DECISION_RECORD.md` rows L50–L58 and P34–P46 — today's decisions (two products, fleet policy, tuning layers,
   event = discipline × format × class × venue × ruleset, dimensions never gate, zero-fault incidents + corrected time,
   telemetry, two tiers, chauffeur/authored routes, WebUI facts).
5. `docs/ncm-online/05_DATA_MODEL.md` — migrations 001–009 as built, 010 designed.

## State of the code (all offline-proven; nothing live-tested yet from Batch 1)
- Core (`ncm/core`, pure Lua, vendored into each resource by `tools\ncm-build.ps1`): 69 tests green under Lua 5.4 and LuaJIT
  (`powershell -NoProfile -ExecutionPolicy Bypass -File tools\ncm-test.ps1`).
- Host stub `tools\ncm-stub.lua` (fake Open77/MySQL, virtual clock): 13 scenarios green —
  `gridcars latearrival pickup authoring onboarding inbox holding dressing telemetry incidents tworace weekend progression`
  (`lua54 tools\ncm-stub.lua <name>`; run `tools\ncm-build.ps1` first).
- Staging (Lightsail, 52.60.225.137, OPEN//77 op77.84 Linux): Batch 1 deployed 2026-09-21 00:08 UTC; migrations 008/009 applied;
  `vocabulary seeded: 11 disciplines, 5 formats, 4 classes, 23 class vehicles, 2 rulesets`; venue `pacifica_stadium` has 4 points.
- Deploy: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-staging.ps1` (builds core, syncs, restarts, greps the log).
  Only when nobody is connected.

## What Batch 1 added (the eleven items)
1 questionnaire → affinity → secret offer (page on first join; `/ncm.q a` twin) · 2 messages inbox (F7, `/ncm.inbox`) ·
3 grid reveal + holding (REPORT TO GRID → team-coloured ring → hold E; lights wait for 75 % or 60 s on organized events) ·
4 venue dressing + loader (`/ncm.au dress <alias>`, `dress npc <template>`, `list/undo/up/down/clear`) · 5 competition
vocabulary (008: `ncm.event.post <route> <min> [sprint|weekend|tworace] [laps]`) · 6 telemetry (5 Hz client stream, chunks per
session, `ncm.telemetry`) · 7 zero-fault incidents + corrected time + live race graph (F8) · 8 weekend/two-race formats ·
9 oval/drag adapters (core only) · 10 driver dimensions (`/ncm.profile`) · 11 docs.

## How I like to work
- Small, exact, ordered steps; tell me exactly what to type and where (chat vs Warden console vs PowerShell). I paste whole logs.
- Don't hyperfixate on small bugs: log them (KNOWN_BUGS or the Results table) and move on.
- Never print secrets (licence key, DB password); read `server.jsonc` only through the masking tools.
- Never restart the server with clients connected.
- Warden console is reached at http://127.0.0.1:11790 through the SSH tunnel
  (`ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem -N -L 11790:127.0.0.1:11780 ubuntu@52.60.225.137`, keep the window open).
- Second local client: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-client.ps1 -Profile ncm-tester2 -Name ncmtester2 -Server 52.60.225.137:11778`,
  then in its dev console (`) `resource.emit open77:shell:autoconnect 52.60.225.137:11778 alpha`. It has no WebUI (KB-4): drive it from the Warden console.

## Where we stopped
Session A, step 2: rejoin staging with the main client → the Driver Profile questionnaire should open by itself
(chat: `Complete your NCM Driver Profile: press F7, or answer here with /ncm.q a|b|c|d.`). Pass line:
`Profile complete. Welcome to Night City Motorsports.` If the page ignores input, wait for the client log `panel input: no`
and use `/ncm.q a` six times. Then continue with the runbook.

## Open items outside the batch (don't start them unless I ask)
Dev asks for OPEN//77 (hosted-mod `Unverifiable` + loaders `NotInIndex`; `minSpeed`/`forcedStartSpeed` on vehicle AI) — drafted in
the record; questionnaire copy + team personality matrix (owner authors); Pacifica coordinates (captured with `/ncm.au` / `/ncm.aw`);
orientation film; audio beds; M8 discipline wiring for ovals/drag once a ring/strip is captured.
