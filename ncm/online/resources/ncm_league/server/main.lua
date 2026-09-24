-- ncm_league / server — v0 (WP M0.2): database readiness + schema migrations. League logic arrives in M3/M4.
local LEAGUE_VERSION = "0.1.0"
local Core = NcmCore

local function log(fmt, ...)
    print(("[ncm_league] " .. fmt):format(...))
end

local dbState = { ready = false, reason = nil, migrated = nil }

AddEventHandler("onResourceStart", function(name)
    if name ~= "ncm_league" then return end
    log("started v%s | ncm-core %s | schema entries %d", LEAGUE_VERSION, Core.VERSION, #(NcmSchema or {}))
    local isReady, why = MySQL.isReady()
    log("database.isReady at start -> %s (%s)", tostring(isReady), tostring(why))
    local queued, reason = MySQL.ready(function()
        dbState.ready = true
        local v = MySQL.scalar.await("SELECT VERSION()")
        log("database reachable: server version %s", tostring(v))
        local n, err = NcmMigrations.apply()
        dbState.migrated = n
        if n == nil then
            log("migrations failed: %s", tostring(err))
        else
            log("migrations: %d applied; %s", n, NcmMigrations.describe(NcmMigrations.status()))
            NcmOrganized.seedTeams()
            if NcmCompetition and NcmCompetition.seed then NcmCompetition.seed() end
            -- KB-30/D7: class ceilings go out on GlobalState so every client, present and future, caps itself.
            if NcmCompetition and NcmCompetition.publishCeilings then NcmCompetition.publishCeilings() end
            if NcmWeather and NcmWeather.start then
                local weatherOk, weatherWhy = NcmWeather.start()
                if not weatherOk then log("weather service unavailable: %s", tostring(weatherWhy)) end
            end
            if NcmCollection and NcmCollection.start then
                local collectionOk, collectionWhy = NcmCollection.start()
                if not collectionOk then log("vehicle collection unavailable: %s", tostring(collectionWhy)) end
            end
            -- Before anything can manufacture: give existing assets the provenance they always had.
            -- This must precede production so the sequences start after real history rather than at 1.
            if NcmProvenance and NcmProvenance.backfill then
                local n, why = NcmProvenance.backfill()
                if n == nil then log("provenance backfill refused: %s", tostring(why))
                elseif n > 0 then log("provenance backfill: %d asset(s) numbered", n) end
            end
            if NcmMarket and NcmMarket.seed then
                local marketOk, marketWhy = NcmMarket.seed()
                if not marketOk then log("market unavailable: %s", tostring(marketWhy)) end
                -- **IDEA-319: number the founding stock BEFORE production can tick.**
                --
                -- The backfill above runs before the seed, so on a first-ever boot it finds nothing: the
                -- bootstrap machines do not exist yet. They are then inserted with NULL ordinals, production
                -- mints with ordinals taken at mint time, and only a LATER boot numbers the founding stock --
                -- after the machines built on top of it. Measured on Development: the three founding market
                -- machines carry NCM #16/#17/#18 and the LAST model ordinal in each line, despite being the
                -- first machines that ever existed. Online is correct only by accident of ordering.
                --
                -- Numbering here is idempotent (`backfill` touches only `production_ordinal IS NULL`) and
                -- costs one no-op query on every later boot. It does NOT renumber anything: ordinals are
                -- append-only and immutable (IDEA-226/L119), so worlds that already mis-ordered keep what
                -- they were given. This fixes the next fresh world, not the past.
                if marketOk and NcmProvenance and NcmProvenance.backfill then
                    local n, why = NcmProvenance.backfill()
                    if n == nil then log("founding-stock numbering refused: %s", tostring(why))
                    elseif n > 0 then log("founding stock numbered before first production: %d asset(s)", n) end
                end
                -- Production starts only after the seed, so a first-ever boot establishes the bootstrap
                -- shelf before the first tick measures it. Starting them the other way round would have the
                -- first tick see an empty market and manufacture stock the seed was about to insert.
                if marketOk and NcmMarket.start then NcmMarket.start() end
            end
            NcmCalendar.start(NcmPackStreet.series)
            NcmRace.start()
            pcall(NcmRecords.refresh)
        end
    end)
    if not queued then
        dbState.reason = reason
        log("MySQL.ready refused: %s (database bridge disabled or unreachable; migrations skipped)", tostring(reason))
    end
end)

RegisterCommand("ncm.db.status", function(source)
    CreateThread(function()
        local isReady, why = MySQL.isReady()
        if not isReady then
            log("db.status: not ready (%s); start-time refusal=%s", tostring(why), tostring(dbState.reason))
            return
        end
        local ok, st = pcall(NcmMigrations.status)
        if not ok then log("db.status: error %s", tostring(st)); return end
        local tables = MySQL.query.await("SHOW TABLES") or {}
        local names = {}
        for _, row in ipairs(tables) do for _, v in pairs(row) do names[#names + 1] = tostring(v) end end
        table.sort(names)
        log("db.status: ready; %s; tables=[%s]", NcmMigrations.describe(st), table.concat(names, ","))
    end)
end, false)

RegisterCommand("ncm.db.migrate", function(source)
    CreateThread(function()
        local isReady, why = MySQL.isReady()
        if not isReady then log("db.migrate: not ready (%s)", tostring(why)); return end
        local n, err = NcmMigrations.apply()
        log("db.migrate: %s", n and (tostring(n) .. " applied") or ("failed: " .. tostring(err)))
    end)
end, false)
