-- NCM Host: the Open77 world model, bound to Cyberpunk through Cyber Engine Tweaks (L338, doc 55 §6).
--
-- The headless API (api/headless.lua) keeps the canonical model -- player, vehicles, blips, environment -- and calls
-- these hooks when something must happen in the game. Every hook is pcall-guarded and reports success: a binding
-- that fails logs ONCE and the world goes on headless for that call (doc 55 §G lists what is bound and what is not).
--
-- P2 (this build) binds: the player's position/heading/vehicle INTO the model every frame; teleport; map pins for
-- blips; the GPS waypoint; toasts. Vehicles, NPCs and props the resources create stay HEADLESS (P3: DynamicEntitySystem
-- + ncm-pace's AIVehicleRacingCommand). NOT VERIFIED IN GAME until MASTER_TEST §TP passes.
local M = {}

local warned = {}
local function once(key, fmt, ...)
    if warned[key] then return end
    warned[key] = true
    print(("[NCM Host/game] " .. fmt):format(...))
end

local function guard(key, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then once(key, "%s failed: %s", key, tostring(a)); return nil, tostring(a) end
    return a, b
end

function M.new()
    local g = { pins = {}, toasts = {}, inSession = false }

    function g.player() local ok, p = pcall(Game.GetPlayer); if ok then return p end end

    --- Every frame while mounted: the game is the truth for where V is.
    function g.sync(h)
        local p = g.player()
        if not p then g.inSession = false; return end
        g.inSession = true
        local w = h.world
        guard("sync.position", function()
            local pos = p:GetWorldPosition()
            w.player.position = { x = pos.x, y = pos.y, z = pos.z }
            w.player.heading = p:GetWorldYaw()
        end)
        guard("sync.vehicle", function()
            local v = Game.GetMountedVehicle(p)
            if v then
                local appearance = nil
                pcall(function() appearance = Game.NameToString(v:GetCurrentAppearanceName()) end)
                w.player.gameVehicle = { record = TDBID.ToStringDEBUG(v:GetRecordID()), appearance = appearance,
                    entityId = tostring(v:GetEntityID().hash) }
            else
                w.player.gameVehicle = nil
            end
        end)
    end

    function g.teleport(pos, heading)
        return guard("teleport", function()
            local p = g.player()
            if not p or not pos then return false end
            Game.GetTeleportationFacility():Teleport(p, Vector4.new(pos.x, pos.y, pos.z, 1.0), EulerAngles.new(0, 0, tonumber(heading) or 0))
            return true
        end)
    end

    -- The GPS waypoint: the game's own custom-position mappin (what the map's "set waypoint" makes) -- drawn in the world.
    local function pinAt(pos)
        local data = NewObject("gamemappinsMappinData")
        data.mappinType = TweakDBID.new("Mappins.DefaultStaticMappin")
        data.variant = Enum.new("gamedataMappinVariant", "CustomPositionVariant")
        data.active = true
        return Game.GetMappinSystem():RegisterMappin(data, Vector4.new(pos.x, pos.y, (pos.z or 0) + 0.5, 1.0))
    end

    -- A resource BLIP is a MAP pin, as OPEN//77 draws it: world map + minimap, never a floating icon across the city
    -- (live 2026-10-07: every landmark, racer and fuel station hung in the sky with a distance). NCM 2.0's proven
    -- recipe (MTERaceBeacon.reds: Custom Map Markers' definition + GameplayRoleMappinData), with no world range.
    local function mapPinAt(pos, spec)
        local role = NewObject("GameplayRoleMappinData")
        role.m_isQuest = false
        role.m_visibleThroughWalls = false
        role.m_range = 0.0
        role.m_gameplayRole = Enum.new("EGameplayRole", "FastTravel")
        role.m_textureID = TweakDBID.new("MappinIcons.GenericDeviceMappin")
        role.m_showOnMiniMap = true
        role.m_isMappinCustom = true
        role.m_isMappinExternal = false
        role.m_customMappinTitle = tostring(spec and spec.title or "NCM")
        role.m_customMappinDescription = tostring(spec and spec.description or "")
        role.m_customMappinTexturePart = CName.new("stopwatch")
        local data = NewObject("gamemappinsMappinData")
        data.mappinType = TweakDBID.new("Mappins.CustomMapMarkersMappinDefinition")
        data.variant = Enum.new("gamedataMappinVariant", "CPO_PingGoHereVariant")
        data.active = true
        data.visibleThroughWalls = false
        data.debugCaption = tostring(spec and spec.title or "NCM")
        data.scriptData = role
        return Game.GetMappinSystem():RegisterMappin(data, Vector4.new(pos.x, pos.y, (pos.z or 0) + 0.5, 1.0))
    end

    -- HOTFIX (live 2026-10-07 19:24, "crazy lag"): ~200 role pins (landmarks + racers every 2 s) through CET cost
    -- whole frames. Map layers are OFF in single player until phase 2 draws them from redscript under a budget
    -- (L340); the GPS waypoint (setWaypoint) is unaffected.
    g.MAP_LAYERS = false
    function g.blipCreated(id, spec)
        if not g.MAP_LAYERS then return end
        local pos = spec and (spec.position or (spec.x and spec))
        if not pos then return end
        local mid = guard("blip.create", mapPinAt, pos, spec)
        if mid then g.pins[id] = mid end
    end
    function g.blipRemoved(id)
        local mid = g.pins[id]
        if not mid then return end
        g.pins[id] = nil
        guard("blip.remove", function() Game.GetMappinSystem():UnregisterMappin(mid) end)
    end
    -- a moving pin (a Paddock racer) is MOVED, not torn down and re-registered every update
    function g.blipUpdated(id, spec)
        if not g.MAP_LAYERS then return end
        local mid = g.pins[id]
        local pos = spec and (spec.position or (spec.x and spec))
        if mid and pos then
            local okM = guard("blip.move", function()
                Game.GetMappinSystem():SetMappinPosition(mid, Vector4.new(pos.x, pos.y, (pos.z or 0) + 0.5, 1.0)); return true end)
            if okM then return end
        end
        g.blipRemoved(id); g.blipCreated(id, spec)
    end

    local waypointPin
    function g.setWaypoint(pos)
        if waypointPin then local old = waypointPin; waypointPin = nil; guard("waypoint.clear", function() Game.GetMappinSystem():UnregisterMappin(old) end) end
        if pos then waypointPin = guard("waypoint.set", pinAt, pos) end
    end

    --- Toasts: the NCM notification text, shown natively, newest last; the deck UI also lists them.
    function g.toast(n)
        local title = type(n) == "table" and (n.title or "NCM") or "NCM"
        local msg = type(n) == "table" and (n.message or n.text or "") or tostring(n)
        g.toasts[#g.toasts + 1] = { title = title, message = msg, at = os.clock() }
        while #g.toasts > 40 do table.remove(g.toasts, 1) end
        guard("toast", function()
            local evt = SimpleScreenMessage.new()
            evt.message = (title ~= "" and (title .. ": ") or "") .. msg
            evt.duration = math.max(3, math.min(12, ((type(n) == "table" and n.durationMs) or 6000) / 1000))
            evt.isShown = true
            Game.GetUISystem():QueueEvent(evt)
        end)
    end

    --- A claimed car goes into V's garage, callable from the vanilla vehicle menu (L338). This writes V's unlocked-vehicle
    --- list into the Cyberpunk save -- the one deliberate save mutation of a claim; `EnablePlayerVehicle(record, false)`
    --- reverses it (doc 55 §8.9). The record must be in Vehicle.vehicle_list (the livery yaml appends all ten).
    function g.giveCar(record)
        return guard("giveCar", function()
            local ok = Game.GetVehicleSystem():EnablePlayerVehicle(record, true, false)
            g.toast({ title = "NCM", message = ok and ("In your garage: " .. record .. " -- call it from the vehicle menu.")
                or ("Claimed, but the game would not add " .. record .. " to your garage (is the livery mod installed?)") })
            return ok
        end)
    end

    function g.attach(h, app)
        h.onNotify = g.toast
        h.onChat = function(text) g.toasts[#g.toasts + 1] = { title = "", message = tostring(text), at = os.clock(), chat = true } end
        g.h = h
    end

    function g.detach(h)
        for id in pairs(g.pins) do g.blipRemoved(id) end
        g.setWaypoint(nil)
        g.h = nil
    end

    return g
end

return M
