-- ncm_probe / server — E0 part B probes. Every result is printed with the [ncm_probe] prefix so the
-- server console is the record. Run `ncm.probe` from the console to execute the on-demand probes;
-- the readiness and restart probes run by themselves.
local RESOURCE = "ncm_probe"

local function log(fmt, ...)
    print(("[ncm_probe] " .. fmt):format(...))
end

-- GetGameTimer() returns a float on the server VM; never hand it to %d (Lua 5.4 refuses).
local function ms(a, b)
    return math.floor((tonumber(a) or 0) - (tonumber(b) or 0) + 0.5)
end

local function describe(ok, a, b)
    return ("ok=%s a=%s b=%s"):format(tostring(ok), tostring(a), tostring(b))
end

-- ---------------------------------------------------------------------------------------------
-- Probe 5 (restart cleanup): resource-private stash across a restart.
-- ---------------------------------------------------------------------------------------------
local stash = nil
if type(Open77.state) == "table" and type(Open77.state.load) == "function" then
    local okLoad, loaded = pcall(Open77.state.load)
    if okLoad and type(loaded) == "table" then stash = loaded end
end
local bootCount = math.floor((stash and tonumber(stash.bootCount) or 0) + 1)
log("boot #%d (state.load %s; previous boot at %s)", bootCount,
    stash and "restored" or "empty", tostring(stash and stash.lastBoot or "n/a"))
if type(Open77.state) == "table" and type(Open77.state.save) == "function" then
    local okSave, err = pcall(Open77.state.save, { bootCount = bootCount, lastBoot = os and os.time and os.time() or "no-os" })
    log("state.save -> %s", describe(okSave, err))
end

-- ---------------------------------------------------------------------------------------------
-- Probe 4 (readiness): hold every joining player for 2 s and see whether onPlayerReady waits.
-- ---------------------------------------------------------------------------------------------
local holds = {}
do
    local ok, a, b = pcall(Open77.ready.participate, { timeoutMs = 15000, reason = "ncm_probe readiness test" })
    log("ready.participate -> %s", describe(ok, a, b))
end

AddEventHandler("onPlayerConnected", function(playerId)
    local id = tonumber(playerId) or 0
    local ok, session, reason = pcall(Open77.ready.hold, id, "ncm_probe 2s hold")
    local t0 = GetGameTimer and GetGameTimer() or 0
    holds[id] = { session = session, t0 = t0 }
    log("hold player=%d -> %s", id, describe(ok, session ~= nil, reason))
    CreateThread(function()
        Wait(2000)
        local okR, a, b = pcall(Open77.ready.release, id, session, "ncm_probe hold released")
        log("release player=%d after %s ms -> %s", id, tostring(ms(GetGameTimer and GetGameTimer() or 0, t0)), describe(okR, a, b))
    end)
end)

AddEventHandler("onPlayerReady", function(playerId)
    local id = tonumber(playerId) or 0
    local h = holds[id]
    local waited = h and ms(GetGameTimer and GetGameTimer() or 0, h.t0) or -1
    log("onPlayerReady player=%d fired %s ms after our hold (expect >= 2000 if holds gate readiness)", id, tostring(waited))
end)

-- ---------------------------------------------------------------------------------------------
-- On-demand probes 1-3.
-- ---------------------------------------------------------------------------------------------
local tunables = nil

RegisterCommand("ncm.probe", function(source, args)
    log("=== on-demand probes by %s ===", tostring(source))

    -- Probe 1: event bus. ncm_world handles ncm:probe:ping and logs; if that log never appears,
    -- TriggerEvent is VM-local on this build.
    local ok, a, b = pcall(TriggerEvent, "ncm:probe:ping", RESOURCE, GetGameTimer and GetGameTimer() or 0)
    log("P1 TriggerEvent(ncm:probe:ping) -> %s  (look for a [ncm_world] pong line)", describe(ok, a, b))
    local okL, aL, bL = pcall(function() return TriggerLocalEvent and TriggerLocalEvent("ncm:probe:ping", RESOURCE, "local") end)
    log("P1b TriggerLocalEvent exists=%s -> %s", tostring(TriggerLocalEvent ~= nil), describe(okL, aL, bL))

    -- Probe 2: permission gating from an ungated resource.
    local okV, aV, bV = pcall(function() return Open77.vehicles.all() end)
    log("P2 Open77.vehicles.all() without world.vehicles -> ok=%s type(a)=%s a=%s b=%s",
        tostring(okV), type(aV), (type(aV) == "table" and ("#" .. tostring(#aV)) or tostring(aV)), tostring(bV))
    local okP, aP, bP = pcall(function() return Open77.players.position(1) end)
    log("P2b Open77.players.position(1) (ungated) -> %s", describe(okP, type(aP) == "table" and "table" or tostring(aP), bP))

    -- Probe 3: tunables round-trip.
    if not tunables then
        local okD, proxy, reason = pcall(Open77.tunables.declare, {
            probeSeconds = { value = 30, type = "integer", min = 1, max = 600, unit = "s", apply = "next_round" },
            probeLive = { value = false, type = "boolean", apply = "live" },
        })
        log("P3 tunables.declare -> ok=%s proxy=%s reason=%s", tostring(okD), type(proxy), tostring(reason))
        if okD and type(proxy) == "table" then tunables = proxy end
    end
    if tunables then
        local before = tunables.probeSeconds
        local okS, aS, bS = pcall(Open77.tunables.set, "probeSeconds", 45)
        local okPend, pending = pcall(Open77.tunables.pending)
        local mid = tunables.probeSeconds
        local okPr, promoted = pcall(Open77.tunables.promote)
        local after = tunables.probeSeconds
        local pendingKeys = {}
        if okPend and type(pending) == "table" then for k, _ in pairs(pending) do pendingKeys[#pendingKeys + 1] = tostring(k) end end
        local promotedKeys = {}
        if okPr and type(promoted) == "table" then for _, k in ipairs(promoted) do promotedKeys[#promotedKeys + 1] = tostring(k) end end
        log("P3 set probeSeconds 30->45: set=%s pending=[%s] value before/mid/after=%s/%s/%s promoted=[%s]",
            describe(okS, aS, bS), table.concat(pendingKeys, ","), tostring(before), tostring(mid), tostring(after), table.concat(promotedKeys, ","))
        local okL2, aL2, bL2 = pcall(Open77.tunables.set, "probeLive", true)
        log("P3b set probeLive (apply=live) -> %s now=%s", describe(okL2, aL2, bL2), tostring(tunables.probeLive))
    end
    log("=== probes done ===")
end, false)

log("loaded; run `ncm.probe` from the console for P1-P3; P4 runs on player connect; P5 across `restart ncm_probe`")
