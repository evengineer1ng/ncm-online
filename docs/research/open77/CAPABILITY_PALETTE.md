# NCM Online — vehicle-interference capability palette

Date: 2026-09-21. Status: **audit complete for the categories asked (IDEA-073); one blocking question remains (§6); roster design deliberately NOT started.**
Build answered for: **2.31.13+op77.78** (no index published for op77.84, which staging runs — treat every `since` as a lower bound).

Evidence captured this session, all in [evidence/](evidence/): `mcp-tools.txt`, `ns-hacking.txt`, `ns-cyberware.txt`,
`ns-nameplates.txt`, `ns-vehicles-server.txt`. Method: hosted devkit MCP, tool `open77_namespace`, via
`query_open77.ps1` after `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` (the 2026-09-18 session was
blocked here and worked around it; this is the fix, and it changes nothing outside that window).

Order followed: **engine capabilities → design palette → roster → balance → implementation.** This file is step two.

---

## 1. The headline: OPEN//77 ships a hacking *framework*, not a fixed hack list

`Open77.hacking` is 18 natives and it is an entitlement + upload + counterplay system whose **content is defined by
the resource**:

| Native | Why it matters to NCM |
|---|---|
| `hacking.define(definition)` | NCM registers **its own** hacks and their grades. The roster is ours to author. |
| `hacking.defineIce(definition)` | **Self-ICE** — defensive implants are a first-class concept, not something we bolt on. |
| `hacking.definePurge(definition)` | **Active purge** — removing an opponent's upload is a defined counterplay primitive. |
| `hacking.start(playerId, targetId, definitionId, gradeId, {operationId})` | Server-authoritative upload from one player against another, with an idempotency key. |
| `hacking.purge(playerId, targetId, definitionId, gradeId, …)` | Purges uploads and statuses through the actor's implant. |
| `hacking.configureProtection(playerId, { safeArea?, resistance? })` | **This is how sanctioned racing is protected (IDEA-068).** A safe-area / resistance scope owned per provider. |
| `hacking.clearProtection(playerId)` | Lift it again when the session ends. |
| `hacking.capabilities()` | Reports schema, profiles, authority model and **hard limits** — the next thing to read. |
| `hacking.state / statuses / action / cancel` | Authoritative per-player state, owned statuses, receipts, cancellation. |
| client `hacking.observe(playerId)` | Target position, camera angle **and local visibility** for real-time selection — targeting *and* a line-of-sight signal. |
| client `hacking.present({actionId, phase, progress})` | The native warning / progress / outcome presentation. Counterplay is legible to the victim without us drawing it. |
| client `hacking.nativeStatus(kind, durationMs)` | Bounded native statuses — but only `blind` and `weapon_jam`. |

**The critical structural point:** the framework carries entitlement, targeting, authority, protection, purge and
presentation. It does **not** carry vehicle effects. A hack that lands is NCM calling `Open77.vehicles.*` itself.
That is good news — it means the effect palette is the vehicle namespace, which is enormous.

## 1b. CORRECTION (same session, after reading the cards): the six hack KINDS are fixed and player-targeted

My first read said "the roster is ours to author". That was too strong, and the `define` card says why:

```
definition = { id, version, grades = { { id, range, uploadMs, staminaCost, cooldownMs,
                                         damage, statusMs, recoveryMs, lockHacking, nonlethal, kind? } } }
```

`kind` selects one of **six fixed native kinds** -- Short Circuit, Overheat, Cyberware Malfunction, Cripple
Movement, Reboot Optics, Weapon Glitch -- each "one warned, interruptible upload". Every one of them targets a
**person**, not a car. What NCM authors is the *grade*: range, upload time, stamina cost, cooldown, damage, status
duration, recovery, lock, lethality. That is tuning and entitlement, not a free-form effect language.

**So a vehicle quickhack is a composition, not a native.** The framework supplies target selection, entitlement,
authority, the warned interruptible upload, counterplay and the native presentation; NCM supplies the vehicle
consequence out of `Open77.vehicles.*` when an upload lands. **The open question that decides everything is
whether a resource can observe completion** -- see the probes in §6.

Also from the card, and it changes §2: **a hack must be entitled by a matching implant registered through
`Open77.cyberware.define` with the same provider, id, version and grade ids, in the `operating_system` slot.**
Self-ICE lives in the `self_ice` slot (profile `self_ice`), active purge in the `purge` slot (profile
`active_purge`).

### Counterplay is fully specified already

| Piece | Grade fields | Meaning |
|---|---|---|
| **Self-ICE** (`defineIce`) | `charges`, `rechargeMs` | A victim holding a charge **blocks an incoming upload and spends it**. Defence is a resource, not a dice roll. |
| **Active purge** (`definePurge`) | `staminaCost`, `cooldownMs`, `allowSelf`, `allowAlly`, `range`, `cancelUploads`, `removeStatuses` | Cancel uploads and strip statuses, on yourself **or an ally in range** -- a team-mate can clean you up mid-race. |
| **Protection** (`configureProtection`) | `safeArea` (refuses *every* upload), `resistance` 0..1 (scales electrical damage) | Requires `players.hacking.policy`. **Scoped to the provider AND the current body -- a new body needs a new call**, so respawn/body change must re-apply it. |

`safeArea = true` is a clean, total answer for sanctioned racing (IDEA-068): applied at grid formation, cleared at
session retire. `resistance` gives a middle tier for "Clean Street" without an all-or-nothing switch.

## 2. `Open77.cyberware` is not the *effect* path -- but it IS the entitlement path

29 natives, and they are **Gorilla Arms and double-jump legs** — melee postures, charge limits, jump leases,
durable/temporary implant records. Nothing vehicular. Useful later for durable implant *ownership* semantics
(`install`, `lease`, `effective`, `current`), but the driving fantasy of IDEA-067 lives in `Open77.hacking`
plus `Open77.vehicles`, not here. **This corrects my earlier framing.**

## 3. Effect palette — what a landed hack can actually do (all server, `world.vehicles`)

| Category | Natives | Verdict |
|---|---|---|
| **Power / speed** | `setPerformance{topSpeedKph, accelerationScale, taperKph}`, `getPerformance`, `clearPerformance` | **AVAILABLE.** Replicated to every viewer, survives ownership change. Debuff *and* self-boost. |
| **Engine** | `setEngine`, `startEngine`, `stopEngine`, `isEngineOn` | **AVAILABLE.** A hard kill and a restart. |
| **Service state** | `setDrivable`, `setUndriveable`, `isDrivable` | **AVAILABLE.** Softer than a kill. |
| **Immobilise** | `setFrozen`, `isFrozen` | **AVAILABLE** (already used for grid holds). Blunt — likely too blunt for racing. |
| **Health** | `getHealth`/`setHealth` (0..1), `getEngineHealth`/`setEngineHealth` | **AVAILABLE.** |
| **Body damage** | `damageBodyCell`, `damageBodyZone`, `setBodyCell`, `setBodyZone`, `setBodyDamage`, `setDamage`, `registerDamageProfile`, `getDamageProfile` | **AVAILABLE**, with resource-defined named zones. |
| **Tyres** | `breakTire`, `setTireBroken`, `setTireMask`, `repairTire`, `repairAllTires` | **AVAILABLE.** Break/repair only — no pressure, wear or temperature. |
| **Glass / lights / parts** | `breakGlass`, `breakAllGlass`, `breakLight`, `detachPart`, `setPartDetached`, `detachedParts()` + full repair set | **AVAILABLE.** Cosmetic-to-serious sabotage. |
| **Destruction** | `explode` | **AVAILABLE.** "Detonates through every viewer's own engine." |
| **Repair (counterplay)** | `repair(scope)`, `repairAllGlass/Lights/Tires`, `repairBodyCell/Zone/Glass/Light/Tire` | **AVAILABLE** and scoped — a repair hack is as authorable as a damage one. |
| **Lights (harassment)** | `setLights`, `setHighBeams`, `setLightsHue`, `setHeadlightColor` | **AVAILABLE.** Cheap, funny, non-destructive. |
| **Horn** | `triggerHorn` / `honk(durationMs)` | **AVAILABLE.** Synchronised. |
| **Eject / lock** | `forcePlayerOutOfVehicle`, `taskPlayerLeave`, `setPlayerExitLocked`, `setLockedForPlayer`, `lockForAll` | **AVAILABLE.** |
| **Proximity / targeting** | `nearby(anchor, radius, {bucket, limit, occupied})`, `closest(anchor, {radius, bucket, occupied})`, plus `Open77.zones` server containment | **AVAILABLE.** Range validation is solid and server-side. |
| **Ownership / authority** | `owner(id)`, `getDriver(id)`, `requestAuthority`, `driverPlayerId` | **AVAILABLE.** |
| **Cooldown / idempotency** | `hacking` `operationId`, state bags, `kvp` compare-and-set, SQL | **AVAILABLE.** |

## 4. Settled negatives — do not design around these

| Not available | Evidence |
|---|---|
| **Steering influence** | Zero matches for "steer" across all 138 server vehicle natives. |
| **Grip / traction / friction / tyre pressure** | Zero matches. `setPerformance` is speed and throttle authority only — there is **no grip term anywhere**. |
| **Per-instance handling changes** | Category A, unchanged. Confirms IDEA-057: wet driving must be a *ceilings* effect, not a grip effect. |
| **Native Cyberpunk quickhacks via CET/redscript** | Client Lua sees only `Open77.*`; no engine RTTI. Everything comes through `Open77.hacking`. |
| **Vehicle-oriented native statuses** | `hacking.nativeStatus` offers only `blind` and `weapon_jam` — both player-oriented. Vehicle effects are ours to compose. |
| **Headless effects** | KB-10: a server vehicle simulates only while a ready client has it streamed. |

## 5. Driver Card (IDEA-070) — `set()` is minimal; `stream()` is the mechanism

`nameplates.set(playerId, options)` accepts only **`label`, `color`, `maxDistance`, `visible`** -- a coloured
string and a draw distance, nothing more. So the rich card cannot be built from `set()`. It must be
`nameplates.stream(page)` into a WebUI page (projection once per game frame) with `render(false)` dropping the
native plate. `set()` remains useful for a cheap fallback and for the panning-name problem (a `label` can be
re-set on a timer), and `maxDistance` is the natural knob for "only show cards for cars near me".

`Open77.nameplates` is 8 client natives, and the one that matters is **`nameplates.stream(page: WebUI.Page)`**:
it streams the native nameplate projection to a WebUI page **once per game frame**. So NCM does not have to fight
the native plate or reinvent world-space projection — it renders its own card (banner, chosen badges, immutable
radar polygon) in WebUI, positioned by the engine's own projection, with `set(playerId, options)` / `remove` /
`clear` / `snapshot` for overrides and `render(enabled)` to drop the native plate entirely. `setTalking` already
shows a speaker icon, which pairs with proximity voice for IDEA-063.

## 6. ANSWERED — the blocking question is a yes

**`onHackingTransition(encodedJson)` is the ledger of every hack**, and it is exactly the hook NCM needed.
Decoded it carries `actionId, owner, attacker, target, attackerIncarnation, targetIncarnation, definition, grade,
kind, phase, reason, startedAt, deadline, statusEndsAt, amount, lockHacking, from, to` (+ `blocks` on a
malfunction). Phases: `challenge, upload_started, upload_progress, blocked, interrupted, impact, completed,
status_applied, status_tick, status_expired, status_purged, effect_applied, effect_refused`.

**So IDEA-067 is real.** NCM registers a hack, the platform runs targeting / entitlement / the warned
interruptible upload / ICE / purge / native presentation, and on `impact` (or `effect_applied`) NCM applies the
*vehicle* consequence from `Open77.vehicles.*`. Correlate on `actionId`, never on arrival order — the guide warns
callbacks in one tick can arrive out of order — and treat only `impact` and `status_tick` as damage.

There is also a per-grade **`effects` block** (`damage`, `freezeMs` 1..10000, `knockdown`, `disableCyberwareMs`)
— but those act on the *person*, not the car. The car is ours.

## 7. Constraints that will shape the roster more than imagination will

| Constraint | Consequence for racing |
|---|---|
| **`range` 1..80 m, `uploadMs` 500..15000** | At 200 km/h you cover 80 m in 1.4 s. A 2 s upload means you must *hold station* within 80 m — hacking at speed is genuinely hard, and that is good tension, not a problem. Slipstream range becomes tactically meaningful. |
| **The victim is ALWAYS warned** | Toast + chat + native `INCOMING <KIND>` bar; if the warning cannot be delivered the upload **fails closed**. No silent hacks exist, by design. Counterplay is always possible. |
| **Line of sight is *client* evidence** | Shared-evidence model, not a server collision query — "two colluding modified clients can defeat it". An integrity note for P11: acceptable in the current threat model, not for a ranked tier. |
| **`recoveryMs`** (`statusMs+500`..60000) | No attacker can hack that victim again inside it — a built-in anti-spam floor. |
| **One status of each kind per victim** | A second same-kind hack lands its hit but its status is refused (`effect_refused`), not refreshed. Different kinds stack. |
| **Combat scope gates everything** | "Your server's combat scope and team rules must allow the attacker to damage the target." And **ally purge needs both players on the same positive combat team** — so NCM teams (L18) must map onto platform combat teams for a team-mate to clean you up mid-race. |
| **Protection scopes combine** | Safe-area flags union; resistance takes the **maximum** across providers. **No other resource can clear NCM's sanctioned safe area.** Exactly the guarantee IDEA-068 wanted. |
| **Cooldowns follow the character, not the session** | Bound to the durable character across reconnects — but **not** across a server restart. |
| **Statuses end on** purge, death, revive, reconnect, bucket change, attacker leaving, provider stopping | A **bucket change ends a status** — and NCM moves players between buckets to start events. Worth knowing before designing anything that should persist into a race. |

## 8. OPERATIONAL: `open77_hacking` is NOT running on staging

The 39 resources on `52.60.225.137` include `open77_cyberware`, `open77_effects`, `open77_nameplates`,
`open77_voice` — and **no `open77_hacking`**. Every `Open77.hacking.*` call would return `hacking_unavailable`
today, and the guide's example declares `dependency "open77_hacking >=0.1.0"`.

Good news: it is a **server-side system resource**, so adding it is a `resources.load` change, not a client mod —
**KB-8 does not block it.** It also needs the `open77_appearance` character adapter (running) and a database
(reachable). Do not add it during the validation pass; it is a deliberate, separate step.

### ⚠ Key collision, already paid for once

`open77_hacking`'s default binds are **hold F8 = upload**, INSERT = purge self, DELETE = purge ally, END = cancel.
**NCM already uses F8 for the race graph.** This is the F7/camera collision (Batch 2 §2.6) about to happen again,
and this time it is a *platform* resource's default rather than ours. Settle NCM's key map against
`resources/system/open77_hacking/client/config.lua` before enabling it. Cross-ref **IDEA-046** (rebindable keys).

## 9. Documentation gaps found while doing this

1. **`Open77.cyberware.define`'s card is narrower than the function.** It documents only
   `slot="arms", profile="gorilla_arms"` with melee-only required fields — yet the hacking guide's own example
   registers `operating_system`/`cyberdeck`, `self_ice`/`self_ice` and `purge`/`active_purge` through the same
   call, passing inert melee values. The card needs a refresh; behaviour is broader than documented.
2. **Permission catalogue is empty for these.** `players.hacking.define` reports *"gates 0 natives — none in the
   catalogue"*, and every hacking card says *"permissions: none checked in the handler"*, while the guide's
   Server API table assigns a permission to every call. Enforcement is real but uncatalogued — the same shape as
   E0's open question about read natives possibly being ungated. **Declare the permissions anyway.**
3. **`open77_changes from=2.31.13+op77.78` returns "0 natives added … (0 releases)"** — the index simply has
   nothing past .78, so what staging's **op77.84** adds remains unknown from the docs. Every `since` above is a
   lower bound.

## 10. Still deliberately not done

No roster. The palette is complete enough to design one: six native kinds as the *delivery mechanism*, the
`effects` block for the person, `Open77.vehicles.*` for the car, ICE and purge as shipped counterplay, safe-area
and resistance as the ruleset gate. That design conversation is next, separately.
