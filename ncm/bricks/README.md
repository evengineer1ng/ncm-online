# ncm/bricks — the candidate queue

Candidate ncm-core modules written outside the repository, waiting for integration review. **Nothing here is
shipped, built or wired.** `tools/ncm-build.ps1` reads only `ncm/core/MANIFEST.lua`; this folder never reaches a
resource or a client.

Contract: [docs/ncm-online/bricks/COMPONENT_GATE.md](../../docs/ncm-online/bricks/COMPONENT_GATE.md).

```
ncm/bricks/
  B-089-race-tags/          one folder per brick id, never renamed across revisions
    BRICK.md                passport; `status:` line is the queue state
    reviews/R1.md, R2.md    integration reviews, append-only
    ...                     the brick folder exactly as delivered (a runnable mini core root)
  _integrated/              moved here on admission, with BRICK.md `integrated_as:` filled in
  _rejected/                moved here on rejection, reason in BRICK.md
```

Run a candidate's own suite without touching core:

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\ncm-test.ps1 -AllowMissing -CoreRoot ncm\bricks\B-089-race-tags
```

`-AllowMissing` is needed because the script looks for `online/resources` beside the core root's parent to run its
`luac -p` gate; a brick folder has none, the gate is skipped, and the script (misleadingly) prints "luac not found".
Verified 2026-09-22 with a probe brick: ALL GREEN under Lua 5.4 and LuaJIT.

Queue state lives in two places only: the `status:` line of `BRICK.md` and the IDEA row in
`docs/ncm-online/BACKLOG.md` (`specified` / `candidate (B-089 v1)` / `revision (R1)` / `built` / `validated`).
