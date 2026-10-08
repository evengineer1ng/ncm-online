-- NCM Host: OPEN//77's `MySQL.*` over SQLite (L338, doc 55 §4).
--
-- The resources call MySQL.query/single/scalar/insert/update/transaction `.await` with positional `?` and a values
-- array; this is the same surface, synchronous (SQLite is in-process, so `.await` never yields). Behaviour copied from
-- the OPEN//77 bridge where the resources depend on it:
--   * a values array whose length (`#values`) differs from the placeholder count is REFUSED (KB-168's lesson);
--   * TINYINT(1) columns come back as booleans (the .NET connector's default; the resources test `== true or == 1`);
--   * a failing statement raises a Lua error (resources wrap the calls they expect to fail in pcall);
--   * transaction.await returns true, or false + reason after rolling back.
-- Runtime DDL (CREATE TABLE IF NOT EXISTS ..., ALTER TABLE ...) is applied to the schema MODEL and synced, never run raw.
local M = { version = "0.1.0" }

--- opts: { driver, model, T (translate), S (schema), clock = { unix(), datetime() }, uuid(), log(fmt, ...) }
function M.new(opts)
    local D, T, S, model = opts.driver, opts.T, opts.S, opts.model
    local log = opts.log or function() end
    local bools = S.booleanColumns(model)
    local cache = {}           -- mariadb text -> { text, select, meta }
    local stats = { statements = 0, errors = 0, ddl = 0, volatile = 0 }
    local inTx = false

    local function translateOnce(sql)
        local c = cache[sql]
        if c then return c end
        local volatile = false
        local meta = {}
        local ctx = {
            datetime = function() volatile = true; return opts.clock.datetime() end,
            unix = function() volatile = true; return opts.clock.unix() end,
            uuid = function() volatile = true; return opts.uuid() end,
            meta = meta,
        }
        local text = T.dml(sql, ctx)
        local fw = T.firstWord(T.tokenize(text))
        c = { text = text, select = (fw == "SELECT" or fw == "WITH" or fw == "PRAGMA"), meta = meta }
        if volatile then stats.volatile = stats.volatile + 1 else cache[sql] = c end
        return c
    end

    local function median(json)
        local arr = {}
        for v in tostring(json or ""):gmatch("-?[%d%.eE+]+") do arr[#arr + 1] = tonumber(v) end
        table.sort(arr)
        local n = #arr
        if n == 0 then return nil end
        local pos = (n - 1) * 0.5 + 1
        local lo = math.floor(pos)
        local frac = pos - lo
        if lo >= n then return arr[n] end
        return arr[lo] + (arr[lo + 1] - arr[lo]) * frac
    end

    local function shape(rows, meta)
        for _, r in ipairs(rows) do
            for k, v in pairs(r) do
                if type(v) == "number" and bools[string.lower(k)] then r[k] = (v ~= 0) end
            end
            if meta.median then for _, a in ipairs(meta.median) do r[a] = median(r[a]) end end
        end
        return rows
    end

    local function run(sql, params, mode)
        if type(sql) ~= "string" then error("MySQL: query must be a string", 3) end
        stats.statements = stats.statements + 1
        local kind = S.kind(sql)
        if kind ~= "dml" then
            stats.ddl = stats.ddl + 1
            S.apply(model, sql)
            S.sync(D, model, opts.clock.unix())
            bools = S.booleanColumns(model)
            return { rows = {}, changes = 0, insertId = 0 }
        end
        local c = translateOnce(sql)
        params = params or {}
        local bound, err = T.bind(c.text, params, #params)
        if not bound then stats.errors = stats.errors + 1; error("MySQL: " .. err .. " in: " .. sql, 3) end
        local ok, res = pcall(function()
            if c.select and mode == "scalar" then
                local v = D.scalar(bound)
                return { rows = {}, scalar = v }
            end
            if c.select then return { rows = shape(D.query(bound), c.meta) } end
            D.exec(bound)
            return { rows = {}, changes = D.changes(), insertId = D.lastId() }
        end)
        if not ok then
            stats.errors = stats.errors + 1
            log("SQL error: %s", tostring(res))
            error("MySQL: " .. tostring(res), 3)
        end
        return res
    end

    local MySQL = {}
    MySQL.query = { await = function(sql, params) return run(sql, params).rows end }
    MySQL.single = { await = function(sql, params) return run(sql, params).rows[1] end }
    MySQL.scalar = { await = function(sql, params) return run(sql, params, "scalar").scalar end }
    MySQL.insert = { await = function(sql, params) return run(sql, params).insertId end }
    MySQL.update = { await = function(sql, params) return run(sql, params).changes end }
    MySQL.prepare = { await = function(sql, params) return run(sql, params).rows end }
    MySQL.transaction = { await = function(list, shared)
        if inTx then error("MySQL: nested transaction", 2) end
        inTx = true
        D.exec("BEGIN")
        local ok, err = pcall(function()
            for _, st in ipairs(list or {}) do
                if type(st) == "string" then run(st, shared)
                else run(st.query or st[1], st.values or st.parameters or st[2] or shared) end
            end
        end)
        if ok then D.exec("COMMIT") else pcall(D.exec, "ROLLBACK") end
        inTx = false
        if not ok then return false, tostring(err) end
        return true
    end }
    MySQL.isReady = function() return true end
    MySQL.ready = function(fn) if opts.spawn then opts.spawn(fn) else fn() end; return true end
    MySQL.stats = stats
    return MySQL
end

return M
