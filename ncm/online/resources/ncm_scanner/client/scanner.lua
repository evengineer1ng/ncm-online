-- ncm_scanner / client / scanner -- the Scanner's client half (`L197`, `IDEA-679`).
--
-- Three owners, one job each:
--   * `ncm-vision` (required mod) SEES AND DRAWS: the green render on Tab / Caps Lock, the native reticle and
--     its two side panels (QUICKHACKS and SCAN DATA, 0.3.0), and a report of the look-at object (EntityID hash,
--     record key, kind, distance, world position) while vision is on.
--   * this file DECIDES THE LOCK: which machine the reticle holds, how far the scan has got (`competition.scanner`
--     `step`, the same function the core tests cover), and what the reticle and panels say.
--   * the server DECIDES KNOWLEDGE: `ncm:scanner.query` says whether a target is an NCM machine, whether this
--     Driver knows it, and which network vehicle it is; `ncm:scanner.scan` is the only write. Fog of war holds
--     on the wire -- an unknown machine's name arrives only in the reply to an admitted scan.
--
-- **Discovery is gated behind the Scanner** (owner, 2026-09-28): proximity no longer identifies a machine. A
-- network vehicle (NCM ambient traffic, a player's car) is `server_measured`; a vanilla per-client car is
-- `client_attested`, which the server rate-limits and records as such.
--
-- Cost: nothing runs per frame. While vision is off this pings the plugin four times a second to learn that it
-- turned on; while it is on, 20 Hz.
local function log(fmt, ...) print(("[ncm_scanner] " .. fmt):format(...)) end

local Scanner = NcmCore.get("competition.scanner")

local ACTIVE_TICK_MS, IDLE_TICK_MS = 50, 250
local IDENTIFIED_SHOW_MS = 3000
local MATCH_DISTANCE_M = 3.0        -- aimedEntity and redscript's look-at agree if they are this close
local QUERY_RETRY_MS = 1500         -- an unanswered query is asked again; one lost reply must never stick
local BUSY_RETRY_MS = 400
local REFRESH_MS = 5000             -- an answered target is re-asked quietly: someone may have got in or out

-- Reticle states: the DLL's `Reticle` enum.
local R = { bare = 0, searching = 1, unknown = 2, known = 3, scanning = 4, identified = 5, refused = 6 }
-- Quickhack row states: the DLL's `HackRow.state`.
local ROW = { ready = 0, unavailable = 1, slotting = 2, uploading = 3, cooling = 4, incoming = 5 }

local REASONS = {
    no_ncm_record = "NO NCM RECORD", out_of_range = "OUT OF RANGE", other_bucket = "NOT IN YOUR WORLD",
    no_snapshot = "SIGNAL LOST", no_server_position = "SIGNAL LOST", attested_too_soon = "SCANNER COOLING DOWN",
    attested_hourly_limit = "SCANNER COOLING DOWN", no_driver = "NO DRIVER PROFILE", write_failed = "INDEX UNAVAILABLE",
    no_record = "NO NCM RECORD",
}

-- ------------------------------------------------------------------------------------------------------------
-- Transport: a loopback surface to the plugin (L129). The plugin owns 38600-38603 -- its own range, never the
-- Carrier's, Rig Bridge's or Radial's. Hidden; it draws nothing.
-- ------------------------------------------------------------------------------------------------------------
local PORT_BASE, PORT_SPAN = 38600, 4
local portIndex = 0
local surface, surfaceReady = nil, false
local health = nil
local lastAttemptAt, attempts = 0, 0

local function url() return ("http://127.0.0.1:%d/vision.html"):format(PORT_BASE + portIndex) end
local function now() return GetGameTimer() end

local function send(payload)
    if not (surface and surfaceReady) then return false end
    return (pcall(function() surface:send("ncm:vision.send", payload) end))
end

local target = { active = false }   -- the plugin's latest report

local function tearDown(why)
    if surface then
        pcall(function() surface:destroy() end)
        log("transport closed (%s)", tostring(why))
    end
    surface, surfaceReady, health = nil, false, nil
    target = { active = false }
end

local function bringUp()
    if surface then return end
    local page, reason = WebUI.create({
        entry = url(), layer = "hud", width = 16, height = 16, fps = 10,
        zIndex = 1, transparent = true, visible = true,
    })
    if not page then
        attempts = attempts + 1
        portIndex = (portIndex + 1) % PORT_SPAN
        if attempts == PORT_SPAN then
            log("no NCM Scanner plugin on 127.0.0.1:%d-%d (%s); green still works, nothing can be identified",
                PORT_BASE, PORT_BASE + PORT_SPAN - 1, tostring(reason))
        end
        return
    end
    surface = page
    pcall(function() page:hide() end)
    page:on("ncm:vision.ready", function()
        surfaceReady, attempts = true, 0
        log("transport connected at %s", url())
        send({ cmd = "health" })
    end)
    page:on("ncm:vision.closed", function(info)
        local wasReady = surfaceReady
        surfaceReady = false
        if not wasReady then
            tearDown("closed before connecting: " .. tostring(type(info) == "table" and info.detail or "?"))
            portIndex = (portIndex + 1) % PORT_SPAN
        end
    end)
    page:on("ncm:vision.target", function(v)
        if type(v) == "table" then target = v end
    end)
    page:on("ncm:vision.health", function(h)
        if type(h) ~= "table" then return end
        if not health then log("plugin %s", tostring(h.version)) end
        health = h
    end)
end

-- ------------------------------------------------------------------------------------------------------------
-- What the reticle is on, and what the server said about it
-- ------------------------------------------------------------------------------------------------------------
local lock = nil                 -- competition.scanner step state
local status = {}                -- entity -> { phase, indexable, known, label, category, reason, token,
                                 --             vehicleId, operator, operatorName }
local nextToken = 0
local pendingByToken = {}        -- token -> entity
local identified = nil           -- { entity, label, at }
local outlined = false

local function token()
    nextToken = nextToken + 1
    return tostring(nextToken)
end

--- Name the target the way the server can check it. A vehicle the server has already placed (its answer
--- carries a vehicle id), or one OPEN//77's aimedEntity agrees on, is `networked`, by id. Anything else goes up
--- as `vanilla` with its record key AND its world position: the server looks for a network vehicle at that
--- point first (live, 2026-09-29: aimedEntity missed players' cars and NCM traffic, which then read as
--- vanilla guesses and could not be hacked).
local function describe(t)
    if not t.active or t.kind ~= "vehicle" or not t.entity or t.entity == "" then return nil end
    local d = tonumber(t.distance) or -1
    local pos = type(t.pos) == "table" and t.pos or nil
    local s = status[t.entity]
    if s and s.vehicleId then
        return { kind = "networked", vehicleId = s.vehicleId, entity = t.entity, distance = d, pos = pos }
    end
    local ok, aimed = pcall(Open77.character.aimedEntity)
    if ok and type(aimed) == "table" and aimed.vehicleId ~= nil then
        local same = tostring(aimed.engineEntity) == t.entity
            or math.abs((tonumber(aimed.distance) or -100) - d) <= MATCH_DISTANCE_M
        if same then
            return { kind = "networked", vehicleId = aimed.vehicleId, entity = t.entity, distance = d, pos = pos }
        end
    end
    local key = (t.recordKey and t.recordKey ~= "") and t.recordKey or nil
    if not key and not pos then return nil end
    return { kind = "vanilla", recordKey = key, entity = t.entity, distance = d, pos = pos }
end

--- Ask the server about a machine, once -- and again if no answer came (`live, 2026-09-28`: a query the server
--- dropped left the reticle on READING for as long as vision stayed on). An answered target is re-asked
--- quietly every few seconds, keeping its answer on screen meanwhile. A late answer to an older token is still
--- accepted: every token for this entity maps back to it.
local function ask(desc)
    local s = status[desc.entity]
    local t = now()
    local due = not s or (s.phase == "query" and t >= (s.retryAt or 0))
        or (s.phase == "answered" and t >= (s.refreshAt or 0))
    if not due then return s end
    local tk = token()
    s = s or { phase = "query", asks = 0 }
    s.token, s.retryAt, s.asks = tk, t + QUERY_RETRY_MS, (s.asks or 0) + 1
    if s.phase == "answered" then s.refreshAt = t + REFRESH_MS end
    s.kind = desc.kind
    status[desc.entity] = s
    pendingByToken[tk] = desc.entity
    TriggerServerEvent("ncm:scanner.query", { token = tk, kind = desc.kind, vehicleId = desc.vehicleId,
        recordKey = desc.recordKey, distance = desc.distance, pos = desc.pos })
    return s
end

RegisterNetEvent("ncm:scanner.result", function(r)
    if type(r) ~= "table" then return end
    local entity = pendingByToken[tostring(r.token)]
    pendingByToken[tostring(r.token)] = nil
    if not entity then return end
    local s = status[entity] or {}
    status[entity] = s
    if r.phase == "query" and r.busy then
        if s.phase ~= "answered" then s.phase, s.retryAt = "query", now() + BUSY_RETRY_MS end
    elseif r.phase == "query" then
        if s.phase ~= "scan" then s.phase = "answered" end
        s.refreshAt = now() + REFRESH_MS
        s.indexable, s.known, s.reason = r.indexable == true, r.known == true, r.reason
        s.label, s.category = r.label or (s.known and s.label) or nil, r.category or (s.known and s.category) or nil
        s.vehicleId = tonumber(r.vehicleId)
        s.operator, s.operatorName = r.operator, r.operatorName
    elseif r.phase == "scan" then
        if r.ok then
            s.phase, s.indexable, s.known, s.label, s.category = "answered", true, true, r.label, r.category
            s.refreshAt = now() + REFRESH_MS
            if r.first then
                identified = { entity = entity, label = r.label, at = now() }
                log("identified %s (%s)", tostring(r.label), tostring(r.basis))
            end
        else
            s.phase, s.reason, s.scanRefused = "answered", r.reason, true
        end
    end
end)

local function setOutline(on)
    if on == outlined then return end
    outlined = on
    pcall(Open77.inspector.outline, on)
end

local function upper(v) return v and tostring(v):upper() or nil end

--- The SCAN DATA panel: what the Scanner knows about the target, vanilla's right-hand column.
local function scanData(frame, desc, s)
    if not desc then return frame end
    local rows = {}
    local operator
    if not (s and s.vehicleId) then operator = (s and s.phase == "answered") and "LOCAL TRAFFIC" or "…"
    elseif s.operator == "driver" then operator = upper(s.operatorName) or "DRIVER"
    elseif s.operator == "traffic" then operator = "NCM TRAFFIC"
    else operator = "UNATTENDED" end
    rows[#rows + 1] = { k = "OPERATOR", v = operator }
    if s and s.phase ~= "query" then
        rows[#rows + 1] = { k = "NETWORK", v = s.vehicleId and "LINKED" or "LOCAL ONLY" }
        local index
        if s.known then index = "IN YOUR INDEX"
        elseif s.indexable then index = "UNIDENTIFIED"
        else index = REASONS[s.reason] or "NO NCM RECORD" end
        rows[#rows + 1] = { k = "INDEX", v = index }
    end
    if desc.distance and desc.distance >= 0 then
        rows[#rows + 1] = { k = "DISTANCE", v = ("%d M"):format(math.floor(desc.distance + 0.5)) }
    end
    local title, sub
    if not s or s.phase == "query" then title, sub = "READING…", nil
    elseif s.known then title, sub = s.label or "KNOWN MACHINE", upper(s.category)
    elseif s.indexable then title, sub = "UNIDENTIFIED MACHINE", "HOLD THE RETICLE TO IDENTIFY"
    else title, sub = "VEHICLE", "NOT AN NCM MACHINE" end
    frame.infoTitle, frame.infoSub, frame.info = title, sub, rows
    return frame
end

--- Everything the reticle says, from the current target, its status and the lock.
local function compose(t)
    local desc = describe(t)
    if not desc then
        lock = Scanner.step(lock, { active = true }, now())
        setOutline(false)
        return { state = R.searching }, nil, nil
    end
    if identified and identified.entity == desc.entity and now() - identified.at < IDENTIFIED_SHOW_MS then
        setOutline(true)
        local s = status[desc.entity]
        return scanData({ state = R.identified, progress = 1, title = identified.label,
                          detail = "ENTERS THE MACHINE INDEX" }, desc, s), desc, s
    end
    local s = ask(desc)
    if s.phase == "query" then
        setOutline(true)
        return scanData({ state = R.searching, detail = "READING…" }, desc, s), desc, s
    end
    if not s.indexable then
        setOutline(s.vehicleId ~= nil)
        return scanData({ state = R.refused, title = REASONS[s.reason] or "NO NCM RECORD" }, desc, s), desc, s
    end
    if s.known then
        setOutline(true)
        lock = nil
        return scanData({ state = R.known, title = s.label or "", detail = "IN YOUR INDEX" }, desc, s), desc, s
    end
    if s.scanRefused then
        setOutline(true)
        return scanData({ state = R.refused, title = REASONS[s.reason] or "SCAN REFUSED",
                          detail = "UNIDENTIFIED MACHINE" }, desc, s), desc, s
    end
    lock = Scanner.step(lock, { active = true, entity = desc.entity, kind = desc.kind, distance = desc.distance }, now())
    setOutline(true)
    if lock.reason == "out_of_range" then
        return scanData({ state = R.refused, title = "OUT OF RANGE",
                          detail = ("%d m"):format(math.floor(desc.distance + 0.5)) }, desc, s), desc, s
    end
    if lock.complete then
        s.phase = "scan"
        local tk = s.token or token()
        s.token = tk
        pendingByToken[tk] = desc.entity
        TriggerServerEvent("ncm:scanner.scan", { token = tk, kind = desc.kind, vehicleId = desc.vehicleId,
            recordKey = desc.recordKey, distance = desc.distance, pos = desc.pos })
    end
    if s.phase == "scan" then
        return scanData({ state = R.scanning, progress = 1, title = "UNIDENTIFIED MACHINE",
                          detail = "IDENTIFYING…" }, desc, s), desc, s
    end
    return scanData({ state = R.scanning, progress = lock.progress, title = "UNIDENTIFIED MACHINE",
                      detail = ("SCANNING  %d%%"):format(math.floor(lock.progress * 100)) }, desc, s), desc, s
end


-- ------------------------------------------------------------------------------------------------------------
-- CHROME: vehicle quickhacks, used from the Scanner and only while scanning (owner, 2026-09-28)
-- ------------------------------------------------------------------------------------------------------------
--
-- While vision is on the whole roster is on screen in the QUICKHACKS column (vanilla's quickhack list): X
-- selects the next hack and Z the previous one (selecting slots it into the deck, a durable cyberware install
-- on the server), and holding G uploads the selected hack onto the car in the reticle, or onto your own car
-- for PURGE and SYSTEM RESTORE. Releasing G cancels. All three are ordinary rebindable mappings. With vision
-- off they do nothing. The server (`ncm_world/server/chrome.lua`) decides everything; this file asks and shows.
local Chrome = NcmCore.get("competition.chrome")
local CHROME_KEYS = {
    cycle = { id = "ncm.chrome.cycle", name = "NCM Chrome: next hack (while scanning)", key = "X" },
    back = { id = "ncm.chrome.back", name = "NCM Chrome: previous hack (while scanning)", key = "Z" },
    upload = { id = "ncm.chrome.upload", name = "NCM Chrome: hold to upload (while scanning)", key = "G" },
}
local HOLD_BEAT_MS = 300
local NOTE_MS = 2500

local chrome = {
    selected = 1,             -- index into the usable roster below
    slotted = nil,            -- the grade the server says the deck holds
    uploading = nil,          -- { token, hack, vehicleId, at }
    progress = nil,           -- { actionId, phase, progress, label, at } for the reticle
    note = nil, noteAt = 0,   -- last result/refusal, shown briefly
    lastBeat = 0,
    cooldowns = {},           -- hack id -> game-timer ms it is usable again (mirrors the server's clock)
}

local ROSTER = {}
for _, h in ipairs(Chrome.ROSTER) do if not h.passive then ROSTER[#ROSTER + 1] = h end end

local CHROME_REASONS = {
    out_of_range = "OUT OF RANGE", no_target = "NO TARGET", own_vehicle = "THAT'S YOUR CAR",
    cooling_down = "COOLING DOWN", not_in_a_vehicle = "NOT IN A VEHICLE", slotting = "SLOTTING INTO DECK",
    needs_driven_ncm_machine = "NEEDS A DRIVEN NCM MACHINE", lock_lost = "LOCK LOST", target_lost = "TARGET LOST",
    left_vehicle = "LEFT THE VEHICLE", cancelled = "CANCELLED", blocked = "BLOCKED BY ICE", interrupted = "INTERRUPTED",
    unknown_hack = "UNKNOWN HACK", no_position = "NO POSITION",
}

local function selectedHack() return ROSTER[chrome.selected] end

local function note(text) chrome.note, chrome.noteAt = text, now() end

local function scanning() return surfaceReady and target.active == true end

local function lockedVehicleId()
    local desc = describe(target)
    return desc and desc.vehicleId or nil
end

local function cycle(step)
    if not scanning() then return end
    chrome.selected = (chrome.selected - 1 + step) % #ROSTER + 1
    TriggerServerEvent("ncm:chrome.select", selectedHack().id)
end

local function uploadPressed()
    if not scanning() or chrome.uploading then return end
    local h = selectedHack()
    local vid = nil
    if h.target == "other" then
        vid = lockedVehicleId()
        if not vid then note(target.kind == "vehicle" and "LOCAL TRAFFIC — NOT ON THE NETWORK" or "NO TARGET"); return end
    end
    local tk = "c" .. token()
    chrome.uploading = { token = tk, hack = h.id, vehicleId = vid, at = now() }
    TriggerServerEvent("ncm:chrome.start", { token = tk, hack = h.id, vehicleId = vid })
end

local function uploadReleased()
    if chrome.uploading then
        TriggerServerEvent("ncm:chrome.cancel")
        chrome.uploading = nil
    end
end

local function registerChromeKeys()
    local reg = (Open77.input and Open77.input.registerKeyMapping) or RegisterKeyMapping
    pcall(reg, { id = CHROME_KEYS.cycle.id, name = CHROME_KEYS.cycle.name, key = CHROME_KEYS.cycle.key,
                 onPressed = function() cycle(1) end })
    pcall(reg, { id = CHROME_KEYS.back.id, name = CHROME_KEYS.back.name, key = CHROME_KEYS.back.key,
                 onPressed = function() cycle(-1) end })
    pcall(reg, { id = CHROME_KEYS.upload.id, name = CHROME_KEYS.upload.name, key = CHROME_KEYS.upload.key, hold = true,
                 onPressed = function() uploadPressed() end, onReleased = function() uploadReleased() end })
end
registerChromeKeys()

RegisterNetEvent("ncm:chrome.state", function(s)
    if type(s) ~= "table" then return end
    if s.slotted ~= nil or s.error then chrome.slotted = s.slotted end
    local h = s.hack and Chrome.hack(s.hack) or nil
    -- The server starts a hack's cooldown when it admits it: an upload that begins, a channel, a self purge.
    if h and (s.result == "uploading" or s.result == "channel" or (s.result == "impact" and h.target == "self")) then
        local until_ = now() + (h.cooldownMs or 0)
        if (chrome.cooldowns[h.id] or 0) < until_ - 1000 or s.result ~= "impact" then chrome.cooldowns[h.id] = until_ end
    end
    if s.token and chrome.uploading and s.token == chrome.uploading.token then
        if s.result == "refused" or s.result == "interrupted" or s.result == "blocked" or s.result == "impact" then
            chrome.uploading = nil
        end
    end
    if s.result == "refused" or s.result == "interrupted" or s.result == "blocked" then
        note(CHROME_REASONS[s.reason] or CHROME_REASONS[s.result] or tostring(s.reason or s.result):upper())
    elseif s.result == "impact" then
        note((h and h.label or tostring(s.hack)) .. " LANDED")
    elseif s.result == "channel" then
        note("RESTORING SYSTEMS")
    end
end)

--- Native bars: the attacker's UPLOAD and the defender's INCOMING, driven here because the platform's reference
--- hacking resource ships in no server package. The reticle mirrors the attacker's side while scanning.
RegisterNetEvent("ncm:chrome.present", function(p)
    if type(p) ~= "table" then return end
    if Open77.hacking and Open77.hacking.present and tonumber(p.actionId) then
        pcall(Open77.hacking.present, { actionId = tonumber(p.actionId), phase = tostring(p.phase),
            progress = tonumber(p.progress) or 0 })
    end
    chrome.progress = { actionId = p.actionId, phase = p.phase, progress = tonumber(p.progress) or 0,
                        label = p.label, at = now() }
    if p.phase == "incoming" then note("INCOMING " .. tostring(p.label or "HACK") .. " — PURGE OR BREAK RANGE") end
end)

--- The QUICKHACKS column: every hack, each saying whether it can be used on this target right now.
local function hackRows(desc, s)
    local t = now()
    local rows = {}
    local p = chrome.progress
    local live = p and t - p.at < 800 and p.phase == "upload" and p or nil
    for i, h in ipairs(ROSTER) do
        local st, right = ROW.ready, nil
        local cd = (chrome.cooldowns[h.id] or 0) - t
        if chrome.uploading and chrome.uploading.hack == h.id then
            st, right = ROW.uploading, live and ("%d%%"):format(math.floor(live.progress * 100)) or "UPLOADING"
        elseif cd > 0 then
            st, right = ROW.cooling, ("%ds"):format(math.ceil(cd / 1000))
        elseif h.target == "other" then
            if not desc then st, right = ROW.unavailable, "NO TARGET"
            elseif not (s and s.vehicleId) then st, right = ROW.unavailable, (s and s.phase == "answered") and "LOCAL ONLY" or "…"
            elseif h.carrier and s.operator ~= "driver" then st, right = ROW.unavailable, "DRIVEN ONLY"
            elseif desc.distance and h.range and desc.distance > h.range then st, right = ROW.unavailable, ("%d M"):format(h.range)
            elseif i == chrome.selected and chrome.slotted ~= h.id then st, right = ROW.slotting, "SLOTTING"
            else right = ("%.1fs"):format((h.uploadMs or 0) / 1000) end
        else
            right = h.channelMs and ("SELF %.0fs"):format(h.channelMs / 1000) or "SELF"
        end
        rows[#rows + 1] = { s = st, l = h.label, r = right or "" }
    end
    return rows
end

--- Layer chrome over the scan frame: the list, any upload in flight on the reticle bar, and the latest note.
local function chromeOverlay(frame, desc, s)
    local t = now()
    local p = chrome.progress
    frame.hacks = hackRows(desc, s)
    frame.selected = chrome.selected - 1
    if p and t - p.at < 800 and (p.phase == "upload" or p.phase == "incoming") then
        frame.state = p.phase == "incoming" and R.refused or R.scanning
        frame.progress = p.progress
        frame.title = (p.phase == "incoming" and "INCOMING " or "") .. tostring(p.label or selectedHack().label) ..
            (p.phase == "incoming" and "" or " UPLOAD")
        frame.detail = ("%d%%"):format(math.floor(p.progress * 100))
        return frame
    end
    if chrome.note and t - chrome.noteAt < NOTE_MS then frame.detail = chrome.note end
    return frame
end

--- Keep an NCM-route upload alive: the server interrupts it when the lock proof stops arriving.
local function chromeBeat()
    local u = chrome.uploading
    if not u or not u.vehicleId then return end
    local t = now()
    if t - chrome.lastBeat < HOLD_BEAT_MS then return end
    chrome.lastBeat = t
    if lockedVehicleId() == u.vehicleId then TriggerServerEvent("ncm:chrome.hold", u.vehicleId) end
end

-- ------------------------------------------------------------------------------------------------------------
-- The loop
-- ------------------------------------------------------------------------------------------------------------
local wasActive = false

CreateThread(function()
    Wait(3000)
    while true do
        local t = now()
        if not surface then
            if t - lastAttemptAt > (attempts < PORT_SPAN and 1500 or 15000) then
                lastAttemptAt = t
                bringUp()
            end
            Wait(IDLE_TICK_MS)
        elseif not surfaceReady then
            Wait(IDLE_TICK_MS)
        elseif target.active then
            if not wasActive then wasActive = true end
            local frame, desc, s = compose(target)
            frame = chromeOverlay(frame, desc, s)
            chromeBeat()
            frame.cmd = "frame"
            frame.progress = frame.progress or 0
            frame.title = frame.title or ""
            frame.detail = frame.detail or ""
            send(frame)
            Wait(ACTIVE_TICK_MS)
        else
            if wasActive then
                -- Vision went off: forget the lock and every answer, so the next look asks again.
                wasActive, lock, status, pendingByToken = false, nil, {}, {}
                setOutline(false)
                -- Hacks are only possible while scanning: vision off ends an upload in flight.
                uploadReleased()
            end
            send({ cmd = "ping" })
            Wait(IDLE_TICK_MS)
        end
    end
end)

-- ------------------------------------------------------------------------------------------------------------
-- /ncm.scanner   transport, plugin and the current target
-- ------------------------------------------------------------------------------------------------------------
RegisterCommand("ncm.scanner", function()
    log("transport: %s (%s)", surfaceReady and "connected" or (surface and "connecting" or "down"), url())
    log("plugin: %s", health and tostring(health.version) or "not heard from -- is the ncm-vision required mod 0.3+ installed?")
    log("vision=%s kind=%s entity=%s recordKey=%s distance=%s pos=%s", tostring(target.active), tostring(target.kind),
        tostring(target.entity), tostring(target.recordKey), tostring(target.distance),
        type(target.pos) == "table" and ("%.1f,%.1f,%.1f"):format(target.pos.x or 0, target.pos.y or 0, target.pos.z or 0) or "nil")
    local ok, aimed = pcall(Open77.character.aimedEntity)
    if ok and type(aimed) == "table" then
        log("aimedEntity: engineEntity=%s kind=%s vehicleId=%s distance=%s", tostring(aimed.engineEntity),
            tostring(aimed.kind), tostring(aimed.vehicleId), tostring(aimed.distance))
    else
        log("aimedEntity: %s", ok and "nothing" or tostring(aimed))
    end
    local s = target.entity and status[target.entity] or nil
    if s then
        log("status: kind=%s phase=%s asks=%s indexable=%s known=%s reason=%s vehicleId=%s operator=%s",
            tostring(s.kind), tostring(s.phase), tostring(s.asks), tostring(s.indexable), tostring(s.known),
            tostring(s.reason), tostring(s.vehicleId), tostring(s.operator))
    end
    if lock then log("lock: entity=%s progress=%.2f reason=%s", tostring(lock.entity), lock.progress or 0, tostring(lock.reason)) end
    log("chrome: selected=%s slotted=%s uploading=%s", tostring(selectedHack().id), tostring(chrome.slotted),
        tostring(chrome.uploading and chrome.uploading.hack))
end, false)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    setOutline(false)
    tearDown("resource stop")
end)
