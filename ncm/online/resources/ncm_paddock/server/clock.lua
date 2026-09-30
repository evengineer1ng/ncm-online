-- ncm_paddock / server / clock -- Night City on US Eastern real time (IDEA-729, KB-217, L231).
--
-- The Paddock already keys every race to Eastern time (`world.clock`); this makes the sky agree. It only works with
-- NCM Clock installed on every client: that required mod flattens the engine's `time_of_the_day_to_timescale` curve to
-- 0.125, so the engine itself advances at 8 x 0.125 = 1x. The OPEN//77 clock then runs at rate 1.0 here, the engine
-- agrees, and the projection has nothing to correct -- no world time-jumps. A client WITHOUT NCM Clock still runs at
-- 8x and gets a correcting jump about every 15 s, so `clockMode` is the kill switch (eastern | off).
--
-- Boot sets rate 1.0 and the Eastern time; every `clockSyncSeconds` it re-reads the canonical clock and writes only
-- when it has drifted past `clockToleranceSec` (a write is itself a jump for everyone).
PaddockClock = { lastSet = nil }

local U = PaddockUtil
local log = U.logger("clock")
local Clock = NcmCore.get("world.clock")
local function set(k, d) return PaddockSettings.get(k, d) end

--- Seconds from a to b on a 24-hour circle, in (-43200, 43200].
local function circular(a, b)
    local d = (b - a) % 86400
    if d > 43200 then d = d - 86400 end
    return d
end
PaddockClock.circular = circular

--- Bring the world clock to Eastern real time. Returns what it did.
function PaddockClock.sync(force)
    if set("clockMode", "eastern") ~= "eastern" then return "off" end
    local e = Clock.eastern(U.now())
    local ok, st = pcall(Open77.environment.getState)
    local did = {}
    if not ok or type(st) ~= "table" then
        log("environment unavailable (%s); setting blind", tostring(st))
        st = {}
    end
    if math.abs((tonumber(st.rate) or 8) - 1) > 1e-3 then
        local okR, _, why = pcall(Open77.environment.setTimeRate, 1.0)
        did[#did + 1] = okR and "rate 1.0" or ("rate refused: " .. tostring(why))
    end
    if st.frozen or st.timeFrozen then pcall(Open77.environment.setTimeFrozen, false); did[#did + 1] = "unfrozen" end
    local drift = st.secondsOfDay and circular(e.secondsOfDay, tonumber(st.secondsOfDay) or 0) or nil
    if force or not drift or math.abs(drift) > set("clockToleranceSec", 120) then
        local okT, res, why = pcall(Open77.environment.setTime, e.hour, e.min, e.sec)
        did[#did + 1] = (okT and res ~= nil) and ("time %02d:%02d:%02d ET"):format(e.hour, e.min, e.sec) or ("time refused: " .. tostring(why or res))
        PaddockClock.lastSet = U.now()
    end
    if #did > 0 then log("%s%s", table.concat(did, ", "), drift and (" (drift was %d s)"):format(drift) or "") end
    return table.concat(did, ", ")
end

function PaddockClock.start()
    CreateThread(function()
        Wait(5000)
        local ok, err = pcall(PaddockClock.sync, true)
        if not ok then log("sync FAILED: %s", tostring(err)) end
        while true do
            Wait(set("clockSyncSeconds", 600) * 1000)
            local okS, errS = pcall(PaddockClock.sync, false)
            if not okS then log("sync FAILED: %s", tostring(errS)) end
        end
    end)
end

RegisterCommand("ncm.paddock.clock", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    local ok, st = pcall(Open77.environment.getState)
    local e = Clock.eastern(U.now())
    print(("[ncm_paddock] clockMode=%s eastern=%02d:%02d:%02d world=%s rate=%s frozen=%s"):format(tostring(set("clockMode", "eastern")),
        e.hour, e.min, e.sec, ok and type(st) == "table" and ("%02d:%02d:%02d"):format(st.hour or 0, st.minute or 0, st.second or 0) or "?",
        ok and type(st) == "table" and tostring(st.rate) or "?", ok and type(st) == "table" and tostring(st.frozen) or "?"))
    CreateThread(function() print("[ncm_paddock] clock sync: " .. tostring(PaddockClock.sync(true))) end)
end, false)
