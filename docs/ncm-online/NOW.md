# NOW — the single next-action index

> **STATUS: LEDGER** — living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) — classified 2026-09-24 (L125).

Last rewritten: **2026-09-24 — Driver Card distance hotfix promoted through Development to Online.**
Commit `80ad0aa` is on `origin/main` and the same resource revision is running in the persistent world.

> **Claim before writing:** decisions through **L130**; MASTER_TEST through **2.18 / §AK**; next QA letter
> **§AL**. BACKLOG next free **IDEA-414**; known issues through **KB-98** plus the existing duplicate KB-87.
> Historical §Z collision remains: qualify by section (2.14 Machine Index vs 2.16 Help).

## Next action: visually re-test §AK6 with a WebUI-capable observing client

Reconnect after the Online restart, face another streamed player, and walk from roughly 5 m toward the ordinary
35 m plate limit. The card should remain full size nearby, shrink smoothly with distance, stay anchored above
the player, and never grow relative to the body. This must be observed from a client whose WebUI host imported
surfaces; the second local process used tonight cannot prove it because KB-4 fired before the card page ran.

## Driver Card hotfix

The first two-client observation found one genuine NCM defect: the rich card stayed 288×84 screen pixels at
every world distance, so it looked progressively larger relative to the remote body. The correction uses the
platform's existing per-frame distance: full size through 5 m, a monotonic taper, and a readable 0.58 floor at
the ordinary 35 m plate limit. It changes no stream range, visibility, bucket audience or through-wall policy.

Focused checks now include five distance-scale assertions and pass **26/26**. The complete repository gate is
green under Lua 5.4 and LuaJIT: **285 core tests per interpreter**, 41 cross-scope checks, 17 QA checks,
35 vehicle-access checks, **165 resource Lua files**, five WebUI scripts, **96 panel assertions**, 26 Driver
Card assertions and documentation authority.

Development restarted at **21:18 EDT** with resource digest `9336284e…`, schema 30 / `pending=[]`, HTTP health
200, zero stderr bytes and no boot-error matches. This is deployment evidence, not the still-owed visual PASS.

Commit `80ad0aa` was pushed before production promotion. Fresh Online rollback artifacts were taken at
`20260925-012200`: a 230 KB database dump containing 63 tables and a 493 KB resource-tree archive. The named
`deploy-staging.ps1 -Target online` pipeline then published digest `e17702fa…` at 01:23 UTC. Service is active,
health is 200, schema remains 30 with `pending=[]`, and the post-restart error count is zero.

## The owner's banner was not missing state

Read-only Online evidence shows `baremetaleven` already has `ncm_default`, and the server published that public
projection successfully. The first local game process activated the custom Driver Card. The second local game
process did not: its OPEN//77 WebHost disconnected with `pipe_read_failed:109`, imported zero WebUI surfaces,
and never emitted the custom-card ready/handoff line. It therefore cannot draw the banner, chat or notifications.
That is the existing platform/hardware limitation KB-4, not a presentation-row defect; no identity data was
altered and no native text fallback is being called a rich-card fix.

## Current Online baseline to preserve

The first owner-authorised promotion earlier tonight advanced migrations 024–030. The hotfix promotion changed
no schema or canonical data: Online still has only `server_id = ncm-dev` and exactly 13 drivers, 13 bindings,
19 assets, 29 results, 23 ledger rows, 14 evidence rows and 14 discoveries. `baremetaleven -> ncm_default`
also remains intact. Both the original `20260924-235549` rollback pair and the fresh hotfix pair remain on-box.

## Other current work to preserve

The rig/FFB line through repository commit `3737a69` remains intact: generic wheel input, axis-level device
detection, panel arming, safe bounded feedback and cleanup. Its live calibration work and owed checks remain in
BACKLOG IDEA-395–412. This Driver Card pass does not modify that code or reinterpret those findings.

## Live QA still owed

MASTER_TEST §AK remains the Driver Card authority. §AK6 has an honest pre-hotfix Online FAIL beside KB-98 and
needs a Development/Online visual re-test after promotion. The remainder of §AK is not silently passed. A
WebUI-capable observing client (normally a separate machine, because of KB-4) is required to prove the owner's
card, exactly-one-renderer handoff, scale/track/cleanup, join/leave, reload, native restoration and Unicode.
