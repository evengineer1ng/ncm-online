-- ncm_sky / client / sky -- the scene for the `ncm-sky` required mod (KB-430).
--
--   exports.scene(owner, bodies)   a resource's bodies, replacing its previous ones ({} clears them). A body is
--                                  { id, kind, app?, p = { x, y, z }, q = { i, j, k, r } } (a unit quaternion; the
--                                  package turns it into the game's own EulerAngles). Kinds are the package's templates
--                                  (core space.sky: 2 the star dome, 3-6 the Earth, 7-9 the Moon). ncm_world's Deep is the
--                                  owner "deep" (L358: the NCWE space render).
--   exports.status()               what the package last reported for each body, and whether it is connected.
--
-- The feed is sent ten times a second whether or not it changed: the DLL empties the sky when it stops hearing it.
local function log(fmt, ...) print(("[ncm_sky] " .. fmt):format(...)) end

local PORT_BASE, PORT_SPAN = 38760, 4
local SEND_MS = 100
local portIndex = 0
local surface, surfaceReady = nil, false
local health, report = nil, { bodies = {} }
local attempts = 0
local owners = {}               -- resource -> { bodies }

local function url() return ("http://127.0.0.1:%d/sky.html"):format(PORT_BASE + portIndex) end
local function now() return GetGameTimer() end

local function send(payload)
    if not (surface and surfaceReady) then return false end
    return (pcall(function() surface:send("ncm:sky.send", payload) end))
end

local function tearDown(why)
    if surface then
        pcall(function() surface:destroy() end)
        log("transport closed (%s)", tostring(why))
    end
    surface, surfaceReady, health = nil, false, nil
end

local function bringUp()
    if surface then return end
    local page, reason = WebUI.create({ entry = url(), layer = "hud", width = 16, height = 16, fps = 10,
        zIndex = 1, transparent = true, visible = true })
    if not page then
        attempts = attempts + 1
        portIndex = (portIndex + 1) % PORT_SPAN
        if attempts == PORT_SPAN then
            log("no NCM Sky plugin on 127.0.0.1:%d-%d (%s); nothing can be drawn", PORT_BASE, PORT_BASE + PORT_SPAN - 1, tostring(reason))
        end
        return
    end
    surface = page
    pcall(function() page:hide() end)
    page:on("ncm:sky.ready", function()
        surfaceReady, attempts = true, 0
        log("transport connected at %s", url())
        send({ cmd = "health" })
    end)
    page:on("ncm:sky.closed", function(info)
        local wasReady = surfaceReady
        surfaceReady = false
        if not wasReady then
            tearDown("closed before connecting: " .. tostring(type(info) == "table" and info.detail or "?"))
            portIndex = (portIndex + 1) % PORT_SPAN
        end
    end)
    page:on("ncm:sky.status", function(s)
        if type(s) ~= "table" then return end
        for id, b in pairs(type(s.bodies) == "table" and s.bodies or {}) do
            local was = report.bodies[id]
            if not was or was.state ~= b.state then
                log("body %s: %s%s", id, ({ "spawned", "moved", "REFUSED", "gone" })[tonumber(b.state) or 0] or tostring(b.state),
                    (b.why and b.why ~= "") and (" -- " .. b.why) or "")
            end
        end
        report = { rev = s.rev, bodies = type(s.bodies) == "table" and s.bodies or {} }
    end)
    page:on("ncm:sky.health", function(h)
        if type(h) ~= "table" then return end
        if not health then log("plugin %s", tostring(h.version)) end
        health = h
    end)
end

local function merged()
    local out, seen = {}, {}
    for owner, list in pairs(owners) do
        for _, b in ipairs(list) do
            local id = tostring(b.id or "")
            if id ~= "" and not seen[id] and type(b.p) == "table" and type(b.q) == "table" then
                seen[id] = true
                out[#out + 1] = { id = id, kind = math.floor(tonumber(b.kind) or 0), app = b.app or "",
                    p = { tonumber(b.p.x or b.p[1]) or 0, tonumber(b.p.y or b.p[2]) or 0, tonumber(b.p.z or b.p[3]) or 0 },
                    q = { tonumber(b.q[1]) or 0, tonumber(b.q[2]) or 0, tonumber(b.q[3]) or 0, tonumber(b.q[4]) or 1 } }
            end
        end
    end
    return out
end

exports("scene", function(owner, bodies)
    owners[tostring(owner or "?")] = type(bodies) == "table" and bodies or {}
    return surfaceReady
end)

exports("status", function()
    return { connected = surfaceReady, plugin = health and health.version or nil, bodies = report.bodies }
end)

CreateThread(function()
    Wait(5000)
    while true do
        if not surface then bringUp() end
        if surfaceReady then send({ cmd = "scene", bodies = merged() }) end
        Wait(SEND_MS)
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    send({ cmd = "scene", bodies = {} })
    tearDown("resource stop")
end)
