# BRICK.md — B-<IDEA>-<slug>

*The passport. Filled in by the author, travels with the code, updated by the integrator on admission. Every field
is present; "none" is a valid answer, a missing field is not.*

```yaml
brick: B-<IDEA>-<slug>
version: 1.0.0            # semver; matches M.version
revision: v1              # v1, v2 … one per delivery; see changelog
gate: 1
core_version: 0.0.1
module: <area>.<name>
file: <area>/<name>.lua
shape: rule | reducer | catalogue
serves: [IDEA-<n>]        # plus KB-<n>, L<n>, P<n> it encodes
author: <who>
delivered: 2026-MM-DD
interpreters_run: [lua5.4, luajit]   # what the author actually ran
status: candidate         # candidate | revision | integrated | rejected  (integrator edits this line)
integrated_as: null       # integrator: "ncm/core/<path> @ core 0.0.1, MANIFEST line N, host seam X"
```

## Purpose
One paragraph. What question this module answers, for whom, when.

## Scope
What it does. Bullet per behaviour.

## Explicit non-goals
What it deliberately does not do, so nobody later assumes it does.

## Files
| Path | Role |
|---|---|
| `<area>/<name>.lua` | the module |
| `tests/test_<name>.lua` | tests (N cases) |
| `fixtures/<x>.lua` | synthetic / captured |
| `QA.md` | live QA procedure |

## Public interface
Signatures with one line each. Tunables in `M.DEFAULTS` listed with their default and meaning.

## Inputs
The schema as implemented (copy from the packet; note any field you ended up not needing).

## Outputs
The schema as implemented, with the stability promise for each field (e.g. "tag ids are stable strings; order is
most-distinctive-first and may change between versions").

## Dependencies
Provided modules used, by name and version. Nothing else.

## State owned
None (Rule / Catalogue) — or the exact shape of the Reducer `state` table and what a fresh one looks like
(`M.newState()`).

## Persistence requirements
What the host must persist for this brick to be useful across sessions, in plain terms (not SQL). "None" if pure.

## Assumptions
Each assumption about the input or the world, one per bullet, so the integrator can confirm or refute them.

## Invariants
Things that are always true of the output. Each has a test.

## Failure behaviour
What happens on bad shape (`error`), on refusal (`nil, reason` — list the reason slugs), on absent facts (declines
which conclusions).

## Edge cases handled
Bullet per case, with the test name that covers it.

## Tests included
| Category | Count | Names |
|---|---|---|
| happy / boundary / invalid / absence / invariant / determinism / regression / purity | | |

Result of the last run under each interpreter (paste the summary line).

## Integration points (author's understanding — integrator corrects)
Where the host should call this, with what, and what it should do with the result.

## Live QA required
Pointer to `QA.md`; one line on what cannot be proven offline.

## Known limitations
…

## Unresolved questions
Numbered. These are the only place to raise anything the packet did not settle.

## Rollback / removal
"Delete `<file>` and its MANIFEST line; the single host call site at <seam> falls back to <behaviour>." If removal is
not that simple, explain why — that is itself a review finding.

## Changelog
- v1 (date): initial delivery.
- v2 (date): revised per review R1 — items 1, 3, 4.
