---
title: Testing
description: NCM's offline gate: ncm-core tests under Lua 5.4 and LuaJIT, host-stub resource tests, syntax and sandbox checks, and the docs authority check. Plus the live test register.
status: dev
---

# Testing

## The offline gate

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\ncm-test.ps1
```

One command, and it must end `ncm-test: ALL GREEN under every interpreter`. It runs:

1. **ncm-core tests:** `ncm/core/tests/run.lua` over the 127 `test_*.lua` files, under **both Lua 5.4 and
   LuaJIT**. Each file returns a table of `name → function(T)`.
2. **Resource tests:** every `tools/test-*.lua`, discovered automatically, under both interpreters. Several stub
   the whole OPEN//77 host (`tools/ncm-stub.lua`, `tools/test-paddock-host.lua`) to drive real server files.
3. **Syntax:** `luac -p` over every resource file, and `node --check` over inline scripts.
4. **Rules the platform enforces at runtime but nothing else would catch:** no handler-less `RegisterNetEvent`,
   and the server sandbox check (`tools/test-server-sandbox.lua`): no `os.*` or `collectgarbage` in server files,
   and valid tunable `apply` values.
5. **Render checks** for the WebUI panels.
6. **Docs authority** (`tools/check-docs-authority.py`): every design document has exactly one valid status banner,
   every relative link resolves, every document is in `INDEX.md`, and backlog IDs are unique.

Why both interpreters: CET runs LuaJIT, the OPEN//77 server runs Lua 5.4, and core code has to run on both. Avoid
`//`, `~`, `goto` and integer semantics that differ. See `ncm/core/COMPAT.md`.

Native plugins carry their own tests (for example `ncm/rig_bridge/tests/`), run by their `tools/build-*.ps1`.

## Writing a test

A core test file:

```lua
-- ncm/core/tests/test_example.lua
return {
    ["Help hides the Market until the Market is live"] = function(T)
        local help = T.Core.get("player.help")
        local function has(list, id) for _, e in ipairs(list) do if e.id == id then return true end end end
        T.falsy(has(help.controls({}), "market"), "absent when not live")
        T.truthy(has(help.controls({ market = true }), "market"), "present when live")
    end,
}
```

Look at `ncm/core/tests/test_voice.lua` and `tools/test-radio.lua` for real examples.

## The live register

Passing offline is not done. **Nothing is done until a live PASS sits beside it** in
`docs/ncm-online/wp/MASTER_TEST.md`: numbered cases that a person runs in the real game on a real server, with the
evidence recorded.

## The website

`python site/build.py --check` builds this site and fails on any broken internal link or missing page. CI runs it
on every push that touches the site, independently of the game's gate.
