# COMPONENT ASSIGNMENT — B-<IDEA>-<slug> v<N>

> **STATUS: HISTORICAL** - brick template - closed experiment. A record of a moment, never architecture.
> Authority map: [INDEX.md](../../INDEX.md) - classified 2026-09-24 (L125)

*Written by the integrator. This packet plus `COMPONENT_GATE.md` plus the attached files is everything the author
gets. If the author has to ask for the repository, the packet was incomplete — fix the packet, not the gate.*

## Identity
- **Brick id:** B-<IDEA>-<slug>   **Revision requested:** v1 (or "v2, revising review R1")
- **Gate:** 1   **NcmCore.VERSION:** 0.0.1
- **Module name:** `<area>.<name>`  →  file `<area>/<name>.lua`
- **Shape:** Rule | Reducer | Catalogue
- **Serves:** IDEA-<n> (verbatim text of the idea row pasted below), plus KB-<n> / L<n> / P<n> where relevant

## The idea, verbatim
> (paste the BACKLOG row(s) and any DECISION_RECORD lines that constrain it; do not paraphrase)

## Domain semantics the author must know
- (each sporting rule that applies, one bullet, with its L/P id: e.g. "L67: a field of one is a time trial; it
  cannot be won" / "incident bands 1..3 escalate ×1.5 per repeat, capped")
- (vocabulary: the exact strings for states, kinds, tiers the brick must use — never invent synonyms)

## Interface
```lua
-- exact public surface the integrator will call
M.evaluate(facts, opts) -> result          -- or M.apply(state, event, ctx) -> state, deltas
M.DEFAULTS = { ... }
```

## Input schema (normalized; absent means "host could not compute it")
```lua
facts = {
  -- field : type : required? : meaning : units
}
```
Attach a fixture of this shape (`fixtures/*.lua`). State whether it is synthetic or captured from real data.

## Output schema
```lua
result = {
  -- field : type : meaning
}
```
Say how the host will consume each field (presentation string, persisted count, further rule input) so the author
knows what precision and stability matters.

## Provided modules (the only allowed dependencies)
| Module | Version | File attached | Why it is allowed |
|---|---|---|---|
| `vocabulary.ids` | 0.0.1 | `provided/vocabulary/ids.lua` | seeded rng, id helpers |

Attached always: `init.lua`, `tests/run.lua`, `COMPONENT_GATE.md`, `COMPONENT_MANIFEST_TEMPLATE.md`.

## Prohibited responsibilities (specific to this brick)
- (e.g. "does not decide whether the session was a race or a time trial — `facts.sessionKind` is given")
- (e.g. "does not rank drivers; positions are input")

## Acceptance criteria
1. (observable, testable statements; each becomes at least one test)
2. …

## Must-never list (each becomes a `never_...` test)
- …

## Known edge cases the author must handle
- …

## Regression cases to encode
- KB-<n>: (one line: input → expected)

## Live QA the integrator will run (author drafts the procedure in QA.md)
- (what a tester will do and what they should observe)

## Test command
`lua5.4 tests/run.lua .` and `luajit tests/run.lua .` from the brick folder; both exit 0.

## Deliver
The brick folder exactly as `COMPONENT_GATE.md` §4, with `BRICK.md` filled in from
`COMPONENT_MANIFEST_TEMPLATE.md`. Zip it, or paste files with their paths. Unresolved questions go in `BRICK.md`,
not in prose around the delivery.
