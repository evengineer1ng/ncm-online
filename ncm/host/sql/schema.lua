-- NCM Host: the MariaDB schema as a MODEL, emitted for SQLite (L338, doc 55 Â§4).
--
-- The resources' migrations (`ncm_league/server/schema/001..NNN`) are MariaDB DDL with ALTER ... MODIFY / CHANGE that
-- SQLite cannot execute. So the host does not execute them: it REPLAYS every DDL statement into this model (tables,
-- columns, keys) and emits the final schema as SQLite DDL. `M.sync` then brings a database to the model -- creating
-- tables, appending columns, or rebuilding a table whose shape changed -- and remembers each table's signature.
-- DML inside migrations (seed rows, backfills) is returned separately and run after the sync, in order.
-- Pure apart from `M.sync`, which takes a driver: { exec(sql), query(sql) -> list }.
local M = { version = "0.1.0" }
local T = nil   -- translate module, injected by M.init

function M.init(translate) T = translate; return M end

local upper, lower = string.upper, string.lower

local function sig(toks, a, b)
    local out = {}
    for j = a or 1, b or #toks do
        local tk = toks[j]
        if tk.t ~= "ws" and tk.t ~= "comment" then out[#out + 1] = tk end
    end
    return out
end
local function W(tk) return tk and tk.t == "word" and upper(tk.v) or nil end
local function isOp(tk, v) return tk and tk.t == "op" and tk.v == v end
local function ident(tk)
    if not tk then return nil end
    if tk.t == "qid" then return tk.name end
    if tk.t == "str" then return tk.s end
    return tk.v
end

local function matchParen(s, k)
    local depth = 0
    for j = k, #s do
        if isOp(s[j], "(") then depth = depth + 1
        elseif isOp(s[j], ")") then depth = depth - 1; if depth == 0 then return j end end
    end
end
local function splitTop(s, a, b)
    local parts, depth, start = {}, 0, a
    for j = a, b do
        if isOp(s[j], "(") then depth = depth + 1
        elseif isOp(s[j], ")") then depth = depth - 1
        elseif isOp(s[j], ",") and depth == 0 then parts[#parts + 1] = { start, j - 1 }; start = j + 1 end
    end
    if start <= b then parts[#parts + 1] = { start, b } end
    return parts
end
local function text(s, a, b)
    local out = {}
    for j = a, b do
        local tk = s[j]
        if tk.t == "str" then out[#out + 1] = T.quote(tk.s) else out[#out + 1] = tk.v end
    end
    -- words need a separator; punctuation does not
    local buf = {}
    for j, v in ipairs(out) do
        local prev = out[j - 1]
        if j > 1 and v ~= "," and v ~= ")" and v ~= "(" and prev ~= "(" then buf[#buf + 1] = " " end
        buf[#buf + 1] = v
    end
    return table.concat(buf)
end

-- (col[, col ...]) -> { "col", ... }   (prefix lengths and ASC/DESC dropped)
local function colList(s, open)
    local close = matchParen(s, open)
    local cols = {}
    for _, p in ipairs(splitTop(s, open + 1, close - 1)) do cols[#cols + 1] = ident(s[p[1]]) end
    return cols, close
end

-- ------------------------------------------------------------------------------------------------ model

function M.newModel() return { tables = {}, order = {} } end

local function getTable(model, name, create)
    local key = lower(name)
    local t = model.tables[key]
    if not t and create then
        t = { name = name, cols = {}, pk = nil, uniques = {}, indexes = {} }
        model.tables[key] = t
        model.order[#model.order + 1] = key
    end
    return t
end
M.table = function(model, name) return getTable(model, name, false) end

local function findCol(t, name)
    for i, c in ipairs(t.cols) do if lower(c.name) == lower(name) then return c, i end end
end

local STOP = { NOT = 1, NULL = 1, DEFAULT = 1, AUTO_INCREMENT = 1, PRIMARY = 1, UNIQUE = 1, COMMENT = 1, CHECK = 1,
    ON = 1, COLLATE = 1, CHARACTER = 1, CHARSET = 1, REFERENCES = 1, GENERATED = 1, AS = 1, FIRST = 1, AFTER = 1,
    INVISIBLE = 1, KEY = 1 }

--- Parse a column definition from significant tokens s[a..b].
local function parseColumn(s, a, b)
    local c = { name = ident(s[a]) }
    local j = a + 1
    local tstart = j
    while j <= b do
        local w = W(s[j])
        if w and STOP[w] then break end
        if isOp(s[j], "(") then j = matchParen(s, j) end
        j = j + 1
    end
    local typeText = text(s, tstart, j - 1)
    c.rawType = typeText
    local ut = upper(typeText)
    c.tinyBool = ut:match("^TINYINT%s*%(%s*1%s*%)") ~= nil or ut:match("^BOOL") ~= nil
    local base = ut:gsub("%s+UNSIGNED", ""):gsub("%s+ZEROFILL", ""):gsub("%s+SIGNED", "")
    if base:match("^ENUM") or base:match("^SET%s*%(") or base:match("^JSON") or base:match("TEXT$") then base = "TEXT" end
    c.type = base
    while j <= b do
        local w = W(s[j])
        if w == "NOT" and W(s[j + 1]) == "NULL" then c.notnull = true; j = j + 2
        elseif w == "NULL" then c.notnull = false; j = j + 1
        elseif w == "DEFAULT" then
            local v = s[j + 1]
            if isOp(v, "(") then local close = matchParen(s, j + 1); c.default = text(s, j + 1, close); j = close + 1
            elseif isOp(v, "-") then c.default = "-" .. v.v .. s[j + 2].v; j = j + 3
            else
                local dv = (v.t == "str") and T.quote(v.s) or v.v
                if W(v) == "CURRENT_TIMESTAMP" then
                    dv = "CURRENT_TIMESTAMP"
                    if isOp(s[j + 2], "(") then j = matchParen(s, j + 2) - 1 end
                end
                c.default = dv; j = j + 2
            end
        elseif w == "AUTO_INCREMENT" then c.autoinc = true; j = j + 1
        elseif w == "PRIMARY" then c.inlinePk = true; j = j + 2
        elseif w == "UNIQUE" then c.inlineUnique = true; j = j + 1; if W(s[j]) == "KEY" then j = j + 1 end
        elseif w == "ON" then j = j + 3   -- ON UPDATE CURRENT_TIMESTAMP (lost: doc 55 Â§G)
        elseif w == "COMMENT" then j = j + 2
        elseif w == "COLLATE" then j = j + 2
        elseif w == "CHARACTER" then j = j + 3
        elseif w == "CHARSET" then j = j + 2
        elseif w == "CHECK" then j = matchParen(s, j + 1) + 1
        elseif w == "REFERENCES" then
            j = j + 2
            if isOp(s[j], "(") then j = matchParen(s, j) + 1 end
            while j <= b and (W(s[j]) == "ON" or W(s[j]) == "MATCH") do
                j = j + 2
                local w2 = W(s[j])
                if w2 == "SET" or w2 == "NO" then j = j + 2 else j = j + 1 end
            end
        elseif w == "GENERATED" or w == "AS" then
            -- [GENERATED ALWAYS] AS (expr) [PERSISTENT|STORED|VIRTUAL] -> SQLite STORED (3.31+); a unique key may sit on it
            while not isOp(s[j], "(") do j = j + 1 end
            local close = matchParen(s, j)
            c.generated = T.expr(text(s, j + 1, close - 1))
            j = close + 1
            local w2 = W(s[j])
            if w2 == "PERSISTENT" or w2 == "STORED" or w2 == "VIRTUAL" then j = j + 1 end
        else j = j + 1 end
    end
    if c.notnull == nil then c.notnull = false end
    return c
end

local function addConstraint(t, s, a, b)
    -- s[a..b] begins at CONSTRAINT/PRIMARY/UNIQUE/KEY/INDEX/FOREIGN/CHECK/FULLTEXT
    local j = a
    if W(s[j]) == "CONSTRAINT" then
        j = j + 1
        if not ({ PRIMARY = 1, UNIQUE = 1, FOREIGN = 1, CHECK = 1 })[W(s[j]) or ""] then j = j + 1 end
    end
    local w = W(s[j])
    if w == "PRIMARY" then
        local open = j + 2
        while not isOp(s[open], "(") do open = open + 1 end
        t.pk = colList(s, open)
    elseif w == "UNIQUE" then
        j = j + 1
        if W(s[j]) == "KEY" or W(s[j]) == "INDEX" then j = j + 1 end
        if W(s[j]) == "IF" then j = j + 3 end
        local name
        if not isOp(s[j], "(") then name = ident(s[j]); j = j + 1 end
        local cols = colList(s, j)
        name = name or ("uq_" .. table.concat(cols, "_"))
        for i, u in ipairs(t.uniques) do if lower(u.name) == lower(name) then table.remove(t.uniques, i); break end end
        t.uniques[#t.uniques + 1] = { name = name, cols = cols }
    elseif w == "KEY" or w == "INDEX" or w == "FULLTEXT" or w == "SPATIAL" then
        j = j + 1
        if W(s[j]) == "KEY" or W(s[j]) == "INDEX" then j = j + 1 end
        if W(s[j]) == "IF" then j = j + 3 end
        local name
        if not isOp(s[j], "(") then name = ident(s[j]); j = j + 1 end
        local cols = colList(s, j)
        name = name or ("ix_" .. table.concat(cols, "_"))
        if w == "KEY" or w == "INDEX" then
            for i, x in ipairs(t.indexes) do if lower(x.name) == lower(name) then table.remove(t.indexes, i); break end end
            t.indexes[#t.indexes + 1] = { name = name, cols = cols }
        end
    end
    -- FOREIGN KEY / CHECK: not modelled (doc 55 Â§G: SQLite enforces neither here)
end

local CONSTRAINT_START = { CONSTRAINT = 1, PRIMARY = 1, UNIQUE = 1, KEY = 1, INDEX = 1, FOREIGN = 1, CHECK = 1,
    FULLTEXT = 1, SPATIAL = 1 }

local function applyColumn(t, c, positionAfter, first)
    local _, i = findCol(t, c.name)
    if i then t.cols[i] = c
    elseif first then table.insert(t.cols, 1, c)
    elseif positionAfter then
        local _, pi = findCol(t, positionAfter)
        table.insert(t.cols, (pi or #t.cols) + 1, c)
    else t.cols[#t.cols + 1] = c end
    if c.inlinePk then t.pk = { c.name } end
    if c.inlineUnique then t.uniques[#t.uniques + 1] = { name = "uq_" .. c.name, cols = { c.name } } end
end

local function positionOf(s, a, b)
    for j = a, b do
        if W(s[j]) == "AFTER" then return ident(s[j + 1]), false, j - 1 end
        if W(s[j]) == "FIRST" then return nil, true, j - 1 end
    end
    return nil, false, b
end

local function alterAction(model, t, s, a, b)
    local w = W(s[a])
    if w == "ADD" then
        local j = a + 1
        if W(s[j]) == "COLUMN" then j = j + 1 end
        if CONSTRAINT_START[W(s[j]) or ""] then return addConstraint(t, s, j, b) end
        local ifNotExists = false
        if W(s[j]) == "IF" then ifNotExists = true; j = j + 3 end
        if isOp(s[j], "(") then   -- ADD (col, col)
            local close = matchParen(s, j)
            for _, p in ipairs(splitTop(s, j + 1, close - 1)) do applyColumn(t, parseColumn(s, p[1], p[2])) end
            return
        end
        local after, first, e = positionOf(s, j, b)
        local c = parseColumn(s, j, e)
        if ifNotExists and findCol(t, c.name) then return end
        applyColumn(t, c, after, first)
    elseif w == "MODIFY" or w == "CHANGE" then
        local j = a + 1
        if W(s[j]) == "COLUMN" then j = j + 1 end
        if W(s[j]) == "IF" then j = j + 2 end
        local old = nil
        if w == "CHANGE" then old = ident(s[j]); j = j + 1 end
        local after, first, e = positionOf(s, j, b)
        local c = parseColumn(s, j, e)
        local prev, i = findCol(t, old or c.name)
        if not i then error(("ALTER %s on missing column %s.%s"):format(w, t.name, old or c.name)) end
        if old and lower(old) ~= lower(c.name) then
            local function ren(list) if list then for k, v in ipairs(list) do if lower(v) == lower(old) then list[k] = c.name end end end end
            ren(t.pk); for _, u in ipairs(t.uniques) do ren(u.cols) end; for _, x in ipairs(t.indexes) do ren(x.cols) end
            c.renamedFrom = old
        end
        c.renamedFrom = c.renamedFrom or prev.renamedFrom
        t.cols[i] = c
        if after or first then
            table.remove(t.cols, i)
            applyColumn(t, c, after, first)
        end
    elseif w == "DROP" then
        local j = a + 1
        local w2 = W(s[j])
        if w2 == "PRIMARY" then t.pk = nil; return end
        if w2 == "INDEX" or w2 == "KEY" then
            j = j + 1
            if W(s[j]) == "IF" then j = j + 2 end
            local name = lower(ident(s[j]))
            for i, x in ipairs(t.indexes) do if lower(x.name) == name then table.remove(t.indexes, i); return end end
            for i, x in ipairs(t.uniques) do if lower(x.name) == name then table.remove(t.uniques, i); return end end
            return
        end
        if w2 == "FOREIGN" or w2 == "CONSTRAINT" or w2 == "CHECK" then return end
        if w2 == "COLUMN" then j = j + 1 end
        if W(s[j]) == "IF" then j = j + 2 end
        local name = ident(s[j])
        local _, i = findCol(t, name)
        if i then table.remove(t.cols, i) end
        local function drop(list) if list then for k = #list, 1, -1 do if lower(list[k]) == lower(name) then table.remove(list, k) end end end end
        drop(t.pk)
        for k = #t.uniques, 1, -1 do drop(t.uniques[k].cols); if #t.uniques[k].cols == 0 then table.remove(t.uniques, k) end end
        for k = #t.indexes, 1, -1 do drop(t.indexes[k].cols); if #t.indexes[k].cols == 0 then table.remove(t.indexes, k) end end
    elseif w == "RENAME" then
        local j = a + 1
        if W(s[j]) == "COLUMN" then
            local old, new = ident(s[j + 1]), ident(s[j + 3])
            local c = findCol(t, old)
            if c then c.renamedFrom = c.renamedFrom or old; c.name = new end
        else
            if W(s[j]) == "TO" or W(s[j]) == "AS" then j = j + 1 end
            local new = ident(s[j])
            model.tables[lower(t.name)] = nil
            for k, n in ipairs(model.order) do if n == lower(t.name) then model.order[k] = lower(new) end end
            t.name = new
            model.tables[lower(new)] = t
        end
    elseif w == "ALTER" then
        local j = a + 1
        if W(s[j]) == "COLUMN" then j = j + 1 end
        local c = findCol(t, ident(s[j]))
        if c then
            if W(s[j + 1]) == "SET" and W(s[j + 2]) == "DEFAULT" then
                local v = s[j + 3]
                c.default = (v.t == "str") and T.quote(v.s) or v.v
            elseif W(s[j + 1]) == "DROP" then c.default = nil end
        end
    end
    -- ALGORITHM= / LOCK= / ENGINE= table options: ignored
end

--- Classify a statement: "create_table" | "alter_table" | "create_index" | "drop_table" | "drop_index" |
--- "rename_table" | "dml".
function M.kind(sql)
    local s = sig(T.tokenize(sql))
    local a, b = W(s[1]), W(s[2])
    if a == "CREATE" then
        if b == "TABLE" or (b == "TEMPORARY" and W(s[3]) == "TABLE") then return "create_table" end
        if b == "INDEX" or b == "UNIQUE" or b == "FULLTEXT" then return "create_index" end
    elseif a == "ALTER" and b == "TABLE" then return "alter_table"
    elseif a == "DROP" and b == "TABLE" then return "drop_table"
    elseif a == "DROP" and b == "INDEX" then return "drop_index"
    elseif a == "RENAME" and b == "TABLE" then return "rename_table" end
    return "dml"
end

--- Apply one DDL statement to the model. Returns the table name it touched (or nil for DML).
function M.apply(model, sql)
    local kind = M.kind(sql)
    if kind == "dml" then return nil end
    local s = sig(T.tokenize(sql))
    if kind == "create_table" then
        local j = 3
        if W(s[2]) == "TEMPORARY" then j = 4 end
        local ifNotExists = false
        if W(s[j]) == "IF" then ifNotExists = true; j = j + 3 end
        local name = ident(s[j])
        local existing = getTable(model, name, false)
        if existing and ifNotExists then return existing.name end
        if existing then error("CREATE TABLE on an existing table: " .. name) end
        local t = getTable(model, name, true)
        local open = j + 1
        if W(s[open]) == "LIKE" then
            local src = getTable(model, ident(s[open + 1]), false)
            for _, c in ipairs(src.cols) do local cc = {}; for k, v in pairs(c) do cc[k] = v end; t.cols[#t.cols + 1] = cc end
            t.pk = src.pk; return t.name
        end
        local close = matchParen(s, open)
        for _, p in ipairs(splitTop(s, open + 1, close - 1)) do
            if CONSTRAINT_START[W(s[p[1]]) or ""] then addConstraint(t, s, p[1], p[2])
            else applyColumn(t, parseColumn(s, p[1], p[2])) end
        end
        return t.name
    elseif kind == "alter_table" then
        local j = 3
        if W(s[j]) == "IF" then j = j + 2 end
        local name = ident(s[j])
        local t = getTable(model, name, false)
        if not t then error("ALTER TABLE on an unknown table: " .. tostring(name)) end
        for _, p in ipairs(splitTop(s, j + 1, #s)) do alterAction(model, t, s, p[1], p[2]) end
        return t.name
    elseif kind == "create_index" then
        local j = 2
        local unique = W(s[j]) == "UNIQUE"
        if unique or W(s[j]) == "FULLTEXT" then j = j + 1 end
        j = j + 1   -- INDEX
        if W(s[j]) == "IF" then j = j + 3 end
        local iname = ident(s[j]); j = j + 1
        assert(W(s[j]) == "ON", "CREATE INDEX without ON")
        local t = getTable(model, ident(s[j + 1]), false)
        local cols = colList(s, j + 2)
        local list = unique and t.uniques or t.indexes
        for i, x in ipairs(list) do if lower(x.name) == lower(iname) then table.remove(list, i); break end end
        list[#list + 1] = { name = iname, cols = cols }
        return t.name
    elseif kind == "drop_table" then
        local j = 3
        if W(s[j]) == "IF" then j = j + 2 end
        for _, p in ipairs(splitTop(s, j, #s)) do
            local key = lower(ident(s[p[1]]))
            if model.tables[key] then
                model.tables[key] = nil
                for k, n in ipairs(model.order) do if n == key then table.remove(model.order, k); break end end
            end
        end
        return nil
    elseif kind == "drop_index" then
        local iname = lower(ident(s[3]))
        local t = getTable(model, ident(s[5]), false)
        if t then
            for i, x in ipairs(t.indexes) do if lower(x.name) == iname then table.remove(t.indexes, i); break end end
            for i, x in ipairs(t.uniques) do if lower(x.name) == iname then table.remove(t.uniques, i); break end end
        end
        return t and t.name
    elseif kind == "rename_table" then
        local t = getTable(model, ident(s[3]), false)
        alterAction(model, t, { { t = "word", v = "RENAME" }, { t = "word", v = "TO" }, s[5] }, 1, 3)
        return t.name
    end
end

-- ------------------------------------------------------------------------------------------------ emit

local function qi(name) return '"' .. name .. '"' end

--- The SQLite CREATE TABLE for a model table (as `name`, default the table's own).
function M.createSQL(t, name)
    local lines = {}
    local autoPk = t.pk and #t.pk == 1 and (function() local c = findCol(t, t.pk[1]); return c and c.autoinc end)()
    for _, c in ipairs(t.cols) do
        local l
        if autoPk and lower(c.name) == lower(t.pk[1]) then
            l = qi(c.name) .. " INTEGER PRIMARY KEY AUTOINCREMENT"
        elseif c.generated then
            l = qi(c.name) .. " " .. c.type .. " GENERATED ALWAYS AS (" .. c.generated .. ") STORED"
        else
            l = qi(c.name) .. " " .. c.type
            if c.notnull then l = l .. " NOT NULL" end
            if c.default ~= nil then l = l .. " DEFAULT " .. c.default end
        end
        lines[#lines + 1] = l
    end
    if t.pk and not autoPk then
        local q = {}
        for _, n in ipairs(t.pk) do q[#q + 1] = qi(n) end
        lines[#lines + 1] = "PRIMARY KEY (" .. table.concat(q, ", ") .. ")"
    end
    for _, u in ipairs(t.uniques) do
        local q = {}
        for _, n in ipairs(u.cols) do q[#q + 1] = qi(n) end
        lines[#lines + 1] = "UNIQUE (" .. table.concat(q, ", ") .. ")"
    end
    return "CREATE TABLE IF NOT EXISTS " .. qi(name or t.name) .. " (\n  " .. table.concat(lines, ",\n  ") .. "\n)"
end

function M.indexSQL(t)
    local out = {}
    for _, x in ipairs(t.indexes) do
        local q = {}
        for _, n in ipairs(x.cols) do q[#q + 1] = qi(n) end
        out[#out + 1] = ("CREATE INDEX IF NOT EXISTS %s ON %s (%s)"):format(qi(t.name .. "__" .. x.name), qi(t.name),
            table.concat(q, ", "))
    end
    return out
end

--- A stable signature of a table's shape (columns, types, nullability, defaults, keys).
function M.signature(t)
    local parts = {}
    for _, c in ipairs(t.cols) do
        parts[#parts + 1] = table.concat({ lower(c.name), c.type, c.notnull and "nn" or "n", tostring(c.default),
            c.autoinc and "ai" or "", c.generated and ("gen(" .. c.generated .. ")") or "" }, ":")
    end
    parts[#parts + 1] = "pk=" .. table.concat(t.pk or {}, ",")
    for _, u in ipairs(t.uniques) do parts[#parts + 1] = "uq=" .. table.concat(u.cols, ",") end
    return table.concat(parts, "|")
end

--- Column names declared TINYINT(1)/BOOL anywhere: the OPEN//77 .NET connector returns these as booleans.
function M.booleanColumns(model)
    local yes, no = {}, {}
    for _, key in ipairs(model.order) do
        for _, c in ipairs(model.tables[key].cols) do
            if c.tinyBool then yes[lower(c.name)] = true else no[lower(c.name)] = true end
        end
    end
    local out = {}
    for n in pairs(yes) do if not no[n] then out[n] = true end end
    return out
end

-- ------------------------------------------------------------------------------------------------ build + sync

--- Replay an ordered list of migrations ({ version, name, statements }) into a model.
--- Returns model, dml where dml = { { version, sql } ... } in order.
-- `ncm_league/server/migrations.lua` creates its ledger at runtime (BOOTSTRAP); the host builds it up front so it can
-- record the migrations it has already applied by model.
M.BOOTSTRAP = [[CREATE TABLE IF NOT EXISTS schema_migrations (
    version INT UNSIGNED NOT NULL,
    name VARCHAR(64) NOT NULL,
    applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (version)
)]]

function M.replay(migrations, model)
    model = model or M.newModel()
    M.apply(model, M.BOOTSTRAP)
    local dml = {}
    for _, m in ipairs(migrations) do
        for _, sql in ipairs(m.statements or {}) do
            local ok, err = pcall(M.apply, model, sql)
            if not ok then error(("migration %03d %s: %s"):format(m.version, m.name, tostring(err)), 0) end
            if M.kind(sql) == "dml" then dml[#dml + 1] = { version = m.version, sql = sql } end
        end
    end
    return model, dml
end

local META = [[CREATE TABLE IF NOT EXISTS "_ncm_host_schema" (
  "table_name" TEXT NOT NULL PRIMARY KEY,
  "signature" TEXT NOT NULL,
  "synced_at" INTEGER NOT NULL
)]]

--- Bring the database to the model. driver = { exec(sql), query(sql) }. Returns a report
--- { created = {..}, altered = {..}, rebuilt = {..} }.
function M.sync(driver, model, nowUnix)
    driver.exec(META)
    local have = {}
    for _, r in ipairs(driver.query([[SELECT "table_name", "signature" FROM "_ncm_host_schema"]])) do have[lower(r.table_name)] = r.signature end
    local existing = {}
    for _, r in ipairs(driver.query("SELECT name FROM sqlite_master WHERE type = 'table'")) do existing[lower(r.name)] = true end
    local report = { created = {}, altered = {}, rebuilt = {} }
    local stamp = math.floor(nowUnix or 0)
    for _, key in ipairs(model.order) do
        local t = model.tables[key]
        local want = M.signature(t)
        if not existing[key] then
            driver.exec(M.createSQL(t))
            for _, x in ipairs(M.indexSQL(t)) do driver.exec(x) end
            report.created[#report.created + 1] = t.name
        elseif have[key] ~= want then
            local cols = {}
            for _, r in ipairs(driver.query(("SELECT name FROM pragma_table_info(%s)"):format(T.quote(t.name)))) do cols[lower(r.name)] = r.name end
            -- fast path: only appended, droppable-safe columns
            local onlyAppend = have[key] ~= nil
            if onlyAppend then
                local prevCount = 0
                for _ in pairs(cols) do prevCount = prevCount + 1 end
                local oldSig = have[key]
                for i = 1, prevCount do
                    local c = t.cols[i]
                    if not c or not cols[lower(c.name)] then onlyAppend = false; break end
                end
                if onlyAppend then
                    -- the keys must be unchanged and the old signature's column part must be the new one's prefix
                    local oldCols = oldSig:match("^(.-)|pk=") or ""
                    local newCols = want:match("^(.-)|pk=") or ""
                    if newCols:sub(1, #oldCols) ~= oldCols or (oldSig:match("|pk=.*$") ~= want:match("|pk=.*$")) then onlyAppend = false end
                end
                if onlyAppend then
                    for i = prevCount + 1, #t.cols do
                        local c = t.cols[i]
                        if (c.notnull and c.default == nil) or c.generated then onlyAppend = false; break end
                    end
                end
            end
            if onlyAppend then
                for _, c in ipairs(t.cols) do
                    if not cols[lower(c.name)] then
                        local l = ("ALTER TABLE %s ADD COLUMN %s %s"):format(qi(t.name), qi(c.name), c.type)
                        if c.notnull then l = l .. " NOT NULL" end
                        if c.default ~= nil then l = l .. " DEFAULT " .. c.default end
                        driver.exec(l)
                    end
                end
                for _, x in ipairs(M.indexSQL(t)) do driver.exec(x) end
                report.altered[#report.altered + 1] = t.name
            else
                -- the SQLite table-rebuild procedure: new table, copy the columns both share (renames followed), swap
                local tmp = t.name .. "__ncm_rebuild"
                driver.exec("DROP TABLE IF EXISTS " .. qi(tmp))
                driver.exec(M.createSQL(t, tmp))
                local dst, src = {}, {}
                for _, c in ipairs(t.cols) do
                    local from = cols[lower(c.name)] or (c.renamedFrom and cols[lower(c.renamedFrom)])
                    if from and not c.generated then
                        dst[#dst + 1] = qi(c.name)
                        -- a column that became NOT NULL takes its default for old NULLs instead of losing the row
                        src[#src + 1] = (c.notnull and c.default ~= nil) and ("COALESCE(%s, %s)"):format(qi(from), c.default) or qi(from)
                    end
                end
                if #dst > 0 then
                    driver.exec(("INSERT OR IGNORE INTO %s (%s) SELECT %s FROM %s"):format(qi(tmp), table.concat(dst, ", "),
                        table.concat(src, ", "), qi(t.name)))
                end
                driver.exec("DROP TABLE " .. qi(t.name))
                driver.exec(("ALTER TABLE %s RENAME TO %s"):format(qi(tmp), qi(t.name)))
                for _, x in ipairs(M.indexSQL(t)) do driver.exec(x) end
                report.rebuilt[#report.rebuilt + 1] = t.name
            end
        end
        driver.exec(("INSERT INTO \"_ncm_host_schema\" (\"table_name\", \"signature\", \"synced_at\") VALUES (%s, %s, %d) " ..
            "ON CONFLICT(\"table_name\") DO UPDATE SET \"signature\" = excluded.\"signature\", \"synced_at\" = excluded.\"synced_at\"")
            :format(T.quote(key), T.quote(want), stamp))
    end
    return report
end

return M
