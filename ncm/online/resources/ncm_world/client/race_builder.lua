-- ncm_world / client / race_builder — the Street Call form: a driver building their own race (`L179`, `L181`).
--
-- WHAT THIS IS NOT, because every one of these was an explicit constraint (owner, 2026-09-27):
--   * NOT a mode of the F6 panel shell. Calling a race is something you do standing in the street and it must
--     not require opening a full-screen menu over the world.
--   * NOT centred and NOT full screen. The card is 520px wide on the RIGHT.
--   * NOT a six-page click-through. ONE form, every field visible at once, submitted once. `L181` replaced the
--     step machine `L179` shipped, and `L193` kept that shape while changing the surface underneath it.
--   * NOT restrictive about where. The start defaults to **where the driver is standing** and every race-legal
--     node is offered for the start, the finish and any number of chained checkpoints.
--   * NOT always present. A hotkey opens it, the hotkey or BACKSPACE closes it.
--
-- ============================================================================================================
-- `L193` (2026-09-28): WHY THIS FILE NO LONGER OWNS A WEBUI PAGE, AND WHAT WAS ACTUALLY BROKEN
-- ============================================================================================================
--
-- The form had never rendered once. The previous session diagnosed that as a payload-size fault and it was
-- half right: it fixed the WRONG HOP, and then blamed a version of the feature that had in fact worked.
--
-- **There are two hops, and only one of them was bounded.**
--
--   1. server -> client. This WAS broken: the schema went out on a player state bag, a bag holds 4,032 bytes
--      (`IDEA-509`) and the schema is 11,515, so every write was discarded. That is `KB-172`, and it is fixed:
--      the form now arrives over `ncm:build` through `NcmStreamRx`, the same bounded head-plus-packets
--      transport the Guide uses. **That fix was correct and is kept.**
--
--   2. client -> WebUI page. This was ALSO broken, and nothing addressed it. `draw()` called
--      `Builder.schemaFromWire(wire)` — which re-expands the node list into BOTH `start` (HERE + 35 rows) and
--      `finish` (35 rows), restoring the full 11,515 bytes — and then handed that whole thing to the page in a
--      single `page:send("build:open", payload)`. **`page:send` silently drops large messages** (`KB-63`: no
--      error, no return value, no log line; ~16.8 KB proven to vanish while a few dozen bytes drew).
--      `client/panel.lua` splits anything over four rows for exactly this reason. So the page never received
--      `build:open`, never rendered, never replied `build:drawn`, and the 2500 ms watchdog logged
--      `FORM DID NOT DRAW` and closed the card. Every single time.
--
-- So the schema was reassembled at the last possible moment before the one hop that could not carry it. That
-- is also why **the six-page version rendered**: each of its steps sent at most five options — a few hundred
-- bytes, comfortably under the threshold. The page count was never the fault. The owner said so and was right.
--
-- **The fix is structural, not a bigger batch.** Splitting the schema into packets would work until the node
-- list grows again, which is the shelf-life fix `ncm_league/server/stream.lua`'s header already argues against.
-- Instead: **the schema never crosses the bridge at all.** Lua holds the node list, the form, the cursor and
-- the picker; the page is a pure renderer that receives only what is on screen — at most fourteen form rows or
-- nine picker rows, a few hundred bytes. The client -> page hop is bounded BY CONSTRUCTION. There is no size
-- at which this feature can silently stop drawing, because no message's size depends on the catalogue.
--
-- **And it costs no WebUI surface.** `kMaximumWebSurfaces` is 8 per resource and `ncm_world` was at 8 of 8 with
-- `web/build.html` (`IDEA-570`) — while `carrier_bridge.lua` and `race.lua`'s bridge probe create pages
-- transiently, so `WebUI.create` here could be refused outright depending on timing. The form is now a block on
-- `web/venue.html`, shared through `NcmVenueSurface` (owner decision, 2026-09-28: *"use venue.html i dont care
-- just make it work without adding a second page"*). Back to 7 of 8, and one spare again.
--
-- **INPUT IS READ IN LUA AND THE PAGE NEVER TAKES FOCUS.** `venue.html` is `pointer-events: none` and never
-- focused — that is precisely what makes it safe to leave attached during a race (`KB-67`). So the form cannot
-- be driven by dropdowns and a mouse, and it is not: arrow keys and a pad move a cursor over the rows, and
-- `Open77.input.isDown` is a PHYSICAL read that needs no focus at all. Arrows are not movement keys in
-- Cyberpunk (WASD is), which is why they were chosen; the vocabulary was read out of the deployed
-- `Open77.dll` (11,139,584 bytes, 2026-09-25) rather than guessed, per the presentation audit's own advice.
--
-- `KB-61` therefore cannot happen here: **there is no focus to hold, so there is nothing to soft-lock.** That
-- is a stronger guarantee than the handshake it replaces. The `build:drawn` reply is kept anyway, as a render
-- confirmation — a page that throws must not leave a phantom card on screen holding the venue list down.
--
-- THE KEY. `KB-62`: three of NCM's four function keys collide with something and the collisions keep moving.
-- F5 was chosen against its occupied list (F2 wardrobe, F6 POV, F7 camera, F9/F10 PolyZone, F8 ours).
-- `/ncm.build` and `/ncm.call` are the durable routes; the key is the convenient one.
local log = function(fmt, ...) print(("[ncm_world/build] " .. fmt):format(...)) end

--- The same core module the host validated with, so the sentinel and the bounds are the ones that defined them
--- rather than a second idea of their shape living on the client.
local Builder = NcmCore.get("competition.race_builder")
local Routes = NcmCore.get("course.routes")

local DRAW_CONFIRM_MS = 2500      -- the page has this long to say it drew before the card is torn down
local HERE_TICK_MS = 700          -- how often the live position is refreshed while the form is open
local TICK_MS = 60                -- input poll; per the API's advice, press edges and hold timers, never per frame
local REPEAT_FIRST_MS = 340       -- same feel as client/nav_input.lua, deliberately
local REPEAT_NEXT_MS = 130
local PICKER_WINDOW = 9           -- rows of a long list on screen at once; the BOUND on the picker message

--- Read by `client/calendar.lua` to yield the venue option list while the card is up, exactly as
--- `NcmClientRaceActive` already does for a live race.
NcmClientBuildActive = false

local S = nil                     -- the whole form state; nil when the card is closed
local drawn = false               -- the page has confirmed a render
local drawToken = 0
local hide                        -- forward declaration

-- ------------------------------------------------------------------------------------------------
-- The surface. Shared with the venue list; this file creates nothing and destroys nothing.
-- ------------------------------------------------------------------------------------------------

local function send(name, value)
    if type(NcmVenueSurface) ~= "table" then return false end
    return NcmVenueSurface.send(name, value) == true
end

local function surfaceReady()
    return type(NcmVenueSurface) == "table" and NcmVenueSurface.page() ~= nil
end

-- ------------------------------------------------------------------------------------------------
-- Position and geometry
-- ------------------------------------------------------------------------------------------------

local function localPosition()
    local ok, x, y, z = pcall(Open77.character.position)
    if ok and type(x) == "number" then return { x = x, y = y, z = z } end
    return nil
end

--- The point a chosen id refers to, or nil when it cannot be measured. HERE is the live position, which may be
--- absent — in which case the preview says the length is unknown rather than inventing one.
local function pointOf(id)
    if id == Builder.START_HERE then return S.here end
    local n = S.byId[id]
    if n and tonumber(n.x) and tonumber(n.y) then return n end
    return nil
end

local function nameOf(id)
    if id == nil then return nil end
    if id == Builder.START_HERE then return "Here" end
    local n = S.byId[id]
    return (n and (n.name or n.id)) or tostring(id)
end

--- The running route length, or nil when any leg is unmeasurable. An unknown total must read as unknown, never
--- as 0, which would look like a refusal the server has not made.
local function previewDistance()
    local f = S.form
    local seq = { f.start }
    for _, id in ipairs(f.checkpoints) do seq[#seq + 1] = id end
    if f.finish then seq[#seq + 1] = f.finish end
    if #seq < 2 then return nil end
    local total = 0
    for i = 2, #seq do
        local a, b = pointOf(seq[i - 1]), pointOf(seq[i])
        if not (a and b) then return nil end
        total = total + Routes.planarDistance(a, b)
    end
    return total * math.max(1, tonumber(f.laps) or 1)
end

local function isLoop() return S.form.finish ~= nil and S.form.start == S.form.finish end

-- ------------------------------------------------------------------------------------------------
-- The option lists. Built once per open, never sent to the page.
-- ------------------------------------------------------------------------------------------------

local function labelFor(list, id)
    for _, o in ipairs(list) do if o.id == id then return o.label or o.name or tostring(o.id) end end
    return nil
end

local function indexOf(list, id)
    for i, o in ipairs(list) do if o.id == id then return i end end
    return nil
end

-- ------------------------------------------------------------------------------------------------
-- The row model. This is what the form IS: one flat list of fields, all visible, in one card.
-- ------------------------------------------------------------------------------------------------
--
-- Each row carries a STABLE KEY and the cursor remembers the key, never the index. That is `I4`'s lesson from
-- `client/calendar.lua` verbatim: a highlight remembered by position silently jumps whenever the list around it
-- changes, and this list changes as checkpoints are added and the Laps row appears on a loop.

local function rowsModel()
    local f, rows = S.form, {}
    local function add(r) rows[#rows + 1] = r end

    add { key = "start", kind = "node", target = "start", label = "Start", value = nameOf(f.start) }

    for i, id in ipairs(f.checkpoints) do
        add { key = "cp" .. i, kind = "node", target = "cp", index = i,
              label = "Checkpoint " .. i, value = nameOf(id), removable = true }
    end
    if #f.checkpoints < S.maxCheckpoints then
        add { key = "addcp", kind = "addcp", label = "Checkpoints",
              value = ("+ add a checkpoint  (%d of %d)"):format(#f.checkpoints, S.maxCheckpoints) }
    else
        add { key = "addcp", kind = "inert", label = "Checkpoints",
              value = ("maximum %d checkpoints"):format(S.maxCheckpoints), dim = true }
    end

    add { key = "finish", kind = "node", target = "finish", label = "Finish",
          value = f.finish and nameOf(f.finish) or "choose a finish", missing = f.finish == nil }

    -- laps only mean anything on a closed route, which is why the row only exists on one
    if isLoop() then
        local n = math.max(1, tonumber(f.laps) or 1)
        add { key = "laps", kind = "enum", target = "laps", label = "Laps",
              value = n == 1 and "1 lap" or (n .. " laps") }
    end

    add { key = "class", kind = "enum", target = "class", label = "Open to",
          value = labelFor(S.class, f.classId) or tostring(f.classId or "—") }
    add { key = "when", kind = "enum", target = "when", label = "Green flag",
          value = labelFor(S.when, f.minutes) or (("In %s min"):format(tostring(f.minutes))) }

    add { key = "post", kind = "post", label = "", value = "POST THE RACE" }
    add { key = "scrap", kind = "scrap", label = "", value = "Scrap" }
    return rows
end

--- The header readout and whether POST is allowed. A PREVIEW of the server's rule, never a replacement for it:
--- `impromptu.lua` re-derives every list and re-measures the route, and can still refuse.
local function readout()
    if #S.nodes == 0 then
        return "No race-legal nodes reached this client — the form cannot be filled.", true, false
    end
    if not S.form.finish then
        return "Choose where it finishes.", true, false
    end
    local route = isLoop() and (nameOf(S.form.finish) .. " loop")
        or (nameOf(S.form.start) .. "  \226\134\146  " .. nameOf(S.form.finish))
    local d = previewDistance()
    if d == nil then
        return route .. "  \194\183  length unknown until posted", false, true
    end
    if d < S.minDistanceM then
        return ("%s  \194\183  %d m  \194\183  too short to be a race"):format(route, math.floor(d + 0.5)), true, false
    end
    local extra = #S.form.checkpoints > 0 and ("  \194\183  %d checkpoint(s)"):format(#S.form.checkpoints) or ""
    return ("%s  \194\183  %.2f km%s"):format(route, d / 1000, extra), false, true
end

-- ------------------------------------------------------------------------------------------------
-- Drawing. Every message below is small because of what it CONTAINS, not because it was split.
-- ------------------------------------------------------------------------------------------------

local function cursorIndex(rows)
    for i, r in ipairs(rows) do if r.key == S.cursor then return i end end
    return 1
end

local function render()
    if not (S and surfaceReady()) then return end
    local rows = rowsModel()
    local sel = cursorIndex(rows)
    S.cursor = rows[sel].key                     -- re-anchor if the row it pointed at is gone

    local line, bad, canPost = readout()
    S.canPost = canPost

    local out = {}
    for i, r in ipairs(rows) do
        out[i] = { label = r.label, value = r.value, sel = i == sel, dim = r.dim == true,
                   missing = r.missing == true, action = r.kind == "post" or r.kind == "scrap" }
    end
    send("build:form", {
        rows = out, readout = line, bad = bad, canPost = canPost,
        error = S.error,
        hint = S.picker and "UP/DOWN choose  \194\183  ENTER pick  \194\183  BACKSPACE cancel"
            or "UP/DOWN move  \194\183  LEFT/RIGHT change  \194\183  ENTER open  \194\183  DEL drop  \194\183  BACKSPACE close",
    })

    if S.picker then
        local list, idx = S.picker.list, S.picker.index
        local first = math.max(1, math.min(idx - math.floor(PICKER_WINDOW / 2),
                                           math.max(1, #list - PICKER_WINDOW + 1)))
        local prows = {}
        for i = first, math.min(#list, first + PICKER_WINDOW - 1) do
            prows[#prows + 1] = { label = list[i].label or list[i].name or tostring(list[i].id), sel = i == idx }
        end
        send("build:picker", { title = S.picker.title, rows = prows, pos = ("%d of %d"):format(idx, #list) })
    else
        send("build:picker", { closed = true })
    end
end

--- Tear the card down. There is no focus to release — that is the point of `L193` — but a card left on screen
--- would keep the venue option list suppressed, so the teardown must still not depend on the page being healthy.
local function teardown()
    send("build:hide", {})
    S, drawn = nil, false
    drawToken = drawToken + 1
end

hide = function(why)
    if not NcmClientBuildActive then return end
    NcmClientBuildActive = false
    teardown()
    TriggerServerEvent("ncm:build.close")
    log("closed (%s)", tostring(why or "key"))
end

-- ------------------------------------------------------------------------------------------------
-- Opening. Called by the stream, never polled: the server decides whether a form exists at all, so its
-- arrival IS the permission.
-- ------------------------------------------------------------------------------------------------

local function open(wire)
    if NcmClientRaceActive and NcmClientRacePhase ~= "complete" then log("open ignored: racing"); return end
    if NcmClientBuildActive then return end
    if type(wire) ~= "table" then return end
    if not surfaceReady() then
        log("NO VENUE SURFACE: web/venue.html has not reported ready, so there is nothing to draw the form on")
        return
    end

    -- The wire is read FIELD BY FIELD and the node list is kept ONCE. `Builder.schemaFromWire` is deliberately
    -- not called: it duplicates the list into `start` and `finish`, which is what restored the 11,515 bytes
    -- immediately before the hop that drops them (`KB-63`). It remains core's tested inverse of `wire` for
    -- anything that genuinely wants the page-shaped schema; nothing on this path does.
    local nodes = type(wire.nodes) == "table" and wire.nodes or {}
    local form = type(wire.form) == "table" and wire.form or Builder.blank({})
    form.checkpoints = type(form.checkpoints) == "table" and form.checkpoints or {}
    form.laps = tonumber(form.laps) or 1

    local byId = {}
    for _, n in ipairs(nodes) do byId[n.id] = n end

    local startOpts = { { id = Builder.START_HERE, label = "Here — where I am standing" } }
    for _, n in ipairs(nodes) do startOpts[#startOpts + 1] = n end

    S = {
        nodes = nodes, byId = byId, startOpts = startOpts,
        class = type(wire.class) == "table" and wire.class or {},
        when = type(wire.when) == "table" and wire.when or {},
        maxCheckpoints = tonumber(wire.maxCheckpoints) or Builder.MAX_CHECKPOINTS,
        minDistanceM = tonumber(wire.minDistanceM) or Builder.MIN_DISTANCE_M,
        hasPosition = wire.hasPosition == true,
        form = form,
        here = localPosition(),
        cursor = "finish",            -- the one field with no default, so the cursor starts on the only decision
        picker = nil, error = nil, canPost = false,
        lastHere = 0,
    }

    NcmClientBuildActive = true
    drawn = false
    drawToken = drawToken + 1
    local token = drawToken

    send("build:open", {})
    render()
    log("opened with %d node(s)", #nodes)

    -- A render confirmation, not a focus handshake. Nothing is being held hostage; but a page that threw must
    -- not leave a card sitting on top of the venue list with no way for the player to tell.
    CreateThread(function()
        Wait(DRAW_CONFIRM_MS)
        if token ~= drawToken then return end
        if not NcmClientBuildActive or drawn then return end
        log("FORM DID NOT DRAW in %d ms -- tearing the card down (check for a build:error; and remember " ..
            "page:send drops large messages silently, which is KB-63)", DRAW_CONFIRM_MS)
        hide("did not draw")
    end)
end

-- The form lands here. Registered at file scope because a stream that begins before its receiver exists is lost.
NcmStreamRx.receive("ncm:build", "nodes", function(wire)
    if NcmClientBuildActive then return end   -- a second arrival while a card is up is not a second card
    open(wire)
end)

--- The hotkey asks the server first. The server decides whether a form may be opened at all (cooldown, quota, a
--- race in progress) and streams the option lists; the client opens the card when the stream lands. That order
--- means a refused request never flashes an empty card.
local function request()
    if NcmClientBuildActive then hide("toggle"); return end
    -- KB-187: the result hold is not a race. The HUD keeps showing the finished session for a minute, and F5 was
    -- refused -- silently -- for all of it. The server's own gate (`busySession`) already ignores a complete one.
    if NcmClientRaceActive and NcmClientRacePhase ~= "complete" then
        log("request ignored: racing")
        pcall(Open77.exports.call, "open77_notifications", "show", { id = "ncm_build_refused", replace = true,
            type = "warning", title = "STREET CALL", message = "Finish the race you are in first.", icon = "NCM",
            durationMs = 5000 })
        return
    end
    TriggerServerEvent("ncm:build.open")
    -- This watcher exists ONLY so that a form which never arrives says so: `KB-172` was invisible for a day
    -- because the refusing side and the waiting side each logged something reasonable and neither logged the
    -- fault. A silent failure here must stay impossible.
    CreateThread(function()
        Wait(3000)
        if NcmClientBuildActive then return end
        log("NO FORM ARRIVED within 3000 ms -- the server refused (check chat) or the ncm:build stream did not " ..
            "land. If chat is silent this is a transport fault, not a refusal.")
    end)
end

-- ------------------------------------------------------------------------------------------------
-- Actions
-- ------------------------------------------------------------------------------------------------

local function openPicker(row)
    if row.target == "start" then
        S.picker = { title = "Start", list = S.startOpts, target = "start",
                     index = indexOf(S.startOpts, S.form.start) or 1 }
    elseif row.target == "finish" then
        if #S.nodes == 0 then return end
        S.picker = { title = "Finish", list = S.nodes, target = "finish",
                     index = indexOf(S.nodes, S.form.finish) or 1 }
    elseif row.target == "cp" then
        if #S.nodes == 0 then return end
        S.picker = { title = "Checkpoint " .. row.index, list = S.nodes, target = "cp", cpIndex = row.index,
                     index = indexOf(S.nodes, S.form.checkpoints[row.index]) or 1 }
    end
end

local function applyPicker()
    local p = S.picker
    if not p then return end
    local chosen = p.list[p.index]
    if chosen then
        if p.target == "start" then S.form.start = chosen.id
        elseif p.target == "finish" then S.form.finish = chosen.id
        elseif p.target == "cp" then S.form.checkpoints[p.cpIndex] = chosen.id end
    end
    S.picker = nil
    S.error = nil
end

--- Nudge a node row by one place in its own list, so a small correction needs no picker.
local function nudgeNode(row, delta)
    local list = row.target == "start" and S.startOpts or S.nodes
    if #list == 0 then return end
    local cur
    if row.target == "start" then cur = indexOf(list, S.form.start)
    elseif row.target == "finish" then cur = indexOf(list, S.form.finish)
    else cur = indexOf(list, S.form.checkpoints[row.index]) end
    local nextIdx = (((cur or 1) - 1 + delta) % #list) + 1
    local chosen = list[nextIdx]
    if not chosen then return end
    if row.target == "start" then S.form.start = chosen.id
    elseif row.target == "finish" then S.form.finish = chosen.id
    else S.form.checkpoints[row.index] = chosen.id end
    S.error = nil
end

local function nudgeEnum(row, delta)
    if row.target == "laps" then
        local n = math.max(1, tonumber(S.form.laps) or 1)
        S.form.laps = ((n - 1 + delta) % 5) + 1
    elseif row.target == "class" then
        if #S.class == 0 then return end
        local cur = indexOf(S.class, S.form.classId) or 1
        S.form.classId = S.class[(((cur - 1 + delta) % #S.class) + 1)].id
    elseif row.target == "when" then
        if #S.when == 0 then return end
        local cur = indexOf(S.when, S.form.minutes) or 1
        S.form.minutes = S.when[(((cur - 1 + delta) % #S.when) + 1)].id
    end
    S.error = nil
end

--- Default a new checkpoint to the first node that is not the point before it, so adding one never produces a
--- zero-length leg the server would refuse.
local function addCheckpoint()
    if #S.form.checkpoints >= S.maxCheckpoints then return end
    local prev = #S.form.checkpoints > 0 and S.form.checkpoints[#S.form.checkpoints] or S.form.start
    local pick = nil
    for _, n in ipairs(S.nodes) do if n.id ~= prev then pick = n.id; break end end
    if not pick then return end
    S.form.checkpoints[#S.form.checkpoints + 1] = pick
    S.cursor = "cp" .. #S.form.checkpoints
    S.error = nil
end

local function submit()
    if not S.canPost then return end
    S.error = nil
    log("submitting form")
    TriggerServerEvent("ncm:build.submit", {
        start = S.form.start,
        checkpoints = S.form.checkpoints,
        finish = S.form.finish,
        classId = S.form.classId,
        minutes = S.form.minutes,
        laps = S.form.laps,
    })
end

local function act(action)
    if not S then return end
    local rows = rowsModel()
    local i = cursorIndex(rows)

    if S.picker then
        local p = S.picker
        if action == "up" or action == "left" then p.index = math.max(1, p.index - 1)
        elseif action == "down" or action == "right" then p.index = math.min(#p.list, p.index + 1)
        elseif action == "pageUp" then p.index = math.max(1, p.index - PICKER_WINDOW)
        elseif action == "pageDown" then p.index = math.min(#p.list, p.index + PICKER_WINDOW)
        elseif action == "activate" then applyPicker()
        elseif action == "back" then S.picker = nil end
        render()
        return
    end

    if action == "up" or action == "down" then
        local step = action == "up" and -1 or 1
        local j = i
        for _ = 1, #rows do
            j = ((j - 1 + step) % #rows) + 1
            if rows[j].kind ~= "inert" then break end
        end
        S.cursor = rows[j].key
    elseif action == "left" or action == "right" then
        local row = rows[i]
        local delta = action == "left" and -1 or 1
        if row.kind == "node" then nudgeNode(row, delta)
        elseif row.kind == "enum" then nudgeEnum(row, delta) end
    elseif action == "activate" then
        local row = rows[i]
        if row.kind == "node" then openPicker(row)
        elseif row.kind == "addcp" then addCheckpoint()
        elseif row.kind == "enum" then nudgeEnum(row, 1)
        elseif row.kind == "post" then submit()
        elseif row.kind == "scrap" then hide("scrapped"); return end
    elseif action == "delete" then
        local row = rows[i]
        if row.removable then
            table.remove(S.form.checkpoints, row.index)
            S.cursor = "addcp"
            S.error = nil
        end
    elseif action == "back" then
        hide("back")
        return
    end
    render()
end

-- ------------------------------------------------------------------------------------------------
-- Input. Physical reads, press edges and repeat timers — no focus, so nothing can be soft-locked.
-- ------------------------------------------------------------------------------------------------
--
-- The keyboard names are the deployed plugin's own vocabulary (`Up`/`Down`/`Left`/`Right`/`Enter`/`Backspace`/
-- `Delete`/`PageUp`/`PageDown`), read out of `Open77.dll` rather than guessed. Arrows and Enter are not bound to
-- movement in Cyberpunk, so reading them while the game still has input costs the player nothing. **ESC is
-- deliberately NOT a close key**: it opens the pause menu, and one control doing two jobs is how `KB-32`
-- happened. BACKSPACE closes, and the hotkey still toggles.

local BINDINGS = {
    { action = "up",       keys = { "Up", "padUp" },                  repeats = true },
    { action = "down",     keys = { "Down", "padDown" },              repeats = true },
    { action = "left",     keys = { "Left", "padLeft" },              repeats = true },
    { action = "right",    keys = { "Right", "padRight" },            repeats = true },
    { action = "pageUp",   keys = { "PageUp", "padLeftShoulder" },    repeats = true },
    { action = "pageDown", keys = { "PageDown", "padRightShoulder" }, repeats = true },
    { action = "activate", keys = { "Enter", "padA" } },
    { action = "back",     keys = { "Backspace", "padB" } },
    { action = "delete",   keys = { "Delete", "padY" } },
}

local held = {}   -- action -> { since, nextAt }

local function anyDown(keys)
    for _, k in ipairs(keys) do
        local ok, down = pcall(Open77.input.isDown, k)
        if ok and down == true then return true end
    end
    return false
end

CreateThread(function()
    while true do
        if NcmClientBuildActive and S then
            if NcmClientRaceActive then
                hide("race started")
            else
                -- another surface holding input (the F6 panel takes keyboard AND cursor) owns these keys
                local captured = false
                pcall(function() captured = Open77.input.isCaptured() == true end)
                local now = Open77.time.monotonic() * 1000

                if not captured then
                    for _, b in ipairs(BINDINGS) do
                        local down = anyDown(b.keys)
                        local h = held[b.action]
                        if down and not h then
                            held[b.action] = { since = now, nextAt = now + REPEAT_FIRST_MS }
                            act(b.action)
                        elseif down and h and b.repeats and now >= h.nextAt then
                            h.nextAt = now + REPEAT_NEXT_MS
                            act(b.action)
                        elseif not down then
                            held[b.action] = nil
                        end
                    end
                else
                    held = {}
                end

                -- Keep the preview honest: a "here" start is resolved at SUBMIT time, so if the driver wanders
                -- while choosing, the route length they are looking at must move with them.
                if S and (now - S.lastHere) >= HERE_TICK_MS then
                    S.lastHere = now
                    local p = localPosition()
                    if p then S.here = p end
                    if S.form.start == Builder.START_HERE then render() end
                end
            end
            Wait(TICK_MS)
        else
            held = {}
            Wait(250)
        end
    end
end)

-- ------------------------------------------------------------------------------------------------
-- The page talking back, and the server talking back
-- ------------------------------------------------------------------------------------------------

if type(NcmVenueSurface) == "table" then
    NcmVenueSurface.on("build:drawn", function()
        drawn = true
        log("form drawn")
    end)
    -- A page that threw may not have drawn; it must not leave a card holding the venue list down.
    NcmVenueSurface.on("build:error", function(d)
        local msg = type(d) == "table" and tostring(d.message or "?") or "?"
        local where = type(d) == "table" and tostring(d.where or "") or ""
        log("PAGE ERROR (%s): %s", where, msg)
        hide("page error")
    end)
else
    log("NcmVenueSurface missing: client/calendar.lua must load before this file")
end

--- The server refused the submitted form. Show it in the card, where the driver is looking.
RegisterNetEvent("ncm:build.refused", function(message)
    if not (NcmClientBuildActive and S) then return end
    S.error = tostring(message or "")
    render()
end)

--- The server posted it. The card's job is done.
RegisterNetEvent("ncm:build.posted", function()
    if NcmClientBuildActive then
        NcmClientBuildActive = false
        teardown()
        log("posted")
    end
end)

pcall(function() RegisterKeyMapping("ncm.build", "NCM: call a race", "F5", request) end)
RegisterCommand("ncm.build", request, false)
-- `/ncm.call` is named as a durable route by this file's own header, by `KB-62` and by `IDEA-646`, and it was
-- never registered -- so the documented fallback for a colliding key did not exist. It does now.
RegisterCommand("ncm.call", request, false)
NcmQuickActions = NcmQuickActions or {}
NcmQuickActions.call = request

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    if NcmClientBuildActive then NcmClientBuildActive = false; teardown() end
end)
