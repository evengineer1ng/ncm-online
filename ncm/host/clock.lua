-- NCM Host clock (L338). One clock for every resource, every tape and the deck.
--   real(state)    -- the wall clock + `state.devSkew` (the DEV time lab's offset; 0 in production). Shared by all tapes,
--                     so skewing time never makes one tape's world diverge from another's real-time rules.
--   virtual(start) -- a settable clock for headless tests and catch-up harnesses; `advance(dt)` moves it.
-- unix() is UTC seconds (fractional); mono() is a monotonic seconds counter (Wait/GetGameTimer); datetime() is the
-- `YYYY-MM-DD HH:MM:SS` UTC text SQL's NOW() becomes.
local M = {}

local function datetime(u) return os.date("!%Y-%m-%d %H:%M:%S", math.floor(u)) end

function M.real(state)
    state = state or {}
    local t0, c0 = os.time(), os.clock()
    local c = { kind = "real", state = state }
    local floor = 0
    function c.unix() return math.max(floor, t0 + (os.clock() - c0) + (tonumber(state.devSkew) or 0)) end
    --- Never earlier than `u`: a Windows clock set backwards must not un-roll a tape (time stands still until it passes).
    function c.setFloor(u) floor = math.max(floor, tonumber(u) or 0) end
    local monoSkew = 0
    function c.mono() return os.clock() + monoSkew end
    function c.datetime() return datetime(c.unix()) end
    --- DEV: jump the wall clock (and every Wait with it, so threads due "later" run now).
    function c.advance(dt) state.devSkew = (tonumber(state.devSkew) or 0) + dt; monoSkew = monoSkew + dt end
    return c
end

function M.virtual(startUnix)
    local now, mono = startUnix or 1791388800, 0
    local c = { kind = "virtual" }
    function c.unix() return now end
    function c.mono() return mono end
    function c.datetime() return datetime(now) end
    function c.advance(dt) now = now + dt; mono = mono + dt end
    function c.set(u) mono = mono + math.max(0, u - now); now = u end
    local floor = 0
    local raw = c.unix
    function c.unix() return math.max(floor, raw()) end
    function c.setFloor(u) floor = math.max(floor, tonumber(u) or 0) end
    return c
end

local seeded = false
function M.uuid()
    if not seeded then math.randomseed(os.time() + math.floor(os.clock() * 1e6)); seeded = true end
    local t = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (t:gsub("[xy]", function(ch)
        local v = (ch == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

return M
