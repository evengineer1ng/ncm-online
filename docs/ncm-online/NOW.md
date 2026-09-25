# NOW — the single next-action index

> **STATUS: LEDGER** — living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) — classified 2026-09-24 (L125).

Last rewritten: **2026-09-24 — Driver Card distance hotfix proven offline and deployed to Development.**
Production still runs the pre-hotfix card while this known revision is committed and pushed.

> **Claim before writing:** decisions through **L130**; MASTER_TEST through **2.18 / §AK**; next QA letter
> **§AL**. BACKLOG next free **IDEA-414**; known issues through **KB-98** plus the existing duplicate KB-87.
> Historical §Z collision remains: qualify by section (2.14 Machine Index vs 2.16 Help).

## Next action: commit/push the Development revision, then promote it through the Online pipeline

The hotfix is deliberately following the normal path despite its size: full gate → Development restart →
commit/push → fresh Online backup → `deploy-staging.ps1 -Target online` → service/schema/data/error checks.
Do not copy individual files to Online and do not treat the current Development boot as a production result.

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

## The owner's banner was not missing state

Read-only Online evidence shows `baremetaleven` already has `ncm_default`, and the server published that public
projection successfully. The first local game process activated the custom Driver Card. The second local game
process did not: its OPEN//77 WebHost disconnected with `pipe_read_failed:109`, imported zero WebUI surfaces,
and never emitted the custom-card ready/handoff line. It therefore cannot draw the banner, chat or notifications.
That is the existing platform/hardware limitation KB-4, not a presentation-row defect; no identity data was
altered and no native text fallback is being called a rich-card fix.

## Current Online baseline to preserve

The owner-authorised promotion earlier tonight backed up both canonical data and the replaceable resource tree
as `ncm-db-20260924-235549.sql.gz` and `ncm-resources-20260924-235549.tar.gz`. Online then advanced migrations
024–030 and verified schema 30 / `pending=[]`, service active, zero errors, only `server_id = ncm-dev`, and stable
counts: 13 drivers, 13 bindings, 19 assets, 29 results, 23 ledger rows, 14 evidence rows and 14 discoveries.
Take a new backup before the hotfix promotion even though this patch has no schema or data write.

## Other current work to preserve

The rig/FFB line through repository commit `3737a69` remains intact: generic wheel input, axis-level device
detection, panel arming, safe bounded feedback and cleanup. Its live calibration work and owed checks remain in
BACKLOG IDEA-395–412. This Driver Card pass does not modify that code or reinterpret those findings.

## Live QA still owed

MASTER_TEST §AK remains the Driver Card authority. §AK6 has an honest pre-hotfix Online FAIL beside KB-98 and
needs a Development/Online visual re-test after promotion. The remainder of §AK is not silently passed. A
WebUI-capable observing client (normally a separate machine, because of KB-4) is required to prove the owner's
card, exactly-one-renderer handoff, scale/track/cleanup, join/leave, reload, native restoration and Unicode.
