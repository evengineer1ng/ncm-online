-- ncm_workshop / server / main -- the Workshop (L361): an engineer's bench.
--
-- Four projects on one grammar (core `engineering.projects`): TEAR DOWN a component you own (destructive reverse
-- engineering: the specimen is consumed, you learn its design stage by stage), FABRICATE a prototype from what you know
-- (a physical thing either way: a nonfunctional result is junk you still own, L134), PROMOTE a working prototype to
-- your own immutable design, RUN your design (1-3 units; rejects are junk). Materials are committed and the clock
-- starts in the same transaction (L134); your own hands cost nothing (L353). Two bench slots per engineer.
--
-- The server is the only writer and the resolver is server-private: outcomes are drawn from a stream keyed by a
-- server secret and the project id at resolution, never shown before the work is done.
--
-- Net events (client -> server), answered with ncm:workshop.state { bench, storage, knowledge, designs, card, ... }:
--   ncm:workshop.request
--   ncm:workshop.start { kind, assetId?, designId?, n?, name?, key }
--   ncm:workshop.collect { projectId }            -> ncm:workshop.sheet { the job sheet }, then state
--   ncm:workshop.list { assetId, price, key }      put a unit of your design on the Base Market
local P = NcmCore.get("engineering.projects")
local Install = NcmCore.get("engineering.installation")
local Comp = NcmCore.get("engineering.competency")
local Lineage = NcmCore.get("engineering.lineage")
local Hash = NcmCore.get("vocabulary.hash")
local Json = NcmCore.get("vocabulary.json")
local ids = NcmCore.get("vocabulary.ids")
local hostRng = function() return math.random() end

local function log(fmt, ...) print(("[ncm_workshop] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end
local function serverId()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    return (ok and type(id) == "table" and id.serverId) or "ncm-dev"
end
-- KB-358: CHAR(36) columns come back as GUID values: compare ids as lowercase text
local function idOf(v) return v ~= nil and tostring(v):lower() or nil end
local function enc(v) local ok, s = pcall(Json.encode, v); return ok and s or "{}" end
local function dec(v) if type(v) == "table" then return v end local ok, x = pcall(Json.decode, tostring(v or "")); return ok and x or nil end

local ok, settings = pcall(Open77.tunables.declare, {
    workshopEnabled = { value = true, type = "boolean", apply = "live" },
    workshopTimeScale = { value = 1.0, type = "number", min = 0.001, max = 10, apply = "live" },
    workshopSecret = { value = "ncm-dev-workshop", type = "string", apply = "next_match" },
})
if not ok then log("tunables.declare FAILED: %s", tostring(settings)); settings = nil end
local function set(k, d)
    if not settings then return d end
    local okV, v = pcall(function() return settings[k] end)
    if okV and v ~= nil then return v end
    return d
end

-- ------------------------------------------------------------------------------------------------ who is who
local driverOf = {}
local function driver(pid)
    pid = tonumber(pid) or 0
    if pid <= 0 then return nil end
    if driverOf[pid] then return driverOf[pid] end
    local okU, userId = pcall(GetPlayerIdentifier, pid)
    if not okU or type(userId) ~= "string" or userId == "" or not MySQL.isReady() then return nil end
    local row = MySQL.single.await("SELECT ncm_driver_id FROM ncm_driver_binding WHERE server_id = ? AND user_id = ?", { serverId(), userId })
    if not (row and row.ncm_driver_id) then return nil end
    local okN, name = pcall(GetPlayerName, pid)
    driverOf[pid] = { id = idOf(row.ncm_driver_id), name = (okN and type(name) == "string" and name ~= "") and name or "Engineer" }
    return driverOf[pid]
end
local function pidOf(driverId)
    for pid, d in pairs(driverOf) do if d.id == driverId then return pid end end
    return nil
end
AddEventHandler("playerDropped", function() local pid = tonumber(source); if pid then driverOf[pid] = nil end end)

--- An engineer's maker identity: a stable key and a three-letter tag for codes.
local function makerOf(d)
    local tag = tostring(d.name):gsub("[^%w]", ""):upper():sub(1, 3)
    if #tag < 3 then tag = (tag .. "ENG"):sub(1, 3) end
    return "p-" .. d.id:sub(1, 8), tag
end

-- ------------------------------------------------------------------------------------------------ designs
--- Every physical design this VM may need: the authored ones (core), R&D, prototypes and player designs.
local function loadDesigns()
    local n = 0
    for _, row in ipairs(MySQL.query.await([[SELECT spec_json FROM component_design WHERE spec_json IS NOT NULL
        AND origin_kind IN ('rnd_physical','prototype','player_design')]]) or {}) do
        local spec = dec(row.spec_json)
        if spec and Install.register(spec) then n = n + 1 end
    end
    return n
end

local function writeDesign(spec, originKind, t)
    MySQL.insert.await([[INSERT IGNORE INTO component_design
      (design_id,lineage_id,revision,manufacturer_key,display_manufacturer,code,subtitle,family,tier,effect,
       price,fidelity,distribution,origin_kind,positions_json,fitment_json,spec_json,created_at)
      VALUES (?,?,?,?,?,?,?,?,?,1,?,'physical','none',?,'[]',?,?,?)]],
      { spec.designId, spec.lineageId, spec.revision or 1, spec.makerKey, spec.manufacturer, spec.code, spec.subtitle or "",
        spec.family, spec.tier or "engineering", spec.price, originKind, enc({ standard = spec.interface }), enc(spec), t })
    Install.register(spec)
    TriggerEvent("ncm:rnd:design", spec)   -- ncm_world and ncm_league register it too (the same event R&D uses)
end

local function tierFor(price) return price >= 12000 and "premium" or (price >= 5000 and "sport" or "street") end

-- ------------------------------------------------------------------------------------------------ competency
local function loadCompetency(driverId)
    local v = MySQL.scalar.await("SELECT state_json FROM driver_engineering WHERE server_id=? AND ncm_driver_id=?", { serverId(), driverId })
    local s = dec(v)
    if type(s) ~= "table" or type(s.skills) ~= "table" then s = Comp.newState() end
    s.families = s.families or {}
    return s
end
local function saveCompetency(driverId, state, t)
    MySQL.insert.await([[INSERT INTO driver_engineering (server_id,ncm_driver_id,state_json,updated_at) VALUES (?,?,?,?)
      ON DUPLICATE KEY UPDATE state_json=VALUES(state_json),updated_at=VALUES(updated_at)]], { serverId(), driverId, enc(state), t })
end

--- Other resources credit work done elsewhere (self repair, mounting) through this server event.
AddEventHandler("ncm:workshop.credit", function(driverId, skillId, base, familyId)
    driverId = idOf(driverId)
    if not driverId or not Comp.isSkill(skillId) then return end
    CreateThread(function()
        local s = loadCompetency(driverId)
        Comp.apply(s, { skillId = skillId, familyId = Comp.isFamily(familyId or "") and familyId or nil,
            base = tonumber(base) or 0, jobLevel = 300, completed = true })
        saveCompetency(driverId, s, now())
    end)
end)

-- ------------------------------------------------------------------------------------------------ knowledge
local function knowledgeOf(driverId, designId)
    local r = MySQL.single.await("SELECT stage,facts_json FROM engineering_knowledge WHERE server_id=? AND ncm_driver_id=? AND design_id=?",
        { serverId(), driverId, designId })
    return r and tonumber(r.stage) or 0, r and dec(r.facts_json) or {}
end

-- ------------------------------------------------------------------------------------------------ reads
local function bench(driverId)
    return MySQL.query.await([[SELECT project_id,kind,slot,input_json,cost,started_at,due_at,state,outcome,result_json
      FROM engineering_project WHERE server_id=? AND ncm_driver_id=? AND state IN ('running','resolved') ORDER BY slot]],
      { serverId(), driverId }) or {}
end

local function snapshot(pid)
    local d = driver(pid)
    if not d then return { unavailable = true, why = "no driver profile" } end
    local t = now()
    local makerKey = makerOf(d)
    local out = { enabled = set("workshopEnabled", true) == true, slots = P.SLOTS, now = t, bench = {}, storage = {},
        knowledge = {}, designs = {}, card = P.card(loadCompetency(d.id)), maker = makerKey }
    for _, r in ipairs(bench(d.id)) do
        local input = dec(r.input_json) or {}
        out.bench[#out.bench + 1] = { projectId = idOf(r.project_id), kind = r.kind, slot = tonumber(r.slot), label = input.label,
            cost = tonumber(r.cost), startedAt = tonumber(r.started_at), dueAt = tonumber(r.due_at), state = r.state, outcome = r.outcome }
    end
    for _, r in ipairs(MySQL.query.await([[SELECT a.asset_id,a.design_id,a.lifecycle,a.acquired_via,d.code,d.origin_kind,d.manufacturer_key
      FROM component_asset a JOIN component_design d ON d.design_id=a.design_id
      WHERE a.server_id=? AND a.ncm_driver_id=? AND a.location_kind='storage' AND a.lifecycle IN ('active','junk')
      ORDER BY a.created_at DESC LIMIT 60]], { serverId(), d.id }) or {}) do
        local spec = Install.design(r.design_id)
        out.storage[#out.storage + 1] = { assetId = idOf(r.asset_id), designId = r.design_id, code = r.code,
            name = spec and spec.name or r.code, family = spec and spec.family, physical = spec ~= nil, junk = r.lifecycle == "junk",
            origin = r.origin_kind, mine = r.manufacturer_key == makerKey, price = spec and spec.price,
            teardownCost = spec and P.cost("teardown", spec.price) }
    end
    for _, r in ipairs(MySQL.query.await([[SELECT k.design_id,k.stage,k.facts_json,d.code FROM engineering_knowledge k
      JOIN component_design d ON d.design_id=k.design_id WHERE k.server_id=? AND k.ncm_driver_id=? ORDER BY k.updated_at DESC]],
      { serverId(), d.id }) or {}) do
        local spec = Install.design(r.design_id)
        out.knowledge[#out.knowledge + 1] = { designId = r.design_id, code = r.code, name = spec and spec.name or r.code,
            stage = tonumber(r.stage), stageLabel = (P.STAGES[tonumber(r.stage) or 0] or {}).label, facts = dec(r.facts_json) or {},
            canFabricate = (tonumber(r.stage) or 0) >= P.FABRICATE_MIN_STAGE and spec ~= nil,
            fabricateCost = spec and P.cost("fabricate", spec.price),
            fabricateMinutes = spec and math.ceil(P.duration("fabricate", spec.massKg, { timeScale = set("workshopTimeScale", 1) }) / 60) }
    end
    for _, r in ipairs(MySQL.query.await([[SELECT design_id,code,price,distribution FROM component_design
      WHERE origin_kind='player_design' AND manufacturer_key=? ORDER BY created_at]], { makerKey }) or {}) do
        local spec = Install.design(r.design_id)
        out.designs[#out.designs + 1] = { designId = r.design_id, code = r.code, name = spec and spec.name or r.code,
            price = tonumber(r.price), listed = r.distribution == "base", runCost = P.cost("run", tonumber(r.price), 1) }
    end
    return out
end

local function push(pid)
    local okS, s = pcall(snapshot, pid)
    TriggerClientEvent("ncm:workshop.state", pid, okS and s or { unavailable = true, why = tostring(s) })
end
RegisterNetEvent("ncm:workshop.request", function() local pid = tonumber(source) or 0; CreateThread(function() push(pid) end) end)

-- ------------------------------------------------------------------------------------------------ starting work
local function freeSlot(driverId)
    local used = {}
    for _, r in ipairs(bench(driverId)) do used[tonumber(r.slot)] = true end
    for i = 1, P.SLOTS do if not used[i] then return i end end
    return nil
end

local function balanceLocks(driverId)
    return {
        { query = "INSERT IGNORE INTO economy_balance_lock (server_id,ncm_driver_id,revision) VALUES (?,?,0)", values = { serverId(), driverId } },
        { query = "UPDATE economy_balance_lock SET revision=revision+1 WHERE server_id=? AND ncm_driver_id=?", values = { serverId(), driverId } },
    }
end

--- Commit materials and start the clock in one transaction. Returns the project id or nil + why.
local function commit(d, kind, slot, input, cost, seconds, idem)
    local t, projectId = now(), ids.uuid4(hostRng)
    input.makerName = d.name   -- the name a design carries is the engineer's when the work began
    local tx = balanceLocks(d.id)
    tx[#tx + 1] = { query = [[INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key)
        SELECT ?,?,'workshop_materials',-?,'eddies',?,?,? FROM DUAL
        WHERE (SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?) >= ?]],
        values = { d.id, serverId(), cost, projectId, ("Workshop: %s"):format(kind), idem, d.id, serverId(), cost } }
    tx[#tx + 1] = { query = [[INSERT IGNORE INTO engineering_project (project_id,idem_key,server_id,ncm_driver_id,kind,slot,input_json,cost,started_at,due_at,state)
        SELECT ?,?,?,?,?,?,?,?,?,?,'running' FROM DUAL WHERE EXISTS (SELECT 1 FROM ledger WHERE idem_key=? AND ncm_driver_id=? AND amount=?)]],
        values = { projectId, idem, serverId(), d.id, kind, slot, enc(input), cost, t, t + seconds, idem, d.id, -cost } }
    local okT, err = MySQL.transaction.await(tx)
    if not okT then return nil, "transaction failed: " .. tostring(err) end
    local exists = MySQL.scalar.await("SELECT project_id FROM engineering_project WHERE idem_key=?", { idem })
    if not exists then return nil, ("you need €$%d for the materials"):format(cost) end
    return idOf(exists)
end

local starters = {}

--- TEAR DOWN: the specimen leaves your storage when the work starts (destructive analysis).
function starters.teardown(d, req, slot, idem)
    local a = MySQL.single.await([[SELECT asset_id,design_id FROM component_asset WHERE asset_id=? AND server_id=? AND ncm_driver_id=?
      AND location_kind='storage' AND lifecycle='active']], { req.assetId, serverId(), d.id })
    if not a then return nil, "that component is not in your storage" end
    local spec = Install.design(a.design_id)
    if not spec then return nil, "factory-interface parts cannot be analysed on the bench yet; physical add-ons can" end
    local plan = P.planTeardown(spec, loadCompetency(d.id), { timeScale = set("workshopTimeScale", 1) })
    -- reserve the specimen first; give it back if the materials cannot be paid
    local moved = MySQL.update.await([[UPDATE component_asset SET location_kind='workshop' WHERE asset_id=? AND ncm_driver_id=?
      AND location_kind='storage' AND lifecycle='active']], { a.asset_id, d.id })
    if (tonumber(moved) or 0) < 1 then return nil, "that component just left your storage" end
    local input = { assetId = idOf(a.asset_id), designId = a.design_id, stages = plan.stages,
        label = ("Tear down %s (to stage %d)"):format(spec.code, plan.stages) }
    local projectId, why = commit(d, "teardown", slot, input, plan.cost, plan.seconds, idem)
    if not projectId then
        MySQL.update.await("UPDATE component_asset SET location_kind='storage' WHERE asset_id=? AND location_kind='workshop'", { a.asset_id })
        return nil, why
    end
    MySQL.update.await("UPDATE component_asset SET lifecycle='torn_down' WHERE asset_id=?", { a.asset_id })
    MySQL.insert.await([[INSERT IGNORE INTO component_asset_transfer (transfer_id,idem_key,server_id,asset_id,from_driver_id,kind,occurred_at)
      VALUES (?,?,?,?,?,'teardown',?)]], { ids.uuid4(hostRng), "teardown:" .. projectId, serverId(), a.asset_id, d.id, now() })
    return projectId, input.label
end

--- FABRICATE: needs the manufacturing method (stage 3) of the design you are copying.
function starters.fabricate(d, req, slot, idem)
    local spec = Install.design(tostring(req.designId or ""))
    if not spec then return nil, "unknown design" end
    local stage = knowledgeOf(d.id, spec.designId)
    if stage < P.FABRICATE_MIN_STAGE then
        return nil, ("you know %s to stage %d; building one needs stage %d (tear more of them down)"):format(spec.code, stage, P.FABRICATE_MIN_STAGE)
    end
    local input = { designId = spec.designId, label = ("Fabricate a %s prototype"):format(spec.code) }
    local projectId, why = commit(d, "fabricate", slot, input, P.cost("fabricate", spec.price),
        P.duration("fabricate", spec.massKg, { timeScale = set("workshopTimeScale", 1) }), idem)
    return projectId, projectId and input.label or why
end

--- PROMOTE: a working prototype of a design you know completely becomes your own design.
function starters.promote(d, req, slot, idem)
    local a = MySQL.single.await([[SELECT a.asset_id,a.design_id,d.origin_kind FROM component_asset a JOIN component_design d ON d.design_id=a.design_id
      WHERE a.asset_id=? AND a.server_id=? AND a.ncm_driver_id=? AND a.location_kind='storage']], { req.assetId, serverId(), d.id })
    if not a or a.origin_kind ~= "prototype" then return nil, "promote a prototype you fabricated" end
    local proto = Install.design(a.design_id)
    if not proto then return nil, "unknown prototype" end
    local stage = knowledgeOf(d.id, proto.parentDesignId or "")
    local okP, whyP = P.canPromote("working", stage)
    if not okP then return nil, whyP == "knowledge" and ("promotion needs complete knowledge (stage 4) of %s"):format(tostring(proto.parentDesignId)) or whyP end
    local name = tostring(req.name or ""):gsub("[%c<>]", ""):sub(1, 32)
    local input = { assetId = idOf(a.asset_id), protoDesignId = proto.designId, name = name, label = ("Promote %s to a design"):format(proto.code) }
    local projectId, why = commit(d, "promote", slot, input, P.cost("promote", proto.price),
        P.duration("promote", proto.massKg, { timeScale = set("workshopTimeScale", 1) }), idem)
    return projectId, projectId and input.label or why
end

--- RUN: repeat manufacture of your own design.
function starters.run(d, req, slot, idem)
    local spec = Install.design(tostring(req.designId or ""))
    local makerKey = makerOf(d)
    if not spec or spec.origin ~= "player_design" or spec.makerKey ~= makerKey then return nil, "run a design you own" end
    local n = math.max(1, math.min(P.RUN_MAX, math.floor(tonumber(req.n) or 1)))
    local input = { designId = spec.designId, n = n, label = ("Make %d x %s"):format(n, spec.code) }
    local projectId, why = commit(d, "run", slot, input, P.cost("run", spec.price, n),
        P.duration("run", spec.massKg, { n = n, timeScale = set("workshopTimeScale", 1) }), idem)
    return projectId, projectId and input.label or why
end

local function reply(pid, okR, title, message)
    TriggerClientEvent("ncm:workshop.result", pid, { ok = okR, text = message })
    pcall(Open77.notifications.send, pid, { type = okR and "success" or "error", title = title, message = message, icon = "NCM", durationMs = 6000 })
end

RegisterNetEvent("ncm:workshop.start", function(req)
    local pid = tonumber(source) or 0
    CreateThread(function()
        local d = driver(pid)
        if not d or type(req) ~= "table" or not starters[req.kind] then return reply(pid, false, "WORKSHOP", "Nothing to start.") end
        if set("workshopEnabled", true) ~= true then return reply(pid, false, "WORKSHOP", "The workshop is closed.") end
        local slot = freeSlot(d.id)
        if not slot then return reply(pid, false, "BENCH FULL", "Both bench slots are busy. Collect a finished job first.") end
        local idem = ("workshop:%s:%s"):format(d.id, tostring(req.key or ids.uuid4(hostRng))):sub(1, 190)
        local okS, projectId, text = pcall(starters[req.kind], d, req, slot, idem)
        if not okS then log("start %s failed: %s", tostring(req.kind), tostring(projectId)); projectId, text = nil, "the bench refused" end
        if projectId then log("START player=%d %s slot %d project %s: %s", pid, req.kind, slot, projectId, tostring(text)) end
        reply(pid, projectId ~= nil, projectId and "ON THE BENCH" or "WORKSHOP", tostring(text))
        push(pid)
    end)
end)

-- ------------------------------------------------------------------------------------------------ resolving work
local function seeded(projectId) return Hash.stream("ncm-workshop", tostring(set("workshopSecret", "")), serverId(), projectId) end

local function mintAsset(designId, driverId, makerKey, via, lifecycle, runId, t)
    local asset = ids.uuid4(hostRng)
    MySQL.transaction.await({
        { query = [[INSERT INTO component_asset (asset_id,server_id,design_id,run_id,ncm_driver_id,manufacturer_key,location_kind,machine_asset_id,
            global_ordinal,maker_ordinal,design_ordinal,factory_original,acquired_via,acquired_at,exposure_m,created_at,lifecycle)
            SELECT ?,?,?,?,?,?,'storage',NULL,NULL,NULL,COALESCE(MAX(design_ordinal),0)+1,0,?,?,0,?,?
            FROM component_asset WHERE server_id=? AND design_id=?]],
          values = { asset, serverId(), designId, runId, driverId, makerKey, via, t, t, lifecycle, serverId(), designId } },
        { query = [[INSERT INTO component_asset_transfer (transfer_id,idem_key,server_id,asset_id,from_driver_id,to_driver_id,kind,occurred_at)
            VALUES (?,?,?,?,NULL,?,?,?)]], values = { ids.uuid4(hostRng), via .. ":" .. asset, serverId(), asset, driverId, via, t } },
    })
    local spec = Install.design(designId)
    if spec and spec.perf and spec.perf.kind == "propellant_tank" and lifecycle == "active" then   -- L334: a new tank comes full
        MySQL.insert.await("INSERT IGNORE INTO component_state (asset_id, propellant_kg, updated_at) VALUES (?,?,?)", { asset, spec.perf.capacityKg or 0, t })
    end
    return asset
end

local resolvers = {}

function resolvers.teardown(row, input, comp, rng, t)
    local spec = Install.design(input.designId)
    if not spec then return "failed", { text = "the design is unknown to this bench" } end
    local skill = Comp.valueOf(comp, "reverse_engineering")
    local facts = P.reveal(spec, input.stages, skill, rng)
    local stage, old = knowledgeOf(row.driver, spec.designId)
    for k, v in pairs(old or {}) do if facts[k] == nil then facts[k] = v end end
    MySQL.insert.await([[INSERT INTO engineering_knowledge (server_id,ncm_driver_id,design_id,stage,facts_json,updated_at) VALUES (?,?,?,?,?,?)
      ON DUPLICATE KEY UPDATE stage=GREATEST(stage,VALUES(stage)),facts_json=VALUES(facts_json),updated_at=VALUES(updated_at)]],
      { serverId(), row.driver, spec.designId, input.stages, enc(facts), t })
    P.applyCredit(comp, "teardown", { stages = input.stages, family = spec.family, jobLevel = 300 })
    local known = math.max(stage, input.stages)
    return "done", { code = spec.code, name = spec.name, stages = input.stages, known = known, facts = facts,
        lines = (function()
            local l = {}
            for i = 1, input.stages do l[#l + 1] = ("Stage %d: %s"):format(i, P.STAGES[i].label) end
            return l
        end)(), canFabricate = known >= P.FABRICATE_MIN_STAGE }
end

function resolvers.fabricate(row, input, comp, rng, t)
    local src = Install.design(input.designId)
    if not src then return "failed", { text = "the design is unknown to this bench" } end
    local stage = knowledgeOf(row.driver, src.designId)
    local makerKey, tag = makerOf({ id = row.driver, name = row.name })
    local r = P.fabricate(src, stage, comp, rng, { makerKey = makerKey })
    P.applyCredit(comp, "fabricate", { family = src.family, jobLevel = 300 })
    if not r or r.class == "junk" then
        local asset = mintAsset(src.designId, row.driver, makerKey, "fabricate", "junk", nil, t)
        return "junk", { code = src.code, assetId = asset, text = r and r.reason or "nothing usable" }
    end
    local spec = r.spec
    local short = tostring(row.project_id):gsub("-", ""):sub(1, 6):upper()
    spec.designId = "proto:" .. tostring(row.project_id)
    spec.lineageId = spec.designId
    spec.revision = 1
    spec.makerKey = makerKey
    spec.manufacturer = row.name
    spec.code = ("%s-P%s"):format(src.code, short)
    spec.name = ("%s prototype (%s)"):format(src.name or src.code, tag)
    spec.subtitle = ("Hand-built from a teardown of the %s. %s."):format(src.code, r.class == "good" and "Better than the original" or
        (r.class == "neutral" and "About as good as the original" or "Not as good as the original"))
    spec.origin = "prototype"
    spec.distribution = "none"
    spec.parentDesignId = src.designId
    spec.price = src.price
    spec.tier = tierFor(src.price)
    spec.grade = r.class
    writeDesign(spec, "prototype", t)
    local asset = mintAsset(spec.designId, row.driver, makerKey, "fabricate", "active", nil, t)
    return r.class, { code = spec.code, name = spec.name, assetId = asset, grade = r.class,
        perf = spec.perf, massKg = spec.massKg, source = { code = src.code, perf = src.perf, massKg = src.massKg } }
end

function resolvers.promote(row, input, comp, rng, t)
    local proto = Install.design(input.protoDesignId)
    if not proto then return "failed", { text = "the prototype's design is unknown" } end
    local makerKey, tag = makerOf({ id = row.driver, name = row.name })
    local n = (tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM component_design WHERE origin_kind='player_design' AND manufacturer_key=?", { makerKey })) or 0) + 1
    local spec = NcmCore.get("world.seed").deepCopy(proto)
    local kindCode = Lineage.KIND_CODE[spec.perf.kind] or "PART"
    spec.designId = ("pd:%s:%s:%03d"):format(Hash.commit(serverId()), makerKey, n)
    spec.lineageId = spec.designId
    spec.revision = 1
    spec.code = ("%s-%s%03d"):format(tag, kindCode, n)
    spec.name = (input.name and input.name ~= "") and input.name or ("%s %s %d"):format(row.name, kindCode, n)
    spec.subtitle = ("%s's own design, from the %s."):format(row.name, tostring(proto.parentDesignId))
    spec.origin = "player_design"
    spec.distribution = "none"
    spec.parentDesignId = proto.parentDesignId
    spec.prototypeDesignId = proto.designId
    spec.lineage = { { id = proto.parentDesignId, relation = "reconstructed_from" } }
    spec.grade = nil
    writeDesign(spec, "player_design", t)
    P.applyCredit(comp, "promote", { family = spec.family, jobLevel = 300 })
    return "done", { code = spec.code, name = spec.name, designId = spec.designId, from = proto.code }
end

function resolvers.run(row, input, comp, rng, t)
    local spec = Install.design(input.designId)
    if not spec then return "failed", { text = "the design is unknown" } end
    local makerKey = makerOf({ id = row.driver, name = row.name })
    local units = P.run(input.n, comp, rng)
    local runId = ids.uuid4(hostRng)
    MySQL.insert.await([[INSERT INTO component_manufacturing_run (run_id,server_id,design_id,allocation_key,quantity,produced_at)
      VALUES (?,?,?,?,?,?)]], { runId, serverId(), spec.designId, "workshop:" .. tostring(row.project_id), #units, t })
    local good, rejects = 0, 0
    for _, u in ipairs(units) do
        mintAsset(spec.designId, row.driver, makerKey, "workshop_run", u == "good" and "active" or "junk", runId, t)
        if u == "good" then good = good + 1 else rejects = rejects + 1 end
    end
    P.applyCredit(comp, "run", { n = input.n, family = spec.family, jobLevel = 300 })
    return "done", { code = spec.code, name = spec.name, good = good, rejects = rejects }
end

local names = {}   -- driverId -> the name their designs carry (the last one seen online)
local function nameOf(driverId)
    local pid = pidOf(driverId)
    if pid then names[driverId] = driverOf[pid].name end
    return names[driverId] or "Engineer"
end

local function resolveDue()
    local t = now()
    for _, r in ipairs(MySQL.query.await([[SELECT * FROM engineering_project WHERE server_id=? AND state='running' AND due_at<=?
      ORDER BY due_at LIMIT 10]], { serverId(), t }) or {}) do
        local nonce = ids.uuid4(hostRng)
        MySQL.update.await("UPDATE engineering_project SET claim_nonce=? WHERE project_id=? AND state='running' AND claim_nonce IS NULL", { nonce, r.project_id })
        if idOf(MySQL.scalar.await("SELECT claim_nonce FROM engineering_project WHERE project_id=?", { r.project_id })) == nonce then
            local row = { project_id = idOf(r.project_id), driver = idOf(r.ncm_driver_id) }
            local input = dec(r.input_json) or {}
            row.name = input.makerName or nameOf(row.driver)
            local comp = loadCompetency(row.driver)
            local okR, outcome, result = pcall(resolvers[r.kind], row, input, comp, seeded(row.project_id), t)
            if not okR then log("RESOLVE %s %s failed: %s", r.kind, row.project_id, tostring(outcome)); outcome, result = "failed", { text = "the bench faulted" } end
            result = result or {}
            result.kind, result.label = r.kind, input.label
            saveCompetency(row.driver, comp, t)
            MySQL.update.await("UPDATE engineering_project SET state='resolved',outcome=?,result_json=?,resolved_at=? WHERE project_id=?",
                { outcome, enc(result), t, r.project_id })
            log("DONE %s %s -> %s", r.kind, row.project_id, tostring(outcome))
            local pid = pidOf(row.driver)
            if pid then
                pcall(Open77.notifications.send, pid, { type = "info", title = "WORKSHOP: JOB DONE",
                    message = ("%s is finished. Collect it in F9 > WORKSHOP."):format(tostring(input.label)), icon = "NCM", durationMs = 7000 })
                push(pid)
            end
        end
    end
end

-- ------------------------------------------------------------------------------------------------ collecting, listing
RegisterNetEvent("ncm:workshop.collect", function(projectId)
    local pid = tonumber(source) or 0
    CreateThread(function()
        local d = driver(pid)
        if not d then return end
        local r = MySQL.single.await([[SELECT project_id,kind,outcome,result_json,input_json,cost FROM engineering_project
          WHERE project_id=? AND server_id=? AND ncm_driver_id=? AND state='resolved']], { tostring(projectId or ""), serverId(), d.id })
        if not r then return reply(pid, false, "WORKSHOP", "Nothing to collect there.") end
        MySQL.update.await("UPDATE engineering_project SET state='collected',collected_at=? WHERE project_id=? AND state='resolved'", { now(), r.project_id })
        local sheet = dec(r.result_json) or {}
        sheet.outcome, sheet.kind, sheet.cost = r.outcome, r.kind, tonumber(r.cost)
        TriggerClientEvent("ncm:workshop.sheet", pid, sheet)
        TriggerEvent("ncm:component.changed", pid, nil)
        push(pid)
    end)
end)

RegisterNetEvent("ncm:workshop.list", function(req)
    local pid = tonumber(source) or 0
    CreateThread(function()
        local d = driver(pid)
        if not d or type(req) ~= "table" then return end
        local makerKey = makerOf(d)
        local a = MySQL.single.await([[SELECT a.asset_id,a.design_id FROM component_asset a JOIN component_design g ON g.design_id=a.design_id
          WHERE a.asset_id=? AND a.server_id=? AND a.ncm_driver_id=? AND a.location_kind='storage' AND a.lifecycle='active'
          AND g.origin_kind='player_design' AND g.manufacturer_key=?]], { tostring(req.assetId or ""), serverId(), d.id, makerKey })
        if not a then return reply(pid, false, "MARKET", "List a working unit of your own design.") end
        local spec = Install.design(a.design_id)
        local price = math.max(10, math.min((spec and spec.price or 1000) * 10, math.floor(tonumber(req.price) or (spec and spec.price) or 1000)))
        local t = now()
        local okT = MySQL.transaction.await({
            { query = [[UPDATE component_design SET distribution='base',price=?,tier=? WHERE design_id=?]], values = { price, tierFor(price), a.design_id } },
            { query = [[INSERT IGNORE INTO component_supply_state (server_id,market_id,design_id,next_tick_index,next_tick_at,batch,interval_sec,initial_done,updated_at)
                VALUES (?,'base_market',?,0,?,0,315360000,1,?)]], values = { serverId(), a.design_id, t + 315360000, t } },
            { query = [[UPDATE component_asset SET ncm_driver_id=NULL,location_kind='market' WHERE asset_id=? AND ncm_driver_id=? AND location_kind='storage']],
                values = { a.asset_id, d.id } },
            { query = [[INSERT INTO component_market_inventory (market_id,asset_id,price,state,listed_at,seller_driver_id) VALUES ('base_market',?,?,'available',?,?)]],
                values = { a.asset_id, price, t, d.id } },
        })
        reply(pid, okT == true, okT and "LISTED" or "MARKET", okT and ("Listed on the Base Market for €$%d. You are paid when it sells."):format(price) or "Listing failed.")
        push(pid)
    end)
end)

-- ------------------------------------------------------------------------------------------------ the clock
NcmWorkshop = NcmWorkshop or {}   -- (a host test presets `stopClock` and calls resolveDue itself)
NcmWorkshop.resolveDue = function() return resolveDue() end
NcmWorkshop.snapshot = function(pid) return snapshot(pid) end
CreateThread(function()
    while not (MySQL and MySQL.isReady and MySQL.isReady()) do Wait(500) end
    Wait(8000)   -- after ncm_league's schema and ncm_world's design seed
    local okL, n = pcall(loadDesigns)
    log("ready (enabled=%s, time scale %.3f, %d bench slots; %s physical design(s) loaded)", tostring(set("workshopEnabled", true)),
        set("workshopTimeScale", 1), P.SLOTS, okL and tostring(n) or ("FAILED " .. tostring(n)))
    while not NcmWorkshop.stopClock do
        local okR, err = pcall(resolveDue)
        if not okR then log("scheduler failed: %s", tostring(err)) end
        Wait(5000)
    end
end)

RegisterCommand("ncm.workshop", function(src)
    if (tonumber(src) or 0) ~= 0 then return end
    local rows = MySQL.query.await("SELECT kind,state,COUNT(*) n FROM engineering_project WHERE server_id=? GROUP BY kind,state", { serverId() }) or {}
    for _, r in ipairs(rows) do log("%s %s: %s", r.kind, r.state, tostring(r.n)) end
end, false)
