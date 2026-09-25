# NOW — the single next-action index

> **STATUS: LEDGER** — living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) — classified 2026-09-24 (L125).

Last rewritten: **2026-09-25 — platform freeroam fully evicted from Development and Online.**

> **Claim before writing:** decisions through **L132**; MASTER_TEST through **2.18 / §AM**; next QA letter
> **§AN**. BACKLOG next free **IDEA-420**; known issues through **KB-102** plus the existing duplicate KB-87.
> Historical §Z collision remains: qualify by section (2.14 Machine Index vs 2.16 Help).

## Next action: one client proves the player-facing result

Connect to Online and run MASTER_TEST §AM4–§AM7: confirm there is no scripted death/respawn on join; prove
`/freeroam`, `/car`, `/race`, `/footrace`, `/pvp` and `/dm` no longer exist or mutate the world; prove
`/anim list`, one named animation and `/anim stop` still work; then die once and record the actual behavior.
The expected current death workaround is reconnect, because NCM does not yet own respawn-after-death.

Do not close KB-100 on boot evidence alone. The kill handler cannot have registered because the resource did
not start, but the player experience still needs the live join observation beside it.

## Deployment result

Commits `833642b` and `0ea0def` are on `origin/main`. Fresh Online rollback artifacts are stamped
`20260925-050408`: database dump (63 tables), NCM resource archive, `server.jsonc`, freeroam manifest and
freeroam config.

The production guard now reports:

```
freeroam loaded        = no
open77_freeroam loaded = no
open77_animations kept = yes
freeroam server tag     = no
load list OK: 36 resources, every dependency satisfied
```

Online restarted at 05:09 UTC after the whitelist was confirmed enabled and the player set was empty. The
normal SIGTERM path again took exactly 90 seconds, but admitted nobody. New boot: 39 resources started after
platform expansion, zero freeroam discoveries/starts, animations and both NCM resources live, schema 30 /
`pending=[]`, zero boot errors, service active and health 200. Canonical state remains under sole world identity
`ncm-dev`: 16 drivers/bindings, 21 assets, 33 results, 32 ledger rows, 18 evidence and 18 discoveries.

## Boundary now in force (L132 / IDEA-416)

The platform vehicle/weapon menu, `/freeroam`, platform racing/PvP commands, forced join kill and separate
`open77_freeroam` persistence/wallet are absent from the load set. `open77_animations` stays; its direct/list/
info/stop commands remain, while freeroam's no-argument picker leaves. The re-applicable guard must be run after
each OPEN//77 upgrade because the vendor tree and config template can restore the removed surfaces.

KB-101 remains independent: NCM can save a pre-incarnation origin placeholder and later restore it. Its
readiness/origin guards are not part of this eviction.

## Live QA still owed

- **§AM4–§AM7:** live join, command absence, animation survival and current death behavior.
- **§AL1–§AL2:** visually confirm the three Market offerings and repeated-open idempotency. §AL3 passed.
- **§AK:** two-client Driver Card renderer handoff, presentation lifecycle and corrected distance scaling.
- **Rig/FFB:** the outstanding physical/in-game checks named in BACKLOG IDEA-395–412.
- Still owed from earlier: IDEA-251 full Market live PASS, §AH21 incident attribution, migration 028 fresh-world.
