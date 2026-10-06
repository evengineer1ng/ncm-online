-- ncm_dev_probe / server -- Racing Week experiments (docs/research/open77/RACING_WEEK_SITE_POPULATION.md §5).
-- Every action logs ids and timings: the log is the result.
--
--   ncm.probe.crowd <site> <n> [seed]   E1/E5  n crowd NPCs on the site's harvested vanilla AISpots, in workspots
--   ncm.probe.clip <i> <clip>           E2     a raw vanilla clip through the workspot escape hatch on probe NPC i
--   ncm.probe.pop [crowd]               E3     read bucket 0's population policy; optionally set crowd, then restore
--   ncm.probe.dress <site>              E4     banner props on three sockets + a firework
--   ncm.probe.state                            what the probe holds (NPC ids, owners, tasks)
--   ncm.probe.clear                            remove everything the probe made
-- Sites: corpo | parque | kabuki (or a full node id from probe_data.lua).
local function log(fmt, ...) print(("[ncm_dev_probe] " .. fmt):format(...)) end
local function mono() return Open77.time.monotonic() * 1000 end   -- ms; the server sandbox has no `os`

local ALIAS = { corpo = "corpo_plaza_-1103_-19", parque = "parque_del_mar_-2326_-1125", kabuki = "kabuki_bridge_-1106_1853" }
local PROFILES = { "clap", "dance", "drink", "phone", "smoke", "handsup", "think", "stretch" }
-- Vanilla banner meshes from the platform's props catalogue (open77_data props "banner"), status
-- `discoverable_not_individually_validated`: E4 is what validates them.
local BANNERS = {
    "base\\environment\\decoration\\advertising\\signage\\6th_street\\th_street_a_banner_a.mesh",
    "base\\environment\\decoration\\advertising\\posters\\banner_lizzies\\banner_lizzies_b.mesh",
    "base\\environment\\decoration\\advertising\\signage\\combat_zone\\terra_cognita_banner_vertical_a.mesh",
}
local FIREWORK = "base\\fx\\quest\\q112\\q112_firework_01.effect"

local npcs, props = {}, {}        -- probe-owned ids, in creation order
local popBefore

local function site(key)
    local id = ALIAS[key or ""] or key
    return id and ProbeData.SITES[id], id
end

-- A small deterministic stream so a probe run is repeatable from its seed (the generator will use world hashes).
local function rng(seed)
    local s = (tonumber(seed) or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function(n) s = (s * 16807) % 2147483647; return (s % n) + 1 end
end

-- Spread the chosen sockets: nearest first, never two within 1.2 m.
local function pickSockets(s, n)
    local out = {}
    for _, k in ipairs(s.sockets) do
        local clear = true
        for _, o in ipairs(out) do
            if (o.x - k.x) ^ 2 + (o.y - k.y) ^ 2 < 1.44 then clear = false; break end
        end
        if clear then out[#out + 1] = k end
        if #out >= n then break end
    end
    return out
end

local function spawnCrowd(siteKey, n, seed)
    local s, id = site(siteKey)
    if not s then log("unknown site %s (corpo | parque | kabuki)", tostring(siteKey)); return end
    n = math.max(1, math.min(60, tonumber(n) or 10))
    local r = rng(seed or 77)
    local chosen = pickSockets(s, n)
    log("E1 crowd: site=%s (%s) want=%d sockets=%d of %d pool=%d seed=%s", s.name, id, n, #chosen, #s.sockets, #ProbeData.CROWD, tostring(seed or 77))
    local t0 = mono()
    for i, k in ipairs(chosen) do
        local record = ProbeData.CROWD[r(#ProbeData.CROWD)]
        local profile = PROFILES[(i - 1) % #PROFILES + 1]
        local ok, npc, reason = pcall(Open77.npcs.create, {
            record = record, position = { x = k.x, y = k.y, z = k.z + 0.05 }, yaw = k.yaw,
            aiMode = Open77.npcs.ai and Open77.npcs.ai.tasks or 0,
            damagePolicy = Open77.npcs.damage and Open77.npcs.damage.invulnerable or 2,
            behavior = { combatEnabled = false, voiceEnabled = false },
            despawnWhenUnobserved = false, persistent = false,
        })
        if not ok or not npc then
            log("  #%d %s at %.1f,%.1f,%.1f (%s) REFUSED: %s", i, record, k.x, k.y, k.z, k.kind, tostring(ok and reason or npc))
        else
            local entry = { id = npc, record = record, profile = profile, socket = k, at = mono() }
            npcs[#npcs + 1] = entry
            log("  #%d npc=%s %s at %.1f,%.1f,%.1f yaw=%.0f socket=%s -> %s", #npcs, tostring(npc), record, k.x, k.y, k.z, k.yaw, k.kind, profile)
            CreateThread(function()
                local okP, pending = pcall(Open77.npcs.whenReady, npc, 20000)
                local ready, err
                if okP and pending then ready, err = pending:await() end
                entry.readyMs = math.floor(mono() - entry.at)
                if not ready then log("  npc=%s NOT READY after %d ms: %s", tostring(npc), entry.readyMs, tostring(err)); return end
                local okO, owner = pcall(Open77.npcs.owner, npc)
                local okW, task, why = pcall(Open77.npcs.tasks.workspot, npc, profile, { loop = true })
                entry.task = okW and task or nil
                log("  npc=%s ready in %d ms owner=%s workspot=%s -> %s", tostring(npc), entry.readyMs,
                    okO and (type(owner) == "table" and tostring(owner.playerId or owner.id or "?") or tostring(owner)) or "?",
                    profile, okW and task and ("task " .. tostring(task)) or ("REFUSED " .. tostring(okW and why or task)))
            end)
        end
        if i % 5 == 0 then Wait(0) end
    end
    log("E1 crowd: %d created in %.0f ms (readiness follows per NPC)", #chosen, mono() - t0)
end

RegisterCommand("ncm.probe.crowd", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    CreateThread(function() spawnCrowd(args and args[1], args and args[2], args and args[3]) end)
end, false)

RegisterCommand("ncm.probe.clip", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local e = npcs[tonumber(args and args[1]) or 0]
    local clip = args and args[2]
    if not e or not clip then log("usage: ncm.probe.clip <i> <clip>  (i from ncm.probe.state)"); return end
    pcall(Open77.npcs.tasks.clear, e.id)
    local ok, task, why = pcall(Open77.npcs.tasks.workspot, e.id, clip, { loop = true })
    log("E2 raw clip on npc=%s: %s -> %s", tostring(e.id), clip, ok and task and ("task " .. tostring(task)) or ("REFUSED " .. tostring(ok and why or task)))
    if ok and task then
        CreateThread(function()
            Wait(3000)
            local okG, st = pcall(Open77.npcs.tasks.get, e.id, task)
            log("E2 after 3 s: %s", okG and type(st) == "table" and (tostring(st.state or st.status) .. " " .. tostring(st.reason or "")) or tostring(st))
        end)
    end
end, false)

local function fmtPop(p)
    if type(p) ~= "table" then return tostring(p) end
    local parts = {}
    for k, v in pairs(p) do parts[#parts + 1] = k .. "=" .. tostring(v) end
    table.sort(parts)
    return table.concat(parts, " ")
end

RegisterCommand("ncm.probe.pop", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local ok, p, why = pcall(Open77.world.getPopulation, 0)
    log("E3 getPopulation(0): %s", ok and p and fmtPop(p) or ("REFUSED " .. tostring(ok and why or p)))
    local crowd = tonumber(args and args[1])
    if not crowd then return end
    popBefore = popBefore or (ok and p) or nil
    local okS, res, whyS = pcall(Open77.world.setPopulation, 0, { crowd = crowd })
    log("E3 setPopulation(0, crowd=%.2f): %s", crowd, okS and res and "ok" or ("REFUSED " .. tostring(okS and whyS or res)))
    log("E3 restore later with ncm.probe.clear (restores %s)", popBefore and fmtPop(popBefore) or "nothing read")
end, false)

RegisterCommand("ncm.probe.dress", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local s = site(args and args[1])
    if not s then log("usage: ncm.probe.dress <corpo|parque|kabuki>"); return end
    -- the three stand-type sockets furthest out, so dressing and crowd do not collide
    local list = {}
    for _, k in ipairs(s.sockets) do if k.kind == "stand" or k.kind == "wall_lean" or k.kind == "rail_lean" then list[#list + 1] = k end end
    for i = 1, math.min(3, #list) do
        local k = list[#list - i + 1]
        local ok, id, why = pcall(Open77.props.create, { model = BANNERS[i], position = { x = k.x, y = k.y, z = k.z + 2.5 }, yaw = k.yaw,
            physics = "static", ttlMs = 30 * 60 * 1000 })
        if ok and id then props[#props + 1] = id end
        log("E4 banner %d %s at %.1f,%.1f,%.1f: %s", i, BANNERS[i]:match("[^\\]+$"), k.x, k.y, k.z + 2.5,
            ok and id and ("prop " .. tostring(id)) or ("REFUSED " .. tostring(ok and why or id)))
    end
    local okF, res, whyF = pcall(Open77.effects.play, FIREWORK, { position = { x = s.x, y = s.y, z = s.z + 25 }, range = 400 })
    log("E4 firework %s over %s: %s", FIREWORK:match("[^\\]+$"), s.name, okF and res and "played" or ("REFUSED " .. tostring(okF and whyF or res)))
end, false)

RegisterCommand("ncm.probe.state", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    log("state: %d npc(s), %d prop(s)", #npcs, #props)
    for i, e in ipairs(npcs) do
        local okT, tasks = pcall(Open77.npcs.tasks.all, e.id)
        log("  %d npc=%s %s %s ready=%s task=%s tasks=%s", i, tostring(e.id), e.record, e.profile, tostring(e.readyMs),
            tostring(e.task), okT and type(tasks) == "table" and tostring(#tasks) or "?")
    end
end, false)

local function clear()
    local n, m = 0, 0
    for _, e in ipairs(npcs) do if pcall(Open77.npcs.remove, e.id) then n = n + 1 end end
    for _, id in ipairs(props) do if pcall(Open77.props.remove, id) then m = m + 1 end end
    npcs, props = {}, {}
    if popBefore then
        local ok, res, why = pcall(Open77.world.setPopulation, 0, popBefore)
        log("population restored to %s: %s", fmtPop(popBefore), ok and res and "ok" or ("REFUSED " .. tostring(ok and why or res)))
        popBefore = nil
    end
    log("cleared %d npc(s), %d prop(s)", n, m)
end

RegisterCommand("ncm.probe.clear", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    clear()
end, false)

AddEventHandler("onResourceStop", function(name)
    if name == GetCurrentResourceName() then clear() end
end)

local count = 0
for _ in pairs(ProbeData.SITES) do count = count + 1 end
log("ready: %d site(s), crowd pool %d; commands ncm.probe.crowd|clip|pop|dress|state|clear", count, #ProbeData.CROWD)
