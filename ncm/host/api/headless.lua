-- NCM Host: the Open77.* surface over a HEADLESS world model (L338, doc 55 §3).
--
-- This is what the resources see when no game is attached: tests, catch-up after absence, and the base the CET game
-- bindings (`game/*.lua`) overlay function by function. It models one player, the vehicles/NPCs/props the resources
-- create, blips, state bags, tunables and the environment. Shapes follow the OPEN//77 API as the resources use it
-- (and as tools/ncm-stub.lua has pinned them). Functions not listed here are counted by the runtime as unsupported.
local M = {}
local unpack = table.unpack or unpack

local function world(h)
    if h.world then return h.world end
    h.world = {
        player = { position = { x = -1418.0, y = 192.0, z = 25.0 }, heading = 0, health = 100, life = "alive",
            seat = nil, bucket = 0, visible = true, ghosted = false, wanted = 0 },
        vehicles = {}, nextVid = 1000,
        npcs = {}, props = {}, nextId = 5000,
        blips = {}, markers = {}, anchors = {}, cameras = {}, waypoint = nil,
        env = { weather = "sunny", weatherFrozen = false, timeRate = 1, timeFrozen = false, fixedSecondsOfDay = nil },
        population = {}, pages = {}, notifications = {}, chat = {}, hud = { visible = true },
        kvp = {},
        tunables = {},          -- resource -> { key -> value } overrides (the host fills serverId etc.)
        declared = {},          -- resource -> spec
    }
    return h.world
end
M.world = world

local function vec(p) if not p then return nil end return { x = tonumber(p.x) or 0, y = tonumber(p.y) or 0, z = tonumber(p.z) or 0 } end

-- seconds of the in-game day: headless follows the host clock (UTC) unless fixed
local function secondsOfDay(h)
    local w = world(h)
    if w.env.fixedSecondsOfDay then return w.env.fixedSecondsOfDay end
    return math.floor(h.clock.unix()) % 86400
end

local function common(h, vm)
    local w = world(h)
    return {
        time = {
            unix = function() return h.clock.unix() end,
            monotonic = function() return h.clock.mono() end,
        },
        runtime = {
            luaVersion = function() return _VERSION end,
            host = function() return "ncm_sp" end,
        },
        resource = {
            name = function() return vm.resource end,
            generation = function() return 1 end,
            restart = function() return nil, "unsupported_in_ncm_host" end,
            state = function() return "started" end,
        },
        kvp = {
            get = function(k) local b = w.kvp[vm.resource]; return b and b[k] end,
            set = function(k, v) w.kvp[vm.resource] = w.kvp[vm.resource] or {}; w.kvp[vm.resource][k] = v; return true end,
        },
        exports = {
            -- open77_* system resources are host built-ins; a call answers like a resolved promise
            call = function(res, fn, ...)
                local own = h.resourceExports[tostring(res) .. "/" .. vm.side]
                if own and own[fn] then
                    local result = { pcall(own[fn], ...) }
                    local p = { result = result[2] }
                    function p.await() return unpack(result, 2) end
                    p.next = function(_, cb) if cb then cb(unpack(result, 2)) end; return p end
                    return p
                end
                local impl = h.exports[res] and h.exports[res][fn]
                if not impl then
                    h.unsupported["export:" .. tostring(res) .. "." .. tostring(fn)] = (h.unsupported["export:" .. tostring(res) .. "." .. tostring(fn)] or 0) + 1
                    return nil, "unsupported_in_ncm_host"
                end
                local result = impl(vm, ...)
                local p = { result = result }
                function p.await() return result end
                p.next = function(_, cb) if cb then cb(result) end; return p end
                return p
            end,
        },
    }
end

function M.server(h, vm)
    local w = world(h)
    local api = common(h, vm)
    local P = w.player

    api.tunables = {
        declare = function(spec)
            w.declared[vm.resource] = spec
            local out = {}
            for k, v in pairs(spec) do out[k] = type(v) == "table" and v.value or v end
            local o = w.tunables["*"]
            if o then for k, v in pairs(o) do if out[k] ~= nil then out[k] = v end end end
            o = w.tunables[vm.resource]
            if o then for k, v in pairs(o) do if out[k] ~= nil then out[k] = v end end end
            return out
        end,
        set = function() return true end,
        pending = function() return {} end,
        promote = function() return true end,
    }
    api.chat = { send = function(pid, text) w.chat[#w.chat + 1] = { pid = pid, text = tostring(text), at = h.clock.unix() }
        if #w.chat > 300 then table.remove(w.chat, 1) end
        if h.onChat then h.onChat(text) end
        return true end }
    api.notifications = { send = function(pid, n) w.notifications[#w.notifications + 1] = { pid = pid, n = n, at = h.clock.unix() }
        if #w.notifications > 300 then table.remove(w.notifications, 1) end
        if h.onNotify then h.onNotify(n) end
        return true end }
    api.players = {
        all = function() return { 1 } end,
        get = function(pid)
            if tonumber(pid) ~= 1 then return nil end
            local p = h.players[1]
            return { id = 1, name = p.name, userId = p.userId, ready = p.ready, position = vec(P.position), x = P.position.x,
                y = P.position.y, z = P.position.z, heading = P.heading, bucket = P.bucket, health = P.health,
                vehicleId = P.seat and P.seat.vehicleId or nil, seat = P.seat and P.seat.seat or nil }
        end,
        positions = function() return { { id = 1, playerId = 1, x = P.position.x, y = P.position.y, z = P.position.z, position = vec(P.position), bucket = P.bucket, heading = P.heading } } end,
        position = function(pid) if tonumber(pid) == 1 then return vec(P.position) end end,
        teleport = function(pid, pos, heading) if tonumber(pid) ~= 1 then return nil, "no_such_player" end
            P.position = vec(pos); if heading then P.heading = heading end
            if h.game and h.game.teleport then h.game.teleport(pos, heading) end
            return true end,
        getVehicleSeat = function(pid) if tonumber(pid) == 1 and P.seat then return { vehicleId = P.seat.vehicleId, seat = P.seat.seat } end return nil end,
        warpIntoVehicle = function(pid, vid, seat) if not w.vehicles[vid] then return nil, "no_such_vehicle" end; P.seat = { vehicleId = vid, seat = seat or "driver" }; return true end,
        taskEnterVehicle = function(pid, vid, seat) if not w.vehicles[vid] then return nil, "no_such_vehicle" end; P.seat = { vehicleId = vid, seat = seat or "driver" }; return true end,
        getLifeState = function() return P.life end,
        isDead = function() return P.life == "dead" end,
        respawn = function() P.life = "alive"; P.health = 100; return true end,
        getHealth = function() return P.health end,
        setHealth = function(_, v) P.health = tonumber(v) or P.health; return true end,
        setRegen = function() return true end,
        setGhosted = function(_, v) P.ghosted = v and true or false; return true end,
        setVisible = function(_, v) P.visible = v and true or false; return true end,
        identifiers = function() return { h.players[1].userId } end,
        name = function() return h.players[1].name end,
        setWanted = function(_, n) P.wanted = tonumber(n) or 0; return true end,
        getWanted = function() return P.wanted end,
        kick = function() return nil, "single_player" end,
    }
    api.routingBuckets = { getPlayer = function() return P.bucket end, setPlayer = function(_, b) P.bucket = tonumber(b) or 0; return true end }
    api.ready = { participate = function() return true end, hold = function() return "hold" end, release = function() return true end }
    api.state = {
        player = function(pid)
            return {
                set = function(_, k, v) return h:bagSet(pid, k, v) end,
                get = function(_, k) return h:bag(pid)[k] end,
                clear = function(_, k) return h:bagSet(pid, k, nil) end,
            }
        end,
        load = function() return w.kvp["__state:" .. vm.resource] end,
        save = function(t) w.kvp["__state:" .. vm.resource] = t; return true end,
    }
    api.environment = {
        getState = function()
            local sod = secondsOfDay(h)
            return { weather = w.env.weather, weatherFrozen = w.env.weatherFrozen, secondsOfDay = sod,
                hour = math.floor(sod / 3600), minute = math.floor(sod % 3600 / 60), timeRate = w.env.timeRate,
                timeFrozen = w.env.timeFrozen, bucket = 0 }
        end,
        setWeather = function(_, weather) if type(_) == "string" then weather = _ end; w.env.weather = weather or w.env.weather
            if h.game and h.game.setWeather then h.game.setWeather(w.env.weather) end; return true end,
        setWeatherFrozen = function(_, v) w.env.weatherFrozen = v and true or false; return true end,
        setTime = function(_, sod) if type(_) == "number" and sod == nil then sod = _ end; w.env.fixedSecondsOfDay = tonumber(sod)
            if h.game and h.game.setTime then h.game.setTime(w.env.fixedSecondsOfDay) end; return true end,
        setTimeRate = function(_, r) w.env.timeRate = tonumber(r) or 1; return true end,
        setTimeFrozen = function(_, v) w.env.timeFrozen = v and true or false; return true end,
        clearBucket = function() return true end,
    }
    api.world = {
        groundZ = function(x, y) return 0.0, { playerId = 1, cached = true } end,
        setPopulation = function(bucket, policy) w.population[tonumber(bucket) or 0] = policy; return true end,
        getPopulation = function(bucket)
            local p = w.population[tonumber(bucket) or 0] or { crowd = 1.0, traffic = 1.0, police = true }
            return { bucket = bucket, crowd = p.crowd, traffic = p.traffic, police = p.police, enabled = true,
                trafficGranularity = "binary", crowdGranularity = "continuous" }
        end,
        setTimeScale = function() return true end,
    }
    local function newId() w.nextId = w.nextId + 1; return w.nextId end
    api.vehicles = {
        create = function(spec)
            if type(spec) ~= "table" or not spec.record then return nil, "invalid_spec" end
            w.nextVid = w.nextVid + 1
            local v = { id = w.nextVid, record = spec.record, position = vec(spec.position) or { x = 0, y = 0, z = 0 }, yaw = spec.yaw or 0,
                health = 1.0, engine = true, frozen = false, perf = nil, paint = nil, ai = nil, created = h.clock.unix(), spec = spec }
            w.vehicles[v.id] = v
            if h.game and h.game.vehicleCreated then h.game.vehicleCreated(v) end
            return v.id
        end,
        remove = function(vid) local v = w.vehicles[vid]; if not v then return false, "no_such_vehicle" end
            w.vehicles[vid] = nil
            if P.seat and P.seat.vehicleId == vid then P.seat = nil end
            if h.game and h.game.vehicleRemoved then h.game.vehicleRemoved(v) end
            h:trigger("server", "onVehicleRemoved", vid)
            return true end,
        get = function(vid) local v = w.vehicles[vid]; if not v then return nil end
            local speed = v.ai and v.ai.speedNow or 0
            return { id = vid, record = v.record, position = vec(v.position), x = v.position.x, y = v.position.y, z = v.position.z,
                yaw = v.yaw, speed = speed, moving = speed > 0.1, driverPlayerId = (P.seat and P.seat.vehicleId == vid) and 1 or nil,
                gear = 1, onGround = true, health = v.health, engine = v.engine, frozen = v.frozen } end,
        getPosition = function(vid) local v = w.vehicles[vid]; return v and vec(v.position) or nil end,
        getPlayerSeat = function(pid) if tonumber(pid) == 1 and P.seat then return { vehicleId = P.seat.vehicleId, seat = P.seat.seat } end return nil end,
        all = function() local out = {}; for id in pairs(w.vehicles) do out[#out + 1] = id end; table.sort(out); return out end,
        owner = function(vid) local v = w.vehicles[vid]; if not v then return nil, "not_streamed" end
            return { authorityPlayerId = 1, physicsOwner = 1, aiDriven = v.ai ~= nil, epoch = 1, readyClients = 1 } end,
        setTransform = function(vid, pos, yaw) local v = w.vehicles[vid]; if not v then return nil, "no_such_vehicle" end
            if type(pos) == "table" and pos.position then yaw = pos.yaw or yaw; pos = pos.position end
            v.position = vec(pos) or v.position; v.yaw = yaw or v.yaw
            if P.seat and P.seat.vehicleId == vid then P.position = vec(v.position) end
            return true end,
        setPerformance = function(vid, prof) local v = w.vehicles[vid]; if not v then return false, "vehicle_not_found" end; v.perf = prof; return true end,
        getPerformance = function(vid) local v = w.vehicles[vid]; return v and v.perf or nil end,
        setEngine = function(vid, on) local v = w.vehicles[vid]; if not v then return false, "vehicle_not_found" end; v.engine = on and true or false; return true end,
        setFrozen = function(vid, on) local v = w.vehicles[vid]; if not v then return false, "vehicle_not_found" end; v.frozen = on and true or false; return true end,
        requestAuthority = function(vid) if not w.vehicles[vid] then return nil, "no_such_vehicle" end; return true end,
        update = function(vid, patch) local v = w.vehicles[vid]; if not v then return nil, "no_such_vehicle" end
            for k, x in pairs(patch or {}) do v[k] = x end; return true end,
        getHealth = function(vid) local v = w.vehicles[vid]; return v and v.health or nil end,
        setHealth = function(vid, x) local v = w.vehicles[vid]; if not v then return nil, "no_such_vehicle" end; v.health = tonumber(x) or v.health; return true end,
        setPaint = function(vid, p) local v = w.vehicles[vid]; if not v then return nil, "no_such_vehicle" end; v.paint = p; return true end,
        forcePlayerOutOfVehicle = function() P.seat = nil; return true end,
        warpPlayerIntoVehicle = function(pid, vid, seat) if not w.vehicles[vid] then return nil, "no_such_vehicle" end; P.seat = { vehicleId = vid, seat = seat or "driver" }; return true end,
        getDriver = function(vid) if P.seat and P.seat.vehicleId == vid then return 1 end return nil end,
        getLights = function() return {} end, setLights = function() return true end,
        repairAllLights = function() return true end, repairAllTires = function() return true end,
        breakLight = function() return true end, breakTire = function() return true end,
        explode = function(vid) local v = w.vehicles[vid]; if v then v.health = 0 end; return true end,
        ai = {
            attachDriver = function(vid) local v = w.vehicles[vid]; if not v then return nil, "no_such_vehicle" end; v.ai = { status = "idle", speedNow = 0 }; return true end,
            removeDriver = function(vid) local v = w.vehicles[vid]; if v then v.ai = nil end; return true end,
            driveTo = function(vid, o) local v = w.vehicles[vid]; if not v or not v.ai then return nil, "no_driver" end
                v.ai.target = vec(o and o.position); v.ai.speed = (o and o.speed) or 10; v.ai.status = "driving"; return { status = "driving" } end,
            followRoute = function(vid, o) local v = w.vehicles[vid]; if not v or not v.ai then return nil, "no_driver" end
                v.ai.route = {}; for i, pt in ipairs((o and o.points) or {}) do v.ai.route[i] = vec(pt) end
                v.ai.target = table.remove(v.ai.route, 1); v.ai.speed = (o and o.speed) or 10; v.ai.status = "driving"; return { status = "driving" } end,
            joinTraffic = function(vid, o) local v = w.vehicles[vid]; if not v or not v.ai then return nil, "no_driver" end
                v.ai.status = "traffic"; v.ai.speed = (o and o.speed) or 6; return { status = "driving" } end,
            stop = function(vid) local v = w.vehicles[vid]; if v and v.ai then v.ai.target = nil; v.ai.route = nil; v.ai.status = "idle"; v.ai.speedNow = 0 end; return true end,
            state = function(vid) local v = w.vehicles[vid]; return v and v.ai and { status = v.ai.status, speed = v.ai.speedNow or 0 } or nil end,
        },
    }
    api.npcs = {
        ai = { tasks = 0, frozen = 1, native = 2 },
        damage = { mortal = 0, immortal = 1, invulnerable = 2 },
        flags = { alive = 1, ragdoll = 2, despawnWhenUnobserved = 4, persistent = 8 },
        create = function(spec) local id = newId(); w.npcs[id] = { spec = spec, position = vec(spec and (spec.position or spec)) }; return id end,
        remove = function(id) if not w.npcs[id] then return false, "no_such_npc" end; w.npcs[id] = nil; return true end,
        get = function(id) local n = w.npcs[id]; if not n then return nil end
            local p = n.position or { x = 0, y = 0, z = 0 }
            return { id = id, x = p.x, y = p.y, z = p.z, position = vec(p), yaw = 0, bucket = 0 } end,
        owner = function(id) if not w.npcs[id] then return nil, "not_found" end
            return { authorityPlayerId = 1, physicsOwner = 1, readyClients = 1, epoch = 1 } end,
        speak = function() return true end,
        tasks = { lookAt = function() return true end, wander = function() return true end },
    }
    api.props = {
        create = function(spec) local id = newId(); w.props[id] = spec; return id end,
        remove = function(id) if not w.props[id] then return false, "no_such_prop" end; w.props[id] = nil; return true end,
    }
    api.effects = { screen = function() return true end, screenCatalog = function() return {} end }
    api.combat = { createScope = function() return newId() end, removeScope = function() return true end, onDamage = function() return true end }
    api.hacking = { define = function() return true end, defineIce = function() return true end, definePurge = function() return true end,
        start = function() return nil, "unsupported_in_ncm_host" end, cancel = function() return true end, purge = function() return true end }
    api.cyberware = { newOperationId = function() return "op-" .. newId() end, current = function() return {} end,
        define = function() return true end, install = function() return nil, "unsupported_in_ncm_host" end }
    return api
end

function M.client(h, vm)
    local w = world(h)
    local api = common(h, vm)
    local P = w.player
    api.players = {
        localId = function() return 1 end,
        all = function() return { 1 } end,
        getVehicleSeat = function() if P.seat then return { vehicleId = P.seat.vehicleId, seat = P.seat.seat } end return nil end,
        freezeRotation = function() return true end, allowAim = function() return true end, allowShoot = function() return true end,
        allowInteraction = function() return true end, resetControls = function() return true end,
    }
    api.character = {
        position = function() return vec(P.position) end,
        state = function() return { position = vec(P.position), heading = P.heading, health = P.health, alive = P.life ~= "dead",
            inVehicle = P.seat ~= nil, vehicleId = P.seat and P.seat.vehicleId or nil, seat = P.seat and P.seat.seat or nil } end,
        frame = function() return { position = vec(P.position), heading = P.heading, forward = { x = 0, y = 1, z = 0 } } end,
        aimedEntity = function() return nil end,
    }
    api.vehicles = {
        get = function(vid) local v = w.vehicles[vid]; if not v then return nil end
            return { id = vid, record = v.record, position = vec(v.position), x = v.position.x, y = v.position.y, z = v.position.z,
                yaw = v.yaw, speed = v.ai and v.ai.speedNow or 0, health = v.health } end,
        getPlayerSeat = function() if P.seat then return { vehicleId = P.seat.vehicleId, seat = P.seat.seat } end return nil end,
        nearby = function() local out = {}; for id in pairs(w.vehicles) do out[#out + 1] = id end; return out end,
        ratedTopSpeed = function() return nil end,
        setPerformanceClass = function() return true end, clearPerformanceClass = function() return true end,
    }
    api.state = {
        localPlayer = function()
            return {
                get = function(_, k) return h:bag(1)[k] end,
                set = function() return nil, "client_cannot_write" end,
            }
        end,
        onChange = function(key, fn)
            if type(key) == "function" then fn, key = key, nil end
            h.bagWatch[#h.bagWatch + 1] = { vm = vm, key = key, fn = fn }
            return #h.bagWatch
        end,
    }
    local function newId() w.nextId = w.nextId + 1; return w.nextId end
    api.blips = {
        create = function(spec) local id = newId(); w.blips[id] = { spec = spec, owner = vm.key }
            if h.game and h.game.blipCreated then h.game.blipCreated(id, spec) end; return id end,
        remove = function(id) local b = w.blips[id]; if not b then return false end; w.blips[id] = nil
            if h.game and h.game.blipRemoved then h.game.blipRemoved(id) end; return true end,
        update = function(id, patch) local b = w.blips[id]; if not b then return false end; for k, x in pairs(patch or {}) do b.spec[k] = x end
            if h.game and h.game.blipUpdated then h.game.blipUpdated(id, b.spec) end; return true end,
        setPosition = function(id, pos) local b = w.blips[id]; if not b then return false end; b.spec.position = vec(pos)
            if h.game and h.game.blipUpdated then h.game.blipUpdated(id, b.spec) end; return true end,
        setIcon = function(id, icon) local b = w.blips[id]; if b then b.spec.icon = icon end; return b ~= nil end,
        setTitle = function(id, t) local b = w.blips[id]; if b then b.spec.title = t end; return b ~= nil end,
        setDescription = function(id, t) local b = w.blips[id]; if b then b.spec.description = t end; return b ~= nil end,
        track = function() return true end,
        list = function() local out = {}; for id in pairs(w.blips) do out[#out + 1] = id end; return out end,
        waypoint = function() return w.waypoint end,
        setWaypoint = function(pos) w.waypoint = vec(type(pos) == "table" and (pos.position or pos) or nil)
            if h.game and h.game.setWaypoint then h.game.setWaypoint(w.waypoint) end; return true end,
        clearWaypoint = function() w.waypoint = nil; if h.game and h.game.setWaypoint then h.game.setWaypoint(nil) end; return true end,
    }
    api.markers = {
        create = function(spec) local id = newId(); w.markers[id] = spec; return id end,
        update = function(id, patch) local m = w.markers[id]; if m then for k, x in pairs(patch or {}) do m[k] = x end end; return m ~= nil end,
        remove = function(id) w.markers[id] = nil; return true end,
    }
    api.anchors = {
        create = function(spec) local id = newId(); w.anchors[id] = spec; return id end,
        update = function() return true end, frame = function() return nil end,
        remove = function(id) w.anchors[id] = nil; return true end, clear = function() w.anchors = {}; return true end,
    }
    api.input = {
        isDown = function(action) return h.input and h.input.isDown and h.input.isDown(action) or false end,
        isCaptured = function() return false end,
        axis = function() return 0 end,
        keyFor = function(action) return h.input and h.input.keyFor and h.input.keyFor(action) or "?" end,
        setActionBlocked = function() return true end,
        devices = function() return { gamepad = true, keyboard = true } end,
        registerKeyMapping = function(spec) return true end,
    }
    api.hud = { setVisible = function(v) w.hud.visible = v and true or false; return true end, setCinematic = function() return true end,
        notify = function(n) if h.onNotify then h.onNotify(n) end; return true end }
    api.screen = { fadeIn = function() return true end, fadeOut = function() return true end }
    api.travel = { teleport = function(pos) P.position = vec(pos); if h.game and h.game.teleport then h.game.teleport(pos) end; return true end,
        teleportAndSettle = function(pos) P.position = vec(pos); if h.game and h.game.teleport then h.game.teleport(pos) end; return true end,
        setNoclip = function() return true end }
    api.camera = {
        create = function() return newId() end, destroy = function() return true end, activate = function() return true end,
        deactivate = function() return true end, setTransform = function() return true end, lookAt = function() return true end,
        project = function() return nil end,
    }
    api.world = { raycast = function() return nil end }
    api.props = {
        create = function(spec) local id = newId(); w.props[id] = spec; return id end,
        remove = function(id) w.props[id] = nil; return true end,
        get = function(id) return w.props[id] end,
        setTransform = function() return true end,
    }
    api.npcs = { entity = function() return nil end }
    api.nameplates = { stream = function() return true end, stopStream = function() return true end }
    api.map = { open = function() return true end }
    api.inspector = { outline = function() return true end }
    api.hacking = { present = function() return true end }
    -- WebUI pages: the CEF pages do not exist in single player. A page object records traffic so page ADAPTERS
    -- (host/webui) can present it natively; `h.pages[entry]` lists every live page.
    api.webui = {
        create = function(opts)
            local page = { id = newId(), opts = opts or {}, entry = (opts or {}).entry, handlers = {}, sent = {}, visible = true,
                focus = false, vm = vm }
            function page:on(ev, fn) self.handlers[ev] = fn; return true end
            function page:send(ev, payload)
                self.sent[ev] = payload
                if h.webui and h.webui.onSend then h.webui.onSend(self, ev, payload) end
                return true
            end
            function page:destroy()
                w.pages[self.id] = nil
                if h.webui and h.webui.onDestroy then h.webui.onDestroy(self) end
                return true
            end
            function page:hide() self.visible = false; return true end
            function page:show() self.visible = true; return true end
            function page:setFocus(f) self.focus = f and true or false; return true end
            --- host side: a native adapter emits an event INTO the resource, as the page's JS would
            function page:emit(ev, payload) local fn = self.handlers[ev]; if fn then h:spawn(vm, fn, "webui " .. ev, payload) end end
            w.pages[page.id] = page
            -- a plugin page whose port has nothing listening is refused, as CEF refused it (resources walk their ports)
            if h.webui and h.webui.onCreate then
                local okC, why = h.webui.onCreate(page)
                if okC == false then w.pages[page.id] = nil; return nil, why or "unreachable" end
            end
            return page
        end,
    }
    api.__WebUI = { create = api.webui.create }
    return api
end

--- Built-in `open77_*` exports the resources call through Open77.exports.call.
function M.exports(h)
    local w = world(h)
    return {
        open77_notifications = {
            show = function(vm, n) w.notifications[#w.notifications + 1] = { pid = 1, n = n, at = h.clock.unix() }
                if h.onNotify then h.onNotify(n) end; return true end,
            hide = function() return true end,
        },
        open77_weather = {
            getState = function()
                local sod = secondsOfDay(h)
                return { weather = w.env.weather, secondsOfDay = sod, frozen = w.env.weatherFrozen }
            end,
            setWeather = function(vm, weather) w.env.weather = weather; return true end,
        },
        open77_interactions = {},
    }
end

return M
