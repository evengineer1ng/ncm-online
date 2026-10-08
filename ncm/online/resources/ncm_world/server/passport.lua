-- ncm_world / server / passport -- L336: THE MACHINE PASSPORT on the server.
--
-- Every Machine gets one host-independent passport (core machine.passport: its catalogue seed, its live paint, its
-- installed parts), persisted in machine_passport. Every host that expresses it asks ONE question --
-- `NcmPassport.express(assetId, host, catalogue)` -- answered by core machine.correspondence and remembered in
-- machine_expression: sticky, changed only by a recorded revision (machine_expression_history). There is no host-to-host
-- mapping here or anywhere.
--
-- Hosts so far: Assetto Corsa (its roster comes from the host bridge's scan, `/ac/roster`). KSA bodies and GTA next.
NcmPassport = {}

local P = NcmCore.get("machine.passport")
local X = NcmCore.get("machine.correspondence")
local Json = NcmCore.get("vocabulary.json")
local BRIDGE = "http://127.0.0.1:47710"

local function log(fmt, ...) print(("[ncm_world/passport] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end

--- The Machine's passport, built fresh from what NCM knows now and persisted (the stored one is the record, not a cache).
function NcmPassport.forAsset(assetId)
    local row = MySQL.single.await("SELECT asset_id, vehicle_key, record, paint_primary, paint_secondary FROM vehicle_asset WHERE asset_id=?", { assetId })
    if not row then return nil, "unknown Machine" end
    local paint = nil
    local okCfg, Config = pcall(function() return NcmCore.get("data.vehicle_config") end)
    if okCfg and Config then
        local p = Config.paintFor(row.vehicle_key, assetId, { primary = row.paint_primary, secondary = row.paint_secondary })
        if p and p.primary then paint = { p.primary.r, p.primary.g, p.primary.b } end
    end
    local Pool = NcmCore.get("data.vehicle_pool")
    local pe = Pool and Pool.byRecord and Pool.byRecord(row.record) or nil
    local added = 0
    if NcmEngineering and NcmEngineering.addedMassKg then added = NcmEngineering.addedMassKg(assetId) or 0 end
    -- the livery this machine's record carries (data.liveries, L338): Kimiko is an appearance of the RB15, not another model
    local livery = nil
    local okL, Liveries = pcall(function() return NcmCore.get("data.liveries") end)
    if okL and Liveries then livery = Liveries.appearance(Liveries.fromRecord(row.record)) end
    local pass = P.forMachine(row.vehicle_key, assetId, { paint = paint, tags = pe and pe.tags, prestige = pe and pe.prestige,
        addedMassKg = added, livery = livery })
    local ok, text = pcall(Json.encode, pass)
    if ok then
        MySQL.update.await([[INSERT INTO machine_passport (asset_id, passport_json, version, updated_at) VALUES (?,?,?,?)
            ON DUPLICATE KEY UPDATE passport_json=VALUES(passport_json), version=VALUES(version), updated_at=VALUES(updated_at)]],
            { assetId, text, P.version, now() })
    end
    return pass
end

--- The body that expresses a Machine in `host`, chosen from `catalogue` ({ { id, passport, variants } }), sticky.
--- Returns { id, variant, score, tier, reason, revision }.
function NcmPassport.express(assetId, host, catalogue)
    local pass, why = NcmPassport.forAsset(assetId)
    if not pass then return nil, why end
    local prior = MySQL.single.await("SELECT expression_id, variant, correspondence, revision FROM machine_expression WHERE asset_id=? AND host=?", { assetId, host })
    local priorT = prior and { id = prior.expression_id, revision = tonumber(prior.revision) or 1 } or nil
    local t = now()
    local choice, rev = X.decide(pass, catalogue, priorT, nil, t)
    if not choice then return nil, "no candidates in " .. host end
    local variant = choice.variant and choice.variant.id or nil
    MySQL.update.await([[INSERT INTO machine_expression (asset_id, host, expression_id, variant, correspondence, tier, reason, revision, established_at)
        VALUES (?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE expression_id=VALUES(expression_id), variant=VALUES(variant),
        correspondence=VALUES(correspondence), tier=VALUES(tier), reason=VALUES(reason), revision=VALUES(revision),
        established_at=IF(revision<>VALUES(revision), VALUES(established_at), established_at)]],
        { assetId, host, choice.id, variant or "", choice.score, choice.tier, choice.reason:sub(1, 500), choice.revision or 1, t })
    if rev then
        if rev.from == nil then
            MySQL.insert.await([[INSERT INTO machine_expression_history (asset_id, host, from_id, to_id, to_score, why, revision, at)
                VALUES (?,?,NULL,?,?,?,?,?)]], { assetId, host, rev.to, rev.toScore or 0, rev.why, choice.revision or 1, t })
        else
            MySQL.insert.await([[INSERT INTO machine_expression_history (asset_id, host, from_id, to_id, to_score, why, revision, at)
                VALUES (?,?,?,?,?,?,?,?)]], { assetId, host, rev.from, rev.to, rev.toScore or 0, rev.why, choice.revision or 1, t })
        end
        log("EXPRESSION ..%s in %s: %s -> %s (%.2f, %s) | %s", tostring(assetId):sub(-6), host, tostring(rev.from or "-"), choice.id,
            choice.score, choice.tier, rev.why)
    end
    log("EXPRESS ..%s in %s: %s skin %s | %.2f %s | %s%s", tostring(assetId):sub(-6), host, choice.id, tostring(variant), choice.score,
        choice.tier, choice.reason, choice.kept and " (kept)" or "")
    return choice
end

-- ------------------------------------------------------------------------------------------------ Assetto Corsa
-- The roster the bridge scanned (ui_car.json + skin colours), as passports. Built once, refreshed hourly.
local acCatalogue, acAt = nil, 0
local function buildAc(list)
    local cat = {}
    for i, c in ipairs(list or {}) do
        cat[#cat + 1] = { id = c.id, passport = P.fromAc(c.id, c.ui or {}), variants = c.skins or {} }
        if i % 25 == 0 then Wait(0) end
    end
    return cat
end

--- The AC catalogue, from the bridge (nil when the bridge has not scanned yet or is unreachable).
function NcmPassport.acCatalogue()
    if acCatalogue and now() - acAt < 3600 then return acCatalogue end
    local r, t0 = nil, now()
    PerformHttpRequest(BRIDGE .. "/ac/roster", function(code, text) r = { code = code, text = text } end, "GET", "", {})
    while not r and now() - t0 < 10 do Wait(50) end
    r = r or { code = "timeout" }
    if tonumber(r.code) ~= 200 then log("AC roster unavailable from the bridge (%s)", tostring(r.code)); return acCatalogue end
    local ok, list = pcall(Json.decode, tostring(r.text or "[]"))
    if not ok or type(list) ~= "table" or #list == 0 then return acCatalogue end
    acCatalogue, acAt = buildAc(list), now()
    log("AC roster: %d cars as passports", #acCatalogue)
    return acCatalogue
end

-- ------------------------------------------------------------------------------------------------ Kitten Space Agency
-- KSA's expressions are NCM's own craft (ncm/ksa/NcmKsa/vehicles): a small bank of archetypes, each with a passport.
-- The Hella first; an unseeded Machine gets the nearest archetype, never a refusal.
local ksaCatalogue = nil
local function ksaBank()
    if not ksaCatalogue then
        ksaCatalogue = { { id = "NcmHella", passport = P.forMachine("archer_hella", nil, {}) } }   -- cross-scope-ok: a KSA craft id
    end
    return ksaCatalogue
end

--- The KSA craft for a Machine: { body, why, correspondence, revision, tier } (nil when it cannot be decided).
function NcmPassport.expressKsa(assetId)
    if not assetId then return nil end
    local ok, choice = pcall(NcmPassport.express, assetId, "ksa", ksaBank())
    if not ok or not choice then log("KSA expression failed for ..%s: %s", tostring(assetId):sub(-6), tostring(choice)); return nil end
    return { body = choice.id, why = choice.reason, correspondence = choice.score, revision = choice.revision, tier = choice.tier }
end

--- The Assetto Corsa body for a Machine: { car, skin, why, correspondence, revision, tier } (nil = use the old table).
function NcmPassport.expressAc(assetId)
    local cat = NcmPassport.acCatalogue()
    if not cat or #cat == 0 or not assetId then return nil end
    local ok, choice = pcall(NcmPassport.express, assetId, "assetto_corsa", cat)
    if not ok or not choice then log("AC expression failed for ..%s: %s", tostring(assetId):sub(-6), tostring(choice)); return nil end
    return { car = choice.id, skin = choice.variant and choice.variant.id or nil, why = choice.reason, correspondence = choice.score,
        revision = choice.revision, tier = choice.tier, mapVersion = "passport-" .. P.version }
end

-- a claimed machine (ncm_league ownership.claim, L338) gets its passport at once: its livery, its model, what the host says
AddEventHandler("ncm:host:claimed", function(_, _, assetId) if assetId then pcall(NcmPassport.forAsset, assetId) end end)
