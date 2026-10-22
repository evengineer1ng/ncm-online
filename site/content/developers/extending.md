---
title: Extending NCM
description: How to add a system to NCM the way the project itself does: core modules, resources, migrations, tunables, native mods and player surfaces.
status: dev
---

# Extending NCM

These are the patterns the project follows. A fork can do what it likes, but code that follows them fits the rest.

## Add pure logic to ncm-core

1. Write `ncm/core/<area>/<name>.lua` with `Core.define("<area>.<name>", function(C) … return M end)`. Call no host
   API: take inputs as arguments and return results.
2. Add it to `ncm/core/MANIFEST.lua`.
3. Add `ncm/core/tests/test_<name>.lua`.
4. Run `tools/ncm-build.ps1` to vendor it into resources, then `tools/ncm-test.ps1`.

## Add a resource

1. Create `ncm/online/resources/ncm_<name>/open77.lua`. Declare only the permissions you need, and add the
   `-- ncm-core:begin` / `-- ncm-core:end` block if you use core.
2. Give it a kill switch tunable, `<name>Enabled`. The server loads `ncm/*`, so a new directory goes live with the
   next deploy.
3. Declare all its tunables in **one** `Open77.tunables.declare` call. `apply` must be `live`, `next_round` or
   `next_match`; anything else rejects the whole declaration.
4. Talk to other resources through events and exports, never their globals.
5. Long loops must yield (`Wait(0)`) to stay inside the server's instruction quota.
6. A new resource deploys **whole**, including its vendored `shared/core/` and `data/`.

## Add a table

Write the next numbered migration, `ncm/online/resources/ncm_league/server/schema/NNN_<name>.lua`, and add its
`server_script` line to `ncm_league/open77.lua`. Every row carries `server_id`. Make data steps replay-safe.

## Add a native capability

Ship it as **its own native mod**, never inside Carrier or Rig Bridge. Prefer the lightest carrier that works: pure
redscript before a DLL. Give a DLL its own loopback port block, and use the page-relay pattern to reach client Lua.
A natives file has no `module` line. Declare it as a required mod; an undeclared plugin is disabled on Online.

## Add a player-facing surface

- Reach it through play and menus, not typed commands.
- No modal layers: a docked panel or an existing surface (the F6 shell, the HUD) that never traps input. `Esc` /
  Back always closes it.
- Add it to the Help catalogue (`ncm/core/player/help.lua`) so Help, and this site's
  [command reference](../commands.md), list it.
- Announce it in `ncm_world/client/landing_content.lua` releases. That also feeds this site's
  [changelog](../changelog.md).

## Record what you did

The project's own sessions follow `AGENTS.md`: decisions go in `DECISION_RECORD.md`, ideas in `BACKLOG.md`, defects
in `KNOWN_BUGS.md`, the current state in `NOW.md`, and live tests in `wp/MASTER_TEST.md`.
