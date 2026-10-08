-- NIGHT CITY MOTORSPORTS 3.0 -- single player (L338, doc 55). The CET half.
--
-- The simulation -- the NCM Host and the NCM resources the dev server runs -- lives in the `ncm_host` RED4ext plugin
-- (its own Lua 5.4 + SQLite: CET's sandbox has no coroutines, no load, no setfenv, no _G -- KB-383/KB-384/KB-385).
-- This CET mod is the front end: the Tape Deck, the Race Week line, and the game bindings. It talks to the plugin
-- with one native, NcmHost_Call(cmd, json) -> json, on CET's own update.
--   onInit          the plugin answers `boot`; the deck is on screen at the main menu
--   a save loads    the deck again; NCM dormant until a choice; a chosen tape mounts in the plugin
--   every frame     `tick`: V's position and car go in; game commands (pins, toasts, teleports, a car to V's garage) come out
--   leaving         the tape unmounts (remembered by the plugin)
local VERSION = "3.0.0-alpha.4"

local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[NCM 3.0] " .. (ok and s or tostring(fmt)))
end

-- ------------------------------------------------------------------------------------------------ the plugin
local call   -- (cmd, payloadString) -> string
local function findPlugin()
    -- a global native through CET's Game table, else the scriptable-system wrapper the .reds declares
    local okG, ready = pcall(function() return Game.NcmHost_Ready() end)
    if okG and ready then
        call = function(c, p) return Game.NcmHost_Call(c, p) end
        return "Game.NcmHost_Call"
    end
    local okS, sys = pcall(function() return Game.GetScriptableSystemsContainer():Get("NcmHostBridge") end)
    if okS and sys then
        local okR, r = pcall(function() return sys:Ready() end)
        if okR and r then
            call = function(c, p) return sys:Call(c, p) end
            return "NcmHostBridge (scriptable system)"
        end
    end
    return nil
end

local function rpc(cmd, payload)
    if not call then return { ok = false, error = "ncm_host plugin not found" } end
    local text = payload and json.encode(payload) or "{}"
    local okC, out = pcall(call, cmd, text)
    if not okC then return { ok = false, error = tostring(out) } end
    local okD, res = pcall(json.decode, out or "")
    if not okD or type(res) ~= "table" then return { ok = false, error = "bad answer: " .. tostring(out):sub(1, 200) } end
    return res
end

-- the deck's remote port
local port = {
    deck = function() local r = rpc("deck"); return r.ok and r or nil end,
    newTape = function() return rpc("newTape") end,
    setDoc = function(k, v) rpc("setDoc", { key = k, value = v }) end,
    dev = function(a, arg) local r = rpc("dev", { action = a, arg = arg }); return r.ok, r.error end,
    garage = function() return rpc("garage") end,
    claim = function(rec, appearance) local r = rpc("claim", { record = rec, appearance = appearance }); return r.ok, r.ok and r.record or r.error end,
    aero = function(action, arg) return rpc("aero", { action = action, arg = arg }) end,
}

-- ------------------------------------------------------------------------------------------------ state
local deck, game, bootError
local overlayOpen, dormant, wasInSession, mounted = false, false, false, nil

local function readModule(rel)
    local chunk, err = loadfile(rel)
    if not chunk then error(err) end
    return chunk()
end

local function inSession()
    local ok, p = pcall(Game.GetPlayer)
    return ok and p ~= nil
end

-- ------------------------------------------------------------------------------------------------ the pad
-- Names the game sends while the deck is up (live 2026-10-07 log). IsButtonJustPressed, not the type name (it read "?").
local UP = { world_map_filter_navigation_up = true, UI_vehicle_customization_slider_up = true, popup_moveUp = true,
    UI_MoveUp = true, dpad_up = true, Choice_MoveUp = true }
local DOWN = { world_map_filter_navigation_down = true, UI_vehicle_customization_slider_down = true, popup_moveDown = true,
    UI_MoveDown = true, dpad_down = true, Choice_MoveDown = true }
local OK = { UI_Apply = true, Choice1 = true, select = true, one_click_confirm = true, popup_proceed = true, proceed = true,
    click = true, UI_Select = true, activate = true }
local BACK = { UI_Cancel = true, cancel = true, back = true, close_popup = true }
local seen, seenN = {}, 0
local function hookPad()
    Observe("PlayerPuppet", "OnAction", function(_, action)
        if not deck or not deck.open or overlayOpen then return end
        local okN, name = pcall(function() return Game.NameToString(ListenerAction.GetName(action)) end)
        if not okN or not name or name:find("Axis") or name:find("_x$") or name:find("_y$") or name:find("^Camera") then return end
        local okP, pressed = pcall(function() return ListenerAction.IsButtonJustPressed(action) end)
        if not (okP and pressed) then return end
        if not seen[name] and seenN < 200 then seen[name] = true; seenN = seenN + 1; log("deck pressed %s", name) end
        if UP[name] then deck.move(-1) elseif DOWN[name] then deck.move(1)
        elseif OK[name] then deck.choose() elseif BACK[name] and deck.mode == "intro" then deck.mode = "deck" end
    end)
end

-- ------------------------------------------------------------------------------------------------ lifecycle
-- The plugin is looked for at onInit and, if it is not reachable yet (the scriptable-system route only exists once a
-- game is running), again every second -- the deck says so instead of failing (no hard boot error for a late plugin).
local pluginReady, nextLook = false, 0
local function ensurePlugin()
    if pluginReady then return true end
    if os.clock() < nextLook then return false end
    nextLook = os.clock() + 1
    local how = findPlugin()
    if not how then
        if deck then deck.status = "Waiting for the NCM Host plugin (red4ext/plugins/ncm_host) ..." end
        return false
    end
    local b = rpc("boot", {})
    if not b.ok then
        if deck then deck.status = "NCM Host plugin did not boot: " .. tostring(b.error) end
        log("plugin boot failed: %s", tostring(b.error))
        return false
    end
    pluginReady = true
    if deck then deck.status = nil; deck.refresh(true) end
    log("plugin found via %s; v%s ready (plugin %s on %s): %d tape(s)", how, VERSION, tostring(b.version), tostring(b.host), #(b.tapes or {}))
    return true
end

registerForEvent("onInit", function()
    local ok, err = pcall(function()
        game = readModule("game/cet.lua").new()
        deck = readModule("ui/deck.lua").new(port)
        ensurePlugin()
        local okPad, why = pcall(hookPad)
        log("pad hook: %s", okPad and "registered" or ("FAILED " .. tostring(why)))
        NCM3 = { deck = deck, rpc = rpc, version = VERSION }   -- CET console: NCM3.rpc("status")
    end)
    if not ok then bootError = tostring(err); log("BOOT FAILED: %s", bootError) end
end)

registerHotkey("ncm_tape_deck", "NCM: Tape Deck", function() if deck then deck.open = not deck.open end end)

local pins = {}
local function perform(cmds)
    for _, c in ipairs(cmds or {}) do
        if c.op == "toast" then game.toast({ title = c.title, message = c.message, durationMs = c.ms })
        elseif c.op == "chat" then game.toasts[#game.toasts + 1] = { title = "", message = c.text, chat = true }
        elseif c.op == "teleport" then game.teleport({ x = c.x, y = c.y, z = c.z }, c.heading)
        elseif c.op == "pin" then game.blipUpdated(c.id, { position = { x = c.x, y = c.y, z = c.z }, title = c.title }); pins[c.id] = true
        elseif c.op == "unpin" then game.blipRemoved(c.id); pins[c.id] = nil
        elseif c.op == "clearPins" then for id in pairs(pins) do game.blipRemoved(id) end; pins = {}
        elseif c.op == "waypoint" then game.setWaypoint(not c.clear and { x = c.x, y = c.y, z = c.z } or nil)
        elseif c.op == "giveCar" then game.giveCar(c.record) end
    end
end

local function playerState()
    local s = {}
    pcall(function()
        local p = Game.GetPlayer()
        local pos = p:GetWorldPosition()
        s.x, s.y, s.z, s.heading = pos.x, pos.y, pos.z, p:GetWorldYaw()
        local v = Game.GetMountedVehicle(p)
        if v then
            local appearance
            pcall(function() appearance = Game.NameToString(v:GetCurrentAppearanceName()) end)
            s.vehicle = { record = TDBID.ToStringDEBUG(v:GetRecordID()), appearance = appearance }
        end
    end)
    return s
end

registerForEvent("onUpdate", function()
    if not deck then return end
    if not ensurePlugin() then return end
    local now = inSession()
    if now and not wasInSession then
        dormant = false
        if not mounted then deck.open = true end
    end
    if not now and wasInSession then
        if mounted then rpc("unmount"); mounted = nil; perform({ { op = "clearPins" } }) end
        deck.choice, deck.hud = nil, nil
        deck.open = true
    end
    wasInSession = now
    if not now then return end

    if deck.choice and not mounted then
        local c = deck.choice
        deck.choice = nil   -- one attempt per choice, never every frame (KB-384)
        if c.kind == "without" then
            dormant = true; deck.open = false
            log("this session: Cyberpunk without NCM")
        elseif c.kind == "tape" then
            local r = rpc("mount", { id = c.id })
            if r.ok then
                mounted = c.id; deck.open = false; deck.status = nil
                deck.returnShownUntil = os.clock() + 30
                log("mounted %s", c.id)
            else
                deck.status = "Could not enter that tape: " .. tostring(r.error)
                log("mount FAILED: %s", tostring(r.error))
            end
        end
    end
    if mounted and not dormant then
        local r = rpc("tick", { player = playerState(), budgetMs = 3 })
        if r.ok then
            deck.hud = r.hud
            if type(r.lastClaim) == "table" then deck.lastClaim = r.lastClaim end
            perform(r.commands)
        elseif not deck.tickError then
            deck.tickError = true
            log("tick error: %s", tostring(r.error))
        end
    end
end)

registerForEvent("onDraw", function()
    if bootError then
        if ImGui.Begin("NCM 3.0##boot") then ImGui.Text("NCM could not start:"); ImGui.TextWrapped(bootError) end
        ImGui.End()
        return
    end
    if not deck then return end
    pcall(deck.draw, overlayOpen, inSession(), mounted ~= nil)
    if not dormant then pcall(deck.drawHud) end
end)

registerForEvent("onOverlayOpen", function() overlayOpen = true end)
registerForEvent("onOverlayClose", function() overlayOpen = false end)
registerForEvent("onShutdown", function() if mounted then pcall(rpc, "unmount") end end)

return { version = VERSION }
