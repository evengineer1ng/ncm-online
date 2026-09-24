# WP M4-lite — Invitational foundations: organized events, teams & seats, race control

> **STATUS: HISTORICAL** - completed work package. A record of a moment, never architecture.
> Authority map: [INDEX.md](../../INDEX.md) - classified 2026-09-24 (L125)

Milestone: M4 (lite slice, first of the TW1 chain — see 04_TESTER_WINDOW_1.md). Status: **COMPLETE 2026-09-20 10:44** (live: offers/accept, seat-ordered grid, penalty + audit; DSQ not exercised live — core-tested). Decisions: L18, L19, L43, L45, P21, P23 (offer is a Messages-v0 placeholder), P25.

## What it does
- **Core:** `competition.teams` (ten NCX teams, two seats each; per-event roster; **sorting hat** `assignSeat` — fewest-occupied teams first, seeded random among ties, explicit team optional; release; grid order by seat), `competition.entry.register` (advance registration → `registered`), `session.grid` seat ordering (`{by="seat"}`), `session.race` race control: `penalty` (applied to classified time, re-orders finished drivers) and `disqualify` (`dsq`, classified last). 6 new tests (47 total).
- **ncm_league:** migration 005 (`team`, `seat`, `rc_audit`; `event.invitation/registration/seats_total/pack_id`; `entry.team_id/seat_index/registered_at`; `session_result` gains `dsq`); NCX pack v0 (teams seeded per server); `server/organized.lua`: `ncm.event.post <route> <minutes>` posts an organized invitation-only event with 20 seats (persisted and restored across restarts with its roster); `ncm.invite <pid> [team]` runs the hat and sends the offer (toast + chat); `/ncm.accept` registers into the seat (bag `ncmEntry` carries team), `/ncm.decline` releases it; venue entry refused for invitation events; grid forms from `registered` entries in **seat order** with `[TEAM] name` displays; race control `ncm.rc.penalty <pid> <sec> [reason]`, `ncm.rc.dsq <pid> [reason]`, `ncm.rc.abort [reason]`, `ncm.rc.log` — all written to `rc_audit` and reflected in results and the drivers' HUD.
- **ncm_world:** heartbeat shows `NCX · INVITATIONAL · n/20 seats` or `NCX · TEAM · you drive for Team (car n)`; no venue prompt and no auto-route for invitation events; grid strip carries the team; results board shows `[TEAM] name`.

## Completion criteria
1. Core tests green on both interpreters (sorting hat variety/full/deterministic, register, seat grid, penalty/DSQ). ✅
2. Live: `ncm.event.post bline 5` → `ncm.invite <you>`, `ncm.invite <tester>` → two different team offers → `/ncm.accept` on both → heartbeat shows team + seat, no venue prompt.
3. Live: grid forms in seat order (P1 = first team in roster order); mid-race `ncm.rc.penalty <tester> 10` → result shows +10 s and re-orders if applicable; `ncm.rc.dsq` on a driver → DSQ last; `ncm.rc.log` prints the audit rows.
4. Tests green, vendoring clean, SP untouched.

## Stub run (offline, 2026-09-20)
Whole league server under Lua 5.4: post → refuse venue entry → three offers (Miyutsaki/Yorinobu/Herrera) → two accepts, one decline → grid formed in seat order `[MIY] → [YOR]` → lights → penalty +10 s on P2 → both finish → `P1 [MIY] 0:32 | P2 [YOR] 0:42 (+10)`.

## Live log (2026-09-20)
- 10:33 `ncm.event.post bline 5` → POSTED, 20 seats; offers: Miyutsaki (owner), Rayfield (tester); both accepted (chat + console). Venue prompt absent for the invitational.
- 10:37 FORMED in seat order `P1 [RAY] ncmtester2 · P2 [MIY] baremetaleven` — both absent at T−30 (not at the venue in time) → DNS/no_starters. Criterion 2 met; grid ordering of 3 met.
- 10:40 street B-line pulled with `ncm.race.now bline` (both already entered): grid, lights, `ncm.rc.penalty 1 10 corner cutting` mid-race → result `P1 1:27.935` (= 1:17.9 + 10), `P2 1:48.066 (+20.131)`; `ncm.rc.log` shows the audit row. Criterion 3 met.
- Fixes from the run: client banner said JUMP START for any penalty (now PENALTY +N s); gate report retries capped at 5; result hold 30 → 60 s.

## E13 attempt (2026-09-20, after M4-lite)
Warden import: the original RB15 zip refused (top-level `RB/` folder → "no known mod root"; verdict *unverified executable*, "request a review once declared"); an inert-only repack (`archive/pc/mod` + `r6/tweaks`, 7 files) and the livery package (3 files, rebuilt with the final Raven art) were accepted and required; server announces `Required mods: 2 declared, digest=3d72…`. **No consent screen**: the launcher's connect (list, deep link with the server id, direct address) never received a catalogue row because the endpoint is loopback/private (KB-7). Hosted-mod delivery moves to the staging server package (M7-lite.0).
