-- ncm_league / server / gearbox -- every machine's gearbox, stamped at birth and never rewritten (L306).
--
-- The arithmetic is core `machine.gearbox`; this file is its persistence. A car is born automatic or manual
-- (`gearbox_*` on `vehicle_asset`, schema 063): a factory roll from its model's mix, deterministic in its assetId, or
-- an explicit spec for a grant. Every surface that offers a car names its gearbox (`NcmGearbox.label`).
--
-- MANUALS ARE MANUALS where NCM Gearbox is a required mod (development and online; owner 2026-10-08: "if car has
-- manual gearbox it is manual"): manual clones spawn and manual stock is sold. Anywhere else manual stock is listed as
-- arriving, never sold: nobody may own a manual that cannot spawn as one. `ncm_gearbox_manual_sales` true/false
-- overrides.
NcmGearbox = {}

local Gearbox = NcmCore.get("machine.gearbox")
local Catalogue = NcmCore.get("data.vehicle_catalogue")
local function log(fmt, ...) print(("[ncm_league/gearbox] " .. fmt):format(...)) end
local function serverId() return NcmCalendar.serverId() end
local function now() return math.floor(Open77.time.unix()) end

local cache = {}                  -- assetId -> gearbox (a stamped gearbox never changes, so it never goes stale)

--- The worlds that require NCM Gearbox, so a manual there always drives as one.
local function gearboxWorld()
    local env = NcmCalendar and NcmCalendar.environment and NcmCalendar.environment() or "unknown"
    return env == "development" or env == "online"
end

function NcmGearbox.manualSales()
    local set = GetConvar and GetConvar("ncm_gearbox_manual_sales", "") or ""
    if set == "true" or set == "false" then return set == "true" end
    return gearboxWorld()
end

--- The gearbox a new machine is born with: `spec` given (a grant), else the model's factory roll.
function NcmGearbox.birth(assetId, vehicleKey, spec)
    if spec then
        local s = Gearbox.spec(spec)
        if s then return { kind = s.kind, spec = s.id, source = Gearbox.SOURCE_FACTORY } end
    end
    local entry = Catalogue.byKey(vehicleKey)
    return Gearbox.factoryRoll(assetId, vehicleKey, entry and entry.category)
end

--- The four column values for an INSERT, in schema order: kind, spec, source, at.
function NcmGearbox.columns(gb)
    return gb.kind, gb.spec, gb.source, now()
end

--- An asset's gearbox. An unstamped row reads as automatic (a mint path that forgot to stamp is a bug, logged once).
local warned = {}
function NcmGearbox.of(assetId)
    if type(assetId) ~= "string" then return Gearbox.preGearbox() end
    local gb = cache[assetId]
    if gb then return gb end
    local ok, row = pcall(MySQL.single.await,
        "SELECT gearbox_kind, gearbox_spec, gearbox_source FROM vehicle_asset WHERE asset_id = ?", { assetId })
    gb = ok and Gearbox.fromRow(row) or nil
    if not gb then
        if ok and row and not warned[assetId] then warned[assetId] = true; log("asset %s has no gearbox stamped -- reads as automatic", assetId:sub(1, 8)) end
        return Gearbox.preGearbox()
    end
    cache[assetId] = gb
    return gb
end

--- Remember a gearbox read in a bulk query (listings), so the next `of` is free.
function NcmGearbox.remember(assetId, row)
    local gb = Gearbox.fromRow(row)
    if gb and assetId then cache[assetId] = gb end
    return gb
end

function NcmGearbox.label(displayName, gb) return Gearbox.label(displayName, gb) end

--- Unsold stock from before schema 063: rolled once from the factory mix, guarded so a stamp is never rewritten.
function NcmGearbox.backfillShelf()
    local rows = MySQL.query.await([[SELECT asset_id, vehicle_key FROM vehicle_asset
        WHERE server_id = ? AND gearbox_kind IS NULL AND ncm_driver_id IS NULL AND owner_principal_kind IS NULL]],
        { serverId() }) or {}
    local manual = 0
    for i, r in ipairs(rows) do
        local gb = NcmGearbox.birth(r.asset_id, r.vehicle_key)
        MySQL.update.await([[UPDATE vehicle_asset SET gearbox_kind = ?, gearbox_spec = ?, gearbox_source = ?, gearbox_at = ?
            WHERE asset_id = ? AND gearbox_kind IS NULL]], { gb.kind, gb.spec, gb.source, now(), r.asset_id })
        if gb.kind == Gearbox.MANUAL then manual = manual + 1 end
        if i % 50 == 0 then Wait(0) end
    end
    log("shelf stock stamped: %d car(s), %d manual; manual sales %s", #rows, manual, NcmGearbox.manualSales() and "OPEN" or "gated (arriving)")
end

RegisterCommand("ncm.gearbox", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    -- `ncm.gearbox clones on|off`: spawn manual assets as their gearbox clones (L306 phase 3). Server-wide and in memory
    -- (SetConvar); only switch it on where every client that will drive a manual has NCM Gearbox installed.
    if args and args[1] == "clones" and (args[2] == "on" or args[2] == "off") then
        local ok = pcall(SetConvar, "ncm_gearbox_spawn_clones", args[2] == "on" and "true" or "false")
        pcall(Open77.kvp.set, "gearbox.clones", args[2] == "on")   -- remembered across restarts
        log("manual clones %s (ncm_gearbox_spawn_clones = %s)%s", args[2] == "on" and "ON" or "OFF",
            tostring(GetConvar and GetConvar("ncm_gearbox_spawn_clones", "false")), ok and "" or " -- SetConvar refused")
        return
    end
    -- `ncm.gearbox refit <assetId or its first 8+ chars> <spec>`: replace one car's stamped gearbox (owner, 2026-10-04:
    -- "can you make it a seven speed"). Console only. Refused unless the spec has a clone for that model
    -- (`Gearbox.cloneSpecs`: its factory mix plus `Gearbox.REFIT`), so a refitted car can always spawn. Takes effect on
    -- the car's next spawn.
    if args and args[1] == "refit" then
        local key, specId = tostring(args[2] or ""), tostring(args[3] or "")
        if #key < 8 then log("refit: give the assetId (or at least its first 8 characters) and a spec, e.g. ncm.gearbox refit 1a2b3c4d m7"); return end
        local rows = MySQL.query.await([[SELECT asset_id, vehicle_key, gearbox_spec FROM vehicle_asset
            WHERE server_id = ? AND asset_id LIKE ?]], { serverId(), key .. "%" }) or {}
        if #rows ~= 1 then log("refit: %d car(s) match '%s' -- need exactly one", #rows, key); return end
        local r = rows[1]
        local entry = Catalogue.byKey(r.vehicle_key)
        local s = Gearbox.spec(specId)
        local fits = false
        if s and s.kind == Gearbox.AUTOMATIC then fits = true end
        for _, id in ipairs(Gearbox.cloneSpecs(r.vehicle_key, entry and entry.category)) do if id == specId then fits = true end end
        if not fits then
            log("refit: %s has no %s clone (fits: a, %s)", tostring(r.vehicle_key), specId,
                table.concat(Gearbox.cloneSpecs(r.vehicle_key, entry and entry.category), ", "))
            return
        end
        MySQL.update.await([[UPDATE vehicle_asset SET gearbox_kind = ?, gearbox_spec = ?, gearbox_source = ?, gearbox_at = ?
            WHERE asset_id = ?]], { s.kind, s.id, Gearbox.SOURCE_REFIT, now(), r.asset_id })
        cache[r.asset_id] = nil
        log("refit: %s (%s) %s -> %s (%s); takes effect on its next spawn", r.asset_id:sub(1, 8), tostring(r.vehicle_key),
            tostring(r.gearbox_spec), s.id, Gearbox.describe({ kind = s.kind, spec = s.id }))
        return
    end
    -- `ncm.gearbox find <vehicleKey>`: the owned cars of a model with their gearbox, to pick an assetId for a refit
    if args and args[1] == "find" and args[2] then
        local rows = MySQL.query.await([[SELECT asset_id, gearbox_spec, gearbox_source, ncm_driver_id, owner_principal_kind
            FROM vehicle_asset WHERE server_id = ? AND vehicle_key = ? AND (ncm_driver_id IS NOT NULL OR owner_principal_kind IS NOT NULL)]],
            { serverId(), tostring(args[2]) }) or {}
        for _, r in ipairs(rows) do
            log("%s  %-4s %-12s driver=%s owner=%s", tostring(r.asset_id), tostring(r.gearbox_spec), tostring(r.gearbox_source),
                tostring(r.ncm_driver_id), tostring(r.owner_principal_kind))
        end
        log("find %s: %d owned car(s)", tostring(args[2]), #rows)
        return
    end
    local rows = MySQL.query.await([[SELECT vehicle_key, gearbox_kind, gearbox_spec, gearbox_source, COUNT(*) n,
        SUM(ncm_driver_id IS NULL AND owner_principal_kind IS NULL) shelf
        FROM vehicle_asset WHERE server_id = ? GROUP BY vehicle_key, gearbox_kind, gearbox_spec, gearbox_source
        ORDER BY vehicle_key, gearbox_spec]], { serverId() }) or {}
    for _, r in ipairs(rows) do
        log("%-24s %-10s %-4s %-12s %4d (shelf %d)", tostring(r.vehicle_key), tostring(r.gearbox_kind),
            tostring(r.gearbox_spec), tostring(r.gearbox_source), tonumber(r.n) or 0, tonumber(r.shelf) or 0)
    end
    log("manual sales %s (convar ncm_gearbox_manual_sales)", NcmGearbox.manualSales() and "OPEN" or "gated")
end, false)

-- Manual clones at boot (owner, 2026-10-04: "its dev server its ok" -- no console command every session): a saved
-- `ncm.gearbox clones on|off` wins; otherwise ON where NCM Gearbox is required (development, online), OFF elsewhere.
CreateThread(function()
    Wait(1000)
    local okK, saved = pcall(Open77.kvp.get, "gearbox.clones")
    local env = NcmCalendar and NcmCalendar.environment and NcmCalendar.environment() or "online"
    local on
    if okK and type(saved) == "boolean" then on = saved else on = gearboxWorld() end
    pcall(SetConvar, "ncm_gearbox_spawn_clones", on and "true" or "false")
    log("manual clones %s at boot (%s)", on and "ON" or "OFF", (okK and type(saved) == "boolean") and "saved setting" or ("default for " .. tostring(env)))
end)
