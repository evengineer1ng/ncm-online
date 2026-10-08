-- NCM Host: SQLite driver over the ncm_host plugin's own SQLite (the `ncmnative` C module). Same interface as
-- driver_ffi.lua / driver_cet.lua. Integers come back as Lua 5.4 integers, as OPEN//77's MySQL bridge gives them.
local M = {}

function M.open(path)
    local native = require("ncmnative")
    local h, err = native.sqlite_open(path)
    if not h then return nil, err end
    local d = { kind = "native" }
    function d.exec(sql) return h:exec(sql) end
    function d.query(sql) return h:query(sql) end
    function d.scalar(sql) return h:scalar(sql) end
    function d.check(sql) return h:check(sql) end
    function d.changes() return h:changes() end
    function d.lastId() return h:lastId() end
    function d.version() return h:version() end
    function d.close() h:close() end
    return d
end

return M
