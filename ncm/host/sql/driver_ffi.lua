-- NCM Host: SQLite driver over LuaJIT FFI (headless tests and tools; the game uses `driver_cet.lua`).
-- Interface (shared with driver_cet): exec(sql) -> true | error;  query(sql) -> { {col=value}, ... };
-- scalar(sql) -> first column of the first row;  check(sql) -> true | nil, err (prepare only, nothing runs);
-- changes() / lastId() for the most recent statement;  version();  close().
local M = {}

function M.open(dllPath, dbPath)
    local ok, ffi = pcall(require, "ffi")
    if not ok then return nil, "ffi unavailable (LuaJIT only)" end
    if not M._cdef then
        ffi.cdef [[
            typedef struct sqlite3 sqlite3;
            typedef struct sqlite3_stmt sqlite3_stmt;
            int sqlite3_initialize(void);
            int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags, const char *zVfs);
            int sqlite3_close_v2(sqlite3 *);
            int sqlite3_exec(sqlite3 *, const char *sql, void *cb, void *arg, char **errmsg);
            void sqlite3_free(void *);
            const char *sqlite3_errmsg(sqlite3 *);
            int sqlite3_prepare_v2(sqlite3 *, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail);
            int sqlite3_step(sqlite3_stmt *);
            int sqlite3_finalize(sqlite3_stmt *);
            int sqlite3_column_count(sqlite3_stmt *);
            const char *sqlite3_column_name(sqlite3_stmt *, int);
            int sqlite3_column_type(sqlite3_stmt *, int);
            double sqlite3_column_double(sqlite3_stmt *, int);
            const unsigned char *sqlite3_column_text(sqlite3_stmt *, int);
            int sqlite3_column_bytes(sqlite3_stmt *, int);
            int sqlite3_changes(sqlite3 *);
            long long sqlite3_last_insert_rowid(sqlite3 *);
            const char *sqlite3_libversion(void);
        ]]
        M._cdef = true
    end
    local okLib, lib = pcall(ffi.load, dllPath)
    if not okLib then return nil, "cannot load " .. tostring(dllPath) .. ": " .. tostring(lib) end
    -- Explicit initialize + open_v2: plain sqlite3_open access-violates against Python's sqlite3.dll build.
    if lib.sqlite3_initialize() ~= 0 then return nil, "sqlite3_initialize failed" end
    local pdb = ffi.new("sqlite3*[1]")
    if lib.sqlite3_open_v2(dbPath or ":memory:", pdb, 6, nil) ~= 0 then return nil, "sqlite3_open_v2 failed" end
    M._keep = M._keep or {}
    M._keep[#M._keep + 1] = lib   -- the library must outlive every handle
    local db = pdb[0]
    local d = {}

    local function err() return ffi.string(lib.sqlite3_errmsg(db)) end

    -- Run every statement in `sql` (a statement list is allowed); collect rows of the LAST row-returning one.
    local function run(sql, wantRows)
        local tail = ffi.new("const char*[1]")
        local cur = sql
        local rows
        local buf = ffi.new("char[?]", #sql + 1, sql)
        local p = buf
        local remaining = #sql
        while remaining > 0 do
            local stmt = ffi.new("sqlite3_stmt*[1]")
            local rc = lib.sqlite3_prepare_v2(db, p, remaining, stmt, tail)
            if rc ~= 0 then error(err() .. " in: " .. cur, 0) end
            if stmt[0] == nil then break end
            local s = stmt[0]
            local ncol = lib.sqlite3_column_count(s)
            local names = {}
            for c = 0, ncol - 1 do names[c] = ffi.string(lib.sqlite3_column_name(s, c)) end
            local got = {}
            while true do
                rc = lib.sqlite3_step(s)
                if rc == 100 then
                    if wantRows then
                        local row, first = {}, nil
                        for c = 0, ncol - 1 do
                            local ty = lib.sqlite3_column_type(s, c)
                            local v
                            if ty == 1 or ty == 2 then v = lib.sqlite3_column_double(s, c)
                            elseif ty == 3 or ty == 4 then
                                local ptr = lib.sqlite3_column_text(s, c)
                                v = ffi.string(ptr, lib.sqlite3_column_bytes(s, c))
                            end
                            if row[names[c]] == nil then row[names[c]] = v end
                            if c == 0 then first = v end
                        end
                        row[0] = first   -- positional first column (scalar); stripped by the MySQL shim
                        got[#got + 1] = row
                    end
                elseif rc == 101 then break
                else
                    local m = err()
                    lib.sqlite3_finalize(s)
                    error(m .. " in: " .. cur, 0)
                end
            end
            lib.sqlite3_finalize(s)
            if ncol > 0 then rows = got end
            local consumed = tail[0] - p
            remaining = remaining - consumed
            p = tail[0]
            if consumed <= 0 then break end
        end
        return rows or {}
    end

    function d.exec(sql) run(sql, false); return true end
    function d.query(sql)
        local rows = run(sql, true)
        for _, r in ipairs(rows) do r[0] = nil end
        return rows
    end
    function d.scalar(sql)
        local rows = run(sql, true)
        return rows[1] and rows[1][0] or nil
    end
    function d.check(sql)
        local stmt = ffi.new("sqlite3_stmt*[1]")
        local rc = lib.sqlite3_prepare_v2(db, sql, #sql, stmt, nil)
        if stmt[0] ~= nil then lib.sqlite3_finalize(stmt[0]) end
        if rc ~= 0 then return nil, err() end
        return true
    end
    function d.changes() return lib.sqlite3_changes(db) end
    function d.lastId() return tonumber(lib.sqlite3_last_insert_rowid(db)) end
    function d.version() return ffi.string(lib.sqlite3_libversion()) end
    function d.close() lib.sqlite3_close_v2(db) end
    d.kind = "ffi"
    return d
end

--- Find a sqlite3.dll on this machine (NCM_SQLITE_DLL, else Python's DLLs folder).
function M.locate()
    local env = os.getenv("NCM_SQLITE_DLL")
    if env and env ~= "" then return env end
    local h = io.popen('python -c "import sys,os;print(os.path.join(sys.base_prefix,\'DLLs\',\'sqlite3.dll\'))" 2>nul')
    if h then
        local p = h:read("*l"); h:close()
        if p and p ~= "" then
            local f = io.open(p, "rb")
            if f then f:close(); return p end
        end
    end
    return nil
end

return M
