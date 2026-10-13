-- ncm_world / client / fx -- NCM FX's native renderer (core `presentation.fx`; owner, 2026-10-12: "a true vfx and sfx
-- dynamic system we can plug the rest of our physics into").
--
-- The physics paths hand this file EMITTERS (client/engineering.lua on the ground, client/deep.lua in Deep, the drives
-- through client/drivefx.lua). Core turns them into a budgeted plan; this file only draws it:
--   * a SUSTAINED cue holds one native effect (`Open77.vfx.play`, duration 0) and is MOVED every frame with
--     `Open77.vfx.update` (position + orientation), which keeps the live particles: the plume rides the nozzle;
--   * an EDGE cue is one `vfx.play` with a short life at the moment it happened;
--   * a tier change swaps the asset (game effects cannot be scaled at run time: size is a choice of asset);
--   * audio goes to the NCM Audio resource when it runs (`ncm_audio` client export `voices`), else nothing --
--     never a vanilla event with no gain where a gain is the whole point;
--   * every asset's first play is logged with its result, so an asset that does not render is found in one session
--     (`presentation.fx_cues` ASSETS carry `seen = false` until looked at).
-- Nothing here is authoritative and nothing is sent anywhere but the local renderer.
local Fx = NcmCore.get("presentation.fx")
local Cues = NcmCore.get("presentation.fx_cues")

local function log(fmt, ...) print(("[ncm_world/client/fx] " .. fmt):format(...)) end

local held = {}          -- activation key -> { handle, asset, owner }
local tried = {}         -- asset key -> true (first play logged)
local owners = {}        -- owner -> { acts (selected), frame, pos, at = ms }
local audioDown = false
local PLAN_MS, AUDIO_MS, STALE_MS = 100, 100, 500
local plannedAt, audioAt = 0, 0
local placed = {}        -- activation key -> the activation last planned (moved every frame between plans)

NcmFx = {}

local function c(a, i, k) return tonumber(a and (a[k] or a[i])) or 0 end

-- machine frame (x right, y forward, z up) -> world, with the car's world axes from Open77.character.frame
local function toWorld(v, frame)
    local r, f, u = frame.right, frame.forward, frame.up
    return {
        c(r, 1, "x") * v[1] + c(f, 1, "x") * v[2] + c(u, 1, "x") * v[3],
        c(r, 2, "y") * v[1] + c(f, 2, "y") * v[2] + c(u, 2, "y") * v[3],
        c(r, 3, "z") * v[1] + c(f, 3, "z") * v[2] + c(u, 3, "z") * v[3],
    }
end

-- the shortest rotation taking +Z (the effects' authored forward, ASSETS.orient) onto unit d, as {x, y, z, w}
local function quatFromZ(d)
    local x, y, z = d[1], d[2], d[3]
    local l = math.sqrt(x * x + y * y + z * z)
    if l < 1e-9 then return { x = 0, y = 0, z = 0, w = 1 } end
    x, y, z = x / l, y / l, z / l
    if z < -0.999999 then return { x = 1, y = 0, z = 0, w = 0 } end
    -- axis = Z x d = (-y, x, 0); angle from cos = z
    local w = 1 + z
    local q = { x = -y, y = x, z = 0, w = w }
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.w * q.w)
    return { x = q.x / n, y = q.y / n, z = 0, w = q.w / n }
end

local function placement(a, frame, pos)
    local at = toWorld(a.at or { 0, 0, 0 }, frame)
    local dir = toWorld(a.dir or { 0, 0, 1 }, frame)
    local out = a.exhaust and { -dir[1], -dir[2], -dir[3] } or { 0, 0, 1 }
    local lift = a.exhaust and 0.45 or 0          -- clear of the housing, along the exhaust
    -- the effect's authored emission axis (ASSETS.orient): a thruster fires down its own -Z, so -Z is turned onto `out`
    local asset = Cues.ASSETS[a.asset or ""]
    local axis = (asset and asset.orient == "-z") and { -out[1], -out[2], -out[3] } or out
    return {
        position = { x = pos.x + at[1] + out[1] * lift, y = pos.y + at[2] + out[2] * lift, z = pos.z + at[3] + out[3] * lift },
        orientation = quatFromZ(axis),
    }
end

local function stop(key)
    local h = held[key]
    if h and h.handle then pcall(Open77.vfx.stop, h.handle) end
    held[key] = nil
end

local function play(a, t, sustained)
    local asset = Cues.ASSETS[a.asset or ""]
    if not asset then return nil end
    local opts = { position = t.position, orientation = t.orientation, duration = sustained and 0 or 2.5, ignoreTimeDilation = true }
    local ok, handle, why = pcall(Open77.vfx.play, asset.effect, opts)
    if not tried[a.asset] then
        tried[a.asset] = true
        log("asset %s (%s): %s", a.asset, asset.effect, (ok and handle) and "PLAYING" or ("REFUSED " .. tostring(ok and why or handle)))
    end
    return (ok and handle) or nil
end

local function audio()
    if audioDown then return end
    local tnow = GetGameTimer()
    if tnow - audioAt < AUDIO_MS then return end
    audioAt = tnow
    -- 2026-10-13 (owner, AV: "sound is nightmarish"): ONE loop per sound per Machine. Four pods each playing the same
    -- whine at slightly different pitches beat against each other; they are merged (loudest gain, gain-weighted pitch,
    -- gain-weighted place). A one-shot plays on its edge only -- never again every 100 ms while its cue stays active.
    local voices, loops = {}, {}
    for owner, o in pairs(owners) do
        for _, a in ipairs(o.acts or {}) do
            if a.audio then
                local v = Cues.VOICES[a.audio.voice]
                if v then
                    local t = placement(a, o.frame, o.pos)
                    local g = tonumber(a.audio.gain) or 0
                    if a.edge then
                        voices[#voices + 1] = { key = owner .. "|" .. a.key .. "@" .. GetGameTimer(), file = v.file, loop = false,
                            oneShot = true, pitch = a.audio.pitch, gain = g, position = t.position }
                    elseif v.loop and not a.audio.oneShot then
                        local k = owner .. "|" .. a.audio.voice
                        local L = loops[k]
                        if not L then
                            L = { key = k, file = v.file, loop = true, gain = 0, w = 0, pitch = 0, px = 0, py = 0, pz = 0 }
                            loops[k] = L
                        end
                        local w = math.max(1e-3, g)
                        L.gain = math.max(L.gain, g)
                        L.w = L.w + w
                        L.pitch = L.pitch + (tonumber(a.audio.pitch) or 1) * w
                        L.px, L.py, L.pz = L.px + t.position.x * w, L.py + t.position.y * w, L.pz + t.position.z * w
                    end
                end
            end
        end
    end
    for _, L in pairs(loops) do
        voices[#voices + 1] = { key = L.key, file = L.file, loop = true, oneShot = false, gain = L.gain, pitch = L.pitch / L.w,
            position = { x = L.px / L.w, y = L.py / L.w, z = L.pz / L.w } }
    end
    local me = owners[NcmFx.localOwner or ""]
    local lis = me and { pos = me.pos, right = me.frame.right, forward = me.frame.forward } or nil
    local ok = pcall(Open77.exports.call, "ncm_audio", "voices", voices, lis)
    if not ok then audioDown = true end   -- not running: stop asking until the next resource start
end

--- One owner's frame: `emitters` from the physics step, `frame` the car's axes, `pos` its world position.
--- `owner` separates the local Machine from others' (replicated) ones.
function NcmFx.frame(owner, emitters, frame, pos, isRemote)
    if type(frame) ~= "table" or type(pos) ~= "table" or not frame.forward then return end
    owners[owner] = { emitters = emitters, frame = frame, pos = pos, at = GetGameTimer() }
    if not isRemote then NcmFx.localOwner = owner end
    local now = GetGameTimer()
    -- 2026-10-12 (the first Deep flight died on the client script budget): the PLAN runs ten times a second (sooner when
    -- a stroke or boom happened); between plans only the held effects move with their cars
    local edge = false
    for _, e in ipairs(emitters or {}) do if e.edge and next(e.edge) then edge = true break end end
    if not edge and now - plannedAt < PLAN_MS then
        for key, a in pairs(placed) do
            local h, o = held[key], owners[a.owner]
            if h and h.handle and o then
                local t = placement(a, o.frame, o.pos)
                pcall(Open77.vfx.update, h.handle, { position = t.position, orientation = t.orientation })
            end
        end
        return
    end
    plannedAt = now
    -- the whole budget is shared across owners: plan over every live owner's emitters
    local all, ownerOf = {}, {}
    for o, rec in pairs(owners) do
        if now - rec.at > 500 then owners[o] = nil
        else
            for _, e in ipairs(rec.emitters or {}) do all[#all + 1] = e; ownerOf[e.id] = o end
        end
    end
    local hk = {}
    for k in pairs(held) do hk[k] = true end
    local keep = Fx.plan(all, hk)
    local want = {}
    for o in pairs(owners) do owners[o].acts = {} end
    placed = {}
    for _, a in ipairs(keep) do
        local o = owners[ownerOf[a.emitter]]
        if o then
            a.owner = ownerOf[a.emitter]
            o.acts[#o.acts + 1] = a
            local t = placement(a, o.frame, o.pos)
            if a.edge then
                play(a, t, false)
            else
                want[a.key] = true
                placed[a.key] = a
                local h = held[a.key]
                if h and h.asset == a.asset and h.handle then
                    local okU, moved = pcall(Open77.vfx.update, h.handle, { position = t.position, orientation = t.orientation })
                    if not (okU and moved) then stop(a.key); h = nil end
                elseif h then
                    stop(a.key); h = nil
                end
                if not h then
                    local handle = play(a, t, true)
                    if handle then held[a.key] = { handle = handle, asset = a.asset } end
                end
            end
        end
    end
    for k in pairs(held) do if not want[k] then stop(k) end end
    audio()
    -- an edge is one moment: drawn now, never again by a later owner's re-plan in this same frame
    for _, rec in pairs(owners) do
        for _, e in ipairs(rec.emitters or {}) do if e.edge and next(e.edge) then e.edge = {} end end
    end
end

-- ---------------------------------------------------------------------------------------------- everyone else
-- The local Machine's compact emitter state goes to the server (server/fx_relay.lua) five times a second while it
-- is doing something visible, and once more when it stops; every other client draws it on that car, moving the
-- effects every frame from the car's own pose. Edges ride the next packet (at most ~200 ms late for a watcher).
local Json = NcmCore.get("vocabulary.json")
local SEND_MS, REMOTE_TTL_MS, REMOTE_RANGE_M = 200, 1200, 400
local tx = { at = 0, active = false, edges = {} }
local remote = {}        -- owner -> { vid, emitters, edges, at }
local myId = nil

local function visible(emitters)
    for _, e in ipairs(emitters or {}) do
        local q = e.q or {}
        if (tonumber(q.throttle) or 0) > 0.02 or q.active or (e.edge and next(e.edge)) or (q.state and q.state ~= "OFF" and q.state ~= "COOLDOWN")
            or (tonumber(q.heatKw) or 0) > 40 then return true end
    end
    return false
end

function NcmFx.publish(owner, vid, emitters)
    for _, e in ipairs(emitters or {}) do
        for what in pairs(e.edge or {}) do tx.edges[#tx.edges + 1] = { e.id, what } end
    end
    local now = GetGameTimer()
    local live = visible(emitters)
    if now - tx.at < SEND_MS or (not live and not tx.active) then return end
    tx.at, tx.active = now, live
    local okJ, blob = pcall(Json.encode, { em = live and Fx.pack(emitters) or {}, edges = tx.edges })
    tx.edges = {}
    if okJ and blob then TriggerServerEvent("ncm:fx.state", { vid = tostring(vid), owner = tostring(owner), json = blob }) end
end

RegisterNetEvent("ncm:fx.state", function(p)
    if type(p) ~= "table" or type(p.json) ~= "string" then return end
    if myId == nil then
        local okS, st = pcall(Open77.network.status)
        myId = okS and type(st) == "table" and st.playerId or false
    end
    if myId and tonumber(p.from) == tonumber(myId) then return end
    local okD, d = pcall(Json.decode, p.json)
    if not okD or type(d) ~= "table" then return end
    local owner = "remote:" .. tostring(p.owner)
    local em = Fx.unpack(d.em)
    local byId = {}
    for _, e in ipairs(em) do byId[e.id] = e end
    for _, ed in ipairs(d.edges or {}) do
        local e = byId[ed[1]]
        if e then e.edge[ed[2]] = true end
    end
    if #em == 0 then remote[owner] = nil; NcmFx.clear(owner); return end
    remote[owner] = { vid = p.vid, emitters = em, at = GetGameTimer(), fresh = true }
end)

CreateThread(function()
    while true do
        Wait(0)
        local okR = pcall(function()
        local now = GetGameTimer()
        for owner, r in pairs(remote) do
            if now - r.at > REMOTE_TTL_MS then
                remote[owner] = nil
                NcmFx.clear(owner)
            else
                local okP, v = pcall(Open77.vehicles.get, r.vid)
                local okF, f = pcall(Open77.character.frame, { vehicleId = r.vid })
                local me = owners[NcmFx.localOwner or ""]
                local near = true
                if me and okP and type(v) == "table" and v.position then
                    local dx, dy, dz = v.position.x - me.pos.x, v.position.y - me.pos.y, v.position.z - me.pos.z
                    near = dx * dx + dy * dy + dz * dz < REMOTE_RANGE_M * REMOTE_RANGE_M
                end
                if near and okP and okF and type(v) == "table" and v.position and type(f) == "table" then
                    NcmFx.frame(owner, r.emitters, f, v.position, true)
                    if r.fresh then   -- an edge plays once
                        r.fresh = false
                        for _, e in ipairs(r.emitters) do e.edge = {} end
                    end
                end
            end
        end
        end)
        if not okR then Wait(100) end    -- a budget overrun here never kills the watcher
    end
end)

-- A car whose updates stop (its flight thread died, it left Deep, the player got out) loses its effects half a second
-- later: nothing NCM drew outlives what drives it (the first Deep flight's plume kept burning after the flight froze).
CreateThread(function()
    while true do
        Wait(250)
        local now = GetGameTimer()
        for o, rec in pairs(owners) do
            if now - (rec.at or 0) > STALE_MS then NcmFx.clear(o) end
        end
    end
end)

--- An owner went away (left Deep, out of the car, a remote Machine streamed out).
function NcmFx.clear(owner)
    owners[owner] = nil
    for k in pairs(held) do if k:sub(1, #owner + 1) == owner .. ":" then stop(k); placed[k] = nil end end
end

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    for k in pairs(held) do stop(k) end
end)

AddEventHandler("onClientResourceStart", function(name) if name == "ncm_audio" then audioDown = false end end)
