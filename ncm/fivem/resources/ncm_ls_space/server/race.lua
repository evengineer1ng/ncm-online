-- ncm_ls_space / server / race: the authority for Snowglobe races (L321; doc 54 §G).
--
-- The server generates the same Snowglobe as every client from `universeSeed` (`space.genesis`), runs each race's NPC
-- field through `space.racesim` (the machine's physics as the car term, `paddock.sim` for the race, keyed by
-- (seed, venue, race number) so it replays), and classifies a finished player beside the NPCs with PROVENANCE: the
-- player's time is `physical`, the NPCs' `simulated`. Machines that physically cannot fly the venue are refused with
-- their reason, logged. Results are logged, not yet persisted (doc 54 §J).
local Core = NcmCore
local U = Core.get("space.universe")
local Seed = Core.get("world.seed")
local Gen = Core.get("space.genesis")
local Race = Core.get("space.racesim")
local Sport = Core.get("space.sport")
local Mach = Core.get("engineering.machine")
local Hash = Core.get("vocabulary.hash")
local C = NcmLsConfig
U.setWorld({ earthRadius = C.earthRadius, surfaceG = C.surfaceG })

local function log(fmt, ...) print(("[ncm_ls_space/race] " .. fmt):format(...)) end

local world = Gen.generate(Seed.root(C.universeSeed):child("snowglobe"))
local models, names, orgName = {}, {}, {}
for _, o in ipairs(world.orgs) do orgName[o.id] = o.short end
for i, m in ipairs(world.machines) do
    models[i] = Mach.assemble(m)
    names[world.pilots[i].id] = world.pilots[i].name .. " (" .. (orgName[m.orgId] or "?") .. ")"
end

CreateThread(function()
    Wait(1500)
    log("Snowglobe from seed %s: %d station(s), %d venue(s), %d organisations, %d designs in its technology history",
        C.universeSeed, #world.stations, #world.venues, #world.orgs, #world.lineage.order)
    local machines = {}
    for i, m in ipairs(world.machines) do
        local fl = world.fleet[i] or {}
        machines[i] = { id = world.pilots[i].id, model = models[i], models = {
            sprint = fl.sprint and Mach.assemble(fl.sprint), fireball = fl.fireball and Mach.assemble(fl.fireball) } }
    end
    for i, e in ipairs(Sport.formEvents(world.venues, machines)) do
        log("  venue %d %s (%s): %s, %d machine(s) can fly it%s", i, e.name, e.kind, e.status, #e.eligible,
            e.envelope and (" -- class envelope %s %.2f..%.2f"):format(e.envelope.metric, e.envelope.min, e.envelope.max) or "")
    end
    for _, s in ipairs(world.stations) do
        local _, _, period = Gen.orbitAt(s.orbit, 0)
        log("  station %s: altitude %.0f m over the %s plane, period %.0f s", s.name, s.altitudeM, s.orbit.anchor, period)
    end
end)

local raceNo, races = 0, {}

RegisterNetEvent("ncm:ls:race:enter", function(n)
    local src = source
    local v = world.venues[tonumber(n) or 0]
    if not v then return end
    raceNo = raceNo + 1
    local rng = Hash.stream(C.universeSeed, "race", v.id, raceNo)
    -- the grid: a seeded shuffle of every organisation's pilot and machine
    local order = {}
    for i = 1, #world.machines do order[i] = i end
    for i = #order, 2, -1 do local j = rng:int(1, i); order[i], order[j] = order[j], order[i] end
    local entrants = {}
    for _, i in ipairs(order) do
        entrants[#entrants + 1] = { id = world.pilots[i].id, orgId = world.machines[i].orgId, pilot = world.pilots[i], machine = models[i] }
    end
    local out = Race.race(v, entrants, rng)
    local field = {}
    if out.sim then
        for _, e in ipairs(out.sim.entrants) do
            field[#field + 1] = { id = e.id, orgId = e.orgId, grid = e.grid, state = e.state, splits = e.splits, dnfSegment = e.dnfSegment }
        end
    end
    races[src] = { raceNo = raceNo, venue = v, out = out }
    log("race %d for player %d at %s: %d NPC(s) start (simulated), %d refused", raceNo, src, v.name, #field, #out.refused)
    for _, r in ipairs(out.refused) do log("  refused %s: %s", names[r.id] or r.id, r.reason) end
    TriggerClientEvent("ncm:ls:race:field", src, { venue = tonumber(n), raceNo = raceNo, entrants = field,
        segments = out.segments or 1, names = names, refused = #out.refused })
end)

RegisterNetEvent("ncm:ls:race:finish", function(no, ms)
    local src = source
    local r = races[src]
    if not r or r.raceNo ~= no then log("finish from player %d for unknown race %s", src, tostring(no)); return end
    races[src] = nil
    local rows = Race.result(r.out)
    for _, row in ipairs(rows) do row.name = names[row.id] end
    rows[#rows + 1] = { id = "player:" .. src, name = GetPlayerName(src), state = "finished", finishMs = math.floor(tonumber(ms) or 0), mode = "physical" }
    table.sort(rows, function(a, b)
        if (a.state == "finished") ~= (b.state == "finished") then return a.state == "finished" end
        return (a.finishMs or math.huge) < (b.finishMs or math.huge)
    end)
    local out = {}
    for i, row in ipairs(rows) do
        out[i] = { position = i, id = row.id, name = row.name, state = row.state, finishMs = row.finishMs, dnfReason = row.dnfReason, mode = row.mode }
        log("  race %d P%d %-28s %-10s %s", no, i, tostring(row.name), row.state == "finished" and ("%.3f"):format((row.finishMs or 0) / 1000) or tostring(row.dnfReason), row.mode)
    end
    TriggerClientEvent("ncm:ls:race:result", src, out)
end)
