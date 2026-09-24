# TW1 — controlled multiplayer QA + capture session: run sheet

> **STATUS: HISTORICAL** - Tester Window 1 run sheet. A record of a moment, never architecture.
> Authority map: [INDEX.md](../INDEX.md) - classified 2026-09-24 (L125)

Decision record L59–L63. Drafted 2026-09-21 with the Batch 2 host kit; the host fills the times on the day.
Field: 3–5 outside OPEN//77 alpha testers (run it with whoever turns up) + the host in-world (baremetaleven) + one
observer on Warden. Length: ~60 min of driving inside a 90-min slot. Testing outranks footage (L59).

## Before the day

- Staging green on the master test doc's Results table (Batch 1 leftovers + Batch 2), deploy pinned, no restart
  planned during the session (a restart takes ~100 s and kicks everyone, KB-5; use `ncm.scenario stop` /
  `ncm.world reset` instead).
- Routes authored and listed (`/ncm.ar list`): `gt1` (Troll Pass — built in), `bad1` (a Badlands stage, 2–3 gates),
  `drift1` (a downhill switchback stretch), `drag1` (a straight ~400 m, 2 gates), `ring1` (a large roundabout, 3 gates,
  loop). `ncm.scenario <discipline> <key> in 2` dry-run each one solo the day before.
- Testers installed per P34 (RB15 + liveries + ArchiveXL/TweakXL allow) — needed only for the Formula segment; the
  street car for everything else comes from the server.
- Recording: OBS on the host client (1080p60, game audio + voice on separate tracks); a second capture on the observer
  client if one exists. Shot list below.
- Warden tunnel open; `ncm.state` and `ncm.scenario field` ready in the console; `tools\deploy-staging.ps1 -Logs` tailing.
- The private Formula note (L61) ready to paste in voice/text once everyone is in.

## The hour

| T | Segment | Host does | Testers do | What we watch / capture |
|---|---|---|---|---|
| −10 | Join | greet, confirm everyone sees the HUD (`/ncm.debug` on each client), `ncm.scenario field` | join, press **F6** once (Race Guide), `/ncm.debug` | join reliability, WebUI on every client, driver IDs bound |
| 0 | Briefing (voice) | "we test, we record, we may stop and restart; say what you see; F6 guide, F9 messages, F8 graph" + the private Formula note | — | — |
| 3 | GT #1 (standing) | `ncm.scenario gt gt1 in 2` | drive to the line (map routes), race | first crossing, checkpoints, results board; **shot: grid + lights** |
| 9 | GT #2 (restart) | `ncm.scenario restart` | line up again, race | restart without a rejoin; `ncm.state` mid-race |
| 14 | Staged contact | `ncm.rules incidents on`; ask two cars to touch at speed on the straight | the two named cars touch, the rest race | both `INCIDENT x2`, corrected-time result; **shot: contact + banner** |
| 19 | Badlands | `ncm.scenario badlands bad1 in 2` | race the stage | off-road checkpoints, telemetry gaps; **shot: dust, jumps** |
| 25 | Drift | `ncm.scenario drift drift1 in 2` | timed run, sideways | incident scoring on walls; **shot: side-by-side drift** |
| 30 | Drag | `ncm.scenario drag drag1 in 2` (pairs; `restart` for the next pair) | two at a time | lane discipline, start reaction; **shot: head-on from the finish** |
| 36 | Oval (rolling) | `ncm.scenario oval ring1 laps 3 in 2` | formation behind pole under the cap, green, 3 laps | rolling start, lap counting, passing before green faults; **shot: pack through the green flag** |
| 44 | Leave / rejoin | ask one tester to quit to menu mid-race and rejoin | one leaves, rejoins | `SUSPENDED` → `RESUMED`, car re-claimed, HUD back (KB-5 risk noted) |
| 48 | Formula (private) | `ncm.scenario ncx gt1 weekend in 3` | seat offers auto-accepted; RB15 at the line; one-run quali → race | team cars, liveries, quali → grid routing; **shot: 10 s of the RB15 grid** (glimpse only, L61) |
| 58 | Wrap | `ncm.scenario stop`, `ncm.world reset`; thanks; where to report | — | ask each tester for one thing that confused them |

Recovery at any point: `ncm.scenario stop` → `ncm.world reset` → repost. If a client loses its UI: relaunch the
game (KB-5), `ncm.scenario restart` when they are back.

## Shot list (L62)

1. Grid + lights from behind the pack (GT #1). 2. First corner, three-wide. 3. A contact + the INCIDENT banner
(staged). 4. Badlands jump / dust. 5. Two cars drifting side by side. 6. Drag from the finish line, head-on. 7. The oval
pack through the green flag. 8. Race Guide page + a map route (UI). 9. Results board. 10. Ten seconds of the RB15 grid
(no explanation in the cut). Titles: *NCM ONLINE / TESTERS-RACERS WANTED / BUILT ON OPEN//77* → OPEN//77 Discord →
the NCM recruitment post. Single-player footage only for cinematic gaps, never as Online functionality.

## Log lines to keep for the write-up

Per scenario id (`S1`…): `POSTED`, `FORMED`, `gate OK … via=client|stream`, `INCIDENT`, `GREEN FLAG`, `COMPLETE`,
`SUSPENDED/RESUMED`, `STOP`, `WORLD RESET`; `ncm.state` dumps at 14 and 44; the client `/ncm.debug` lines at join.
