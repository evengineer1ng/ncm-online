-- ncm_world / client / panel — the NCM panel page (web/panel.html): the Driver Profile questionnaire on first join
-- (L48, P29), the Messages inbox (P30) and the Race Guide (P47: F6 / /ncm.guide; interest = the ordinary entry). One interactive WebUI page on the "menu" layer; it takes focus only
-- while open, so the race HUD and the game are untouched otherwise. F7 / /ncm.msgs opens the inbox. Every action
-- has a chat twin (/ncm.q, /ncm.inbox, /ncm.read, /ncm.accept) so a client whose page cannot take input still works.
local Core = NcmCore
local Q = Core.get("onboarding.questionnaire")
local Chunks = Core.get("vocabulary.chunks")
local Landing = Core.get("player.landing")

local function log(fmt, ...) print(("[ncm_world/client/panel] " .. fmt):format(...)) end

local page, pageReady = nil, false
local open = nil            -- F6 shell mode, questionnaire/landing, or nil
local inputSeen = false
local pendingQuestionnaire = false
local lastInbox = nil
local lastThreads = nil      -- the conversation graph (ncm:graph.threads)
local selectedThread = nil   -- which conversation the player has open; the server defaults it when nil
local lastGuide = nil
local lastResults = nil
local lastCollection = nil
-- Assets of this player's that are materialised in the world right now (server-pushed; see
-- `server/vehicle_access.lua`). Held here so the button is right the instant the panel draws.
local lastCalled = nil
local lastMarket = nil
local lastComponents = nil
local lastTrade = nil
local lastVisibility = nil
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

-- Forward declaration: the pad's BACK action must close the panel through the SAME Lua path the keybind uses,
-- never through the page. See `client/nav_input.lua` and KB-61.
local hide

local function applyFocus(on)
    if not page then return end
    local ok, focused, reason = pcall(function() return page:setFocus(on, on) end)
    if not ok then log("setFocus failed: %s", tostring(focused))
    elseif focused == false then log("setFocus refused: %s", tostring(reason)) end

    -- Gamepad navigation follows focus exactly, so every panel mode gets it from this one place rather than
    -- each surface growing its own controller code. Attaching only while focused also means nothing polls the
    -- pad while the player is simply driving.
    if type(NcmNavInput) ~= "table" then return end
    if on then
        pcall(NcmNavInput.attach, page, { onBack = function() if hide then hide() end end })
    else
        pcall(NcmNavInput.detach)
    end
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

--- MESSAGES. A shell tab now, not a hotkey (owner, 2026-09-28): the inbox was the only NCM surface with its own
--- function key and no seat in the F6 shell, which made it the one surface a player had to be told about. It sits
--- immediately left of HELP.
---
--- Two payloads feed it and they are deliberately separate. `ncm:inbox` is the NOTICE list -- seat offers, which
--- are addressed to the player, carry a deadline and are answered rather than discussed. `ncm:graph.threads` is
--- the conversation graph. Asking for both means a player with a pending seat offer and a pending Dex message
--- sees both, rather than whichever system happened to write last.
---
--- They are two payloads and no longer two surfaces: the page folds a notice into the thread list as mail from
--- its sender (`KB-173`), so this client still sends both and makes no decision about where they are drawn.
local function showMessages()
    if not page or not pageReady then return end
    TriggerServerEvent("ncm:inbox")
    TriggerServerEvent("ncm:graph.threads", selectedThread)
    setOpen("messages")   -- BEFORE the send: the page can answer panel:drawn faster than the next line runs
    page:send("panel:show", { panel = "messages" })
    sendBig("panel:inbox", lastInbox or { items = {}, unread = 0 }, "items")
    if lastThreads then sendBig("panel:graph", lastThreads, "lines") end
end

local function showGuide()
    if not page or not pageReady then return end
    TriggerServerEvent("ncm:guide")
    setOpen("guide")   -- BEFORE the send: the page can answer panel:drawn faster than the next line runs
    page:send("panel:show", { panel = "guide" })
    sendBig("panel:guide", lastGuide or { rows = {}, loading = true }, "rows")
end

-- ---------------------------------------------------------------------------------------------------------
-- Session Landing Panel.
--
-- Appears on every session entry during alpha, not once per install: the progression contract stays true for
-- the whole of development, so a player who joined in week one still needs to read it in week nine.
--
-- The "already seen" watermark is a CLIENT KVP, not a schema column. `Open77.kvp` is isolated by connection
-- address, resource and key, which is exactly the right scope for a presentation preference -- and it keeps a
-- landing panel from stacking a migration on top of 036, whose twice-applied dry-run is still owed. The cost
-- is honest and small: a player on a second machine sees the same releases marked NEW once more.
local SEEN_KEY = "landing.lastReleaseDate"
local landingPayload = nil

local function landingSeen()
    local ok, value = pcall(Open77.kvp.get, SEEN_KEY)
    if ok and type(value) == "string" and value ~= "" then return { lastReleaseDate = value } end
    return {}
end

local function landingAdvance(payload)
    local nextSeen = Landing.advance(landingSeen(), payload)
    if nextSeen and nextSeen.lastReleaseDate then
        pcall(Open77.kvp.set, SEEN_KEY, nextSeen.lastReleaseDate)
    end
end

--- Build the payload. Content is authored client-side in `landing_content.lua`, so the panel never waits on
--- the host to render -- session initialisation must not depend on this panel, and this panel must not depend
--- on session initialisation either.
local function landingBuild()
    local content = type(NcmLandingContent) == "table" and NcmLandingContent or {}
    local ok, payload = pcall(Landing.payload, content, landingSeen())
    if not ok then log("landing payload failed: %s", tostring(payload)); return nil end
    return payload
end

local function showLanding()
    if not page or not pageReady then return end
    landingPayload = landingBuild()
    if not landingPayload then return end
    setOpen("landing")
    page:send("panel:show", { panel = "landing", landing = landingPayload })
end

local function showDriver()
    if not page or not pageReady then return end
    TriggerServerEvent("ncm:visibility.request")
    setOpen("driver")
    page:send("panel:show", { panel = "driver", driver = lastVisibility or { loading = true } })
end

local function showCollection()
    if not page or not pageReady then return end
    TriggerServerEvent("ncm:collection")
    TriggerServerEvent("ncm:component.inventory.request")
    TriggerServerEvent("ncm:vehicle.active.request")
    setOpen("collection")   -- BEFORE the send: the page can answer panel:drawn faster than the next line runs
    page:send("panel:show", { panel = "collection" })
    sendBig("panel:collection", lastCollection or { slots = {}, loading = true }, "slots")
    if lastComponents then sendBig("panel:components",lastComponents,"parts") end
    if lastCalled then page:send("panel:vehicle.active", lastCalled) end
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

--- EXCHANGE. A first-class F6 surface: exact Machines, stored Parts and cash from both Drivers. The payload is
--- streamed because a mature garage is deliberately unbounded; the page receives rows in small batches too.
local function showTrade()
    if not page or not pageReady then return end
    setOpen("trade")
    page:send("panel:show", { panel = "trade" })
    sendBig("panel:trade", lastTrade or { state="idle", rows={}, loading=true }, "rows", 2)
    TriggerServerEvent("ncm:trade.request")
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

-- Assigns the forward-declared local above (not `local function`), so `applyFocus` and the pad's BACK share
-- this exact close path.
function hide()
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
    -- The player has read the landing panel. Only then does the "seen" watermark move, so a panel that was
    -- opened and never drawn cannot silently mark releases as read.
    page:on("panel:landing.seen", function()
        if landingPayload then landingAdvance(landingPayload) end
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
        if d.panel == "driver" then showDriver()
        elseif d.panel == "guide" then showGuide() elseif d.panel == "market" then showMarket()
        elseif d.panel == "collection" then showCollection()
        elseif d.panel == "trade" then showTrade()
        elseif d.panel == "wheel" then showWheel()
        elseif d.panel == "messages" then showMessages()
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
    page:on("panel:component.service",function(d)
        if type(d)=="table" and d.componentAssetId and d.conditionId then TriggerServerEvent("ncm:component.service",tostring(d.componentAssetId),tostring(d.conditionId),tostring(d.idempotencyKey or "")) end
    end)
    page:on("panel:trade.invite",function(d)
        if type(d)=="table" and d.playerId then TriggerServerEvent("ncm:trade.invite",tonumber(d.playerId)) end
    end)
    page:on("panel:trade.respond",function(d)
        TriggerServerEvent("ncm:trade.respond",type(d)=="table" and d.accept==true)
    end)
    page:on("panel:trade.edit",function(d)
        if type(d)=="table" then TriggerServerEvent("ncm:trade.edit",d) end
    end)
    page:on("panel:trade.confirm",function(d)
        if type(d)=="table" then TriggerServerEvent("ncm:trade.confirm",tonumber(d.revision)) end
    end)
    page:on("panel:trade.cancel",function() TriggerServerEvent("ncm:trade.cancel") end)
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
    -- The same button, once the Machine is already out there. Storing needs no placement and no proximity,
    -- so the client has nothing to contribute beyond the identity.
    page:on("panel:vehicle.store", function(d)
        if type(d) == "table" and type(d.assetId) == "string" then
            TriggerServerEvent("ncm:vehicle.store", d.assetId)
        end
    end)
    -- CONVERSATION. Three actions, and all three are advisory: the SERVER re-projects the choice against fresh
    -- state and refuses one the page should no longer be offering (§0.3). The page is a view, never the authority.
    page:on("panel:graph.open", function(d)
        inputSeen = true
        if type(d) ~= "table" or type(d.contactId) ~= "string" then return end
        selectedThread = d.contactId
        TriggerServerEvent("ncm:graph.open", d.contactId)
    end)
    page:on("panel:graph.reply", function(d)
        inputSeen = true
        if type(d) ~= "table" or type(d.contactId) ~= "string" or type(d.choiceId) ~= "string" then return end
        selectedThread = d.contactId
        TriggerServerEvent("ncm:graph.reply", d.contactId, d.choiceId)
    end)
    page:on("panel:graph.shelf", function(d)
        inputSeen = true
        if type(d) ~= "table" or type(d.contactId) ~= "string" or type(d.key) ~= "string" then return end
        selectedThread = d.contactId
        TriggerServerEvent("ncm:graph.shelf", d.contactId, d.key)
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
        if page and pageReady and open == "messages" then sendBig("panel:inbox", value, "items") end
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

-- IDEA-595 / KB-160. Every list payload arrives as a head plus numbered row packets, because the whole-payload
-- event is the thing that disappears once it grows -- four times now (KB-59, KB-86, KB-153, KB-160), each time
-- with no error, no return value and no log line. `ncm_league/server/stream.lua` is the sending half.
--
-- A partial stream is never handed on: a schedule drawn with rows missing and no way to tell is worse than one
-- that has not drawn yet. `onComplete(value)` gets the reassembled payload with `loading` cleared.
local function receiveStream(channel, listKey, onComplete)
    local wire = nil

    local function finish()
        if not wire or not Chunks.complete(wire.rx) then return end
        local rows, why = Chunks.collect(wire.rx)
        if not rows then
            log("%s stream %s refused at assembly: %s", channel, tostring(wire.id), tostring(why))
            wire = nil
            return
        end
        local value = wire.head
        value[listKey] = rows
        value.loading = false
        log("%s stream complete id=%s %s=%d", channel, tostring(wire.id), listKey, #rows)
        wire = nil
        onComplete(value)
    end

    RegisterNetEvent(channel .. ".stream.begin", function(meta)
        if type(meta) ~= "table" or type(meta.id) ~= "string" then return end
        local head = type(meta.head) == "table" and meta.head or {}
        head[listKey] = {}
        head.loading = true
        wire = { id = meta.id, head = head, rx = Chunks.receiver(tonumber(meta.parts) or 0) }
        log("%s stream begin id=%s packets=%d %s=%s", channel, meta.id, wire.rx.expected, listKey, tostring(meta.count))
        finish()   -- an empty list has no part events at all
    end)

    RegisterNetEvent(channel .. ".stream.part", function(part)
        if not wire or type(part) ~= "table" or tostring(part.id or "") ~= wire.id then return end
        local accepted, why = Chunks.accept(wire.rx, part.index, part.items)
        if accepted == nil then
            log("%s stream %s bad part %s: %s", channel, wire.id, tostring(part.index), tostring(why))
        end
        finish()
    end)
end

receiveStream("ncm:guide", "rows", function(value)
    lastGuide = value
    -- A new Guide may follow a finished race, so the cached history is no longer necessarily complete.
    lastResults = nil
    if page and pageReady and open == "guide" then sendBig("panel:guide", value, "rows") end
end)

receiveStream("ncm:guide.results", "results", function(value)
    lastResults = value
    if page and pageReady and open == "guide" then sendBig("panel:guideResults", value, "results") end
end)

receiveStream("ncm:inbox", "items", function(value) onBag("ncmInbox", value) end)

--- The conversation graph. `lines` is the streamed list because a transcript is the only unbounded part;
--- the sidebar and the projected replies ride in the head (see `server/graph.lua`).
receiveStream("ncm:graph", "lines", function(value)
    lastThreads = value
    if type(value.thread) == "table" and type(value.thread.contactId) == "string" then
        selectedThread = value.thread.contactId
    end
    if page and pageReady and open == "messages" then sendBig("panel:graph", value, "lines") end
end)

receiveStream("ncm:collection", "slots", function(value)
    lastCollection = value
    if page and pageReady and open == "collection" then sendBig("panel:collection", value, "slots") end
end)

receiveStream("ncm:component.inventory", "parts", function(value)
    lastComponents = value
    local ids = {}
    for _, m in ipairs(type(value.machines) == "table" and value.machines or {}) do ids[#ids + 1] = m.asset_id end
    TriggerServerEvent("ncm:component.state.request", ids)
    if page and pageReady and open == "collection" then sendBig("panel:components", value, "parts") end
end)

receiveStream("ncm:trade", "rows", function(value)
    lastTrade=value
    if page and pageReady and open=="trade" then sendBig("panel:trade",value,"rows",2) end
end)

-- Legacy whole-payload receivers, kept for ONE mixed-version restart window, exactly as the Market hop kept its
-- own (KB-153). A current server emits none of them.
RegisterNetEvent("ncm:guide.payload", function(value)
    if type(value) ~= "table" then return end
    lastGuide = value
    log("guide payload received whole (legacy): %d row(s)", type(value.rows) == "table" and #value.rows or 0)
    if page and pageReady and open == "guide" then sendBig("panel:guide", value, "rows") end
end)

RegisterNetEvent("ncm:visibility.payload", function(value)
    if type(value) ~= "table" then return end
    lastVisibility = value
    if page and pageReady and open == "driver" then page:send("panel:driver", value) end
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
RegisterNetEvent("ncm:component.service.result",function(value) if page and pageReady then page:send("panel:component.service.result",type(value)=="table" and value or {}) end end)
RegisterNetEvent("ncm:market.purchase.result",function(value) if page and pageReady then page:send("panel:market.purchase.result",type(value)=="table" and value or {}) end end)
RegisterNetEvent("ncm:component.purchase.result",function(value) if page and pageReady then page:send("panel:component.purchase.result",type(value)=="table" and value or {}) end end)
RegisterNetEvent("ncm:trade.result",function(value) if page and pageReady then page:send("panel:trade.result",type(value)=="table" and value or {}) end end)
RegisterNetEvent("ncm:trade.open",function() showTrade() end)

-- The Machine Index's CALL VEHICLE button needs to react; a toast behind the open panel is not a reaction.
RegisterNetEvent("ncm:vehicle.result", function(value)
    if page and pageReady then page:send("panel:vehicle.result", type(value) == "table" and value or {}) end
end)

-- Which owned Machines are standing in the world. The page turns CALL into STORE from this and nothing else,
-- so it is held across opens: a car called before the panel was closed is still out there.
RegisterNetEvent("ncm:vehicle.active", function(value)
    lastCalled = type(value) == "table" and value or { assets = {} }
    if page and pageReady then page:send("panel:vehicle.active", lastCalled) end
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

local function toggleMessages()
    if open == "messages" then hide() else showMessages() end
end
-- **NO KEY MAPPING.** Messages had F9 (and F7 before it, which collided with the camera toggle in owner QA).
-- The key is deliberately released, 2026-09-28: `KB-62` records that three of NCM's four function keys collide
-- with something and that the collisions keep moving, so a surface that can live in the shell should not spend
-- one. Messages is now a tab in the F6 shell, immediately left of HELP. The chat twins below still work, and
-- a player who has bound F9 themselves keeps it -- nothing here claims the key.
-- Last resort if a panel ever holds input again: this runs entirely in Lua and never touches the page.
RegisterCommand("ncm.release", function()
    open = nil
    releaseFocus("ncm.release")
    pcall(function() if page and pageReady then page:send("panel:hide", {}) end end)
end, false)

RegisterCommand("ncm.msgs", toggleMessages, false)
RegisterCommand("ncm.panel", toggleMessages, false)
RegisterCommand("ncm.messages", toggleMessages, false)

local function toggleGuide()
    if open == "guide" then hide() else showGuide() end
end
-- F6 opens the whole shell now -- guide, market, exchange, machine index, messages -- so it is the HUB, not
-- the race guide (owner, 2026-09-28). The mapping id stays `ncm.guidepage` so nobody's rebinding is lost.
pcall(function() RegisterKeyMapping("ncm.guidepage", "NCM: hub", "F6", toggleGuide) end)
RegisterCommand("ncm.guidepage", toggleGuide, false)
NcmQuickActions = NcmQuickActions or {}
NcmQuickActions.hub = toggleGuide

local function toggleCollection()
    if open == "collection" then hide() else showCollection() end
end
pcall(function() RegisterKeyMapping("ncm.collectionpage", "NCM: Machine Index", "F10", toggleCollection) end)
RegisterCommand("ncm.collectionpage", toggleCollection, false)

-- ---------------------------------------------------------------------------------------------------------
-- Landing panel: automatic on session entry, plus a retrieval path that survives dismissal.
local function toggleLanding()
    if open == "landing" then hide() else showLanding() end
end
RegisterCommand("ncm.whatsnew", toggleLanding, false)
RegisterCommand("ncm.landing", toggleLanding, false)

--- The chat twin. Essential information must not become reachable only through one graphical path, so the
--- contract, today's capabilities and the newest release are all readable without the panel at all.
RegisterCommand("ncm.alpha", function()
    local payload = landingBuild()
    -- `Open77.chat` is SERVER-only. A client resource talks to the chat through `open77_chat`'s own client
    -- export, which takes a string or a table. Fire and forget: the promise is not awaited, because a chat
    -- line must never be able to stall a command.
    local function tell(text)
        pcall(Open77.exports.call, "open77_chat", "addMessage", "[NCM] " .. text)
    end
    if not payload then tell("Alpha status unavailable."); return end
    tell(payload.contract.headline .. " -- " .. payload.contract.body)
    local live = {}
    for _, capability in ipairs(payload.capabilities) do
        if capability.state ~= "soon" then
            live[#live + 1] = capability.label .. (capability.state == "partial" and " (partial)" or "")
        end
    end
    tell("You can: " .. table.concat(live, " / "))
    local newest = payload.currentRelease
    if newest then
        tell(("Latest: %s (%s). /ncm.whatsnew for the full changelog."):format(newest.title, newest.date))
    end
end, false)

-- Automatic on session entry. Deliberately independent of every other boot step: the world, the player and
-- the economy initialise normally whether or not this panel is open or dismissed, so a player who leaves it up
-- for ten minutes cannot wedge anything. The delay only lets the page finish loading.
local landingShown = false
local function landingOnEntry()
    if landingShown then return end
    landingShown = true
    CreateThread(function()
        Wait(6000)
        -- Never steal a surface the player already opened, and never interrupt a race.
        if open ~= nil then return end
        showLanding()
    end)
end

AddEventHandler("open77:worldReady", landingOnEntry)
CreateThread(function() Wait(12000); landingOnEntry() end)   -- covers a resource that starts after worldReady

AddEventHandler("onClientResourceStop", function(name)
    if name == "ncm_world" then hide() end
end)
