-- ncm_paddock / server / hacking -- NPC racers quickhack, defend and purge (owner brief 2026-10-08:
-- "Quickhacking is racecraft. Make the field capable of racing that way").
--
-- Every NPC entrant of a race gets an agent (core `npc.hacking`): a persistent hacking profile from its Paddock person,
-- and a decision loop. This file is the host:
--   * PHYSICAL cars (the bubble): each bubble tick builds the racer's situation from the street -- the cars and human
--     drivers around it, gaps along the line, closing speeds, rivals, the lights -- and executes its decisions on the
--     REAL chrome machinery in ncm_world (`ncm:chrome:npcStart / npcCancel / npcPurge`): the same uploads, Self-ICE,
--     purge and effects a human's hacks use. A human under attack sees INCOMING and can purge, exactly as a racer can.
--   * MODEL cars (nobody near): the same decisions on the race model, resolved statistically (`Hack.resolveModel`),
--     provenance `simulated` (owner ruling 2026-10-08: "physical + modelled").
--   * RULES: the race's tier decides allowed / restricted / prohibited (`competition.hackrules`). The physics is never
--     gated; an offence officials attribute costs time or a DSQ, recorded as its own fact apart from the incident.
--   * MEMORY: who hacked whom goes into each person's evidence (`evidence.hacks`), so a racer hacked by the same rival
--     race after race grows wary of them, and payback is remembered.
-- The decision trace is the `[ncm_paddock/hack]` log and the console's `ncm.hack.trace`; nothing of it is player UI.
PaddockHack = { byRace = {} }

local Hack = NcmCore.get("npc.hacking")
local Rules = NcmCore.get("competition.hackrules")
local Chrome = NcmCore.get("competition.chrome")
local Tape = NcmCore.get("paddock.tape")
local Hash = NcmCore.get("vocabulary.hash")
local R = NcmCore.get("paddock.racestate")

local function log(fmt, ...) print(("[ncm_paddock/hack] " .. fmt):format(...)) end
local function set(k, d) return PaddockSettings.get(k, d) end
local function nowMs() return math.floor((Open77.time.unix() or 0) * 1000) end
local function d2(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local TRACE_KEEP = 200
local traceRing = {}

local function remember(line)
    traceRing[#traceRing + 1] = line
    if #traceRing > TRACE_KEEP then table.remove(traceRing, 1) end
    log("%s", line)
end

local function person(id) return PaddockStore.world and PaddockStore.world.people[id] or nil end
local function nameOf(id)
    local p = person(id)
    if p and p.first then return (p.first .. " " .. (p.last or "")):gsub("%s+$", "") end
    return tostring(id)
end

--- The race's hacking state, made on first use: its rules and, for the deterministic first test, its two subjects.
local function stateFor(race)
    local H = PaddockHack.byRace[race.raceId]
    if H then return H end
    H = { agents = {}, byVid = {}, incoming = {}, rules = Rules.forTier(race.tier), test = {}, lastModelAt = 0, humans = {} }
    PaddockHack.byRace[race.raceId] = H
    if set("hackTest", "auto") == "auto" and H.rules ~= "prohibited" then
        local ids = (race.frozen and race.frozen.grid) or (race.model and race.model.order) or {}
        local bestO, bestOv, bestD, bestDv
        for _, id in ipairs(ids) do
            local p = person(id)
            if p and not (PaddockHumans and PaddockHumans.isHuman(race, id)) then
                local prof = Hack.profile(p, PaddockStore.world.seed)
                local ov, dv = prof.offense * prof.aptitude, prof.defense
                if not bestOv or ov > bestOv then bestO, bestOv = id, ov end
                if not bestDv or dv > bestDv then bestD, bestDv = id, dv end
            end
        end
        if bestO == bestD then bestD = nil end
        H.test = { offense = bestO, defense = bestD }
        log("%s: test subjects -- offence %s, defence %s (rules %s)", race.raceId, tostring(bestO), tostring(bestD), H.rules)
    end
    return H
end

local function agentFor(race, H, id)
    local ag = H.agents[id]
    if ag then return ag end
    local p = person(id)
    if not p then return nil end
    local prof = Hack.profile(p, PaddockStore.world.seed)
    if H.test.offense == id then
        prof.aptitude, prof.offense, prof.timing, prof.targetQuality = 0.92, 0.95, 0.9, 0.85
        prof.maxSeverity, prof.sabotage, prof.patience, prof.conservation = 5, 0.95, 0.2, 0.15
        prof.regulatoryAwareness = 0.3
    elseif H.test.defense == id then
        prof.defense, prof.hasIce, prof.canPurge, prof.perceptionMs = 0.95, true, true, 500
    end
    ag = Hack.newAgent(id, prof, { seed = race.raceId, startMs = nowMs() })
    H.agents[id] = ag
    log("%s: %s hacking profile apt %.2f off %.2f def %.2f maxSev %d timing %.2f ice %s%s", race.raceId, id, prof.aptitude, prof.offense,
        prof.defense, prof.maxSeverity, prof.timing, tostring(prof.hasIce),
        H.test.offense == id and " [TEST OFFENCE]" or (H.test.defense == id and " [TEST DEFENCE]" or ""))
    return ag
end

local function raceOfVid(vid)
    for raceId, H in pairs(PaddockHack.byRace) do
        local id = H.byVid[tonumber(vid) or -1]
        if id then return raceId, H, id end
    end
end

local function raceOfAgent(personId)
    for raceId, H in pairs(PaddockHack.byRace) do if H.agents[personId] then return raceId, H end end
end

-- --------------------------------------------------------------------------------------- bubble car lifecycle
function PaddockHack.carSpawned(race, id, vid)
    if not set("hackEnabled", true) then return end
    local H = stateFor(race)
    local ag = agentFor(race, H, id)
    H.byVid[tonumber(vid)] = id
    TriggerEvent("ncm:chrome:raceCar", vid, { personId = id, ice = ag and ag.prof.hasIce or false })
end

function PaddockHack.carRemoved(race, id, vid)
    local H = race and PaddockHack.byRace[race.raceId]
    if H then
        H.byVid[tonumber(vid) or -1] = nil
        local ag = H.agents[id]
        if ag and ag.upload then TriggerEvent("ncm:chrome:npcCancel", id); Hack.outcome(ag, "interrupted", nowMs()) end
        H.incoming[id] = nil
    end
    TriggerEvent("ncm:chrome:raceCar", vid, nil)
end

-- --------------------------------------------------------------------------------------- the physical decision tick
local function phaseOf(race, d, now)
    if race.opensAt and now < race.opensAt * 1000 then return "grid" end
    local len = race.model and race.model.lengthM
    if len and d and d > 0.85 * len then return "final" end
    return "racing"
end

local function execute(race, H, id, car, actions)
    local p = person(id)
    for _, a in ipairs(actions) do
        if a.op == "start" then
            TriggerEvent("ncm:chrome:npcStart", { personId = id, vid = car.vid, hack = a.hack, targetVid = a.targetVid })
            if p then p.evidence = p.evidence or {}; Hack.remember(p.evidence, "used"); PaddockStore.markPerson(id) end
            remember(("%s: %s UPLOAD %s -> %s | %s"):format(race.raceId, id, a.hack, tostring(a.target), a.why))
        elseif a.op == "cancel" then
            TriggerEvent("ncm:chrome:npcCancel", id)
            remember(("%s: %s ABORT | %s"):format(race.raceId, id, a.why))
        elseif a.op == "purge" then
            TriggerEvent("ncm:chrome:npcPurge", id, car.vid)
            remember(("%s: %s PURGE | %s"):format(race.raceId, id, a.why))
        elseif a.op == "trace" then
            local ag = H.agents[id]
            if ag and ag.lastTraced ~= a.why then
                ag.lastTraced = a.why
                remember(("%s: %s %s | %s"):format(race.raceId, id, a.kind, a.why))
            end
        end
    end
end

--- Called from the bubble tick for a race with physical cars (`b.cars`), pre-grid or running.
function PaddockHack.step(race, b, players)
    if not set("hackEnabled", true) or not b or not next(b.cars) then return end
    local H = stateFor(race)
    local now = nowMs()
    local model = race.model
    local tMs = race.modelGoAt and (now - race.modelGoAt * 1000) or 0
    local places = {}
    if model and race.state == "running" then
        local okS, rows = pcall(R.standings, model, tMs)
        if okS and type(rows) == "table" then for i, r in ipairs(rows) do places[r.id] = r.pos or i end end
    end
    -- human drivers near the field: the same targets an NPC sees (no privileged ontology either way)
    local humans = {}
    for ppid, pp in pairs(players or {}) do
        local pid = tonumber(ppid)
        local okS, seat = pcall(Open77.players.getVehicleSeat, pid)
        local vid = okS and type(seat) == "table" and tonumber(seat.vehicleId or seat.vehicle or seat.id) or tonumber(seat)
        if vid and not H.byVid[vid] then
            local hd = model and R.project(model, pp, -1e9, 1e9) or nil
            local prev = H.humans[pid]
            local speed = (prev and prev.d and hd and now > prev.t) and math.abs(hd - prev.d) / ((now - prev.t) / 1000) or 0
            H.humans[pid] = { d = hd, t = now }
            humans[#humans + 1] = { id = "player:" .. pid, vid = vid, human = true, bound = true, pos = pp, d = hd, speed = speed }
        end
    end
    for id, car in pairs(b.cars) do
        if car.pos and car.seated ~= false then
            local ag = agentFor(race, H, id)
            if ag then
                if not H.byVid[car.vid] then H.byVid[car.vid] = id; TriggerEvent("ncm:chrome:raceCar", car.vid, { personId = id, ice = ag.prof.hasIce }) end
                local me = person(id)
                local rivals = me and me.evidence and me.evidence.rivals or {}
                local others = {}
                for oid, oc in pairs(b.cars) do
                    if oid ~= id and oc.pos then
                        local gap = (oc.lastD or 0) - (car.lastD or 0)
                        local closing = gap >= 0 and ((car.lastSpeed or 0) - (oc.lastSpeed or 0)) or ((oc.lastSpeed or 0) - (car.lastSpeed or 0))
                        others[#others + 1] = { id = oid, vid = oc.vid, human = false, dist = d2(car.pos, oc.pos), gapM = gap,
                            closingMps = closing, pos = places[oid], rival = rivals[oid],
                            damaged = race.carDamage and race.carDamage[oid] and (race.carDamage[oid].frac or 0) > 0.3 }
                    end
                end
                for _, h in ipairs(humans) do
                    local gap = (h.d and car.lastD) and (h.d - car.lastD) or 0
                    local closing = gap >= 0 and ((car.lastSpeed or 0) - h.speed) or (h.speed - (car.lastSpeed or 0))
                    others[#others + 1] = { id = h.id, vid = h.vid, human = true, bound = h.bound, dist = d2(car.pos, h.pos),
                        gapM = gap, closingMps = closing }
                end
                local inc = {}
                for _, x in pairs(H.incoming[id] or {}) do inc[#inc + 1] = x end
                local sit = { nowMs = now, phase = phaseOf(race, car.lastD, now), greenAtMs = race.opensAt and race.opensAt * 1000,
                    rules = H.rules, physical = true, self = { vid = car.vid, speed = car.lastSpeed }, others = others, incoming = inc }
                local okA, actions = pcall(Hack.step, ag, sit)
                if okA then execute(race, H, id, car, actions) else log("%s: %s step failed: %s", race.raceId, id, tostring(actions)) end
            end
        end
    end
end

-- --------------------------------------------------------------------------------------- the model (nobody near)
--- Off-bubble exchanges: model cars near each other on the line run the same decisions; an upload resolves after its
--- upload time if the two are still within range on the model. Outcomes are `simulated`.
function PaddockHack.modelStep(race, b)
    if not (set("hackEnabled", true) and set("hackModelEnabled", true)) or not race.model or race.state ~= "running" then return end
    local H = stateFor(race)
    local now = nowMs()
    local tMs = now - (race.modelGoAt or race.opensAt) * 1000
    H.pending = H.pending or {}
    -- resolve uploads that have run their time
    for i = #H.pending, 1, -1 do
        local u = H.pending[i]
        if now >= u.at then
            table.remove(H.pending, i)
            local a, t = R.carAt(race.model, u.attacker, tMs), R.carAt(race.model, u.target, tMs)
            local h = Chrome.hack(u.hack)
            local agA, agT = H.agents[u.attacker], agentFor(race, H, u.target)
            local res
            if not (a and t and a.state == "racing" and t.state == "racing") or math.abs(a.d - t.d) > h.range then
                res = { landed = false, reason = "out of range on the model" }
            else
                res = Hack.resolveModel(agA.prof, agT.prof, u.hack, Hash.stream("model-hack", race.raceId, u.attacker, u.target, u.at))
            end
            if agA then Hack.outcome(agA, res.landed and "impact" or (res.purged and "purged" or (res.iced and "blocked" or "interrupted")), now) end
            if res.landed then
                if agT then Hack.hit(agT, u.attacker, u.hack) end
                if res.dnf then
                    R.anchor(race.model, u.target, tMs, t.d, true)
                    race.carDamage = race.carDamage or {}
                    race.carDamage[u.target] = { frac = 1, wrecked = true }
                elseif res.timeLossS then
                    R.penalize(race.model, u.target, math.floor(res.timeLossS * 1000 + 0.5))
                end
                PaddockHack.learn(u.attacker, u.target, true)
            end
            remember(("%s: MODEL %s %s -> %s: %s%s (simulated)"):format(race.raceId, u.attacker, u.hack, u.target,
                res.landed and "LANDED" or "failed", res.dnf and " -- car destroyed, DNF" or (res.timeLossS and (" -- %.1f s lost"):format(res.timeLossS) or (" -- " .. tostring(res.reason)))))
            if res.landed then PaddockHack.regulate(race, H, u.attacker, u.hack, "simulated") end
        end
    end
    if now - H.lastModelAt < set("hackModelEverySec", 5) * 1000 then return end
    H.lastModelAt = now
    local cars = {}
    for _, id in ipairs(race.model.order) do
        if not (b and b.cars[id]) and not (PaddockHumans and PaddockHumans.isHuman(race, id)) then
            local p = R.carAt(race.model, id, tMs)
            if p and p.state == "racing" then cars[#cars + 1] = { id = id, d = p.d, speed = p.speed or 0 } end
        end
    end
    for _, c in ipairs(cars) do
        local ag = agentFor(race, H, c.id)
        if ag and not ag.upload then
            local others = {}
            for _, o in ipairs(cars) do
                if o.id ~= c.id and math.abs(o.d - c.d) <= 80 then
                    local gap = o.d - c.d
                    others[#others + 1] = { id = o.id, human = false, dist = math.abs(gap), gapM = gap,
                        closingMps = gap >= 0 and (c.speed - o.speed) or (o.speed - c.speed) }
                end
            end
            if #others > 0 then
                local sit = { nowMs = now, phase = phaseOf(race, c.d, now), rules = H.rules, physical = false, others = others, incoming = {} }
                local okA, actions = pcall(Hack.step, ag, sit)
                if okA then
                    for _, a in ipairs(actions) do
                        if a.op == "start" then
                            H.pending[#H.pending + 1] = { attacker = c.id, target = a.target, hack = a.hack, at = now + Chrome.hack(a.hack).uploadMs }
                            remember(("%s: MODEL %s UPLOAD %s -> %s | %s"):format(race.raceId, c.id, a.hack, tostring(a.target), a.why))
                        end
                    end
                end
            end
        end
    end
end

-- --------------------------------------------------------------------------------------- memory and rules
--- Persistent memory of a landed hack: the attacker's skill, the victim's wariness of that attacker.
function PaddockHack.learn(attackerId, targetId, landed)
    if not landed then return end
    local a, t = person(attackerId), person(targetId)
    if a then a.evidence = a.evidence or {}; Hack.remember(a.evidence, "landed"); PaddockStore.markPerson(attackerId) end
    if t then t.evidence = t.evidence or {}; Hack.remember(t.evidence, "received", attackerId); PaddockStore.markPerson(targetId) end
end

--- Officials: an offence under this race's rules may be ATTRIBUTED; if it is, the sporting penalty applies and the
--- attribution becomes its own public fact. An unattributed hack stays only in the truth ledger (chrome_event).
function PaddockHack.regulate(race, H, attackerId, hackId, provenance)
    if not Rules.offence(H.rules, hackId) then return end
    local ag = H.agents[attackerId]
    local stealth = ag and ag.prof.stealth or 0
    local rng = Hash.stream("officials", race.raceId, attackerId, hackId, nowMs())
    if not Rules.attribute(H.rules, hackId, rng, stealth) then
        remember(("%s: OFFICIALS did not attribute %s by %s (rules %s)"):format(race.raceId, hackId, tostring(attackerId), H.rules))
        return
    end
    local pen = Rules.penalty(H.rules, hackId)
    local modelId = attackerId
    if type(attackerId) == "string" and attackerId:find("^player:") and PaddockHumans and PaddockHumans.entrantFor then
        modelId = PaddockHumans.entrantFor(race, tonumber(attackerId:sub(8)))
    end
    if race.model and modelId and race.model.cars[modelId] then
        if pen.kind == "time" then R.penalize(race.model, modelId, pen.seconds * 1000)
        elseif pen.kind == "dsq" then
            -- no DSQ status in a Paddock result: classified last by a penalty the length of the race (expression loss)
            R.penalize(race.model, modelId, 3600 * 1000)
        end
    end
    remember(("%s: OFFICIALS attributed %s to %s -> %s%s"):format(race.raceId, hackId, tostring(attackerId), pen.kind,
        pen.seconds and (" " .. pen.seconds .. " s") or ""))
    pcall(function()
        PaddockStory.record({ Tape.event("chrome_attack", race.raceId .. ":" .. tostring(attackerId) .. ":" .. hackId .. ":" .. nowMs(),
            math.floor(nowMs() / 1000), { entities = { { "person", tostring(attackerId) } },
            facts = { hack = hackId, penalty = pen.kind, rules = H.rules, raceId = race.raceId },
            publicSummary = ("Officials attribute a %s quickhack to %s."):format(Chrome.hack(hackId).label, nameOf(attackerId)),
            provenance = provenance or "physical" }) })
    end)
end

--- A race car destroyed in a race (the bubble saw it): the physical incident, with its cause if a hack had just landed.
function PaddockHack.destroyed(race, id, vid, pos)
    local H = PaddockHack.byRace[race.raceId]
    local cause = H and H.recent and H.recent[tonumber(vid) or -1]
    if cause and nowMs() - cause.at > 10000 then cause = nil end
    TriggerEvent("ncm:week:fact", "vehicle_destroyed", 1)
    local ev = Tape.event("vehicle_destroyed", race.raceId .. ":" .. tostring(id), math.floor(nowMs() / 1000), {
        entities = { { "person", tostring(id) } },
        facts = { raceId = race.raceId, x = pos and pos.x, y = pos and pos.y, z = pos and pos.z },
        publicSummary = ("%s's car is destroyed during the race."):format(nameOf(id)), provenance = "physical" })
    pcall(PaddockStory.record, { ev })
    remember(("%s: DESTROYED %s (vehicle %s)%s"):format(race.raceId, tostring(id), tostring(vid),
        cause and (" -- %s from %s landed %.1f s before (attribution: chrome_event)"):format(cause.hack, cause.attacker, (nowMs() - cause.at) / 1000) or ""))
end

-- --------------------------------------------------------------------------------------- events from ncm_world chrome
AddEventHandler("ncm:chrome:incoming", function(ev)
    if type(ev) ~= "table" then return end
    local raceId, H, id = raceOfVid(ev.targetVid)
    if not H then return end
    H.incoming[id] = H.incoming[id] or {}
    H.incoming[id][ev.key] = { key = ev.key, attacker = ev.attacker, hack = ev.hack, startedMs = ev.startedMs, uploadMs = ev.uploadMs }
    remember(("%s: %s INCOMING %s from %s (%.1f s upload)"):format(raceId, id, tostring(ev.hack), tostring(ev.attacker), (ev.uploadMs or 0) / 1000))
end)

AddEventHandler("ncm:chrome:resolved", function(ev)
    if type(ev) ~= "table" then return end
    local now = nowMs()
    local attackerId = type(ev.key) == "string" and ev.key:match("^npc:(.+)$") or ev.key
    -- the attacker's side
    if type(ev.key) == "string" and ev.key:find("^npc:") then
        local raceId, H = raceOfAgent(attackerId)
        if H then
            Hack.outcome(H.agents[attackerId], ev.outcome, now)
            remember(("%s: %s upload %s ended: %s%s"):format(raceId, attackerId, tostring(ev.hack), tostring(ev.outcome), ev.detail and (" (" .. ev.detail .. ")") or ""))
        end
    end
    -- the target's side
    local raceId, H, id = raceOfVid(ev.targetVid)
    if not H then return end
    if H.incoming[id] then H.incoming[id][ev.key] = nil end
    if ev.outcome == "impact" and Chrome.harms(ev.hack) then
        local ag = H.agents[id]
        if ag then Hack.hit(ag, attackerId, ev.hack) end
        PaddockHack.learn(attackerId, id, true)
        H.recent = H.recent or {}
        H.recent[tonumber(ev.targetVid)] = { attacker = attackerId, hack = ev.hack, at = now }
        local race = PaddockRaces.byId[raceId]
        if race then PaddockHack.regulate(race, H, attackerId, ev.hack, "physical") end
    end
end)

--- A race that is no longer live leaves nothing behind (called from the bubble tick).
function PaddockHack.prune()
    for raceId in pairs(PaddockHack.byRace) do
        local race = PaddockRaces.byId[raceId]
        if not race or (race.state ~= "running" and race.state ~= "scheduled" and race.state ~= "priced") then
            PaddockHack.byRace[raceId] = nil
        end
    end
end

-- ncm.hack.trace [n]  (console only) -- why the field's racers hacked, held off, defended or did not
RegisterCommand("ncm.hack.trace", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local n = math.min(#traceRing, tonumber(args and args[1]) or 40)
    for i = #traceRing - n + 1, #traceRing do print("[ncm_paddock/hack trace] " .. traceRing[i]) end
    for raceId, H in pairs(PaddockHack.byRace) do
        for id, ag in pairs(H.agents) do
            if ag.state ~= "idle" or ag.lastWhy then
                print(("[ncm_paddock/hack trace] %s %s state=%s last=%s"):format(raceId, id, ag.state, tostring(ag.lastWhy)))
            end
        end
    end
end, false)
