-- ncm_league migration runner. Applies every entry of NcmSchema (registered by server/schema/*.lua,
-- loaded earlier in manifest order) whose version is not yet in schema_migrations. Idempotent:
-- a second run applies nothing. Statements of one migration run inside one transaction where the
-- bridge allows it; the version row is written in the same transaction.
NcmMigrations = {}

local function log(fmt, ...)
    print(("[ncm_league/db] " .. fmt):format(...))
end

local BOOTSTRAP = [[CREATE TABLE IF NOT EXISTS schema_migrations (
    version INT UNSIGNED NOT NULL,
    name VARCHAR(64) NOT NULL,
    applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]]

local function sortedSchema()
    local list = {}
    for i = 1, #(NcmSchema or {}) do list[i] = NcmSchema[i] end
    table.sort(list, function(a, b) return a.version < b.version end)
    return list
end

--- Returns { applied = {version=name,...}, pending = { {version,name}, ... } }. Must run inside a thread.
function NcmMigrations.status()
    MySQL.update.await(BOOTSTRAP)
    local rows = MySQL.query.await("SELECT version, name FROM schema_migrations ORDER BY version") or {}
    local applied = {}
    for _, r in ipairs(rows) do applied[tonumber(r.version)] = r.name end
    local pending = {}
    for _, m in ipairs(sortedSchema()) do
        if not applied[m.version] then pending[#pending + 1] = m end
    end
    return { applied = applied, pending = pending }
end

--- Applies every pending migration in version order. Returns number applied, or nil + reason.
function NcmMigrations.apply()
    local st = NcmMigrations.status()
    local count = 0
    for _, m in ipairs(st.pending) do
        local statements = {}
        for _, sql in ipairs(m.statements) do statements[#statements + 1] = { query = sql } end
        statements[#statements + 1] = { query = "INSERT INTO schema_migrations (version, name) VALUES (?, ?)", values = { m.version, m.name } }
        local ok, reason = MySQL.transaction.await(statements)
        if not ok then
            log("migration %03d %s FAILED: %s", m.version, m.name, tostring(reason))
            return nil, ("migration_failed:" .. tostring(m.version) .. ":" .. tostring(reason))
        end
        log("migration %03d %s applied (%d statement(s))", m.version, m.name, #m.statements)
        count = count + 1
    end
    if count == 0 then log("no pending migrations") end
    return count
end

--- Human-readable one-liner for the console.
function NcmMigrations.describe(st)
    local appliedList = {}
    for v, name in pairs(st.applied) do appliedList[#appliedList + 1] = ("%03d:%s"):format(v, name) end
    table.sort(appliedList)
    local pendingList = {}
    for _, m in ipairs(st.pending) do pendingList[#pendingList + 1] = ("%03d:%s"):format(m.version, m.name) end
    return ("applied=[%s] pending=[%s]"):format(table.concat(appliedList, ","), table.concat(pendingList, ","))
end
