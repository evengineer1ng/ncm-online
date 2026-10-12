-- ncm_workshop's server (L361) against deterministic doubles: tear parts down until the method is known, fabricate a
-- prototype, promote it to your own design, make a run and list a unit -- and every refusal on the way (the bench cap,
-- knowledge, money, idempotent retries, nonfunctional results that persist).
local root = arg[1] or "."
local passed = 0
local realPrint = print
local logs = {}
local function check(label, value)
    if not value then
        realPrint("  FAIL " .. label)
        for _, l in ipairs(logs) do realPrint("    log| " .. l) end
        error(label, 0)
    end
    passed = passed + 1; realPrint("  PASS " .. label)
end

-- ---------------------------------------------------------------- platform doubles
math.randomseed(361)
local events, results, states, sheets = {}, {}, {}, {}
function AddEventHandler(name, fn) events[name] = events[name] or {}; table.insert(events[name], fn) end
function RegisterNetEvent(name, fn) AddEventHandler(name, fn) end
function RegisterCommand() end
function TriggerEvent(name, ...) for _, fn in ipairs(events[name] or {}) do fn(...) end end
function TriggerClientEvent(name, pid, body)
    if name == "ncm:workshop.result" then results[#results + 1] = body end
    if name == "ncm:workshop.state" then states[pid] = body end
    if name == "ncm:workshop.sheet" then sheets[#sheets + 1] = body end
end
function CreateThread(fn) fn() end
function Wait() end
function GetPlayerIdentifier(pid) return "user:" .. tostring(pid) end
function GetPlayerName(pid) return ({ "Ana", "Ben" })[pid] or "X" end
function print(s) logs[#logs + 1] = tostring(s) end
GlobalState = { ncmIdentity = { serverId = "test" } }
local clock = 1790000000
Open77 = {
    time = { unix = function() return clock end },
    tunables = { declare = function() return {} end },
    notifications = { send = function() return true end },
}
local function fire(name, pid, ...) source = pid; for _, fn in ipairs(events[name] or {}) do fn(...) end end
NcmWorkshop = { stopClock = true }

-- ---------------------------------------------------------------- database double
local Json
local drivers = { ["user:1"] = "D-ANA", ["user:2"] = "D-BEN" }
local ledger, designs, assets, knowledge, comp, projects = {}, {}, {}, {}, {}, {}
local transfers, runs, inventory, supply, cstate = {}, {}, {}, {}, {}
local function lc(v) return v and tostring(v):lower() or nil end
local function balance(d) local s = 0 for _, l in ipairs(ledger) do if l.driver == lc(d) then s = s + l.amount end end return s end
local function hasIdem(idem, d, amount)
    for _, l in ipairs(ledger) do if l.idem == idem and (d == nil or l.driver == lc(d)) and (amount == nil or l.amount == amount) then return true end end
    return false
end
local function asset(id, design, driver, extra)
    local a = { asset_id = id, design_id = design, ncm_driver_id = driver, location_kind = "storage", lifecycle = "active",
        manufacturer_key = "zetatech", acquired_via = "purchase", created_at = clock, design_ordinal = 1 }
    for k, v in pairs(extra or {}) do a[k] = v end
    assets[id] = a
    return a
end

local function exec(sql, v)
    if sql:find("economy_balance_lock") then return 1 end
    if sql:find("INSERT IGNORE INTO ledger") then
        if hasIdem(v[6]) then return 0 end
        if balance(v[7]) >= v[9] then ledger[#ledger + 1] = { driver = lc(v[1]), amount = -v[3], idem = v[6] }; return 1 end
        return 0
    end
    if sql:find("INTO engineering_project") then
        for _, p in pairs(projects) do if p.idem_key == v[2] then return 0 end end
        if not hasIdem(v[11], v[12], v[13]) then return 0 end
        projects[v[1]] = { project_id = v[1], idem_key = v[2], ncm_driver_id = v[4], kind = v[5], slot = v[6], input_json = v[7],
            cost = v[8], started_at = v[9], due_at = v[10], state = "running" }
        return 1
    end
    if sql:find("INSERT INTO component_asset %(") then
        local n = 0
        for _, a in pairs(assets) do if a.design_id == v[3] then n = math.max(n, a.design_ordinal or 0) end end
        assets[v[1]] = { asset_id = v[1], design_id = v[3], run_id = v[4], ncm_driver_id = v[5], manufacturer_key = v[6],
            location_kind = "storage", acquired_via = v[7], acquired_at = v[8], created_at = v[9], lifecycle = v[10], design_ordinal = n + 1 }
        return 1
    end
    if sql:find("component_asset_transfer") then transfers[#transfers + 1] = v; return 1 end
    if sql:find("UPDATE component_design SET distribution='base'") then
        local d = designs[v[3]]; d.distribution, d.price, d.tier = "base", v[1], v[2]; return 1
    end
    if sql:find("component_supply_state") then supply[#supply + 1] = v; return 1 end
    if sql:find("SET ncm_driver_id=NULL,location_kind='market'") then
        local a = assets[v[1]]
        if a and a.ncm_driver_id == v[2] and a.location_kind == "storage" then a.ncm_driver_id, a.location_kind = nil, "market"; return 1 end
        return 0
    end
    if sql:find("INSERT INTO component_market_inventory") then
        inventory[#inventory + 1] = { asset_id = v[1], price = v[2], state = "available", seller = v[4] }; return 1
    end
    error("unexpected statement: " .. sql)
end

MySQL = {
    isReady = function() return true end,
    transaction = { await = function(tx) for _, st in ipairs(tx) do exec(st.query, st.values) end return true end },
    single = { await = function(sql, p)
        if sql:find("ncm_driver_binding") then local d = drivers[p[2]]; return d and { ncm_driver_id = d } or nil end
        if sql:find("FROM engineering_knowledge WHERE") then
            local k = knowledge[lc(p[2]) .. "|" .. p[3]]; return k and { stage = k.stage, facts_json = k.facts_json } or nil
        end
        if sql:find("SELECT asset_id,design_id FROM component_asset WHERE asset_id=%?") then
            local a = assets[p[1]]
            if a and a.ncm_driver_id == p[3] and a.location_kind == "storage" and a.lifecycle == "active" then return { asset_id = a.asset_id, design_id = a.design_id } end
            return nil
        end
        if sql:find("SELECT a.asset_id,a.design_id,d.origin_kind") then
            local a = assets[p[1]]
            if a and a.ncm_driver_id == p[3] and a.location_kind == "storage" then
                return { asset_id = a.asset_id, design_id = a.design_id, origin_kind = (designs[a.design_id] or {}).origin_kind }
            end
            return nil
        end
        if sql:find("SELECT a.asset_id,a.design_id FROM component_asset a JOIN component_design g") then
            local a = assets[p[1]]
            local d = a and designs[a.design_id]
            if a and d and a.ncm_driver_id == p[3] and a.location_kind == "storage" and a.lifecycle == "active"
                and d.origin_kind == "player_design" and d.manufacturer_key == p[4] then return { asset_id = a.asset_id, design_id = a.design_id } end
            return nil
        end
        if sql:find("FROM engineering_project") and sql:find("state='resolved'") then
            local r = projects[p[1]]
            if r and r.ncm_driver_id == p[3] and r.state == "resolved" then return r end
            return nil
        end
        error("unexpected single: " .. sql)
    end },
    scalar = { await = function(sql, p)
        if sql:find("FROM driver_engineering") then return comp[lc(p[2])] end
        if sql:find("SELECT project_id FROM engineering_project WHERE idem_key") then
            for _, r in pairs(projects) do if r.idem_key == p[1] then return r.project_id end end
            return nil
        end
        if sql:find("SELECT claim_nonce FROM engineering_project") then return projects[p[1]].claim_nonce end
        if sql:find("SELECT COUNT%(%*%) FROM component_design WHERE origin_kind='player_design'") then
            local n = 0 for _, d in pairs(designs) do if d.origin_kind == "player_design" and d.manufacturer_key == p[1] then n = n + 1 end end
            return n
        end
        error("unexpected scalar: " .. sql)
    end },
    query = { await = function(sql, p)
        local out = {}
        if sql:find("WHERE spec_json IS NOT NULL") then
            for _, d in pairs(designs) do if d.spec_json and (d.origin_kind == "prototype" or d.origin_kind == "player_design") then out[#out + 1] = d end end
            return out
        end
        if sql:find("FROM engineering_project WHERE server_id=%? AND ncm_driver_id=%?") then
            for _, r in pairs(projects) do if r.ncm_driver_id == p[2] and (r.state == "running" or r.state == "resolved") then out[#out + 1] = r end end
            table.sort(out, function(a, b) return a.slot < b.slot end)
            return out
        end
        if sql:find("state='running' AND due_at<=") then
            for _, r in pairs(projects) do if r.state == "running" and r.due_at <= p[2] then out[#out + 1] = r end end
            return out
        end
        if sql:find("FROM component_asset a JOIN component_design d ON d.design_id=a.design_id") then
            for _, a in pairs(assets) do
                if a.ncm_driver_id == p[2] and a.location_kind == "storage" and (a.lifecycle == "active" or a.lifecycle == "junk") then
                    local d = designs[a.design_id] or {}
                    out[#out + 1] = { asset_id = a.asset_id, design_id = a.design_id, lifecycle = a.lifecycle, acquired_via = a.acquired_via,
                        code = d.code, origin_kind = d.origin_kind, manufacturer_key = d.manufacturer_key }
                end
            end
            return out
        end
        if sql:find("FROM engineering_knowledge k") then
            for key, k in pairs(knowledge) do
                if key:sub(1, #lc(p[2]) + 1) == lc(p[2]) .. "|" then
                    out[#out + 1] = { design_id = k.design_id, stage = k.stage, facts_json = k.facts_json, code = (designs[k.design_id] or {}).code }
                end
            end
            return out
        end
        if sql:find("origin_kind='player_design' AND manufacturer_key=%? ORDER BY") then
            for _, d in pairs(designs) do if d.origin_kind == "player_design" and d.manufacturer_key == p[1] then out[#out + 1] = d end end
            return out
        end
        error("unexpected query: " .. sql)
    end },
    insert = { await = function(sql, p)
        if sql:find("INTO driver_engineering") then comp[lc(p[2])] = p[3]; return 1 end
        if sql:find("INTO engineering_knowledge") then
            local key = lc(p[2]) .. "|" .. p[3]
            local k = knowledge[key]
            knowledge[key] = { design_id = p[3], stage = math.max(k and k.stage or 0, p[4]), facts_json = p[5] }
            return 1
        end
        if sql:find("INSERT IGNORE INTO component_design") then
            if not designs[p[1]] then
                designs[p[1]] = { design_id = p[1], manufacturer_key = p[4], code = p[6], price = p[10], origin_kind = p[11], spec_json = p[13],
                    distribution = "none", created_at = clock }
            end
            return 1
        end
        if sql:find("component_asset_transfer") then transfers[#transfers + 1] = p; return 1 end
        if sql:find("component_manufacturing_run") then runs[#runs + 1] = p; return 1 end
        if sql:find("component_state") then cstate[p[1]] = p[2]; return 1 end
        error("unexpected insert: " .. sql)
    end },
    update = { await = function(sql, p)
        if sql:find("SET location_kind='workshop'") then
            local a = assets[p[1]]
            if a and a.ncm_driver_id == p[2] and a.location_kind == "storage" and a.lifecycle == "active" then a.location_kind = "workshop"; return 1 end
            return 0
        end
        if sql:find("SET location_kind='storage' WHERE asset_id=%? AND location_kind='workshop'") then
            local a = assets[p[1]]; if a and a.location_kind == "workshop" then a.location_kind = "storage"; return 1 end; return 0
        end
        if sql:find("SET lifecycle='torn_down'") then assets[p[1]].lifecycle = "torn_down"; return 1 end
        if sql:find("SET claim_nonce") then
            local r = projects[p[2]]; if r.state == "running" and not r.claim_nonce then r.claim_nonce = p[1]; return 1 end; return 0
        end
        if sql:find("SET state='resolved'") then
            local r = projects[p[4]]; r.state, r.outcome, r.result_json, r.resolved_at = "resolved", p[1], p[2], p[3]; return 1
        end
        if sql:find("SET state='collected'") then local r = projects[p[2]]; if r.state == "resolved" then r.state = "collected" end; return 1 end
        error("unexpected update: " .. sql)
    end },
}

-- ---------------------------------------------------------------- load core + the resource
NcmCore = dofile(root .. "/ncm/core/init.lua")
for _, f in ipairs(dofile(root .. "/ncm/core/MANIFEST.lua")) do dofile(root .. "/ncm/core/" .. f) end
NcmCore.warm()
Json = NcmCore.get("vocabulary.json")
local Install = NcmCore.get("engineering.installation")
for _, d in ipairs(Install.DESIGNS) do
    designs[d.designId] = { design_id = d.designId, manufacturer_key = d.makerKey, code = d.code, price = d.price, origin_kind = "design", distribution = "engineering" }
end
local RP16 = "eng:zetatech:rp16:r1"
ledger[#ledger + 1] = { driver = "d-ana", amount = 200000, idem = "seed-ana" }
for i = 1, 12 do asset("rp-" .. i, RP16, "d-ana") end
asset("ben-1", RP16, "d-ben")
dofile(root .. "/ncm/online/resources/ncm_workshop/server/main.lua")

local function last() return results[#results] end
local function start(pid, req) req.key = req.key or tostring(math.random()); fire("ncm:workshop.start", pid, req); return last() end
local function finish() clock = clock + 3600; NcmWorkshop.resolveDue() end
local function collectAll(pid)
    fire("ncm:workshop.request", pid)
    for _, j in ipairs(states[pid].bench or {}) do if j.state == "resolved" then fire("ncm:workshop.collect", pid, j.projectId) end end
end
local function knownStage() local k = knowledge["d-ana|" .. RP16]; return k and k.stage or 0 end

-- ---------------------------------------------------------------- the lanes
fire("ncm:workshop.request", 1)
check("the bench opens: storage, two slots, a novice reaching stage 1", states[1] and #states[1].storage == 12 and states[1].slots == 2 and states[1].card.depth == 1)

local before = balance("d-ana")
check("a teardown starts", start(1, { kind = "teardown", assetId = "rp-1" }).ok == true)
check("its materials are committed up front (2 % of the price)", balance("d-ana") == before - 130)
check("the specimen is consumed when the work starts", assets["rp-1"].lifecycle == "torn_down" and assets["rp-1"].location_kind == "workshop")
check("fabrication is refused without the method", start(1, { kind = "fabricate", designId = RP16 }).ok == false and last().text:find("stage 3"))
check("a second teardown takes the second slot", start(1, { kind = "teardown", assetId = "rp-2" }).ok == true)
check("a third is refused: the bench is full", start(1, { kind = "teardown", assetId = "rp-3" }).ok == false and last().text:find("busy"))
check("...and its part stays in storage", assets["rp-3"].location_kind == "storage" and assets["rp-3"].lifecycle == "active")

finish()
check("finished work is resolved by the scheduler", (function() local n = 0 for _, p in pairs(projects) do if p.state == "resolved" then n = n + 1 end end return n == 2 end)())
check("a teardown teaches stage 1 of the design", knownStage() == 1)
collectAll(1)
check("collecting gives the job sheet", #sheets == 2 and sheets[1].kind == "teardown" and sheets[1].lines and #sheets[1].lines >= 1)
check("the engineer has learned (a deeper teardown now)", states[1].card.depth >= 2)

-- tear down, one at a time, until the method is known (a teardown's depth is set when it starts)
local nextSpecimen = 3
local function learnTo(stage)
    while knownStage() < stage and nextSpecimen <= 12 do
        start(1, { kind = "teardown", assetId = "rp-" .. nextSpecimen }); nextSpecimen = nextSpecimen + 1
        finish(); collectAll(1)
    end
end
learnTo(3)
check(("practice reaches the manufacturing method (stage 3) after %d teardowns"):format(nextSpecimen - 1), knownStage() >= 3 and nextSpecimen <= 7)

-- fabricate until a working prototype exists (a nonfunctional one still persists)
local proto, junk = nil, 0
for attempt = 1, 8 do
    start(1, { kind = "fabricate", designId = RP16 })
    finish(); collectAll(1)
    local s = sheets[#sheets]
    if s.outcome == "junk" then
        junk = junk + 1
        check("a nonfunctional result is a physical thing you own", assets[s.assetId] and assets[s.assetId].lifecycle == "junk")
    else
        proto = s; break
    end
end
check("a working prototype is fabricated", proto and proto.assetId and assets[proto.assetId].lifecycle == "active")
local protoDesign = assets[proto.assetId].design_id
check("it is its own prototype design, never listed, made by the engineer", designs[protoDesign].origin_kind == "prototype"
    and designs[protoDesign].distribution == "none" and designs[protoDesign].manufacturer_key == "p-d-ana")
check("and it can be mounted (registered as a physical design)", Install.design(protoDesign) ~= nil)

-- promotion needs the principles (stage 4)
if knownStage() < 4 then
    check("promotion is refused without the principles", start(1, { kind = "promote", assetId = proto.assetId }).ok == false and last().text:find("stage 4"))
    learnTo(4)
end
check("the principles are known", knownStage() == 4)
check("the prototype is promoted", start(1, { kind = "promote", assetId = proto.assetId }).ok == true)
finish(); collectAll(1)
local pd
for id, d in pairs(designs) do if d.origin_kind == "player_design" then pd = d end end
check("a player design exists, coded by its maker", pd and pd.code:match("^ANA%-THR%d%d%d$"))
check("the prototype is untouched by promotion", assets[proto.assetId].design_id == protoDesign and assets[proto.assetId].lifecycle == "active")

-- a run
check("a run of three starts", start(1, { kind = "run", designId = pd.design_id, n = 3 }).ok == true)
finish(); collectAll(1)
local unitsGood, unitsJunk = 0, 0
for _, a in pairs(assets) do if a.design_id == pd.design_id then if a.lifecycle == "active" then unitsGood = unitsGood + 1 else unitsJunk = unitsJunk + 1 end end end
check("three units exist, rejects kept as junk", unitsGood + unitsJunk == 3 and #runs == 1)

-- list one
local unit
for _, a in pairs(assets) do if a.design_id == pd.design_id and a.lifecycle == "active" and a.location_kind == "storage" then unit = a end end
fire("ncm:workshop.list", 1, { assetId = unit.asset_id, price = 9000 })
check("a unit is listed on the Base Market with its seller", last().ok == true and inventory[1] and inventory[1].seller == "d-ana" and unit.location_kind == "market")
check("the design is now on sale", designs[pd.design_id].distribution == "base" and #supply == 1)

-- money and idempotence
check("no money, no materials: refused, and the part comes back", start(2, { kind = "teardown", assetId = "ben-1" }).ok == false
    and last().text:find("need") and assets["ben-1"].location_kind == "storage" and assets["ben-1"].lifecycle == "active")
local n0 = 0 for _ in pairs(projects) do n0 = n0 + 1 end
local spent = balance("d-ana")
start(1, { kind = "fabricate", designId = RP16, key = "same-click" })
start(1, { kind = "fabricate", designId = RP16, key = "same-click" })
local n1 = 0 for _ in pairs(projects) do n1 = n1 + 1 end
check("a retried click starts one project and pays once", n1 == n0 + 1 and balance("d-ana") == spent - NcmCore.get("engineering.projects").cost("fabricate", 6500))

realPrint(("workshop host: %d passed, 0 failed"):format(passed))
