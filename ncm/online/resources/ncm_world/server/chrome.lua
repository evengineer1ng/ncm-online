-- ncm_world / server / chrome -- NCM Chrome: vehicle quickhacks on OPEN//77's hacking framework (`L200`).
--
-- **Chrome affects vehicles only, and it adapts the platform's framework rather than replacing it**
-- (`docs/research/open77/CAPABILITY_PALETTE.md` §1-§3, IDEA-067). The platform runs target selection, entitlement,
-- the warned interruptible upload (1..80 m), line-of-sight challenges, Self-ICE and purge. NCM registers ONE deck
-- (`ncm.chrome`) whose grades are the roster, every grade `cosmetic`, `nonlethal`, `damage = 0`: the person is
-- never touched. When `onHackingTransition` reports `impact`, this file applies the VEHICLE consequence.
--
-- Where the consequence goes:
--   * LIMITER / LIMP / POWER SURGE / OVERCLOCK -> the `chrome` layer of the target Machine's handling, delivered by
--     the Carrier governor (`handling.lua` asks `NcmChrome.contributorFor` and `NcmChrome.capKph`). Speed is never
--     written through `setPerformance` here.
--   * ENGINE CUT / TIRE SABOTAGE / BLACKOUT / LIMP health / TOTAL FAILURE -> `Open77.vehicles.*` natives, on any
--     network vehicle.
--
-- Two routes onto a target:
--   * `platform` -- the car has a human driver: `Open77.hacking.start(attacker, driver, deck, hack)`. The platform
--     warns the victim and runs the counterplay; its transitions are relayed to both clients, which drive the
--     native bars with `Open77.hacking.present` (the reference `open77_hacking` resource ships in no server package).
--   * `ncm` -- nobody human is driving (AI traffic): the same grade's range and upload time, timed here, with the
--     attacker's client proving every 600 ms that it is still holding the lock. There is no victim to warn.
--
-- Admission between players needs PvP scope. One scope per bucket admits hacks, and a damage arbiter refuses every
-- player-on-player hit with an amount, so weapons stay exactly as off as they were. Allowed everywhere (owner,
-- 2026-09-28): no ruleset refusal yet.
NcmChrome = {}

local Chrome = NcmCore.get("competition.chrome")
local Json = NcmCore.get("vocabulary.json")

local function log(fmt, ...) print(("[ncm_world/chrome] " .. fmt):format(...)) end
local function nowMs() return math.floor((tonumber(Open77.time.unix()) or 0) * 1000) end

local HEARTBEAT_MS = 600      -- the ncm route's proof that the attacker is still holding the lock
local RANGE_SLACK_M = 10.0    -- a moving target's snapshot trails the attacker's view
local TICK_MS = 200

local effects = {}       -- vehicleId -> { { hack, startedAt, endsAt, actor } }
local timers = {}        -- { at, fn, label }
local actions = {}       -- platform actionId -> { attacker, target, vehicleId, hack, token }
local early = {}         -- platform actionId -> transitions that arrived before `start` returned
local ncmUploads = {}    -- attacker pid -> { hack, vehicleId, startedAt, deadline, heartbeat, token }
local channels = {}      -- attacker pid -> { hack, vehicleId, deadline } (SYSTEM RESTORE)
local cooldowns = {}     -- pid -> { [hack] = ready-at ms }
local deck = {}          -- pid -> { grade = slotted grade, pending = grade being installed, ticket }
local defined = false

-- ---------------------------------------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------------------------------------

local function after(ms, label, fn) timers[#timers + 1] = { at = nowMs() + ms, fn = fn, label = label } end

local function vcall(name, ...)
    local fn = Open77.vehicles and Open77.vehicles[name]
    if type(fn) ~= "function" then return nil, "no_native:" .. name end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil, tostring(a) end
    return a, b
end

local function driverId(pid)
    local ok, profile = pcall(function() return NcmIdentity and NcmIdentity.get and NcmIdentity.get(pid) end)
    return ok and type(profile) == "table" and profile.ncmDriverId or nil
end

local function vehiclePos(vid)
    local v = vcall("get", vid)
    if type(v) ~= "table" then return nil end
    if type(v.position) == "table" then return v.position, v end
    if type(v.x) == "number" then return { x = v.x, y = v.y, z = v.z }, v end
    return nil, v
end

local function playerPos(pid)
    local ok, p = pcall(Open77.players.get, tonumber(pid) or 0)
    if ok and type(p) == "table" and type(p.position) == "table" then return p.position, p end
    return nil, ok and p or nil
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

--- The vehicle this player is sitting in, or nil.
local function ownVehicle(pid)
    local seat = nil
    if Open77.players and type(Open77.players.getVehicleSeat) == "function" then
        local ok, s = pcall(Open77.players.getVehicleSeat, pid)
        if ok then seat = s end
    end
    if type(seat) == "table" then return tonumber(seat.vehicleId or seat.vehicle or seat.id) end
    return tonumber(seat)
end

--- The persistent Machine riding on this network vehicle, if it is an NCM asset someone is operating.
local function assetFor(vid)
    if not (NcmVehicleAccess and NcmVehicleAccess.liveAssets) then return nil end
    for _, a in ipairs(NcmVehicleAccess.liveAssets()) do
        if tonumber(a.vehicleId) == tonumber(vid) then return a end
    end
    return nil
end

local function humanDriver(vid)
    local d = vcall("getDriver", vid)
    return tonumber(type(d) == "table" and (d.playerId or d.id) or d)
end

local function record(fields)
    local ok, err = pcall(function()
        MySQL.insert.await([[INSERT INTO chrome_event (event_id, server_id, attacker_driver_id, target_driver_id,
            hack, outcome, route, target_vehicle_id, target_record, catastrophic, detail, occurred_at)
            VALUES (UUID(), ?, NULLIF(?, ''), NULLIF(?, ''), ?, ?, ?, NULLIF(?, -1), NULLIF(?, ''), ?, NULLIF(?, ''), ?)]],
            { (NcmIdentity and NcmIdentity.serverId and NcmIdentity.serverId()) or (GetConvar and GetConvar("ncm_server_id", "ncm")) or "ncm",
              fields.attacker and driverId(fields.attacker) or "", fields.target and driverId(fields.target) or "",
              fields.hack, fields.outcome, fields.route, tonumber(fields.vehicleId) or -1, fields.record or "",
              fields.catastrophic and 1 or 0, fields.detail or "", math.floor(nowMs() / 1000) })
    end)
    if not ok then log("ledger write failed (%s %s): %s", tostring(fields.hack), tostring(fields.outcome), tostring(err)) end
end

local function tell(pid, body)
    if pid and pid > 0 then TriggerClientEvent("ncm:chrome.state", pid, body) end
end

local function present(pid, actionId, phase, progress, label)
    if pid and pid > 0 then
        TriggerClientEvent("ncm:chrome.present", pid, { actionId = actionId, phase = phase,
            progress = progress or 0, label = label })
    end
end

-- ---------------------------------------------------------------------------------------------------------
-- Effects on a vehicle
-- ---------------------------------------------------------------------------------------------------------

local function republish(vid)
    local a = assetFor(vid)
    if a and NcmHandling and NcmHandling.recompute then pcall(NcmHandling.recompute, a.assetId, "chrome") end
end

local function clearEffects(vid, why)
    local list = effects[vid]
    effects[vid] = nil
    if list and #list > 0 then
        republish(vid)
        log("vehicle=%s chrome cleared (%s, %d effect(s))", tostring(vid), tostring(why), #list)
    end
    vcall("setEngine", vid, true)
end

local function addTimed(vid, hack, actor)
    local h = Chrome.hack(hack)
    local t = nowMs()
    effects[vid] = effects[vid] or {}
    table.insert(effects[vid], { hack = hack, startedAt = t, endsAt = t + (h.durationMs or 0), actor = actor })
end

--- Apply one landed hack to one vehicle. Returns true, or false and why.
local function applyEffect(vid, hack, actor)
    local h = Chrome.hack(hack)
    if not h then return false, "unknown_hack" end
    local e = h.effect or {}
    if e.cap or e.handling then
        addTimed(vid, hack, actor)
        republish(vid)
    end
    if e.healthTo then
        local hp = tonumber((vcall("getHealth", vid))) or 1
        vcall("setHealth", vid, math.min(hp, e.healthTo))
    end
    if e.engineCut then
        vcall("setEngine", vid, false)
        after(h.durationMs or 3000, "engine restore", function() vcall("setEngine", vid, true) end)
    end
    if e.breakTire then
        vcall("breakTire", vid, math.random(0, 3))
    end
    if e.blackout then
        local prior = vcall("getLights", vid)
        vcall("setLights", vid, "off")
        for i = 0, 7 do vcall("breakLight", vid, i) end
        after(h.durationMs or 15000, "lights restore", function()
            vcall("repairAllLights", vid)
            vcall("setLights", vid, (type(prior) == "string" and prior ~= "off") and prior or "on")
        end)
    end
    if e.after then
        after(h.durationMs or 0, hack .. " aftermath", function()
            local hp = tonumber((vcall("getHealth", vid))) or 1
            if e.after.healthDrop then vcall("setHealth", vid, math.max(0.05, hp - e.after.healthDrop)) end
            if e.after.engineCutMs then
                vcall("setEngine", vid, false)
                after(e.after.engineCutMs, "overclock restart", function() vcall("setEngine", vid, true) end)
            end
        end)
    end
    if e.purge then clearEffects(vid, "purge") end
    if e.restore then
        clearEffects(vid, "system restore")
        vcall("repairAllTires", vid)
        vcall("repairAllLights", vid)
        local hp = tonumber((vcall("getHealth", vid))) or 1
        vcall("setHealth", vid, math.max(hp, 0.6))
    end
    if e.explode then vcall("explode", vid) end
    log("IMPACT %s on vehicle=%s by player=%s", hack, tostring(vid), tostring(actor))
    return true
end

--- For `handling.lua`: the `chrome` contributor of one Machine, or nil.
function NcmChrome.contributorFor(assetId)
    local a = NcmVehicleAccess and NcmVehicleAccess.liveAsset and NcmVehicleAccess.liveAsset(assetId)
    if not a or not a.vehicleId then return nil end
    return Chrome.handling(effects[tonumber(a.vehicleId)], nowMs())
end

--- For `handling.lua`: the chrome speed cap of one Machine in km/h against its authored baseline, or nil.
function NcmChrome.capKph(assetId, baselineKph)
    local a = NcmVehicleAccess and NcmVehicleAccess.liveAsset and NcmVehicleAccess.liveAsset(assetId)
    if not a or not a.vehicleId then return nil end
    return Chrome.capKph(effects[tonumber(a.vehicleId)], nowMs(), baselineKph)
end

-- ---------------------------------------------------------------------------------------------------------
-- Definitions and implants
-- ---------------------------------------------------------------------------------------------------------

local function defineAll()
    if not (Open77.hacking and Open77.hacking.define) then log("Open77.hacking unavailable on this host"); return false end
    local steps = {
        { "hacking.define", function() return Open77.hacking.define(Chrome.deckDefinition()) end },
        { "hacking.defineIce", function() return Open77.hacking.defineIce(Chrome.iceDefinition()) end },
        { "hacking.definePurge", function() return Open77.hacking.definePurge(Chrome.purgeDefinition()) end },
    }
    for _, impl in ipairs(Chrome.implants()) do
        steps[#steps + 1] = { "cyberware.define " .. impl.id, function() return Open77.cyberware.define(impl) end }
    end
    local all = true
    for _, s in ipairs(steps) do
        local ok, res, why = pcall(s[2])
        if not ok or not res then
            all = false
            log("%s FAILED: %s", s[1], tostring(ok and why or res))
        end
    end
    if all then log("defined: deck %s (%d grades), Self-ICE, purge, and their implants", Chrome.DECK_ID, #Chrome.deckHacks()) end
    return all
end

local installQueue = {}   -- pid -> list of { id, grade }
local installing = {}     -- pid -> { ticket, id, grade }

local function pumpInstall(pid)
    if installing[pid] then return end
    local q = installQueue[pid]
    if not q or #q == 0 then return end
    local ok, rec = pcall(Open77.cyberware.current, pid)
    if not ok or type(rec) ~= "table" then
        after(2000, "install retry", function() pumpInstall(pid) end)
        return
    end
    local item = table.remove(q, 1)
    local okOp, opId = pcall(Open77.cyberware.newOperationId)
    local okI, res, why = pcall(Open77.cyberware.install, pid, item.id, item.grade,
        { expectedRevision = rec.revision, operationId = okOp and opId or ("ncm-chrome-" .. pid .. "-" .. nowMs()) })
    if not okI or not res then
        log("install %s/%s for player=%d refused: %s", item.id, item.grade, pid, tostring(okI and why or res))
        if item.id == Chrome.DECK_ID and deck[pid] then deck[pid].pending = nil end
        tell(pid, { slotted = deck[pid] and deck[pid].grade or nil, error = tostring(okI and why or res) })
        return pumpInstall(pid)
    end
    if res.ticket then
        installing[pid] = { ticket = res.ticket, id = item.id, grade = item.grade }
    else
        if item.id == Chrome.DECK_ID then deck[pid] = { grade = item.grade }; tell(pid, { slotted = item.grade }) end
        pumpInstall(pid)
    end
end

local function queueInstall(pid, id, grade)
    installQueue[pid] = installQueue[pid] or {}
    for i = #installQueue[pid], 1, -1 do
        if installQueue[pid][i].id == id then table.remove(installQueue[pid], i) end
    end
    table.insert(installQueue[pid], { id = id, grade = grade })
    pumpInstall(pid)
end

AddEventHandler("onCyberwareOperationCompleted", function(playerId, ticket, encoded)
    local pid = tonumber(playerId) or 0
    local cur = installing[pid]
    if not cur or cur.ticket ~= ticket then return end
    installing[pid] = nil
    local ok, result = pcall(Json.decode, tostring(encoded or ""))
    local success = ok and type(result) == "table" and (result.ok == true or result.status == "completed" or result.error == nil)
    if cur.id == Chrome.DECK_ID then
        if success then deck[pid] = { grade = cur.grade } else if deck[pid] then deck[pid].pending = nil end end
        tell(pid, { slotted = deck[pid] and deck[pid].grade or nil, error = not success and tostring(encoded) or nil })
    end
    log("install %s/%s player=%d %s", cur.id, cur.grade, pid, success and "completed" or ("failed: " .. tostring(encoded)))
    pumpInstall(pid)
end)

local function equip(pid)
    deck[pid] = deck[pid] or {}
    queueInstall(pid, Chrome.ICE_ID, Chrome.ICE_GRADE.id)
    queueInstall(pid, Chrome.PURGE_ID, Chrome.PURGE_GRADE.id)
    deck[pid].pending = "limiter"
    queueInstall(pid, Chrome.DECK_ID, "limiter")
end

-- ---------------------------------------------------------------------------------------------------------
-- PvP scope: admits hacks between players; the arbiter keeps weapon PvP off
-- ---------------------------------------------------------------------------------------------------------

local scopes = {}       -- bucket -> { id, sig }
local scoped = {}       -- pid -> true while in one of our scopes

local function reconcileScopes()
    if not (Open77.combat and Open77.combat.createScope) then return end
    local byBucket = {}
    for _, raw in ipairs(Open77.players.all() or {}) do
        local pid = tonumber(raw)
        local ok, p = pcall(Open77.players.get, pid)
        if pid and ok and type(p) == "table" and p.ready ~= false then
            local b = tonumber(p.bucket) or 0
            byBucket[b] = byBucket[b] or {}
            table.insert(byBucket[b], pid)
        end
    end
    local seen = {}
    local nextScoped = {}
    for bucket, roster in pairs(byBucket) do
        table.sort(roster)
        while #roster > 32 do table.remove(roster) end
        local sig = table.concat(roster, ",")
        seen[bucket] = true
        local cur = scopes[bucket]
        if #roster >= 2 then
            if not cur or cur.sig ~= sig then
                if cur and cur.id then pcall(Open77.combat.removeScope, cur.id) end
                local ok, id, why = pcall(Open77.combat.createScope, { bucket = bucket, players = roster })
                if ok and id then
                    scopes[bucket] = { id = id, sig = sig }
                    log("chrome scope bucket=%d players=%s", bucket, sig)
                else
                    scopes[bucket] = { sig = sig }
                    log("chrome scope bucket=%d REFUSED: %s", bucket, tostring(ok and why or id))
                end
            end
            if scopes[bucket] and scopes[bucket].id then for _, pid in ipairs(roster) do nextScoped[pid] = true end end
        elseif cur then
            if cur.id then pcall(Open77.combat.removeScope, cur.id) end
            scopes[bucket] = nil
        end
    end
    for bucket, cur in pairs(scopes) do
        if not seen[bucket] then
            if cur.id then pcall(Open77.combat.removeScope, cur.id) end
            scopes[bucket] = nil
        end
    end
    scoped = nextScoped
end

local function installArbiter()
    if not (Open77.combat and Open77.combat.onDamage) then return end
    Open77.combat.onDamage(function(ev)
        local a, v = tonumber(ev and ev.attacker), tonumber(ev and ev.victim)
        if a and v and a ~= v and scoped[a] and scoped[v] and (tonumber(ev.amount) or 0) > 0 then
            return false
        end
    end)
end

-- ---------------------------------------------------------------------------------------------------------
-- The platform route: transitions from OPEN//77's hacking ledger
-- ---------------------------------------------------------------------------------------------------------

local PHASE = { challenge = "upload", upload_started = "upload", upload_progress = "upload", blocked = "block",
                interrupted = "cancel", impact = "impact" }

local function progressOf(t)
    local s, d = tonumber(t.startedAt), tonumber(t.deadline)
    if not s or not d or d <= s then return 0 end
    return math.max(0, math.min(1, (nowMs() - s) / (d - s)))
end

local function onTransition(t)
    local a = actions[t.actionId]
    if not a then
        early[t.actionId] = early[t.actionId] or {}
        table.insert(early[t.actionId], t)
        return
    end
    local h = Chrome.hack(a.hack)
    local label = h and h.label or a.hack
    local phase = PHASE[t.phase]
    if phase then
        local p = phase == "impact" and 1 or progressOf(t)
        present(a.attacker, t.actionId, phase, p, label)
        present(a.target, t.actionId, phase == "upload" and "incoming" or phase, p, label)
    end
    if t.phase == "impact" then
        applyEffect(a.vehicleId, a.hack, a.attacker)
        record({ attacker = a.attacker, target = a.target, hack = a.hack, outcome = "impact", route = "platform",
                 vehicleId = a.vehicleId, catastrophic = h and h.catastrophic })
        tell(a.attacker, { token = a.token, result = "impact", hack = a.hack })
    elseif t.phase == "blocked" or t.phase == "interrupted" then
        record({ attacker = a.attacker, target = a.target, hack = a.hack, outcome = t.phase, route = "platform",
                 vehicleId = a.vehicleId, detail = t.reason })
        tell(a.attacker, { token = a.token, result = t.phase, reason = t.reason, hack = a.hack })
    end
    if t.phase == "completed" or t.phase == "blocked" or t.phase == "interrupted" then actions[t.actionId] = nil end
end

AddEventHandler("onHackingTransition", function(encoded)
    local ok, t = pcall(Json.decode, tostring(encoded or ""))
    if not ok or type(t) ~= "table" or t.definition ~= Chrome.DECK_ID then return end
    onTransition(t)
end)

-- ---------------------------------------------------------------------------------------------------------
-- Requests from the Scanner
-- ---------------------------------------------------------------------------------------------------------

local refusalsLogged = {}   -- pid -> count; the first few per session are logged, so a silent refusal is visible

local function refuse(pid, token, hack, why)
    local n = (refusalsLogged[pid] or 0) + 1
    refusalsLogged[pid] = n
    if n <= 30 then log("start %s player=%d refused: %s", tostring(hack), pid, tostring(why)) end
    tell(pid, { token = token, result = "refused", reason = why, hack = hack })
end

--- Slot a hack into the player's deck (a durable cyberware install); the Scanner calls this on selection.
RegisterNetEvent("ncm:chrome.select", function(hack)
    local pid = tonumber(source) or 0
    local h = Chrome.hack(tostring(hack or ""))
    if not h then return end
    if h.target ~= "other" then tell(pid, { selected = h.id }); return end
    deck[pid] = deck[pid] or {}
    if deck[pid].grade == h.id or deck[pid].pending == h.id then tell(pid, { slotted = deck[pid].grade }); return end
    deck[pid].pending = h.id
    queueInstall(pid, Chrome.DECK_ID, h.id)
end)

RegisterNetEvent("ncm:chrome.start", function(req)
    local pid = tonumber(source) or 0
    if type(req) ~= "table" then return end
    local token = tostring(req.token or "")
    local hackId = tostring(req.hack or "")
    local h = Chrome.hack(hackId)
    if not h then return refuse(pid, token, hackId, "unknown_hack") end
    local t = nowMs()
    local own = ownVehicle(pid)
    local target = tonumber(req.vehicleId)
    local me = playerPos(pid)
    local there = target and vehiclePos(target) or nil
    local asset = target and assetFor(target) or nil
    local facts = { hack = hackId, ownVehicle = own, targetVehicle = h.target == "other" and target or nil,
        distance = (me and there) and dist(me, there) or nil, targetBound = asset ~= nil and asset.pid ~= nil,
        cooldownUntil = cooldowns[pid] and cooldowns[pid][hackId], now = t }
    if facts.distance and h.range then facts.distance = math.max(0, facts.distance - RANGE_SLACK_M) end
    local admitted, why = Chrome.admit(facts)
    if not admitted then return refuse(pid, token, hackId, why) end

    -- Self hacks act on the player's own vehicle.
    if h.target == "self" then
        if hackId == "purge" then
            local okOp, opId = pcall(Open77.cyberware.newOperationId)
            pcall(Open77.hacking.purge, pid, pid, Chrome.PURGE_ID, Chrome.PURGE_GRADE.id,
                { operationId = okOp and opId or ("purge-" .. pid .. "-" .. t) })
            applyEffect(own, "purge", pid)
            record({ attacker = pid, hack = hackId, outcome = "purged", route = "ncm", vehicleId = own })
            tell(pid, { token = token, result = "impact", hack = hackId })
        elseif hackId == "system_restore" then
            channels[pid] = { hack = hackId, vehicleId = own, startedAt = t, deadline = t + (h.channelMs or 3000), token = token }
            tell(pid, { token = token, result = "channel", hack = hackId, ms = h.channelMs })
        end
        cooldowns[pid] = cooldowns[pid] or {}
        cooldowns[pid][hackId] = t + (h.cooldownMs or 0)
        return
    end

    local driver = humanDriver(target)
    if driver and driver ~= pid then
        -- The platform route. The deck must hold this grade: selection slots it.
        if not deck[pid] or deck[pid].grade ~= hackId then
            TriggerEvent("ncm:chrome.internalSelect", pid, hackId)
            return refuse(pid, token, hackId, "slotting")
        end
        local okOp, opId = pcall(Open77.cyberware.newOperationId)
        opId = okOp and opId or ("chrome-" .. pid .. "-" .. token)
        local okS, res, reason
        if hackId == "ally_purge" then
            okS, res, reason = pcall(Open77.hacking.purge, pid, driver, Chrome.PURGE_ID, Chrome.PURGE_GRADE.id, { operationId = opId })
            if okS and res then
                applyEffect(target, "ally_purge", pid)
                record({ attacker = pid, target = driver, hack = hackId, outcome = "purged", route = "platform", vehicleId = target })
                tell(pid, { token = token, result = "impact", hack = hackId })
            end
        else
            okS, res, reason = pcall(Open77.hacking.start, pid, driver, Chrome.DECK_ID, hackId, { operationId = opId })
        end
        if not okS or not res then
            return refuse(pid, token, hackId, tostring(okS and reason or res))
        end
        if res.actionId and hackId ~= "ally_purge" then
            actions[res.actionId] = { attacker = pid, target = driver, vehicleId = target, hack = hackId, token = token }
            for _, pending in ipairs(early[res.actionId] or {}) do onTransition(pending) end
            early[res.actionId] = nil
        end
        cooldowns[pid] = cooldowns[pid] or {}
        cooldowns[pid][hackId] = t + (h.cooldownMs or 0)
        log("start %s player=%d -> vehicle=%s driver=%d (platform)", hackId, pid, tostring(target), driver)
        tell(pid, { token = token, result = "uploading", hack = hackId, route = "platform" })
        return
    end

    -- The NCM route: nobody human is driving.
    -- The defender of a car nobody is driving is the player the Machine is attached to (parked, owner on foot):
    -- they are warned exactly as a driver would be, and their PURGE still clears whatever lands.
    local defender = asset and tonumber(asset.pid) or nil
    if defender == pid then defender = nil end
    ncmUploads[pid] = { hack = hackId, vehicleId = target, startedAt = t, deadline = t + (h.uploadMs or 2000),
                        heartbeat = t, token = token, actionId = 900000000 + (t % 100000000), defender = defender }
    cooldowns[pid] = cooldowns[pid] or {}
    cooldowns[pid][hackId] = t + (h.cooldownMs or 0)
    log("start %s player=%d -> vehicle=%s defender=%s (ncm)", hackId, pid, tostring(target), tostring(defender))
    tell(pid, { token = token, result = "uploading", hack = hackId, route = "ncm" })
end)

AddEventHandler("ncm:chrome.internalSelect", function(pid, hackId)
    deck[pid] = deck[pid] or {}
    if deck[pid].pending == hackId then return end
    deck[pid].pending = hackId
    queueInstall(pid, Chrome.DECK_ID, hackId)
end)

--- The attacker's client, every few hundred ms while its lock holds.
RegisterNetEvent("ncm:chrome.hold", function(vehicleId)
    local pid = tonumber(source) or 0
    local u = ncmUploads[pid]
    if u and tonumber(vehicleId) == u.vehicleId then u.heartbeat = nowMs() end
end)

RegisterNetEvent("ncm:chrome.cancel", function()
    local pid = tonumber(source) or 0
    -- A platform upload is the attacker's to cancel too: releasing the key ends it, as the reference F8 did.
    for actionId, a in pairs(actions) do
        if a.attacker == pid and Open77.hacking and Open77.hacking.cancel then pcall(Open77.hacking.cancel, actionId) end
    end
    local u = ncmUploads[pid]
    if u then
        ncmUploads[pid] = nil
        present(pid, u.actionId, "cancel", 0, u.hack)
        tell(pid, { token = u.token, result = "interrupted", reason = "cancelled", hack = u.hack })
    end
    channels[pid] = nil
end)

-- ---------------------------------------------------------------------------------------------------------
-- The tick: NCM-route uploads, channels, timers, expiry, scopes
-- ---------------------------------------------------------------------------------------------------------

local lastScope = 0

local function tick()
    local t = nowMs()
    for pid, u in pairs(ncmUploads) do
        local h = Chrome.hack(u.hack)
        local me, there = playerPos(pid), vehiclePos(u.vehicleId)
        local why
        if not there then why = "target_lost"
        elseif not me or dist(me, there) > (h.range or 60) + RANGE_SLACK_M then why = "out_of_range"
        elseif t - u.heartbeat > HEARTBEAT_MS then why = "lock_lost" end
        if why then
            ncmUploads[pid] = nil
            present(pid, u.actionId, "cancel", 0, h.label)
            present(u.defender, u.actionId, "cancel", 0, h.label)
            record({ attacker = pid, target = u.defender, hack = u.hack, outcome = "interrupted", route = "ncm",
                     vehicleId = u.vehicleId, detail = why })
            tell(pid, { token = u.token, result = "interrupted", reason = why, hack = u.hack })
        elseif t >= u.deadline then
            ncmUploads[pid] = nil
            present(pid, u.actionId, "impact", 1, h.label)
            present(u.defender, u.actionId, "impact", 1, h.label)
            applyEffect(u.vehicleId, u.hack, pid)
            record({ attacker = pid, target = u.defender, hack = u.hack, outcome = "impact", route = "ncm", vehicleId = u.vehicleId,
                     catastrophic = h.catastrophic })
            tell(pid, { token = u.token, result = "impact", hack = u.hack })
        else
            local pr = (t - u.startedAt) / (u.deadline - u.startedAt)
            present(pid, u.actionId, "upload", pr, h.label)
            present(u.defender, u.actionId, "incoming", pr, h.label)
        end
    end
    for pid, c in pairs(channels) do
        if ownVehicle(pid) ~= c.vehicleId then
            channels[pid] = nil
            tell(pid, { token = c.token, result = "interrupted", reason = "left_vehicle", hack = c.hack })
        elseif t >= c.deadline then
            channels[pid] = nil
            applyEffect(c.vehicleId, c.hack, pid)
            record({ attacker = pid, hack = c.hack, outcome = "impact", route = "ncm", vehicleId = c.vehicleId })
            tell(pid, { token = c.token, result = "impact", hack = c.hack })
        end
    end
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= t then due[#due + 1] = table.remove(timers, i) end
    end
    for _, tm in ipairs(due) do
        local ok, err = pcall(tm.fn)
        if not ok then log("timer %s failed: %s", tostring(tm.label), tostring(err)) end
    end
    for vid, list in pairs(effects) do
        local keep, expired = {}, false
        for _, e in ipairs(list) do
            if e.endsAt > t then keep[#keep + 1] = e else expired = true end
        end
        if #keep == 0 then effects[vid] = nil else effects[vid] = keep end
        if expired then republish(vid) end
    end
    if t - lastScope >= 5000 then
        lastScope = t
        pcall(reconcileScopes)
    end
end

AddEventHandler("onPlayerReady", function(playerId)
    local pid = tonumber(playerId) or 0
    if pid <= 0 then return end
    CreateThread(function()
        Wait(4000)
        if defined then equip(pid) end
    end)
end)

AddEventHandler("onPlayerDisconnected", function(playerId)
    local pid = tonumber(playerId) or 0
    ncmUploads[pid], channels[pid], cooldowns[pid], deck[pid] = nil, nil, nil, nil
    installQueue[pid], installing[pid], scoped[pid] = nil, nil, nil
    refusalsLogged[pid] = nil
end)

CreateThread(function()
    Wait(2000)
    for attempt = 1, 12 do
        defined = defineAll()
        if defined then break end
        Wait(10000)
    end
    if defined then
        installArbiter()
        for _, raw in ipairs(Open77.players.all() or {}) do equip(tonumber(raw)) end
    end
    while true do
        local ok, err = pcall(tick)
        if not ok then log("tick failed: %s", tostring(err)) end
        Wait(TICK_MS)
    end
end)

-- /ncm.chrome <playerId>  (console) -- what the player has slotted and what is active on vehicles
RegisterCommand("ncm.chrome", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    log("defined=%s scopes=%d", tostring(defined), (function() local n = 0; for _ in pairs(scopes) do n = n + 1 end; return n end)())
    for pid, d in pairs(deck) do log("player=%d deck=%s pending=%s", pid, tostring(d.grade), tostring(d.pending)) end
    for vid, list in pairs(effects) do
        local names = {}
        for _, e in ipairs(list) do names[#names + 1] = e.hack end
        log("vehicle=%s active: %s", tostring(vid), table.concat(names, ", "))
    end
end, false)
