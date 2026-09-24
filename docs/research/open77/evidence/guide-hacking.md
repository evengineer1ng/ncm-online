# Hacking and counterplay âº Hacking and counterplay

Build multiplayer hacking abilities with server-owned definitions, grants and target validation. The following sections describe the supported implants, upload rules and Lua interfaces.

Default keys: hold **F8** to upload on the aimed player, **INSERT** to purge yourself,
**DELETE** to purge the aimed ally, **END** to cancel your own upload. Players rebind them
in Pause â Settings â KEY BINDINGS; the defaults live in
`resources/system/open77_hacking/client/config.lua`.


## Hacking and counterplay âº Minimal example

A resource that defines one Short Circuit deck, one Self-ICE and one purge implant, and
installs them on the player who runs `/hackkit deck`, `/hackkit ice` or `/hackkit purge`.
It needs the `open77_appearance` character adapter and a configured database, like every
[cyberware](cyberware.md) resource. Hacking implants are ordinary implants: the hacking
definition and a cyberware definition with the same ID, version and grade IDs.

`open77.lua`:

```lua
resource "my_hacking"
version "1.0.0"
dependency "open77_hacking >=0.1.0"
server_script "server/main.lua"
permissions {
    "players.hacking.define", "players.hacking.read", "players.hacking.activate",
    "players.cyberware.define", "players.cyberware.read", "players.cyberware.manage"
}
```

`server/main.lua`:

```lua
local inert = { normalDamage = 0, chargedDamage = 0, knockbackMeters = 0, cooldownMs = 100, chargeMs = 100 }
local kit = {
    deck  = { id = "myserver.short_circuit", slot = "operating_system", profile = "cyberdeck" },
    ice   = { id = "myserver.self_ice",      slot = "self_ice",         profile = "self_ice" },
    purge = { id = "myserver.purge",         slot = "purge",            profile = "active_purge" },
}

CreateThread(function()
    assert(Open77.hacking.define({ id = kit.deck.id, version = 1, grades = {
        { id = "training", range = 20, uploadMs = 2000, staminaCost = 20, cooldownMs = 5000,
          damage = 25, statusMs = 750, recoveryMs = 4000, nonlethal = true },
    }}))
    assert(Open77.hacking.defineIce({ id = kit.ice.id, version = 1, grades = {
        { id = "training", charges = 1, rechargeMs = 15000 },
    }}))
    assert(Open77.hacking.definePurge({ id = kit.purge.id, version = 1, grades = {
        { id = "training", staminaCost = 15, cooldownMs = 8000, allowSelf = true, allowAlly = true,
          range = 10, cancelUploads = true, removeStatuses = true },
    }}))
    for _, item in pairs(kit) do
        local grade = { id = "training" }
        for k, v in pairs(inert) do grade[k] = v end
        assert(Open77.cyberware.define({ id = item.id, version = 1, slot = item.slot,
            profile = item.profile, grades = { grade } }))
    end
end)

RegisterCommand("hackkit", function(source, args)
    local player, item = tonumber(source), kit[args[1] or "deck"]
    if not player or player <= 0 or not item then return end
    local record, reason = Open77.cyberware.current(player)
    if not record then print("character not ready: " .. tostring(reason)); return end
    local result, error = Open77.cyberware.install(player, item.id, "training",
        { expectedRevision = record.revision, operationId = assert(Open77.cyberware.newOperationId()) })
    print("hackkit: " .. (result and json.encode(result) or tostring(error)))
end, false)
```

The attacker runs `/hackkit deck`, waits for the installation to complete (see
[transactions](cyberware.md#transactions)), aims at a visible player within 20 m and
holds **F8** until the bar fills. The target sees an `INCOMING SHORT CIRCUIT` bar and a
warning, and can step behind cover, leave range, damage the hacker, or press **INSERT**
if `/hackkit purge` was installed. `/hackkit ice` makes the next upload bounce off
Self-ICE. Your server's combat scope and team rules must allow the attacker to damage
the target, exactly as for any other attack.

_natives: CreateThread, server:CreateThread, server:Open77.hacking.define, server:Open77.hacking.defineIce, server:Open77.hacking.definePurge, server:Open77.cyberware.define, RegisterCommand, server:RegisterCommand, server:Open77.cyberware.current, server:Open77.cyberware.install, server:Open77.cyberware.newOperationId Â· permissions: players.hacking.define, players.hacking.read, players.hacking.activate, players.cyberware.define, players.cyberware.read, players.cyberware.manage_

## Hacking and counterplay âº Server API

All calls live under `Open77.hacking` (and `Open77.statuses` for the two status calls).
Failures return `nil, reason`; mutations return `{ok = true, actionId = ...}`.

| Call | Permission | Purpose |
|---|---|---|
| `define(definition)` | `players.hacking.define` | Hack definition and grades |
| `defineIce(definition)` | `players.hacking.define` | Self-ICE definition and grades |
| `definePurge(definition)` | `players.hacking.define` | Purge definition and grades |
| `state(playerId)` | `players.hacking.read` | Cooldowns, ICE charges, uploads, statuses, and the running gates `cyberwareSuspendedMs`, `frozenMs`, `malfunctionMs`, `malfunctionBlocks`, `crippledMs`, `crippleHeavy`, `blindedMs`, `weaponGlitchedMs` |
| `action(actionId)` | `players.hacking.read` | A running action or its terminal receipt |
| `statuses(playerId)` / `Open77.statuses.list(playerId)` | `players.hacking.read` | Statuses currently on a player |
| `start(actor, target, definition, grade, options)` | `players.hacking.activate` | Start an upload from script |
| `purge(actor, target, definition, grade, options)` | `players.hacking.activate` | Purge from script, through the same rules as the key |
| `cancel(actionId)` | `players.hacking.cancel` | Cancel your own upload |
| `configureProtection(playerId, {safeArea = bool, resistance = number})` | `players.hacking.policy` | Safe-area flag and electrical resistance (0â1) for a player's current body |
| `clearProtection(playerId)` | `players.hacking.policy` | Remove only your protection scope |
| `Open77.statuses.apply(actor, target, definition, grade)` | `players.statuses.apply` | Apply a grade's status directly, subject to the same eligibility |
| `Open77.statuses.remove(actionId)` | `players.statuses.purge` | Remove your status; damage already committed stays |
| `capabilities()` | `players.hacking.read` | The kinds, fields and caps below |

`start` and `purge` require `options = {operationId = "..."}`; reuse the ID when you
retry the same call, a reused ID with different arguments is refused. Definitions belong
to the resource that registered them; stopping it revokes them and cancels its uploads
but leaves installed implants on the record.


## Hacking and counterplay âº Options




### Hacking and counterplay âº Hack grade

| Field | Default | Accepted values |
|---|---|---|
| `kind` | `"short_circuit"` | `short_circuit`, `overheat`, `malfunction`, `cripple`, `reboot_optics`, `weapon_glitch` |
| `range` | `20` | 1â80 m |
| `uploadMs` | `2000` | 500â15000 |
| `staminaCost` | `20` | 0â300 |
| `cooldownMs` | `5000` | 250â600000 |
| `damage` | `25` | 0â300, the direct electrical hit of every kind |
| `statusMs` | `750` | 0â2000; the Short Circuit disruption. Ignored by the other kinds |
| `recoveryMs` | `4000` | `statusMs + 500` up to 60000; no attacker can hack this victim again inside it |
| `lockHacking` | `false` | Short Circuit also blocks the victim's own hacking for `statusMs` |
| `nonlethal`, `cosmetic` | `false` | Nonlethal never kills; cosmetic commits no damage |
| `friendlyFire`, `allowSafeArea` | `false` | Grade eligibility; the server's combat veto still wins |
| `interruptOnDamage`, `interruptDamage` | `true`, `0` | Whether accepted damage above the threshold (0â300) interrupts the hacker |
| `evidenceFreshMs`, `challengeMs` | `500`, `1000` | 100â750 / 250â2000 ms for the line-of-sight evidence |
| `effects` | `nil` | The outcome block below |
| `burn`, `malfunction`, `cripple`, `optics`, `glitch` | `nil` | One block, matching `kind`; a block on the wrong kind is `invalid_definition` |


### Hacking and counterplay âº What each kind does

| Kind | On the victim | Server refuses | Block |
|---|---|---|---|
| `short_circuit` | Electrical hit, `statusMs` disruption | Hacking if `lockHacking` | â |
| `overheat` | Direct hit, then a burn ticked by the server | â | `burn = {totalDamage 0â300 (40), durationMs 1000â15000 (5000), tickMs 250â1000 (500)}` |
| `malfunction` | Listed abilities stop answering | Dash, Ground Slam, Gorilla arming, hacking and purge with `cyberware_suspended` | `malfunction = {durationMs 1000â30000 (5000), blocks = subset of dash, ground_slam, gorilla, hacking (all four)}` |
| `cripple` | The victim's client slows itself: speed x0.75, or x0.4 with `heavy`, no dodge or double jump | Dash and Ground Slam with `crippled` | `cripple = {durationMs 1000â30000 (5000), heavy false}` |
| `reboot_optics` | The victim's client applies the native blind: static, scanner off, accuracy x0.01 | Nothing | `optics = {durationMs 1000â15000 (5000)}` |
| `weapon_glitch` | The victim's client jams the held weapon: it cannot fire | Gorilla arming with `weapon_glitched` | `glitch = {durationMs 1000â15000 (5000)}` |

Every block is optional (defaults in brackets). A burn is split evenly over
`durationMs / tickMs` ticks, the first landing one `tickMs` after impact; `totalDamage = 0`
is a burn with no damage. A malfunction that lists `hacking` also denies the victim its
own INSERT; an ally's DELETE still works.


### Hacking and counterplay âº The `effects` block

Any grade can add outcomes to its connected upload:

```lua
{ id = "stun", range = 20, uploadMs = 2000, staminaCost = 20, cooldownMs = 6000,
  statusMs = 750, recoveryMs = 6000, nonlethal = true,
  effects = {
      damage = 10,              -- replaces `damage`; 0â300
      freezeMs = 2000,          -- hold the victim; 1â10000, at most recoveryMs
      knockdown = true,         -- victim to the floor; needs recoveryMs >= 1500
      disableCyberwareMs = 5000 -- Dash, Ground Slam, Gorilla, hacking and purge refused; 1â30000
  } }
```

`knockdown` and `freezeMs` share one hold: the victim goes to the floor once (about three
seconds); a longer freeze keeps the ability gate running, and the victim's own client
locks the body from the third second to the deadline. `disableCyberwareMs` is bound to
the character, so a reconnect does not clear it; a Malfunction status, by contrast, is
lifted by purge, death, reconnect and a bucket change.


### Hacking and counterplay âº Self-ICE and purge grades

| Grade | Field | Default | Accepted values |
|---|---|---|---|
| ICE | `charges` | `1` | 1â8 uploads blocked before recharging |
| ICE | `rechargeMs` | `15000` | 1000â600000 |
| Purge | `staminaCost` | `15` | 0â300 |
| Purge | `cooldownMs` | `8000` | 250â600000 |
| Purge | `allowSelf`, `allowAlly` | `true`, `false` | At least one |
| Purge | `range` | `10` | 1â40 m, for ally purge |
| Purge | `cancelUploads`, `removeStatuses` | `true`, `true` | At least one |

Ally purge needs both players on the same positive combat team. A purge charges its cost
only when it finds something to cancel or remove, and never heals damage already dealt.


## Hacking and counterplay âº Events

`onHackingTransition(encodedJson)` is the ledger of every hack. Decode the argument with
`json.decode`: `actionId`, `owner`, `attacker`, `target`, `attackerIncarnation`,
`targetIncarnation`, `definition`, `grade`, `kind`, `phase`, `reason`, `startedAt`,
`deadline`, `statusEndsAt`, `amount`, `lockHacking`, `from`, `to` and, on a malfunction,
`blocks`. Phases: `challenge`, `upload_started`, `upload_progress`, `blocked`,
`interrupted`, `impact`, `completed`, `status_applied`, `status_tick` (one per burn
tick, `amount` = damage committed), `status_expired`, `status_purged`, `effect_applied`
and `effect_refused`.

```lua
AddEventHandler("onHackingTransition", function(encoded)
    local t = json.decode(encoded)
    if t.phase == "impact" or t.phase == "effect_applied" then
        print(("%s hacked %s: %s %s %s"):format(t.attacker, t.target, t.kind, t.phase, tostring(t.reason)))
    end
end)
```

Do not infer a second hit from `status_applied` or `completed`; only `impact` and
`status_tick` are damage. Callbacks in one tick can arrive out of order, so correlate on
`actionId` rather than on arrival.

_natives: AddEventHandler, server:AddEventHandler_

## Hacking and counterplay âº Optional lab

`open77_hacking_lab` (`auto_start false`) ships every kind as a grade of `lab.short_circuit`
plus ICE and purge, and installs them through the cyberware APIs. Grant testers the
`command.hacklab` ACL. With two connected, alive players `1` and `2` in bucket `0`:

```text
/hacklab attacker 1 training hacking-a-01      -- or overheat, malfunction, malfunction_motion,
                                                --    cripple, cripple_heavy, reboot_optics,
                                                --    weapon_glitch, stun, freeze_long, cosmetic
/hacklab protected 2 training hacking-b-ice-01
/hacklab ally 2 training hacking-b-purge-01
/hacklab scope 0 1 2                            -- allow PvP between the two; /hacklab unscope <id>
/hacklab state 2
/hacklab purge 2                                -- self purge from the server; /hacklab purge 2 1 for an ally
/hacklab protection 2 on 0                      -- safe area; "off 0.5" = 50% resistance
/hacklab remove 2 self_ice hacking-b-ice-remove-01
```

The last argument of an install or removal is the operation ID; use a new one for each
new operation. The grades are in `resources/gamemodes/open77_hacking_lab/server/config.lua`.


## Hacking and counterplay âº Limits

**One status of each kind per victim.** A second Overheat, Malfunction, Cripple, Reboot
Optics or Weapon Glitch inside the first lands its direct hit and `effects` but its
status is refused, not refreshed: `effect_refused` with the running deadline in
`statusEndsAt` (`status_stacked` from `statuses.apply`). Statuses of different kinds
coexist. With `recoveryMs >= durationMs` nobody is even admitted while the status runs.

**Two halves.** The slow, the blind and the jam are applied by the victim's own client;
the ability refusals (`cyberware_suspended`, `crippled`, `weapon_glitched`, `frozen`)
are the server's. A modified client can ignore its own slow, blind or jam, but it cannot
dash, slam or arm Gorilla Arms through the gate. Reboot Optics has no server half at all.

**Line of sight is client evidence.** The server issues short-lived challenges to both
participants and each client traces the same segment against static and dynamic
collision. A missing, stale or failed trace blocks the upload. This is a shared-evidence
model, not a server-side collision query: two colluding modified clients can defeat it.

**The victim is always warned.** Every incoming upload produces a toast, a chat warning
and the native `INCOMING <KIND>` bar. If the victim's notification cannot be delivered the
upload fails closed. Repeated challenges do not repeat the warning.

**Damage is one ledger write.** The direct hit is electrical (`hacking_impact`, no blood,
no native hit reaction); `resistance` and safe areas reduce it. Burn ticks are thermal
and ignore electrical resistance; a tick the combat rules refuse ends the burn. Purge,
death, revive, reconnect, bucket change, the attacker leaving and the provider stopping
all end a status; committed damage stays.

**Cooldowns follow the character.** Hack, purge and recovery timers are bound to the
durable character across reconnects for the life of the server process; they do not
survive a server restart.

**Protection scopes combine.** Safe-area flags union and electrical resistance takes the
maximum across providers, so one resource cannot clear another's protection. Scopes
expire with the body they were set on.


## Hacking and counterplay âº Advanced: presentation

`open77_hacking` renders every kind with fixed identifiers; replace its
`server/presentation.lua` to change what observers see, and `client/config.lua`
(`HackingInput.feedback = {flash = true, sound = true}`) to switch the victim's flash and
local sound off.

| Kind | Observers and attacker | Victim's own screen | Everyone in range |
|---|---|---|---|
| Short Circuit | Electrocuted effect on `RightHand` and `Chest`, `electric.arc` on `RightHand`, 1.5 s (to status end, max 2 s) | `status_electrocuted`, electric-blue flash | `quickhack_shortcircuit` |
| Overheat | `fire.tiny` and `smoke.steam` on `Chest` for the burn | `hacks_overheat_lvl1`, heat-orange flash | `quickhack_overheat` |
| Malfunction | EMP and electrocuted effects on `Chest`, `sparks.cable` on `RightHand` for the suppression | `hacks_cyberware_malfunction`, violet flash | `quickhack_cyberware_malfunction` |
| Cripple | No body layer; the slow itself | `hacking_glitch_low`, crippled HUD icon, violet-blue flash | `quickhack_locomotion_malfunction` |
| Reboot Optics | `electric.arc` on `Chest` for the blind | `status_blinded`, `hacking_glitch_low`, blinded HUD icon, white-cyan flash | `quickhack_optics_malfunction` |
| Weapon Glitch | Electrocuted effect and `sparks.cable` on `RightHand` for the jam | `hacks_weapon_malfunction`, jammed-weapon HUD icon, amber flash | `quickhack_weapon_malfunction` |

The attacker's bar shows `<KIND> UPLOAD` while holding, then `<KIND> IMPACT`; the victim's
shows `INCOMING <KIND>`. The bar is drawn at 1.5x while it carries a hacking header.
Client resources can observe a streamed target with `Open77.hacking.observe(playerId)`
and drive the bar with `present({actionId, phase, progress, kind})` / `clear()` behind
`player.hacking.project`; the victim-side statuses use `Open77.hacking.nativeStatus`
(`player.hacking.status`) and `Open77.movement.lock` (`player.movement.lock`). None of
these grant hacking authority, and the `open77:hacking:*` network events cannot be sent
by a resource.

