-- ncm_paddock / server / util -- small shared helpers for this VM.
PaddockUtil = {}

local Json = NcmCore.get("vocabulary.json")
local ids = NcmCore.get("vocabulary.ids")

function PaddockUtil.logger(tag)
    return function(fmt, ...)
        local ok, line = pcall(string.format, fmt, ...)
        print("[ncm_paddock/" .. tag .. "] " .. (ok and line or tostring(fmt)))
    end
end

function PaddockUtil.now() return math.floor(Open77.time.unix()) end
function PaddockUtil.sid() return PaddockSettings.get("serverId", "ncm-dev") end

local hostRng = function() return math.random() end
function PaddockUtil.uuid() return ids.uuid4(hostRng) end

function PaddockUtil.encode(v)
    local ok, s = pcall(Json.encode, v)
    return ok and s or nil
end

function PaddockUtil.decode(s)
    if type(s) ~= "string" or s == "" then return nil end
    local ok, v = pcall(Json.decode, s)
    return ok and v or nil
end

-- The platform caps statements per transaction (weather.lua learned it at 48); chunk everything.
PaddockUtil.TX_CHUNK = 40

--- Run a list of { query, values } statements in chunked transactions, yielding between chunks. Returns ok, err.
function PaddockUtil.transact(statements)
    local i = 1
    while i <= #statements do
        local tx = {}
        for k = i, math.min(i + PaddockUtil.TX_CHUNK - 1, #statements) do tx[#tx + 1] = statements[k] end
        local ok, err = MySQL.transaction.await(tx)
        if not ok then return false, err end
        i = i + PaddockUtil.TX_CHUNK
        if i <= #statements then Wait(0) end
    end
    return true
end

--- Yield every `n` calls: `local y = PaddockUtil.yielder(8); for ... do y() end`.
function PaddockUtil.yielder(n)
    local c = 0
    return function()
        c = c + 1
        if c >= n then c = 0; Wait(0) end
    end
end

function PaddockUtil.fmtSec(ms)
    if not ms then return "-" end
    local s = ms / 1000
    local m = math.floor(s / 60)
    return string.format("%d:%05.2f", m, s - m * 60)
end
