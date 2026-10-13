-- ncm-core module: competition.class
-- A class is which cars may enter and their balance-of-performance ceiling (L52, P38): the ceiling is applied by
-- the host with `setPerformance` per vehicle instance at issue time; the base car stays the inert record.
local Core = NcmCore

Core.define("competition.class", function(C)
    local M = { version = "0.0.1" }
    local Teams = C.get("competition.teams")
    local Pool = C.get("data.vehicle_pool")

    local function rb15Records()
        local out = { "Vehicle.v_sport1_rb15_f1" }
        for _, t in ipairs(Teams.NCX) do out[#out + 1] = Teams.liveryRecord(t.teamId) end
        return out
    end

    local function poolRecords(classes)
        local out = {}
        for _, cls in ipairs(classes) do
            for _, r in ipairs(Pool.records(cls)) do out[#out + 1] = r.id end
        end
        return out
    end

    M.LIST = {
        { id = "street_open", name = "Street (open)", packId = "ncm_pack_street", topSpeedKph = 0, accelScale = 1.0, taperKph = 12,
          records = "any", enabled = true },
        { id = "street_sport", name = "Street Sport", packId = "ncm_pack_street", topSpeedKph = 0, accelScale = 1.0, taperKph = 12,
          records = poolRecords({ "Sport", "Muscle" }), enabled = true },
        -- KB-30 / D7 / L77: the RB15 collapses from ~360 km/h to ~60 km/h, deterministically -- an engine limit
        -- NCM does not expect to be fixed. The ceiling is the permanent answer, not a stopgap, and the owner set
        -- it at 355 after measuring the cliff live (2026-09-22). The taper rolls throttle off before the cliff
        -- rather than at it, so the car never reaches the failure point under power.
        --
        -- **DISABLED 2026-09-26 (`KB-144`): the RB15 was withdrawn over licensing and is no longer installed.**
        -- This class was the ONLY producer of record ceilings, so `recordCeilings()` was publishing eleven
        -- entries for records that do not exist on any client -- which is why, the moment the `KB-136`
        -- transport was fixed, every client refused all eleven (154 attempts, zero applied). The ceilings
        -- were not broken; their target was gone. The definition is kept rather than deleted because the
        -- measurement behind it is real and would have to be redone if the car ever returns.
        { id = "ncx_rb15", name = "NCX Formula (RB15)", packId = "ncm_pack_ncx", topSpeedKph = 355, accelScale = 1.0, taperKph = 20,
          records = rb15Records(), enabled = false },
        { id = "kart", name = "Kart Cup", packId = "ncm_pack_street", topSpeedKph = 120, accelScale = 1.0, taperKph = 8,
          records = {}, enabled = false },
    }

    local byId
    function M.byId(id)
        if not byId then byId = {}; for _, c in ipairs(M.LIST) do byId[c.id] = c end end
        return byId[id]
    end

    --- The `setPerformance` profile for a class, or nil when the class sets no ceiling.
    function M.performance(id)
        local c = M.byId(id)
        if not c or (c.topSpeedKph or 0) <= 0 then return nil end
        return { topSpeedKph = c.topSpeedKph, accelerationScale = c.accelScale or 1.0, taperKph = c.taperKph or 12 }
    end

    --- Every class ceiling as { record -> profile }, for a host that applies the governor per vehicle RECORD.
    --- Only classes that actually set a ceiling appear; a class with `records = "any"` cannot be expressed this
    --- way and is skipped (it has no ceiling today, and an open class capping every car in Night City would be
    --- exactly the wrong reading of L52).
    function M.recordCeilings()
        local out = {}
        for _, c in ipairs(M.LIST) do
            local prof = c.enabled and M.performance(c.id) or nil
            if prof and type(c.records) == "table" then
                for _, record in ipairs(c.records) do out[record] = prof end
            end
        end
        return out
    end

    --- May this record enter the class?
    function M.eligible(id, record)
        local c = M.byId(id)
        if not c then return false, "unknown_class" end
        if c.records == "any" then
            if Pool.isAerial(record) then return false, "aerial" end   -- open to every street car, never a flight machine
            return true
        end
        for _, r in ipairs(c.records) do if r == record then return true end end
        return false, "record_not_in_class"
    end

    --- Rows for persistence: { classId, record, eligible }.
    function M.vehicleRows()
        local out = {}
        for _, c in ipairs(M.LIST) do
            if type(c.records) == "table" then
                for _, r in ipairs(c.records) do out[#out + 1] = { classId = c.id, record = r, eligible = true } end
            end
        end
        return out
    end

    return M
end)
