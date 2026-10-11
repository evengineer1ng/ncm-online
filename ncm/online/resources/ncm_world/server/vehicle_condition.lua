-- The server's canonical vehicle damage follows the serialized Machine for the current Racing Week.
-- This is chassis/visual damage. Component exposure and repair remain owned by parts.wear.
NcmVehicleCondition = {}
local Json = NcmCore.get("vocabulary.json")
local Service = NcmCore.get("engineering.vehicle_service")
local Competency = NcmCore.get("engineering.competency")
local Ids = NcmCore.get("vocabulary.ids")
local Vehicles = NcmCore.get("data.vehicle_catalogue")
local Garages = NcmCore.get("paddock.garages")
local function now() return math.floor(Open77.time.unix()) end
local function serverId() local v = GlobalState.ncmIdentity; return v and v.serverId or "ncm-dev" end
local function dec(s) local ok, v = pcall(Json.decode, tostring(s or "")); return ok and type(v) == "table" and v or nil end
local function enc(v) local ok, s = pcall(Json.encode, v); return ok and s or nil end
local collapsing = false
AddEventHandler("ncm:week:collapse.begin", function() collapsing = true end)
AddEventHandler("ncm:week:collapse.abort", function() collapsing = false end)
AddEventHandler("ncm:week:collapsed", function() collapsing = false end)

local function snapshot(vehicleId)
    local id = tonumber(vehicleId) or vehicleId
    local okD, d = pcall(Open77.vehicles.getDamage, id)
    local okH, h = pcall(Open77.vehicles.getHealth, id)
    if not okD or type(d) ~= "table" or not okH or type(h) ~= "number" then return nil end
    if h ~= h or h < 0 or h > 1 then return nil end
    d.health = h
    return d
end

function NcmVehicleCondition.save(assetId, vehicleId)
    if collapsing then return false, "week_reset_in_progress" end
    local state = snapshot(vehicleId)
    if not state then return false, "damage_unreadable" end
    local json = enc(state)
    if not json then return false, "damage_unserializable" end
    MySQL.update.await([[INSERT INTO vehicle_week_condition (asset_id,server_id,damage_json,recorded_at)
        VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE server_id=VALUES(server_id),damage_json=VALUES(damage_json),recorded_at=VALUES(recorded_at)]],
        { assetId, serverId(), json, now() })
    return true
end

AddEventHandler("ncm:week:collapse.prepare", function()
    for _, cur in ipairs(NcmVehicleAccess and NcmVehicleAccess.liveAssets and NcmVehicleAccess.liveAssets() or {}) do
        local ok, result = pcall(NcmVehicleCondition.save, cur.assetId, cur.vehicleId)
        if not ok or result == false then print("[ncm_world/condition] pre-reset checkpoint failed: " .. tostring(cur.assetId)) end
    end
end)

function NcmVehicleCondition.restore(assetId, vehicleId)
    local row = MySQL.single.await("SELECT damage_json,repair_json FROM vehicle_week_condition WHERE asset_id=? AND server_id=?", { assetId, serverId() })
    if NcmHandling then NcmHandling.setRepair(assetId, row and dec(row.repair_json), false) end
    if not row or not row.damage_json then return true end
    local damage = dec(row.damage_json)
    if not damage then return false, "stored_damage_invalid" end
    local ok, applied = pcall(Open77.vehicles.setDamage, vehicleId, damage)
    -- Applied again once the car has streamed in: a set in the same tick as `create` lands on the server's record,
    -- but a client that already streamed the car keeps the engine's clean one -- the owner's car came back "100%
    -- damaged" and looked new (2026-10-09). Paint has the same two-pass fix in vehicle_access.lua.
    if ok and applied == true then
        CreateThread(function()
            for _, waitMs in ipairs({ 1500, 2500 }) do
                Wait(waitMs)
                if not (NcmVehicleAccess and NcmVehicleAccess.assetForVehicle
                    and NcmVehicleAccess.assetForVehicle(vehicleId) == assetId) then return end
                local okAgain, again = pcall(Open77.vehicles.setDamage, vehicleId, damage)
                print(("[ncm_world/condition] damage pass asset=%s ok=%s ret=%s"):format(tostring(assetId):sub(1, 8),
                    tostring(okAgain), tostring(again)))
            end
        end)
    end
    return ok and applied == true, ok and "damage_rejected" or tostring(applied)
end

AddEventHandler("onVehicleDamageChanged", function(vehicleId)
    local assetId = NcmVehicleAccess and NcmVehicleAccess.assetForVehicle and NcmVehicleAccess.assetForVehicle(vehicleId)
    if not assetId then return end
    CreateThread(function()
        local ok, why = pcall(NcmVehicleCondition.save, assetId, vehicleId)
        if not ok or why == false then print("[ncm_world/condition] damage checkpoint failed for " .. assetId .. ": " .. tostring(why)) end
    end)
end)

local repairBusy = {}
local function nearWorkshop(pid)
    local ok, player = pcall(Open77.players.get, pid)
    if not ok or type(player) ~= "table" or type(player.position) ~= "table" then return false end
    local pos = player.position
    for _, site in ipairs(Garages.sites()) do
        if (site.kind == "garage" or site.kind == "workshop") and Garages.distance(site,pos) <= 25
            and math.abs((tonumber(pos.z) or math.huge) - (tonumber(site.z) or 0)) <= 12 then return true end
    end
    return false
end
function NcmVehicleCondition.repair(pid, assetId, provider, requestKey)
    local profile = NcmIdentity.get(pid)
    if not profile then return nil, "no_driver" end
    if type(assetId) ~= "string" or #assetId ~= 36 then return nil, "bad_asset" end
    if provider ~= "self" and provider ~= "shop" then return nil, "bad_provider" end
    if type(requestKey) ~= "string" or #requestKey < 8 or #requestKey > 60 then return nil, "bad_request_key" end
    local idem = "vehicle_repair:" .. serverId() .. ":" .. requestKey
    local prior = MySQL.single.await("SELECT asset_id,provider,amount,workmanship_json FROM vehicle_repair WHERE idem_key=?", { idem })
    if prior then
        if prior.asset_id == assetId and prior.provider == provider then return prior end
        return nil, "idempotency_conflict"
    end
    if repairBusy[assetId] then return nil, "repair_busy" end
    repairBusy[assetId] = true
    local ok, result, why = pcall(function()
        local owned = MySQL.single.await("SELECT asset_id,vehicle_key FROM vehicle_asset WHERE asset_id=? AND server_id=? AND ncm_driver_id=?",
            { assetId, serverId(), profile.ncmDriverId })
        if not owned then return nil, "not_owned" end
        if provider == "self" and not nearWorkshop(pid) then return nil, "go_to_garage_workshop" end
        if NcmVehicleAccess and NcmVehicleAccess.liveAsset(assetId) then return nil, "store_vehicle_before_service" end
        local row = MySQL.single.await("SELECT damage_json FROM vehicle_week_condition WHERE asset_id=? AND server_id=?", { assetId, serverId() })
        local before = row and dec(row.damage_json)
        if not before then return nil, "no_damage_record" end
        local model = Vehicles.byKey(owned.vehicle_key)
        local value = 8000 * (model and tonumber(model.prestige) or 1)
        local quote, quoteWhy = Service.quote(before, provider, value)
        if not quote then return nil, quoteWhy end
        -- A bench operation occupies the mechanic for seconds; availability and components are the larger economy.
        Wait(quote.benchSeconds * 1000)
        if provider == "self" and not nearWorkshop(pid) then return nil, "left_workshop" end
        if NcmVehicleAccess and NcmVehicleAccess.liveAsset(assetId) then return nil, "vehicle_left_service_bay" end
        local skillState = Competency.newState()
        if provider == "self" then
            local skillRow = MySQL.single.await("SELECT state_json FROM driver_engineering WHERE server_id=? AND ncm_driver_id=?",
                { serverId(), profile.ncmDriverId })
            skillState = skillRow and dec(skillRow.state_json) or skillState
        end
        local skill = Competency.valueOf(skillState, "restoration")
        local after, work = Service.resolve(before, provider, skill, math.random, value)   -- one roll per section
        if provider == "self" then
            Competency.apply(skillState, { skillId="restoration", familyId="chassis", base=12,
                jobLevel=math.floor(quote.severity * 1000), completed=true })
        end
        local beforeJson, afterJson, workJson = enc(before), enc(after), enc(work)
        local stateJson = enc(skillState)
        if not beforeJson or not afterJson or not workJson or not stateJson then return nil, "serialization_failed" end
        local repairId = Ids.uuid4(function() return math.random() end)
        local t = now()
        local tx = {
            { query = [[INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,asset_id)
                SELECT ?,?,'vehicle_repair',-?,'eddies',?,'Vehicle service',?,? FROM DUAL
                WHERE (SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?) >= ?]],
                values = { profile.ncmDriverId,serverId(),quote.cost,assetId,idem,assetId,profile.ncmDriverId,serverId(),quote.cost } },
            { query = [[INSERT INTO vehicle_repair
                (repair_id,idem_key,server_id,asset_id,ncm_driver_id,provider,before_json,after_json,workmanship_json,amount,occurred_at)
                SELECT ?,?,?,?,?,?,?,?,?,?,? FROM DUAL WHERE EXISTS
                (SELECT 1 FROM ledger WHERE idem_key=? AND ncm_driver_id=? AND amount=?)]],
                values = { repairId,idem,serverId(),assetId,profile.ncmDriverId,provider,beforeJson,afterJson,workJson,quote.cost,t,
                    idem,profile.ncmDriverId,-quote.cost } },
            { query = [[UPDATE vehicle_week_condition c JOIN vehicle_repair r ON r.asset_id=c.asset_id AND r.idem_key=?
                SET c.damage_json=?,c.repair_json=?,c.recorded_at=? WHERE c.asset_id=? AND c.server_id=?]],
                values = { idem,afterJson,workJson,t,assetId,serverId() } },
        }
        if provider == "self" then tx[#tx + 1] = { query = [[INSERT INTO driver_engineering
            (server_id,ncm_driver_id,state_json,updated_at) SELECT ?,?,?,? FROM DUAL
            WHERE EXISTS(SELECT 1 FROM vehicle_repair WHERE idem_key=?)
            ON DUPLICATE KEY UPDATE state_json=VALUES(state_json),updated_at=VALUES(updated_at)]],
            values = { serverId(),profile.ncmDriverId,stateJson,t,idem } } end
        local committed, txWhy = MySQL.transaction.await(tx)
        if not committed then return nil, "repair_transaction:" .. tostring(txWhy) end
        local held = MySQL.single.await("SELECT asset_id,provider,amount,workmanship_json FROM vehicle_repair WHERE idem_key=?", { idem })
        if not held then return nil, "insufficient_funds" end
        if NcmHandling then NcmHandling.setRepair(assetId, work, true) end
        return held
    end)
    repairBusy[assetId] = nil
    if not ok then return nil, tostring(result) end
    return result, why
end

-- Older paid jobs recorded partial chassis relief. Remove only that residual from the latest job;
-- damage acquired afterward remains. Never carry a correction across a completed Week reset.
CreateThread(function()
    Wait(5000)
    local ok, err = pcall(function()
        local rows = MySQL.query.await([[SELECT r.repair_id,r.asset_id,r.after_json,r.workmanship_json,
            c.damage_json FROM vehicle_repair r
            JOIN vehicle_week_condition c ON c.asset_id=r.asset_id AND c.server_id=r.server_id
            LEFT JOIN vehicle_repair_correction fix ON fix.repair_id=r.repair_id
            WHERE r.server_id=? AND r.repair_id=(SELECT r2.repair_id FROM vehicle_repair r2
                WHERE r2.asset_id=r.asset_id AND r2.server_id=r.server_id
                ORDER BY r2.occurred_at DESC,r2.repair_id DESC LIMIT 1)
                AND fix.repair_id IS NULL AND c.damage_json IS NOT NULL
                AND r.occurred_at > COALESCE((SELECT MAX(w.finished_at) FROM racing_week_collapse w
                    WHERE w.server_id=r.server_id AND w.mode='live' AND w.state='done'),0)]], { serverId() }) or {}
        for _, row in ipairs(rows) do
            local old, current = dec(row.after_json), dec(row.damage_json)
            if old and current and Service.severity(old)>0 then
                local work = dec(row.workmanship_json) or {}
                work.relief = 1
                work.scalars = Service.scalarsFromSetup(work.setup)
                local restored = Service.correctPaidResidual(current, old)
                local nextDamage, nextWork = enc(restored), enc(work)
                if nextDamage and nextWork then
                    local committed = MySQL.transaction.await({
                        { query = [[UPDATE vehicle_week_condition SET damage_json=?,repair_json=?,recorded_at=?
                            WHERE asset_id=? AND server_id=? AND damage_json=?]],
                          values = { nextDamage,nextWork,now(),row.asset_id,serverId(),row.damage_json } },
                        { query = [[INSERT INTO vehicle_repair_correction
                            (repair_id,server_id,asset_id,old_json,new_json,corrected_at)
                            SELECT ?,?,?,?,?,? FROM vehicle_week_condition WHERE asset_id=? AND server_id=?
                            AND damage_json=?]],
                          values = { row.repair_id,serverId(),row.asset_id,row.damage_json,nextDamage,now(),
                            row.asset_id,serverId(),nextDamage } },
                    })
                    if committed then print("[ncm_world/condition] corrected paid repair " .. row.repair_id) end
                end
            end
        end
    end)
    if not ok then print("[ncm_world/condition] paid repair reconciliation failed: " .. tostring(err)) end
end)

-- ------------------------------------------------------------------------------------------- the Engineering panel
-- `ncm_engineering`'s SERVICE tab (owner 2026-10-09: service and parts leave Machine Index, which is for observing
-- discoveries). One small reply per request: every Machine this Driver owns, its Week condition by area, both
-- quotes, where the nearest workshop is, and the last job's per-section workmanship.
local function nearestSite(pid)
    local ok, player = pcall(Open77.players.get, pid)
    if not ok or type(player) ~= "table" or type(player.position) ~= "table" then return nil end
    local pos, best = player.position, nil
    for _, site in ipairs(Garages.sites()) do
        if site.kind == "garage" or site.kind == "workshop" then
            local d = Garages.distance(site, pos)
            if not best or d < best.distance then
                best = { siteId = site.id, label = Garages.label(site), distance = math.floor(d + 0.5), x = site.x, y = site.y, z = site.z,
                    usable = d <= 25 and math.abs((tonumber(pos.z) or math.huge) - (tonumber(site.z) or 0)) <= 12 }
            end
        end
    end
    return best
end

function NcmVehicleCondition.serviceView(pid)
    local profile = NcmIdentity.get(pid)
    if not profile then return nil, "no_driver" end
    local rows = MySQL.query.await([[SELECT a.asset_id,a.vehicle_key,c.damage_json,c.repair_json FROM vehicle_asset a
        LEFT JOIN vehicle_week_condition c ON c.asset_id=a.asset_id AND c.server_id=a.server_id
        WHERE a.server_id=? AND a.ncm_driver_id=? ORDER BY a.asset_id]], { serverId(), profile.ncmDriverId }) or {}
    local bal = MySQL.single.await("SELECT COALESCE(SUM(amount),0) AS b FROM ledger WHERE ncm_driver_id=? AND server_id=?",
        { profile.ncmDriverId, serverId() })
    local skillRow = MySQL.single.await("SELECT state_json FROM driver_engineering WHERE server_id=? AND ncm_driver_id=?",
        { serverId(), profile.ncmDriverId })
    local skill = Competency.valueOf(skillRow and dec(skillRow.state_json) or Competency.newState(), "restoration")
    local cars = {}
    for _, row in ipairs(rows) do
        local model = Vehicles.byKey(row.vehicle_key)
        local value = 8000 * (model and tonumber(model.prestige) or 1)
        local damage = row.damage_json and dec(row.damage_json) or nil
        local work = row.repair_json and dec(row.repair_json) or nil
        local live = NcmVehicleAccess and NcmVehicleAccess.liveAsset and NcmVehicleAccess.liveAsset(row.asset_id)
        cars[#cars + 1] = {
            assetId = row.asset_id, vehicleKey = row.vehicle_key,
            name = model and (model.displayName or model.name) or row.vehicle_key,
            maker = model and model.manufacturer or nil,
            stored = not live,
            severity = damage and Service.severity(damage) or 0,
            areas = damage and Service.breakdown(damage) or nil,
            selfQuote = damage and Service.quote(damage, "self", value) or nil,
            shopQuote = damage and Service.quote(damage, "shop", value) or nil,
            work = work and { grade = work.grade, provider = work.provider, sections = work.sections, scalars = work.scalars } or nil,
        }
    end
    return { cars = cars, balance = tonumber(bal and bal.b) or 0, skill = skill, site = nearestSite(pid), serverNow = now() }
end

RegisterNetEvent("ncm:eng.service.request", function()
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    CreateThread(function()
        local ok, view, why = pcall(NcmVehicleCondition.serviceView, pid)
        if not ok then print("[ncm_world/condition] service view failed: " .. tostring(view)) return end
        TriggerClientEvent("ncm:eng.service", pid, view or { cars = {}, error = tostring(why) })
    end)
end)

RegisterNetEvent("ncm:vehicle.repair", function(assetId, provider, requestKey)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    CreateThread(function()
        local result, why = NcmVehicleCondition.repair(pid, assetId, provider, requestKey)
        local message = result and ("Vehicle serviced for €$%d. %s work recorded."):format(tonumber(result.amount) or 0,
            provider == "self" and "Your" or "Shop") or tostring(why)
        local work = result and dec(result.workmanship_json) or nil
        if work then message = message .. (" Chassis restored; %s handling workmanship."):format(tostring(work.grade)) end
        TriggerClientEvent("ncm:vehicle.repair.result", pid, { ok = result ~= nil, message = message,
            assetId = assetId, workmanship = work })
        pcall(Open77.notifications.send, pid, { type=result and "success" or "error",
            title=result and "SERVICE COMPLETE" or "SERVICE REFUSED", message=message, icon="NCM", durationMs=6500 })
    end)
end)
