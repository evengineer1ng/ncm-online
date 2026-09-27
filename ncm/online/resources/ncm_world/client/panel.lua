-- ncm_world / client / panel — the NCM panel page (web/panel.html): the Driver Profile questionnaire on first join
-- (L48, P29), the Messages inbox (P30) and the Race Guide (P47: F6 / /ncm.guide; interest = the ordinary entry). One interactive WebUI page on the "menu" layer; it takes focus only
-- while open, so the race HUD and the game are untouched otherwise. F7 / /ncm.msgs opens the inbox. Every action
-- has a chat twin (/ncm.q, /ncm.inbox, /ncm.read, /ncm.accept) so a client whose page cannot take input still works.
local Core = NcmCore
local Q = Core.get("onboarding.questionnaire")
local Chunks = Core.get("vocabulary.chunks")

local function log(fmt, ...) print(("[ncm_world/client/panel] " .. fmt):format(...)) end

local page, pageReady = nil, false
local open = nil            -- "questionnaire" | "inbox" | "guide" | "market" | "collection" | "help" | nil
local inputSeen = false
local pendingQuestionnaire = false
local lastInbox = nil
local lastGuide = nil
local lastResults = nil
local lastCollection = nil
local lastMarket = nil
local lastComponents = nil
local marketWire = nil

-- KB-61. Focus is the dangerous part of this file.
--
-- `page:setFocus(true, true)` takes the mouse AND the keyboard. The two ways back out were F6, which the focused
-- page swallows before the keybind sees it, and ESC, which is handled by the page's own JavaScript -- so both
-- escapes ran through the page, and the page is precisely what fails. A player was left unable to open the
-- pause menu, unable to move the cursor, and had to kill the game.
--
-- So focus now FOLLOWS a confirmed draw instead of leading it: `panel:show` is sent unfocused, the page replies
-- `panel:drawn`, and only then do we capture input. If that reply never comes, `focusWatchdog` gives the game
-- back. Nothing about releasing focus may depend on the page being healthy.
local FOCUS_CONFIRM_MS = 2500
local focusToken = 0

local function applyFocus(on)
    if not page then return end
    local ok, focused, reason = pcall(function() return page:setFocus(on, on) end)
    if not ok then log("setFocus failed: %s", tostring(focused))
    elseif focused == false then log("setFocus refused: %s", tostring(reason)) end
end

--- Give input back, whatever state the page is in. Safe to call repeatedly.
local function releaseFocus(why)
    focusToken = focusToken + 1
    applyFocus(false)
    if why then log("focus released: %s", why) end
end

-- KB-65. The panel sometimes fails to answer `panel:show` in time and the watchdog closes it. It could not be
-- diagnosed because ONLY FAILURES were reported: with no successful baseline, a fault line cannot tell you
-- whether this is one open in five or one in fifty, and a visitor's client log lives on their machine where we
-- will never read it. So every open reports itself to the SERVER, success and failure alike, in the same shape.
--
-- Deliberately counts and timestamps only -- no encoding, no string building of any size. The last attempt to
-- measure this transport by serialising it is what hit `Open77 script execution budget exceeded`.
local openStamp = 0        -- GetGameTimer() when panel:show went out
local sentChunks = 0       -- panel:list.part messages this open put on the bridge
local wantChunks = 0       -- how many it intended to send

--- One line per panel open, whatever the outcome. `ok` is the whole point: faults are only interpretable
--- next to successes.
local function reportOpen(which, ok, page_)
    local ms = openStamp > 0 and (GetGameTimer() - openStamp) or -1
    local p = type(page_) == "table" and page_ or {}
    TriggerServerEvent("ncm:panel.telemetry", {
        panel = tostring(which or "?"),
        ok = ok and true or false,
        ms = ms,                                   -- client-side: request -> confirmation
        pageMs = tonumber(p.ms) or -1,             -- page-side: show received -> drawn
        sent = sentChunks, want = wantChunks,      -- what the bridge put out
        got = tonumber(p.parts) or -1,             -- what the page actually received (KB-63 is silent)
        head = tonumber(p.head) or -1,
        held = tonumber(p.held) or -1,             -- rows the page holds at draw time
    })
end

local function setOpen(which)
    if not page then return end
    open = which
    focusToken = focusToken + 1
    if which == nil then
        applyFocus(false)
        return
    end
    openStamp, sentChunks, wantChunks = GetGameTimer(), 0, 0
    -- deliberately NOT focusing yet: wait for panel:drawn
    local token = focusToken
    CreateThread(function()
        Wait(FOCUS_CONFIRM_MS)
        if token ~= focusToken then return end          -- drawn, or something else happened
        if open ~= which then return end
        -- the page never confirmed it drew. Do not hold the player's input hostage to it.
        log("PANEL DID NOT DRAW in %d ms (panel=%s, sent %d/%d chunk(s)) -- releasing input and closing (KB-61)",
            FOCUS_CONFIRM_MS, tostring(which), sentChunks, wantChunks)
        open = nil
        applyFocus(false)
        pcall(function() page:send("panel:hide", {}) end)
        reportOpen(which, false, nil)
        TriggerServerEvent("ncm:panel.fault", tostring(which), "did not draw in " .. FOCUS_CONFIRM_MS .. " ms", "")
    end)
end

-- KB-63. `page:send` (client Lua -> WebUI page) silently drops large messages.
--
-- Proven 2026-09-22 by the same panel succeeding and failing on message size alone: with `lastGuide` nil the
-- placeholder drew fine; after a reconnect populated it, the identical call carrying ~16.8 KB never drew and the
-- watchdog closed it. Twice. The server->client NET EVENT carries 16.8 KB happily -- it is this bridge, not the
-- network, and it fails without an error, a return value or a log line.
--
-- The first attempt at a fix JSON-encoded the payload and split the string. That died on a second platform
-- limit: `Open77 script execution budget exceeded` -- encoding 16.8 KB in Lua is too much work for one client
-- script slice. So nothing is encoded here. The payload's LIST (rows / slots / items) is sent in small batches
-- of whole table values and the bridge serialises each batch itself, which is work it was always going to do.
local ROWS_PER_CHUNK = 4
local chunkSeq = 0

--- Send `value` to the page, splitting its list field when it is long enough to risk the drop.
--- `listKey` is the field holding the big array ("rows", "slots", "items").
local function sendBig(name, value, listKey, rowsPerChunk)
    if not (page and pageReady) then return end
    if type(value) ~= "table" then return end
    local list = value[listKey]
    rowsPerChunk = math.max(1, math.floor(tonumber(rowsPerChunk) or ROWS_PER_CHUNK))
    if type(list) ~= "table" or #list <= rowsPerChunk then
        page:send(name, value)
        return
    end

    -- everything except the list: small, and it carries serverNow, capabilities, weather and the rest
    local head = {}
    for k, v in pairs(value) do if k ~= listKey then head[k] = v end end

    chunkSeq = chunkSeq + 1
    local id = tostring(chunkSeq)
    local n = math.ceil(#list / rowsPerChunk)
    page:send("panel:list.begin", { id = id, name = name, listKey = listKey, n = n, head = head })
    wantChunks = wantChunks + n          -- several typed streams may compose one screen
    for i = 1, n do
        local part = {}
        for j = (i - 1) * rowsPerChunk + 1, math.min(i * rowsPerChunk, #list) do
            part[#part + 1] = list[j]
        end
        page:send("panel:list.part", { id = id, i = i, items = part })
        sentChunks = sentChunks + 1
    end
    log("sendBig: %s split into %d batch(es) of <=%d", name, n, rowsPerChunk)
end

local function sendMarket(value)
    if not (page and pageReady) or type(value)~="table" then return end
    local head={}
    for k,v in pairs(value) do
        if k~="items" and k~="offerings" and k~="vehicleOfferings" and k~="componentOfferings" then head[k]=v end
    end
    page:send("panel:market.head",head)
    sendBig("panel:market.vehicles",{offerings=value.vehicleOfferings or value.offerings or {}},"offerings")
    -- Component rows carry fitment, projection and next-asset provenance. One per WebUI message keeps the
    -- second hop bounded too; the server->client stream is independently bounded by the same rule.
    sendBig("panel:market.components",{componentOfferings=value.componentOfferings or {}},"componentOfferings",1)
end

local function questionsForPage()
    local out = {}
    for i, q in ipairs(Q.QUESTIONS) do
        local opts = {}
        for j, o in ipairs(q.options) do opts[j] = { key = o.key, text = o.text } end
        out[i] = { id = q.id, text = q.text, options = opts }
    end
    return out
end

local function showQuestionnaire()
    if not page or not pageReady then pendingQuestionnaire = true; return end
    pendingQuestionnaire = false
    setOpen("questionnaire")   -- BEFORE the send: the page can answer panel:drawn faster than the next line runs
    page:send("panel:show", { panel = "questionnaire", version = Q.VERSION, questions = questionsForPage() })
    log("questionnaire shown (v%d, %d questions)", Q.VERSION, #Q.QUESTIONS)
    -- fallback signal: if no pointer or key reaches the page within 12 s, say so in the log (the chat twin still works)
    CreateThread(function()
        Wait(12000)
        if open == "questionnaire" and not inputSeen then log("panel input: no (no pointer/key seen in 12 s) — use /ncm.q a|b|c|d") end
    end)
end

local function showInbox()
    if not page or not pageReady then return end
    TriggerServerEvent("ncm:inbox")
    setOpen("inbox")   -- BEFORE the send: the page can answer panel:drawn faster than the next line runs
    page:send("panel:show", { panel = "inbox" })
    sendBig("panel:inbox", lastInbox or { items = {}, unread = 0 }, "items")
end

local function showGuide()
    if not page or not pageReady then return end
    TriggerServerEvent("ncm:guide")
    setOpen("guide")   -- BEFORE the send: the page can answer panel:drawn faster than the next line runs
    page:send("panel:show", { panel = "guide" })
    sendBig("panel:guide", lastGuide or { rows = {}, loading = true }, "rows")
end

local function showCollection()
    if not page or not pageReady then return end
    TriggerServerEvent("ncm:collection")
    TriggerServerEvent("ncm:component.inventory.request")
    setOpen("collection")   -- BEFORE the send: the page can answer panel:drawn faster than the next line runs
    page:send("panel:show", { panel = "collection" })
    sendBig("panel:collection", lastCollection or { slots = {}, loading = true }, "slots")
    if lastComponents then sendBig("panel:components",lastComponents,"parts") end
end

-- Help. Opened by `/ncm help` (server sets the `ncmHelp` bag) rather than by a key: three of NCM's four
-- bindings already collide (KB-62), and a recovery surface that needs a free function key is not a recovery
-- surface. The command is the route, exactly as it is for the chat twins.
local lastHelp, lastHelpSeq = nil, nil
local function showHelp()
    if not page or not pageReady then return end
    TriggerServerEvent("ncm:help")
    setOpen("help")
    page:send("panel:show", { panel = "help" })
    -- no sendBig: the Help payload has no long list, so it crosses the bridge whole
    if lastHelp then page:send("panel:help", lastHelp) end
end

local function showMarket()
    if not page or not pageReady then return end
    TriggerServerEvent("ncm:market")
    setOpen("market")
    page:send("panel:show", { panel = "market" })
    sendMarket(lastMarket or { vehicleOfferings = {}, componentOfferings = {}, markets = {}, loading = true })
end

--- The WHEEL tab (`IDEA-399`).
---
--- **Unlike every other tab, its data does not come from the server.** It comes from the companion process on
--- this player's own machine, up the FFB bridge and through `NcmClientFfbState()`. So there is no
--- `TriggerServerEvent` here and nothing to wait for -- the state is local and always immediately available,
--- including the state "no companion is running", which is the one a new player will see first.
local function showWheel()
    if not page or not pageReady then return end
    setOpen("wheel")
    page:send("panel:show", { panel = "wheel" })
    local state = (type(NcmClientFfbState) == "function") and NcmClientFfbState() or nil
    page:send("panel:wheel", state or { enabled = false, connected = false })
end

--- Redraw the WHEEL tab whenever the bridge's state actually changes.
---
--- **The tab cannot be a one-shot read.** Creating the surface, loading the companion's page and waiting for
--- its socket all take longer than the button press that started them, so a snapshot taken at click time says
--- *"companion not detected"* and then stays wrong while a healthy companion sits connected behind it. That
--- is what happened on the first live run. The bridge now announces; this listens.
AddEventHandler("ncm:ffb.state", function()
    if not (page and pageReady) or open ~= "wheel" then return end
    local state = (type(NcmClientFfbState) == "function") and NcmClientFfbState() or nil
    page:send("panel:wheel", state or { enabled = false, connected = false })
end)

local function hide()
    if page and pageReady then page:send("panel:hide", {}) end
    setOpen(nil)
end

AddEventHandler("onClientResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    local reason
    page, reason = WebUI.create({
        entry = "web/panel.html", layer = "menu", width = 1920, height = 1080,
        fps = 30, zIndex = 900, transparent = true, visible = true,
    })
    if not page then log("panel WebUI failed: %s", tostring(reason)); return end
    page:on("panel:ready", function()
        pageReady = true
        log("panel ready")
        if pendingQuestionnaire then showQuestionnaire() end
    end)
    page:on("panel:pointer", function() if not inputSeen then inputSeen = true; log("panel input: yes") end end)
    page:on("panel:answer", function(d)
        inputSeen = true
        if type(d) ~= "table" then return end
        TriggerServerEvent("ncm:onboarding", d.version or Q.VERSION, d.answers or {})
        setOpen(nil)
    end)
    page:on("panel:act", function(d)
        inputSeen = true
        if type(d) == "table" and d.id and d.action then TriggerServerEvent("ncm:inbox.act", d.id, d.action) end
    end)
    page:on("panel:read", function(d)
        inputSeen = true
        if type(d) == "table" and d.id then TriggerServerEvent("ncm:inbox.read", d.id) end
    end)
    page:on("panel:interest", function(d)
        inputSeen = true
        if type(d) ~= "table" or not d.eventId then return end
        if d.action == "withdraw" then TriggerServerEvent("ncm:guide.withdraw", d.eventId) else TriggerServerEvent("ncm:guide.interest", d.eventId) end
    end)
    page:on("panel:navigate", function(d)
        if type(d) ~= "table" then return end
        if d.panel == "guide" then showGuide() elseif d.panel == "market" then showMarket()
        elseif d.panel == "collection" then showCollection()
        elseif d.panel == "wheel" then showWheel()
        elseif d.panel == "help" then showHelp() end
    end)
    -- The page owns the report id and reuses it on retry, so a resend is the same report (idempotent by key).
    page:on("panel:report.submit", function(d)
        if type(d) ~= "table" then return end
        TriggerServerEvent("ncm:report.submit", tostring(d.reportId or ""), tostring(d.text or ""),
            { panel = tostring(d.panel or "help"), ms = tonumber(d.ms) })
    end)

    -- Every wheel action is a local command to the companion; none of it reaches the server, because none
    -- of it is anyone else's business (`IDEA-388`).
    page:on("panel:wheel.command", function(d)
        if type(d) ~= "table" or type(NcmClientFfbCommand) ~= "function" then return end
        pcall(NcmClientFfbCommand, tostring(d.kind or ""), d.payload)
        -- Redraw from the authoritative state rather than from what the page assumed it just did.
        if page and pageReady and open == "wheel" then
            local state = (type(NcmClientFfbState) == "function") and NcmClientFfbState() or nil
            page:send("panel:wheel", state or { enabled = false, connected = false })
        end
    end)

    page:on("panel:market.purchase", function(d)
        if type(d) == "table" and d.marketId and d.assetId then
            TriggerServerEvent("ncm:market.purchase", d.marketId, d.assetId)
        end
    end)
    page:on("panel:component.purchase",function(d)
        if type(d)=="table" and d.assetId then TriggerServerEvent("ncm:component.purchase",tostring(d.marketId or "base_market"),tostring(d.assetId),tostring(d.idempotencyKey or "")) end
    end)
    page:on("panel:component.install",function(d)
        if type(d)=="table" and d.componentAssetId and d.machineAssetId then TriggerServerEvent("ncm:component.install",tostring(d.componentAssetId),tostring(d.machineAssetId),tostring(d.idempotencyKey or "")) end
    end)
    -- Selecting an offering is a player-facing encounter with that model, which the server may treat as a
    -- Machine Index discovery. The client only reports the act; it never decides that anything was learned.
    -- The player opened PAST RESULTS. Ask for it; it is not in the Guide payload by design.
    page:on("panel:guide.results", function()
        if lastResults then sendBig("panel:guideResults", lastResults, "results")
        else TriggerServerEvent("ncm:guide.results") end
    end)

    page:on("panel:market.inspect", function(d)
        if type(d) == "table" and type(d.vehicleKey) == "string" and d.vehicleKey ~= "" then
            TriggerServerEvent("ncm:market.inspect", tostring(d.marketId or "base_market"), d.vehicleKey)
        end
    end)
    page:on("panel:vehicle.call", function(d)
        if type(d) == "table" and type(d.assetId) == "string" then
            TriggerServerEvent("ncm:vehicle.call", d.assetId)
        end
    end)
    page:on("panel:closed", function() setOpen(nil) end)

    -- the page drew what we asked for: NOW it is safe to give it the mouse and keyboard (KB-61)
    page:on("panel:drawn", function(d)
        local which = type(d) == "table" and d.panel or nil
        if open == nil or (which ~= nil and which ~= open) then
            -- The page drew something we are no longer (or not yet) expecting. This used to be a silent
            -- `return`, and it cost a deploy: `panel:show` was sent BEFORE `setOpen` recorded the panel, so a
            -- fast reply landed while `open` was still nil, was dropped here, and the watchdog then reported
            -- "did not draw" about a panel that had drawn perfectly well.
            log("panel:drawn ignored (drawn=%s, open=%s)", tostring(which), tostring(open))
            return
        end
        focusToken = focusToken + 1      -- cancel the watchdog for this open
        applyFocus(true)
        local ms = openStamp > 0 and (GetGameTimer() - openStamp) or -1
        log("panel drawn: %s in %d ms (chunks %s/%d sent, page held %s)", tostring(which), ms,
            tostring(type(d) == "table" and d.parts or "?"), wantChunks,
            tostring(type(d) == "table" and d.held or "?"))
        reportOpen(which, true, type(d) == "table" and d or nil)
    end)

    -- the page threw while rendering. Release input first, then say what happened: this log line is the whole
    -- reason a blank panel is diagnosable at all (KB-59's second defect).
    page:on("panel:error", function(d)
        local panel = type(d) == "table" and tostring(d.panel or "?") or "?"
        local message = type(d) == "table" and tostring(d.message or "?") or "?"
        local where = type(d) == "table" and tostring(d.where or "") or ""
        open = nil
        releaseFocus("render error")
        log("PANEL RENDER ERROR panel=%s: %s %s", panel, message, where ~= "" and ("(" .. where .. ")") or "")
        -- upward, not sideways: there is no client-side chat API, and a server-side log line is the thing that
        -- makes a blank panel diagnosable without asking the player to find their own log file
        TriggerServerEvent("ncm:panel.fault", panel, message, where)
    end)
end)

-- Server state drives the panel: onboarding pending -> questionnaire; inbox bag -> list refresh.
local function onBag(key, value)
    if key == "ncmOnboarding" and type(value) == "table" then
        if value.pending and open ~= "questionnaire" then showQuestionnaire()
        elseif value.complete and open == "questionnaire" then hide() end
    elseif key == "ncmInbox" and type(value) == "table" then
        lastInbox = value
        if page and pageReady and open == "inbox" then sendBig("panel:inbox", value, "items") end
    elseif key == "ncmHelp" and type(value) == "table" then
        -- `seq` changes on every request, so asking for Help twice reopens it rather than doing nothing
        if value.seq and value.seq ~= lastHelpSeq then
            lastHelpSeq = value.seq
            showHelp()
        end
    elseif key == "ncmGuide" and type(value) == "table" then
        lastGuide = value
        -- A new Guide may follow a finished race, so the cached history is no longer necessarily complete.
        lastResults = nil
        if page and pageReady and open == "guide" then sendBig("panel:guide", value, "rows") end
    end
end

-- A Guide request gets a direct response. The replicated bag remains a mirror/fallback, but deploy 11 showed
-- that its larger championship payload may be written successfully without becoming observable on the client.
--- This driver's own results. Batched like every other list that crosses the bridge (KB-63) -- twenty rows
--- is small, but "small enough today" is exactly the reasoning that broke the Guide.
RegisterNetEvent("ncm:guide.results.payload", function(value)
    if type(value) ~= "table" then return end
    lastResults = value
    if page and pageReady and open == "guide" then sendBig("panel:guideResults", value, "results") end
end)

-- KB-97: inbox moved off the `player(id)` bag, which reached every player in the routing bucket. Message and
-- seat-offer bodies now arrive only here, at the driver they belong to.
RegisterNetEvent("ncm:inbox.payload", function(value)
    if type(value) ~= "table" then return end
    onBag("ncmInbox", value)
end)

RegisterNetEvent("ncm:guide.payload", function(value)
    if type(value) ~= "table" then return end
    lastGuide = value
    log("guide payload received: %d row(s)", type(value.rows) == "table" and #value.rows or 0)
    if page and pageReady and open == "guide" then sendBig("panel:guide", value, "rows") end
end)

RegisterNetEvent("ncm:collection.payload", function(value)
    if type(value) ~= "table" then return end
    lastCollection = value
    if page and pageReady and open == "collection" then sendBig("panel:collection", value, "slots") end
end)

RegisterNetEvent("ncm:component.inventory",function(value)
    if type(value)~="table" then return end
    lastComponents=value
    local ids={};for _,m in ipairs(type(value.machines)=="table" and value.machines or {}) do ids[#ids+1]=m.asset_id end
    TriggerServerEvent("ncm:component.state.request",ids)
    if page and pageReady and open=="collection" then sendBig("panel:components",value,"parts") end
end)
RegisterNetEvent("ncm:component.state",function(value) if page and pageReady then page:send("panel:component.states",type(value)=="table" and value or {}) end end)
RegisterNetEvent("ncm:component.install.result",function(value) if page and pageReady then page:send("panel:component.install.result",type(value)=="table" and value or {}) end end)

-- The Machine Index's CALL VEHICLE button needs to react; a toast behind the open panel is not a reaction.
RegisterNetEvent("ncm:vehicle.result", function(value)
    if page and pageReady then page:send("panel:vehicle.result", type(value) == "table" and value or {}) end
end)

RegisterNetEvent("ncm:help.payload", function(value)
    if type(value) ~= "table" then return end
    lastHelp = value
    if page and pageReady and open == "help" then page:send("panel:help", value) end
end)

RegisterNetEvent("ncm:report.result", function(value)
    if page and pageReady then page:send("panel:report.result", type(value) == "table" and value or {}) end
end)

local function finishMarketWire()
    local s=marketWire
    if not s or not Chunks.complete(s.vehicles) or not Chunks.complete(s.components) then return end
    local vehicles,vehicleWhy=Chunks.collect(s.vehicles)
    local components,componentWhy=Chunks.collect(s.components)
    if not vehicles or not components then
        log("market stream %s refused at assembly: %s/%s",tostring(s.id),tostring(vehicleWhy),tostring(componentWhy))
        marketWire=nil;return
    end
    local value=s.head
    value.offerings=vehicles;value.vehicleOfferings=vehicles;value.componentOfferings=components;value.loading=false
    lastMarket=value;marketWire=nil
    log("market stream complete id=%s vehicles=%d components=%d",tostring(s.id),#vehicles,#components)
    if page and pageReady and open=="market" then sendMarket(value) end
end

RegisterNetEvent("ncm:market.stream.begin",function(meta)
    if type(meta)~="table" or type(meta.id)~="string" then return end
    local head=type(meta.head)=="table" and meta.head or {}
    head.offerings={};head.vehicleOfferings={};head.componentOfferings={};head.loading=true
    marketWire={id=meta.id,head=head,vehicles=Chunks.receiver(meta.vehicleParts),components=Chunks.receiver(meta.componentParts)}
    lastMarket=head
    log("market stream begin id=%s packets=%d+%d",meta.id,marketWire.vehicles.expected,marketWire.components.expected)
    if page and pageReady and open=="market" then sendMarket(head) end
    finishMarketWire() -- the empty-market case has no part events
end)

RegisterNetEvent("ncm:market.stream.part",function(part)
    local s=marketWire
    if not s or type(part)~="table" or tostring(part.id or "")~=s.id then return end
    local rx=part.kind=="vehicles" and s.vehicles or (part.kind=="components" and s.components or nil)
    if not rx then return end
    local accepted,why=Chunks.accept(rx,part.index,part.items)
    if accepted==nil then log("market stream %s bad %s part %s: %s",s.id,tostring(part.kind),tostring(part.index),tostring(why)) end
    finishMarketWire()
end)

-- Legacy one-packet receive stays for one mixed-version restart window. New servers never emit it.
RegisterNetEvent("ncm:market.payload", function(value)
    if type(value) ~= "table" then return end
    lastMarket = value
    if page and pageReady and open == "market" then sendMarket(value) end
end)

--- Re-read our own player bag and apply one key. A change on somebody else's bag lands here too, so this must
--- never trust the event's payload; reading localPlayer() is what makes it ours (KB-41).
local function onLocalBag(key)
    local ok, bag = pcall(Open77.state.localPlayer)
    if ok and type(bag) == "table" then onBag(key, bag[key]) end
end

CreateThread(function()
    Wait(1500)
    local okWatch, err = pcall(function()
        -- KB-41: player bags are visible to EVERY client, so these fire for whoever changed -- and the old code
        -- passed the incoming `value` straight to onBag, discarding the selector. Any joiner's
        -- `ncmOnboarding = {pending=true}` therefore opened the Driver Profile questionnaire on every client at
        -- once, and answering it would have re-submitted the local player's own profile. Treat the watcher as a
        -- notification only and always read our own bag: correct whatever shape the selector takes, and it
        -- matches the polling fallback below, which was right all along.
        Open77.state.onChange("player", "ncmOnboarding", function() onLocalBag("ncmOnboarding") end)
        -- KB-97: `ncmInbox` and `ncmGuide` are no longer bags. Onboarding stays -- it is a harmless
        -- completion flag, and the join race the poll below guards against is real for it.
    end)
    if not okWatch then log("state.onChange unavailable: %s", tostring(err)) end
    -- poll as well: a bag written before the watcher existed (join) must still open the questionnaire
    while true do
        local ok, bag = pcall(Open77.state.localPlayer)
        if ok and type(bag) == "table" then
            if type(bag.ncmOnboarding) == "table" and bag.ncmOnboarding.pending and open ~= "questionnaire" and not pendingQuestionnaire then showQuestionnaire() end
            if type(bag.ncmHelp) == "table" then onBag("ncmHelp", bag.ncmHelp) end
        end
        Wait(2000)
    end
end)

local function toggleInbox()
    if open == "inbox" then hide() else showInbox() end
end
pcall(function() RegisterKeyMapping("ncm.panel", "NCM: messages", "F9", toggleInbox) end)   -- F7 collided with the camera toggle (owner QA)
-- Last resort if a panel ever holds input again: this runs entirely in Lua and never touches the page.
RegisterCommand("ncm.release", function()
    open = nil
    releaseFocus("ncm.release")
    pcall(function() if page and pageReady then page:send("panel:hide", {}) end end)
end, false)

RegisterCommand("ncm.msgs", toggleInbox, false)
RegisterCommand("ncm.panel", toggleInbox, false)

local function toggleGuide()
    if open == "guide" then hide() else showGuide() end
end
pcall(function() RegisterKeyMapping("ncm.guidepage", "NCM: race guide", "F6", toggleGuide) end)
RegisterCommand("ncm.guidepage", toggleGuide, false)

local function toggleCollection()
    if open == "collection" then hide() else showCollection() end
end
pcall(function() RegisterKeyMapping("ncm.collectionpage", "NCM: Machine Index", "F10", toggleCollection) end)
RegisterCommand("ncm.collectionpage", toggleCollection, false)

AddEventHandler("onClientResourceStop", function(name)
    if name == "ncm_world" then hide() end
end)
