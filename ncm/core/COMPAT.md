# ncm-core compatibility contract

ncm-core runs unchanged in three places: Cyber Engine Tweaks (LuaJIT 2.1, Lua 5.1 semantics), the OPEN//77 dedicated server and client (Lua 5.4.8), and the local test runner (Lua 5.4.6 + LuaJIT 2.1). Every core file must therefore stay inside the **intersection** of Lua 5.1/LuaJIT and Lua 5.4. `tools/ncm-test.ps1` enforces this by running the whole suite under both interpreters.

## Language

| Do not use | Why | Use instead |
|---|---|---|
| `//` integer division | LuaJIT: syntax error | `math.floor(a / b)` |
| `&`, `|`, `~`, `<<`, `>>` | LuaJIT: syntax error | arithmetic (`% 16`, `* 256`, `math.floor`) |
| `goto` / labels | 5.1-class semantics differ; avoid | loops with flags / early `return` |
| integer subtype assumptions (`math.type`, `3 == 3.0` distinctions, `%d` with non-integral floats) | 5.4 errors "number has no integer representation"; LuaJIT has no integers | `math.floor` before formatting; format numbers with `%s`/`%.Nf` or the `hexByte` pattern |
| `string.pack`/`unpack`, `utf8.*`, `table.move`, `coroutine.close` | absent in LuaJIT | plain loops |
| `table.unpack` vs `unpack` | different names | `local unpack = table.unpack or unpack` |
| `#` on tables with holes | undefined in both | track counts explicitly |
| `__gc`, `__close`, `<const>`, `<close>` | 5.4-only / behave differently | do not rely on them |
| `os.*`, `io.*`, `require`, `package`, `dofile`, `load` with env tricks | server VM lacks them; core must be host-agnostic | hosts inject `ctx.now()`, `ctx.rng`, storage effects |
| `print` in core modules | hosts own logging | return diagnostics; hosts log |

## Structure

- One global only: `NcmCore` (created by `init.lua`). Modules register with `NcmCore.define(name, factory)` and resolve dependencies with `Core.get(name)` inside the factory or at call time — never at file top level except `local Core = NcmCore`.
- Load order is `MANIFEST.lua`; dependencies precede dependents. The build tool and the CET shim use the same list.
- Modules return plain tables. State records are JSON-safe (strings, numbers, booleans, arrays, string-keyed tables; no functions, no cycles, no `nil` holes in arrays).
- Time and randomness are injected. Determinism under a seeded rng is a test requirement for anything that simulates.
- Errors: validate inputs and `error()` with a message naming the module and function; return `nil, reason` for expected refusals.

## Testing

- `ncm/core/tests/*.lua` use the tiny harness in `tests/run.lua`. Each test file returns a table of `name = function(T) ... end`.
- `tools/ncm-test.ps1` runs the suite under Lua 5.4 **and** LuaJIT; both must pass. A deliberate violation (e.g. `7 // 2`) must fail under LuaJIT — that is the proof the gate works.
