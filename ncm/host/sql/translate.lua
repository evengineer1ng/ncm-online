-- NCM Host: MariaDB -> SQLite statement translation (L338, doc 55 §4).
--
-- The NCM resources speak the MariaDB 10.11 dialect through OPEN//77's `MySQL.*`. The single-player host runs them
-- UNCHANGED over SQLite (CET's per-mod `db`), so every statement passes through here once and the result is cached.
-- Pure: no IO, no clock (the caller supplies `ctx.now()` / `ctx.uuid()`), LuaJIT ∩ Lua 5.4.
--
-- What is rewritten (DML; DDL goes through `sql/schema.lua`):
--   INSERT IGNORE                       -> INSERT OR IGNORE
--   ON DUPLICATE KEY UPDATE x=VALUES(x) -> ON CONFLICT DO UPDATE SET x=excluded.x   (SQLite >= 3.35: no target = any
--                                          uniqueness constraint, which IS MariaDB's rule; INSERT..SELECT gets WHERE 1)
--   NOW() / CURRENT_TIMESTAMP / UUID() / UNIX_TIMESTAMP() -> literals from the HOST clock (dev skew applies)
--   UNIX_TIMESTAMP(x) -> CAST(strftime('%s', x) AS INTEGER);  GREATEST/LEAST -> MAX/MIN;  IF -> IIF
--   CONCAT(a, b) -> (a || b);  LEFT(s, n) -> SUBSTR(s, 1, n);  VERSION() / DATABASE() -> constants
--   FIELD(x, a, b) -> (CASE x WHEN a THEN 1 WHEN b THEN 2 ELSE 0 END)
--   UPDATE t a JOIN u b ON c SET a.x=.. WHERE w -> UPDATE t AS a SET x=.. FROM u AS b WHERE (c) AND (w)
--   information_schema.COLUMNS -> a sqlite_master x pragma_table_info view
--   "double quoted" strings -> 'single quoted';  MariaDB backslash escapes decoded
-- Parameters stay `?`; `M.bind` inlines them as typed literals (CET's `db` has no bound parameters).
local M = { version = "0.1.0" }

local upper, sub, find, byte = string.upper, string.sub, string.find, string.byte

-- ------------------------------------------------------------------------------------------------ tokens

--- Tokens: { t = "ws"|"word"|"num"|"str"|"qid"|"param"|"op"|"comment", v = text }. `str` tokens carry `s`, the
--- decoded string value, and are re-emitted SQLite-quoted.
function M.tokenize(sql)
    local out, i, n = {}, 1, #sql
    while i <= n do
        local c = sub(sql, i, i)
        if find(c, "%s") then
            local j = i
            while j + 1 <= n and find(sub(sql, j + 1, j + 1), "%s") do j = j + 1 end
            out[#out + 1] = { t = "ws", v = sub(sql, i, j) }; i = j + 1
        elseif c == "-" and sub(sql, i + 1, i + 1) == "-" then
            local j = find(sql, "\n", i, true) or n
            out[#out + 1] = { t = "comment", v = " " }; i = j + 1
        elseif c == "#" then
            local j = find(sql, "\n", i, true) or n
            out[#out + 1] = { t = "comment", v = " " }; i = j + 1
        elseif c == "/" and sub(sql, i + 1, i + 1) == "*" then
            local _, j = find(sql, "*/", i + 2, true)
            out[#out + 1] = { t = "comment", v = " " }; i = (j or n) + 1
        elseif c == "'" or c == '"' then
            local q, j, buf = c, i + 1, {}
            while j <= n do
                local d = sub(sql, j, j)
                if d == "\\" and j < n then
                    local e = sub(sql, j + 1, j + 1)
                    local map = { n = "\n", t = "\t", r = "\r", ["0"] = "\0", b = "\b", Z = "\26" }
                    buf[#buf + 1] = map[e] or e; j = j + 2
                elseif d == q then
                    if sub(sql, j + 1, j + 1) == q then buf[#buf + 1] = q; j = j + 2
                    else break end
                else buf[#buf + 1] = d; j = j + 1 end
            end
            out[#out + 1] = { t = "str", s = table.concat(buf), v = sub(sql, i, j) }; i = j + 1
        elseif c == "`" then
            local j = find(sql, "`", i + 1, true) or n
            out[#out + 1] = { t = "qid", v = sub(sql, i, j), name = sub(sql, i + 1, j - 1) }; i = j + 1
        elseif c == "?" then
            out[#out + 1] = { t = "param", v = "?" }; i = i + 1
        elseif find(c, "[%a_]") then
            local j = i
            while j + 1 <= n and find(sub(sql, j + 1, j + 1), "[%w_$]") do j = j + 1 end
            out[#out + 1] = { t = "word", v = sub(sql, i, j) }; i = j + 1
        elseif find(c, "%d") then
            local j = i
            while j + 1 <= n and find(sub(sql, j + 1, j + 1), "[%w%.]") do j = j + 1 end
            out[#out + 1] = { t = "num", v = sub(sql, i, j) }; i = j + 1
        else
            local two = sub(sql, i, i + 1)
            if two == "<=" or two == ">=" or two == "<>" or two == "!=" or two == "||" or two == ":=" then
                out[#out + 1] = { t = "op", v = two }; i = i + 2
            else
                out[#out + 1] = { t = "op", v = c }; i = i + 1
            end
        end
    end
    return out
end

local function quote(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end
M.quote = quote

function M.emit(tokens)
    local b = {}
    for k = 1, #tokens do
        local tk = tokens[k]
        if tk.t == "str" then b[#b + 1] = quote(tk.s) else b[#b + 1] = tk.v end
    end
    return table.concat(b)
end

-- ------------------------------------------------------------------------------------------------ helpers

local function W(tk) return tk and tk.t == "word" and upper(tk.v) or nil end
local function isOp(tk, v) return tk and tk.t == "op" and tk.v == v end

--- Index of the next non-whitespace token after k (or nil).
local function nextSig(toks, k)
    k = k + 1
    while toks[k] and (toks[k].t == "ws" or toks[k].t == "comment") do k = k + 1 end
    return toks[k] and k or nil
end
M.nextSig = nextSig

--- Index of the ')' matching the '(' at k.
local function matchParen(toks, k)
    local depth = 0
    for j = k, #toks do
        if isOp(toks[j], "(") then depth = depth + 1
        elseif isOp(toks[j], ")") then depth = depth - 1; if depth == 0 then return j end end
    end
    return nil
end
M.matchParen = matchParen

--- Split tokens [a, b] on top-level commas: list of { from, to }.
local function splitArgs(toks, a, b)
    local parts, depth, start = {}, 0, a
    for j = a, b do
        local tk = toks[j]
        if isOp(tk, "(") then depth = depth + 1
        elseif isOp(tk, ")") then depth = depth - 1
        elseif isOp(tk, ",") and depth == 0 then parts[#parts + 1] = { start, j - 1 }; start = j + 1 end
    end
    parts[#parts + 1] = { start, b }
    return parts
end
M.splitArgs = splitArgs

local function slice(toks, a, b)
    local out = {}
    for j = a, b do out[#out + 1] = toks[j] end
    return out
end
local function lit(v) return { t = "word", v = v } end

-- ------------------------------------------------------------------------------------------------ functions

local SIMPLE = { GREATEST = "MAX", LEAST = "MIN", IF = "IIF", IFNULL = "IFNULL", SUBSTRING = "SUBSTR",
    CHAR_LENGTH = "LENGTH", LCASE = "LOWER", UCASE = "UPPER" }

--- Rewrites MariaDB scalar functions in place-copy; returns the new token list.
local function rewriteFunctions(toks, ctx)
    local out, k = {}, 1
    while k <= #toks do
        local tk = toks[k]
        local w = W(tk)
        local nk = w and nextSig(toks, k)
        local call = nk and isOp(toks[nk], "(")
        local prev = out[#out]
        local qualified = prev and isOp(prev, ".")
        if w and not qualified and (w == "CURRENT_TIMESTAMP" or w == "UTC_TIMESTAMP" or w == "LOCALTIMESTAMP") and not call then
            out[#out + 1] = lit(quote(ctx.datetime())); k = k + 1
        elseif call and not qualified and (w == "NOW" or w == "CURRENT_TIMESTAMP" or w == "UTC_TIMESTAMP" or w == "SYSDATE") then
            out[#out + 1] = lit(quote(ctx.datetime())); k = matchParen(toks, nk) + 1
        elseif call and not qualified and w == "UUID" then
            out[#out + 1] = lit(quote(ctx.uuid())); k = matchParen(toks, nk) + 1
        elseif call and not qualified and w == "VERSION" then
            out[#out + 1] = lit(quote("10.11.14-ncm-host-sqlite")); k = matchParen(toks, nk) + 1
        elseif call and not qualified and w == "DATABASE" then
            out[#out + 1] = lit(quote("main")); k = matchParen(toks, nk) + 1
        elseif call and not qualified and w == "UNIX_TIMESTAMP" then
            local close = matchParen(toks, nk)
            local inner = rewriteFunctions(slice(toks, nk + 1, close - 1), ctx)
            local empty = true
            for _, t in ipairs(inner) do if t.t ~= "ws" then empty = false end end
            if empty then out[#out + 1] = lit(tostring(math.floor(ctx.unix())))
            else
                out[#out + 1] = lit("CAST(strftime('%s', ")
                for _, t in ipairs(inner) do out[#out + 1] = t end
                out[#out + 1] = lit(") AS INTEGER)")
            end
            k = close + 1
        elseif call and not qualified and w == "CONCAT" then
            local close = matchParen(toks, nk)
            local inner = rewriteFunctions(slice(toks, nk + 1, close - 1), ctx)
            local parts = splitArgs(inner, 1, #inner)
            out[#out + 1] = lit("(")
            for p = 1, #parts do
                if p > 1 then out[#out + 1] = lit(" || ") end
                out[#out + 1] = lit("(")
                for j = parts[p][1], parts[p][2] do out[#out + 1] = inner[j] end
                out[#out + 1] = lit(")")
            end
            out[#out + 1] = lit(")")
            k = close + 1
        elseif call and not qualified and w == "LEFT" then
            local close = matchParen(toks, nk)
            local inner = rewriteFunctions(slice(toks, nk + 1, close - 1), ctx)
            local parts = splitArgs(inner, 1, #inner)
            out[#out + 1] = lit("SUBSTR(")
            for j = parts[1][1], parts[1][2] do out[#out + 1] = inner[j] end
            out[#out + 1] = lit(", 1, ")
            for j = parts[2][1], parts[2][2] do out[#out + 1] = inner[j] end
            out[#out + 1] = lit(")")
            k = close + 1
        elseif call and not qualified and w == "FIELD" then
            -- FIELD(x, a, b, ..) -> (CASE x WHEN a THEN 1 WHEN b THEN 2 .. ELSE 0 END): MariaDB's 1-based position,
            -- 0 when absent. (A NULL x also gives 0 in both.)
            local close = matchParen(toks, nk)
            local inner = rewriteFunctions(slice(toks, nk + 1, close - 1), ctx)
            local parts = splitArgs(inner, 1, #inner)
            out[#out + 1] = lit("(CASE ")
            for j = parts[1][1], parts[1][2] do out[#out + 1] = inner[j] end
            for p = 2, #parts do
                out[#out + 1] = lit(" WHEN ")
                for j = parts[p][1], parts[p][2] do out[#out + 1] = inner[j] end
                out[#out + 1] = lit(" THEN " .. (p - 1))
            end
            out[#out + 1] = lit(" ELSE 0 END)")
            k = close + 1
        elseif call and not qualified and w == "MEDIAN" then
            -- MEDIAN(x) OVER (...) AS a -> json_group_array(x) OVER (...) AS a; the MySQL shim reduces the array to
            -- MariaDB's MEDIAN (PERCENTILE_CONT 0.5) per row. The alias is recorded in ctx.meta.median.
            out[#out + 1] = lit("json_group_array")
            local close = matchParen(toks, nk)
            local j = nextSig(toks, close)
            if j and W(toks[j]) == "OVER" then
                local o = nextSig(toks, j)
                local oc = matchParen(toks, o)
                local a = nextSig(toks, oc)
                if a and W(toks[a]) == "AS" then
                    local alias = toks[nextSig(toks, a)]
                    if ctx.meta then
                        ctx.meta.median = ctx.meta.median or {}
                        ctx.meta.median[#ctx.meta.median + 1] = alias.t == "qid" and alias.name or alias.v
                    end
                end
            end
            k = k + 1
        elseif call and not qualified and SIMPLE[w] then
            out[#out + 1] = lit(SIMPLE[w]); k = k + 1
        elseif w == "DUAL" and prev then
            -- `FROM DUAL`: drop the FROM we already emitted.
            local j = #out
            while j > 0 and out[j].t == "ws" do j = j - 1 end
            if W(out[j]) == "FROM" then for _ = j, #out do out[#out] = nil end end
            k = k + 1
        else
            out[#out + 1] = tk; k = k + 1
        end
    end
    return out
end

-- information_schema.COLUMNS / TABLES -> live catalogue views over sqlite_master.
local IS_COLUMNS = "(SELECT 'main' AS TABLE_SCHEMA, m.name AS TABLE_NAME, p.name AS COLUMN_NAME, p.type AS DATA_TYPE, " ..
    "p.type AS COLUMN_TYPE, CASE WHEN p.`notnull` = 1 THEN 'NO' ELSE 'YES' END AS IS_NULLABLE, p.cid + 1 AS ORDINAL_POSITION " ..
    "FROM sqlite_master m JOIN pragma_table_info(m.name) p WHERE m.type = 'table')"
local IS_TABLES = "(SELECT 'main' AS TABLE_SCHEMA, name AS TABLE_NAME, 'BASE TABLE' AS TABLE_TYPE FROM sqlite_master WHERE type = 'table')"

local function rewriteInformationSchema(toks)
    local out, k = {}, 1
    while k <= #toks do
        local tk = toks[k]
        if W(tk) == "INFORMATION_SCHEMA" and isOp(toks[k + 1], ".") and toks[k + 2] then
            local what = upper(toks[k + 2].t == "qid" and toks[k + 2].name or toks[k + 2].v)
            if what == "COLUMNS" then out[#out + 1] = lit(IS_COLUMNS); k = k + 3
            elseif what == "TABLES" then out[#out + 1] = lit(IS_TABLES); k = k + 3
            else out[#out + 1] = tk; k = k + 1 end
        else out[#out + 1] = tk; k = k + 1 end
    end
    return out
end

-- ------------------------------------------------------------------------------------------------ statements

local function firstWord(toks)
    for _, tk in ipairs(toks) do
        if tk.t == "word" then return upper(tk.v) end
        if tk.t ~= "ws" and tk.t ~= "comment" and not isOp(tk, "(") then return nil end
    end
end
M.firstWord = firstWord

local function findTop(toks, a, b, word)
    local depth = 0
    for j = a, b do
        local tk = toks[j]
        if isOp(tk, "(") then depth = depth + 1
        elseif isOp(tk, ")") then depth = depth - 1
        elseif depth == 0 and W(tk) == word then return j end
    end
end

-- INSERT IGNORE / ON DUPLICATE KEY UPDATE.
local function rewriteInsert(toks)
    local out, k = {}, 1
    local dupAt
    -- locate ON DUPLICATE KEY UPDATE at depth 0
    local depth = 0
    for j = 1, #toks do
        if isOp(toks[j], "(") then depth = depth + 1 elseif isOp(toks[j], ")") then depth = depth - 1
        elseif depth == 0 and W(toks[j]) == "ON" then
            local a = nextSig(toks, j)
            if a and W(toks[a]) == "DUPLICATE" then dupAt = j; break end
        end
    end
    -- INSERT ... SELECT without a top-level WHERE before ON: SQLite would read ON as a join constraint.
    local needWhere = false
    if dupAt then
        local sel = findTop(toks, 1, dupAt - 1, "SELECT")
        if sel and not findTop(toks, sel, dupAt - 1, "WHERE") then needWhere = true end
    end
    while k <= #toks do
        local tk = toks[k]
        local w = W(tk)
        if w == "INSERT" then
            out[#out + 1] = tk
            local a = nextSig(toks, k)
            if a and W(toks[a]) == "IGNORE" then
                out[#out + 1] = lit(" OR IGNORE"); k = a + 1
            else k = k + 1 end
        elseif dupAt and k == dupAt then
            -- ON DUPLICATE KEY UPDATE
            local a = nextSig(toks, k); local b = nextSig(toks, a); local c = nextSig(toks, b)
            assert(W(toks[b]) == "KEY" and W(toks[c]) == "UPDATE", "malformed ON DUPLICATE KEY UPDATE")
            if needWhere then out[#out + 1] = lit("WHERE 1 ") end
            out[#out + 1] = lit("ON CONFLICT DO UPDATE SET")
            k = c + 1
            -- the assignment list: VALUES(col) -> excluded.col
            while k <= #toks do
                local t2 = toks[k]
                if W(t2) == "VALUES" then
                    local p = nextSig(toks, k)
                    if p and isOp(toks[p], "(") then
                        local close = matchParen(toks, p)
                        local name
                        for j = p + 1, close - 1 do if toks[j].t == "word" or toks[j].t == "qid" then name = toks[j] end end
                        out[#out + 1] = lit("excluded.")
                        out[#out + 1] = name
                        k = close + 1
                    else out[#out + 1] = t2; k = k + 1 end
                else out[#out + 1] = t2; k = k + 1 end
            end
        else
            out[#out + 1] = tk; k = k + 1
        end
    end
    return out
end

-- Single-table UPDATE/DELETE ... [WHERE w] ORDER BY .. LIMIT n (SQLite builds without SQLITE_ENABLE_UPDATE_DELETE_LIMIT
-- refuse it) -> ... WHERE rowid IN (SELECT rowid FROM t [WHERE w] ORDER BY .. LIMIT n).
local function limitByRowid(toks, tableTok, fromAt)
    local orderAt = findTop(toks, fromAt, #toks, "ORDER")
    local limitAt = findTop(toks, fromAt, #toks, "LIMIT")
    local tailAt = orderAt or limitAt
    if not tailAt then return toks end
    local whereAt = findTop(toks, fromAt, tailAt - 1, "WHERE")
    local out = slice(toks, 1, (whereAt or tailAt) - 1)
    out[#out + 1] = lit(" WHERE rowid IN (SELECT rowid FROM ")
    out[#out + 1] = tableTok
    out[#out + 1] = lit(" ")
    for j = whereAt or tailAt, #toks do out[#out + 1] = toks[j] end
    out[#out + 1] = lit(")")
    return out
end

-- UPDATE with an alias and/or JOINs -> UPDATE .. AS .. SET .. FROM .. WHERE.
local function rewriteUpdate(toks)
    local setAt = findTop(toks, 1, #toks, "SET")
    if not setAt then return toks end
    local u = findTop(toks, 1, setAt, "UPDATE")
    -- header tokens between UPDATE and SET (significant only)
    local head = {}
    for j = u + 1, setAt - 1 do if toks[j].t ~= "ws" and toks[j].t ~= "comment" then head[#head + 1] = j end end
    if #head <= 1 then return limitByRowid(toks, toks[head[1]], setAt) end   -- plain `UPDATE t SET`
    local tableTok = toks[head[1]]
    local alias, joins, i = nil, {}, 2
    local function hw(n) return head[n] and W(toks[head[n]]) end
    if head[i] and not ({ JOIN = 1, INNER = 1, LEFT = 1, CROSS = 1, AS = 1 })[hw(i)] and toks[head[i]].t ~= "op" then
        alias = toks[head[i]]; i = i + 1
    elseif hw(i) == "AS" then alias = toks[head[i + 1]]; i = i + 2 end
    -- JOIN <t> [alias] ON <cond>  (INNER only)
    local from, conds = {}, {}
    local pos = head[i] and head[i] or setAt
    while pos and pos < setAt do
        local w = W(toks[pos])
        if w == "INNER" or w == "CROSS" then pos = nextSig(toks, pos); w = W(toks[pos]) end
        if w == "LEFT" or w == "RIGHT" then error("UPDATE with LEFT/RIGHT JOIN is not translated") end
        if w ~= "JOIN" and not isOp(toks[pos], ",") then error("unexpected UPDATE header token " .. tostring(toks[pos].v)) end
        local t = nextSig(toks, pos)
        local after = nextSig(toks, t)
        local a2
        if after and after < setAt and W(toks[after]) == "AS" then a2 = toks[nextSig(toks, after)]; after = nextSig(toks, nextSig(toks, after))
        elseif after and after < setAt and toks[after].t ~= "op" and W(toks[after]) ~= "ON" and W(toks[after]) ~= "JOIN" then a2 = toks[after]; after = nextSig(toks, after) end
        from[#from + 1] = { tbl = toks[t], alias = a2 }
        if after and after < setAt and W(toks[after]) == "ON" then
            -- condition until next top-level JOIN/INNER/comma or SET
            local depth, j = 0, after + 1
            local stop = setAt
            while j < setAt do
                if isOp(toks[j], "(") then depth = depth + 1 elseif isOp(toks[j], ")") then depth = depth - 1
                elseif depth == 0 and (W(toks[j]) == "JOIN" or W(toks[j]) == "INNER" or W(toks[j]) == "CROSS" or W(toks[j]) == "LEFT") then stop = j; break end
                j = j + 1
            end
            conds[#conds + 1] = slice(toks, after + 1, stop - 1)
            pos = stop < setAt and stop or nil
        else
            pos = (after and after < setAt) and after or nil
        end
    end
    -- the SET list ends at a top-level WHERE / ORDER / LIMIT
    local whereAt = findTop(toks, setAt + 1, #toks, "WHERE")
    local tailAt = findTop(toks, setAt + 1, #toks, "ORDER") or findTop(toks, setAt + 1, #toks, "LIMIT")
    local setEnd = (whereAt or tailAt or (#toks + 1)) - 1
    -- strip `x.` qualifiers on SET targets (SQLite forbids them)
    local setToks = slice(toks, setAt + 1, setEnd)
    local parts = splitArgs(setToks, 1, #setToks)
    local setOut = {}
    for p = 1, #parts do
        local a, b = parts[p][1], parts[p][2]
        local eq
        for j = a, b do if isOp(setToks[j], "=") then eq = j; break end end
        if p > 1 then setOut[#setOut + 1] = lit(",") end
        local tgt = {}
        for j = a, (eq or b + 1) - 1 do if setToks[j].t ~= "ws" then tgt[#tgt + 1] = setToks[j] end end
        setOut[#setOut + 1] = lit(" ")
        setOut[#setOut + 1] = tgt[#tgt]   -- the bare column
        setOut[#setOut + 1] = lit(" ")
        for j = eq, b do setOut[#setOut + 1] = setToks[j] end
    end
    local out = { lit("UPDATE "), tableTok }
    if alias then out[#out + 1] = lit(" AS "); out[#out + 1] = alias end
    out[#out + 1] = lit(" SET")
    for _, t in ipairs(setOut) do out[#out + 1] = t end
    if #from > 0 then
        out[#out + 1] = lit(" FROM ")
        for f = 1, #from do
            if f > 1 then out[#out + 1] = lit(", ") end
            out[#out + 1] = from[f].tbl
            if from[f].alias then out[#out + 1] = lit(" AS "); out[#out + 1] = from[f].alias end
        end
    end
    local wh = {}
    for _, c in ipairs(conds) do wh[#wh + 1] = c end
    if whereAt then wh[#wh + 1] = slice(toks, whereAt + 1, (tailAt or (#toks + 1)) - 1) end
    if #wh > 0 then
        out[#out + 1] = lit(" WHERE ")
        for w = 1, #wh do
            if w > 1 then out[#out + 1] = lit(" AND ") end
            out[#out + 1] = lit("(")
            for _, t in ipairs(wh[w]) do out[#out + 1] = t end
            out[#out + 1] = lit(")")
        end
    end
    if tailAt then
        -- SQLite only allows ORDER/LIMIT on UPDATE when compiled with it; drop (single-row targets in practice)
        local w = W(toks[tailAt])
        if w ~= "LIMIT" and w ~= "ORDER" then for j = tailAt, #toks do out[#out + 1] = toks[j] end end
    end
    return out
end

-- DELETE a FROM a JOIN b ON c WHERE w -> DELETE FROM a WHERE rowid IN (SELECT a.rowid FROM a JOIN b ON c WHERE w)
local function rewriteDelete(toks)
    local d = findTop(toks, 1, #toks, "DELETE")
    local f = findTop(toks, d + 1, #toks, "FROM")
    if not f then return toks end
    local between = false
    for j = d + 1, f - 1 do if toks[j].t ~= "ws" then between = true end end
    local hasJoin = findTop(toks, f + 1, #toks, "JOIN")
    if not between and not hasJoin then return limitByRowid(toks, toks[nextSig(toks, f)], f) end
    local t = nextSig(toks, f)
    local target = toks[t]
    local out = { lit("DELETE FROM "), target, lit(" WHERE rowid IN (SELECT "), target, lit(".rowid FROM ") }
    for j = t, #toks do out[#out + 1] = toks[j] end
    out[#out + 1] = lit(")")
    return out
end

--- Translate a bare expression (generated columns, defaults).
function M.expr(text, ctx)
    return M.emit(rewriteFunctions(M.tokenize(text), ctx or { datetime = function() return "1970-01-01 00:00:00" end,
        unix = function() return 0 end, uuid = function() return "" end }))
end

--- Translate one DML statement. Returns the SQLite SQL text (with `?` placeholders intact).
function M.dml(sql, ctx)
    local toks = M.tokenize(sql)
    toks = rewriteInformationSchema(toks)
    toks = rewriteFunctions(toks, ctx)
    toks = M.tokenize(M.emit(toks))   -- re-read the literals the passes above inserted as real tokens
    local fw = firstWord(toks)
    if fw == "INSERT" or fw == "REPLACE" then toks = rewriteInsert(toks)
    elseif fw == "UPDATE" then toks = rewriteUpdate(toks)
    elseif fw == "DELETE" then toks = rewriteDelete(toks) end
    return M.emit(toks)
end

-- ------------------------------------------------------------------------------------------------ binding

local function literal(v)
    local tv = type(v)
    if v == nil then return "NULL" end
    if tv == "boolean" then return v and "1" or "0" end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "NULL" end
        if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
        return string.format("%.17g", v)
    end
    if tv == "string" then
        if find(v, "\0", 1, true) then v = v:gsub("%z", "") end
        return quote(v)
    end
    if tv == "table" then error("cannot bind a table as an SQL parameter") end
    return quote(tostring(v))
end
M.literal = literal

--- Inline positional parameters. `params` may have holes (OPEN//77 measures `#values`; nil becomes NULL here).
--- Returns the bound SQL, or nil + "param_count_mismatch" when the counts disagree.
function M.bind(sql, params, count)
    params = params or {}
    local toks = M.tokenize(sql)
    local b, n = {}, 0
    for k = 1, #toks do
        local tk = toks[k]
        if tk.t == "param" then n = n + 1; b[#b + 1] = literal(params[n])
        elseif tk.t == "str" then b[#b + 1] = quote(tk.s)
        else b[#b + 1] = tk.v end
    end
    local supplied = count or #params
    if supplied > n then return nil, ("param_count_mismatch: %d placeholders, %d values"):format(n, supplied) end
    return table.concat(b), n
end

return M
