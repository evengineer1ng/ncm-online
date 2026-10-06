-- NCM Deep, run by Assetto Corsa (L329, "NCM 3.0 - one universe"). ONE Deep: the same ncm-core modules Cyberpunk runs
-- (space.deep, space.guidance, space.canonical, engineering.installation / controls; vendored by tools/ncm-build.ps1),
-- the same Earth frame, the same venues, the same server-owned record. AC is a runner and a renderer:
--
--   ascent  -- AC is authoritative (its physics, its car). Above ASCENT_M the planet NCM flies over is drawn BEHIND the
--              near world: a fullscreen pass at depth MASK_NEAR_M, so the car and the track close by stay AC's own
--              (real depth composition -- CSP allows what Cyberpunk's overlay could not).
--   deep    -- above DEEP_M, climbing: the Machine's state is captured from AC's physics (CSP's own track coordinates
--              give latitude/longitude), NCM becomes authoritative, AC only holds the body and draws it. The planet is
--              drawn at depth HOLD_DEPTH_M so everything but the car is NCM's universe. Guidance, the Machine's own
--              propulsors, heat and fuel run on the shared core; the record is checkpointed to NCM every second.
--   back    -- arriving over THIS track: descend below DEEP_M near it and AC takes the Machine back, moving.
--              Night City: the bridge launches Cyberpunk in the background while you approach; when Cyberpunk has the
--              Machine, AC is released and closes. Another AC venue: an expression loss for now (AC restarts there).
-- Expression losses (said, not hidden): AC's chase camera only; roll is not shown (setCarPosition takes a direction);
-- the held body sits above the track in AC's world while NCM moves it on the planet.
local M = {}
local ASCENT_M, DEEP_M, MASK_NEAR_M, HOLD_DEPTH_M = 1500, 6000, 3000, 60
local NC = { id = "night_city", name = "Night City", region = "California (Cyberpunk 2077)", lat = 35.37, lon = -120.85,
  alt = 11000, host = "cyberpunk" }   -- held at ~14 km so Cyberpunk takes it at its own seam (12 km)

local C, D, G, CN, I, CT, VN, FM
local fm, dyn, devAtt = nil, nil, false   -- L331: the full machine model and its state
local ctx
local F = nil              -- AC world <-> local ENU at the track
local mode = "off"
local s, devices, devState, ctl, mass, axis = nil, {}, nil, nil, 1925, nil
local GD = { open = false, sel = 1, engaged = false, route = nil, msg = nil, held = {}, approachSent = false }
local fuelKg, devFuel, devHeat = 0, true, true
local lastCheck, released = 0, false
local HOLD, holdDir = nil, nil
local list = {}

local function v3t(v) return { v.x, v.y, v.z } end

-- ------------------------------------------------------------------------------------------------ the track frame
local function measure()
  if F then return F end
  local okC, c0 = pcall(ac.getTrackCoordinatesDeg, vec3(0, 0, 0))
  local _, cx = pcall(ac.getTrackCoordinatesDeg, vec3(1000, 0, 0))
  local _, cz = pcall(ac.getTrackCoordinatesDeg, vec3(0, 0, 1000))
  if not okC or not c0 or (math.abs(c0.x) < 1e-6 and math.abs(c0.y) < 1e-6) then return nil end
  local R, rad = D.R, math.rad
  local function en(c) return rad(c.y - c0.y) * R * math.cos(rad(c0.x)), rad(c.x - c0.x) * R end
  local ex, nx = en(cx); local ez, nz = en(cz)
  F = { lat0 = c0.x, lon0 = c0.y, ex = ex / 1000, nx = nx / 1000, ez = ez / 1000, nz = nz / 1000, y0 = ctx.groundY0() or 0,
        alt0 = (ctx.H() and ctx.H().venue and ctx.H().venue.alt) or 0 }
  F.det = F.ex * F.nz - F.ez * F.nx
  return F
end
local function toEnu(v) return { v.x * F.ex + v.z * F.ez, v.x * F.nx + v.z * F.nz, v.y } end
local function fromEnu(e) return vec3((e[1] * F.nz - e[2] * F.ez) / F.det, e[3], (F.ex * e[2] - F.nx * e[1]) / F.det) end
--- an AC world point -> ECEF (lat/lon from CSP itself, altitude from the track's ground and elevation)
local function worldToEcef(pos)
  local c = ac.getTrackCoordinatesDeg(pos)
  return D.llaToEcef(c.x, c.y, F.alt0 + (pos.y - F.y0)), c.x, c.y
end

-- ------------------------------------------------------------------------------------------------ input (pad + keys)
local PADB = { up = "DPadUp", left = "DPadLeft", right = "DPadRight", a = "A", b = "B" }
local KEYS = { up = "G", left = "Z", right = "C", a = "F", b = "X" }
local function down(name)
  local b = ac.GamepadButton[PADB[name]]
  for gi = 0, 7 do if ac.isGamepadButtonPressed(gi, b) then return true end end
  local k = ac.KeyIndex[KEYS[name]]
  return k ~= nil and ac.isKeyDown(k)
end
local function edge(name)
  local d = down(name)
  local was = GD.held[name]
  GD.held[name] = d
  return d and not was
end
local function stick(axisName)
  local v = 0
  for gi = 0, 3 do
    local ok, a = pcall(ac.getGamepadAxisValue, gi, ac.GamepadAxis[axisName])
    if ok and type(a) == "number" and math.abs(a) > math.abs(v) then v = a end
  end
  return math.abs(v) < 0.15 and 0 or v
end

local function thrustAxis()
  local a = { 0, 0, 0 }
  for _, d in ipairs(devices) do
    if d.kind == "reaction_engine" then a = D.vec.add(a, D.vec.scale(d.axis or { 0, 1, 0 }, (d.perf and d.perf.thrustN) or 0)) end
  end
  return D.vec.len(a) > 0 and D.vec.unit(a) or nil
end

-- ------------------------------------------------------------------------------------------------ lifecycle
function M.init(context)
  ctx = context
  C = ctx.Core
  D, G, CN, I, CT, VN = C.get("space.deep"), C.get("space.guidance"), C.get("space.canonical"), C.get("engineering.installation"),
    C.get("engineering.controls"), C.get("space.venues")
  FM = C.get("engineering.flightmodel")
  list = { NC }
  for _, v in ipairs(VN.VENUES) do list[#list + 1] = v end
end

function M.mode() return mode end

local function adopt(arrival)
  arrival = arrival or {}
  devices = {}
  for _, d in ipairs(arrival.devices or {}) do
    local perf = {}
    for k, x in pairs(d.perf or {}) do perf[k] = x end
    perf.kind = perf.kind or d.kind
    devices[#devices + 1] = { componentId = d.componentId, code = d.code, kind = d.kind, axis = d.axis, pos = d.pos, perf = perf,
      thermal = d.thermal }
  end
  devState = I.newState(devices)
  ctl = CT.newState()
  mass = tonumber(arrival.mass or arrival.massKg) or 1925
  fuelKg, devFuel, devHeat = tonumber(arrival.fuelKg) or 0, arrival.devFuel ~= false, arrival.devHeat ~= false
  devAtt = arrival.devAttitude == true
  axis = thrustAxis()
  -- L331: the same machine Cyberpunk flies (install + chassis + its own tank)
  local fk = fuelKg
  if fk <= 0 and devFuel then fk = 40 end
  fm = FM.build(devices, { vehicleKey = arrival.vehicleKey or "archer_hella", fuelKg = fk })
end

--- AC -> Deep at the seam: the Machine's state from AC's physics.
function M.begin(car)
  if not measure() then ctx.note("NCM Deep: this track has no coordinates (CSP); cannot leave through the sky"); return false end
  local H = ctx.H()
  adopt(H and H.arrival)
  local p, lat, lon = worldToEcef(car.position)
  local vel = D.enuToEcef(toEnu(car.velocity), lat, lon)
  local fwd = D.enuToEcef(toEnu(car.look), lat, lon)
  local up = D.enuToEcef(toEnu(car.up), lat, lon)
  s = { p = p, v = vel, t = 0, basis = { forward = D.vec.unit(fwd), up = D.vec.unit(up), right = D.vec.unit(D.vec.cross(fwd, up)) } }
  dyn = FM.state(fm, s)
  HOLD, holdDir, mode, released = car.position:clone(), car.look:clone(), "deep", false
  pcall(physics.disableCarCollisions, 0, true)
  ctx.post({ type = "probe", what = "deepEntry", lat = lat, lon = lon, alt = F.alt0 + (car.position.y - F.y0), speed = car.velocity:length() })
  M.checkpoint(true)
  ac.setMessage("NCM", "NCM Deep -- the same Deep as Night City. D-pad up: Guidance.", nil, 6)
  return true
end

--- Started in Deep (AC opened by the player while their Machine is canonically in Deep).
function M.resume(rec, car)
  if not measure() then return false end
  adopt(rec)
  s = CN.toDeep(rec)
  dyn = FM.state(fm, s, rec.dyn)
  HOLD, holdDir, mode, released = car.position + vec3(0, DEEP_M, 0), car.look:clone(), "deep", false
  pcall(physics.disableCarCollisions, 0, true)
  if rec.guidance and rec.guidance.engaged and rec.guidance.venueId then
    for i, v in ipairs(list) do if v.id == rec.guidance.venueId then GD.sel, GD.route, GD.engaged = i, G.plan(s, v), true end end
  end
  ctx.post({ type = "probe", what = "deepResume" })
  return true
end

function M.checkpoint(transition, place, locationId)
  local H = ctx.H() or {}
  local rec = s and CN.fromDeep(s, 0, { asset = H.arrival and H.arrival.asset or (H.rec and H.rec.asset), massKg = mass, devices = devices,
    devState = devState, fuelKg = fuelKg, devFuel = devFuel, devHeat = devHeat, devAttitude = devAtt, host = "assetto_corsa",
    vehicleKey = fm and fm.vehicleKey or "archer_hella", dyn = dyn and FM.carry(dyn) or nil,
    guidance = GD.route and { venueId = GD.route.venue.id, engaged = GD.engaged } or nil }) or nil
  ctx.post({ type = "canonical", driverId = H.driverId, place = place or "deep", locationId = locationId, rec = rec, transition = transition == true })
end

--- The server says another host has the Machine: stop, and let AC close.
function M.release(why)
  if released then return end
  released, mode = true, "released"
  ac.setMessage("NCM", "The Machine is in " .. tostring(why or "another host") .. ".", nil, 3)
  setTimeout(function() ac.shutdownAssettoCorsa() end, 1.5)
end

-- ------------------------------------------------------------------------------------------------ the flight
local function guidanceInput(dt)
  if edge("up") then GD.open = not GD.open end
  if GD.open then
    if edge("left") then GD.sel = (GD.sel - 2) % #list + 1 end
    if edge("right") then GD.sel = GD.sel % #list + 1 end
    if edge("a") then
      if GD.engaged then GD.engaged, GD.msg = false, "Autopilot off: you have the Machine."
      else
        local sus = G.thrustBudget(devices, nil, devHeat)
        local ok, _, why = G.feasible(sus, mass)
        if not ok then GD.msg = "Guidance cannot fly this Machine: " .. tostring(why)
        else GD.route, GD.engaged, GD.msg, GD.approachSent = G.plan(s, list[GD.sel]), true, nil, false end
      end
    end
    if edge("b") then if GD.engaged then GD.engaged = false else GD.open = false end end
  end
end

function M.update(dt, car)
  if mode ~= "deep" or released then return end
  dt = math.min(0.05, math.max(0.001, dt))
  -- AC holds the body still where it entered; NCM moves it on the planet
  local dirAC = fromEnu(D.ecefToEnu(s.basis.forward, D.ecefToLla(s.p)))
  if dirAC:length() > 0.01 then holdDir = dirAC:normalize() end
  physics.setCarPosition(0, HOLD, holdDir)
  physics.setCarVelocity(0, vec3(0, 0, 0))
  guidanceInput(dt)
  -- L331: one step of the FULL machine model (the same one Cyberpunk and the server step)
  local cmd = { throttle = {}, discharge = {} }
  local opts = { devFuel = devFuel, devHeat = devHeat }
  -- the Machine's own components, its own bindings
  local bindings = (ctx.H() and ctx.H().arrival and ctx.H().arrival.bindings) or {}
  local pressed = {}
  for _, b in ipairs(bindings) do pressed[b.control] = ctx.controlDown(b.control) end
  M.clockMs = (M.clockMs or 0) + dt * 1000
  local cmds = CT.step(ctl, bindings, devices, pressed, M.clockMs)
  for id, c in pairs(cmds) do
    if c.throttle then cmd.throttle[id] = c.throttle end
    if c.discharge then cmd.discharge[id] = true end
  end
  -- the sticks: torque from attitude parts, or the labelled development waiver
  if not GD.engaged then
    local pitch, yaw, roll = stick("LeftThumbY"), stick("LeftThumbX"), GD.open and 0 or stick("RightThumbX")
    if pitch ~= 0 or yaw ~= 0 or roll ~= 0 then
      if #(fm.attitude or {}) > 0 then cmd.torque = { pitch, roll, -yaw }
      elseif devAtt then opts.rig = { pitch = pitch * 1.1, yaw = yaw * 1.1, roll = roll * 1.1 } end
    end
  end
  if GD.engaged and GD.route then
    local ok, why = FM.canPoint(fm, devAtt)
    if not FM.mainAxis(fm) then GD.engaged, GD.msg = false, "Guidance cannot fly this Machine: no sustained thrust installed."
    elseif not ok then GD.engaged, GD.msg = false, "Guidance cannot point this Machine: " .. tostring(why)
    else
      local gc, waiver, info = G.fly(GD.route, fm, dyn, { devHeat = devHeat, waiver = devAtt and #(fm.attitude or {}) == 0 })
      for id, th in pairs(gc.throttle) do cmd.throttle[id] = th end
      if gc.torque then cmd.torque = gc.torque end
      opts.waiver = waiver
      GD.phase, GD.km, GD.eta = info.phase, info.distanceM / 1000, info.etaS
      -- Cyberpunk needs ~1-2 min to boot: start it while still ~60 km out
      local dnow = FM.deep(dyn)
      if GD.route.venue.id == "night_city" and not GD.approachSent and (info.distanceM < 60000 or G.arrived(GD.route, dnow)) then
        GD.approachSent = true
        ctx.post({ type = "approach", target = "night_city", etaS = info.etaS })
        GD.msg = "Night City ahead: Cyberpunk is starting in the background."
      end
      if G.arrived(GD.route, dnow) and GD.route.venue.id ~= "night_city" then GD.arrivedAt = GD.route.venue end
    end
  end
  local tel
  dyn, tel = FM.step(fm, dyn, cmd, dt, opts)
  if not devFuel then fuelKg = FM.fuelKg(fm, dyn) end
  s = FM.deep(dyn)
  M.thrustN, M.waiver, M.spin = tel.thrustN or 0, tel.waiver == true, D.vec.len(dyn.omega)
  M.authority = FM.authorityText(fm)
  local la, lo, alt = D.ecefToLla(s.p)
  M.alt, M.lat, M.lon, M.speed = alt, la, lo, D.vec.len(s.v)
  -- back to THIS track: descend near it below the seam and AC takes the Machine, moving
  local H = ctx.H()
  local here = H and H.venue
  if here and alt - (here.alt or 0) < DEEP_M - 500 and D.distance(la, lo, F.lat0, F.lon0) < 8000 then
    -- metres east / north of the track origin, at the track's own latitude
    local enu = { math.rad(lo - F.lon0) * D.R * math.cos(math.rad(F.lat0)), math.rad(la - F.lat0) * D.R, F.y0 + (alt - F.alt0) }
    local pos = fromEnu(enu)
    pcall(physics.disableCarCollisions, 0, false)
    physics.setCarPosition(0, pos, holdDir)
    physics.setCarVelocity(0, fromEnu(D.ecefToEnu(s.v, la, lo)))
    mode = "off"
    ctx.post({ type = "probe", what = "deepExit", venue = here.id, alt = alt })
    M.checkpoint(true, "host_surface", here.id)
    ac.setMessage("NCM", "Back in " .. tostring(here.name) .. ".", nil, 5)
    return
  end
  if alt < ((GD.route and G.groundBelow(GD.route, la, lo) or 0) + 25) and (not here or D.distance(la, lo, F.lat0, F.lon0) >= 8000) then
    -- came down where no host is: the flight ends there; NCM recovers the Machine (Night City)
    mode = "off"
    ctx.post({ type = "canonical", driverId = H and H.driverId, place = "landed", locationId = ("%.3f,%.3f"):format(la, lo), transition = true })
    ctx.post({ type = "approach", target = "night_city", why = "landed" })
    ac.setMessage("NCM", "Came down far from any host. NCM is bringing the Machine home.", nil, 8)
    return
  end
  lastCheck = lastCheck + dt
  if lastCheck >= 1 then lastCheck = 0; M.checkpoint(false) end
end

-- ------------------------------------------------------------------------------------------------ drawing
local pass = nil
local function cameraEcef(sim, car, deep)
  local camPos, lat, lon, alt
  if deep then
    local la, lo = D.ecefToLla(s.p)
    local rel = D.enuToEcef(toEnu(sim.cameraPosition - car.position), la, lo)
    camPos = D.vec.add(s.p, rel)
    lat, lon = la, lo
  else
    camPos, lat, lon = worldToEcef(sim.cameraPosition)
  end
  local function dir(v) return D.vec.unit(D.enuToEcef(toEnu(v), lat, lon)) end
  local _, _, a = D.ecefToLla(camPos)
  return camPos, a, dir(sim.cameraLook), dir(sim.cameraUp), dir(sim.cameraSide)
end

function M.draw3D(car, heightAboveGround)
  local sim = ac.getSim()
  local deep = mode == "deep"
  if not deep and (not heightAboveGround or heightAboveGround < ASCENT_M) then return end
  if not measure() then return end
  local k = deep and 1 or math.max(0, math.min(1, (heightAboveGround - ASCENT_M) / (DEEP_M - ASCENT_M)))
  k = k * k * (3 - 2 * k)
  local cam, alt, fwd, up, side = cameraEcef(sim, car, deep)
  pass = pass or {
    async = true, blendMode = render.BlendMode.AlphaBlend, depth = MASK_NEAR_M,
    textures = { txEarth = ctx.dir .. "/earth.jpg" },
    values = { gCam = vec3(), gAlt = 0, gFwd = vec3(), gUp = vec3(), gSide = vec3(), gTan = 0.5, gAspect = 1.7, gSun = vec3(), gK = 0, gR = D.R },
    shader = [[
      float4 main(PS_IN pin) {
        float2 ndc = float2(pin.Tex.x * 2 - 1, 1 - pin.Tex.y * 2);
        float3 d = normalize(gFwd + ndc.x * gTan * gAspect * gSide + ndc.y * gTan * gUp);
        float3 o = gCam;
        float b = dot(o, d);
        float c = gAlt * (2 * gR + gAlt);
        float disc = b * b - c;
        float airTop = saturate(1 - gAlt / 70000.0);
        float dayHere = saturate(dot(normalize(o), gSun) * 3 + 0.4);
        float2 sph = float2(atan2(d.y, d.x), asin(clamp(d.z, -1, 1)));
        float2 cell = floor(sph * 400);
        float h = frac(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
        float star = step(0.9975, h) * (0.5 + 0.5 * h) * (1 - airTop * dayHere);
        float3 col = float3(0.35, 0.55, 0.9) * airTop * dayHere + star;
        if (disc > 0) {
          float t = -b - sqrt(disc);
          if (t > 0) {
            float3 n = normalize(o + d * t);
            float2 uv = float2(atan2(n.y, n.x) / 6.2831853 + 0.5, 0.5 - asin(clamp(n.z, -1, 1)) / 3.1415927);
            float3 tex = txEarth.Sample(samAnisotropic, uv).rgb;
            float day = smoothstep(-0.08, 0.25, dot(n, gSun));
            float3 lit = tex * (0.03 + 0.97 * day);
            lit = lerp(lit, float3(0.6, 0.72, 0.9) * (0.1 + 0.9 * day), 0.35 * saturate(t / 400000.0) * airTop);
            col = lit;
          }
        }
        return float4(col, gK);
      }
    ]]
  }
  pass.depth = deep and HOLD_DEPTH_M or MASK_NEAR_M
  local V = pass.values
  -- camera-relative precision: the shader works in metres from the Earth's centre (float32 is fine at planet scale)
  V.gCam = vec3(cam[1], cam[2], cam[3]); V.gAlt = alt
  V.gFwd, V.gUp, V.gSide = vec3(fwd[1], fwd[2], fwd[3]), vec3(up[1], up[2], up[3]), vec3(side[1], side[2], side[3])
  V.gTan = math.tan(math.rad(sim.cameraFOV) / 2)
  V.gAspect = sim.windowWidth / math.max(1, sim.windowHeight)
  -- one sun on NCM's clock (space.deep.sunAt): night is night here as in Night City
  local utc = ctx.utcNow and ctx.utcNow()
  local sun = utc and D.sunAt(utc) or D.sun(13)
  V.gSun = vec3(sun[1], sun[2], sun[3]); V.gK = k
  render.fullscreenPass(pass)
end

local function text(str, x, y, size, col) ui.dwriteDrawText(str, size or 16, vec2(x, y), col or rgbm(0.62, 1, 1, 1)) end

function M.drawUI(heightAboveGround)
  local sw = ui.windowSize()
  if mode ~= "deep" then
    if heightAboveGround and heightAboveGround > ASCENT_M then
      text(("ALT %.2f km above the track   NCM DEEP in %.2f km"):format(heightAboveGround / 1000, (DEEP_M - heightAboveGround) / 1000),
        sw.x / 2 - 200, sw.y - 40, 15)
    end
    return
  end
  ui.drawRectFilled(vec2(16, 16), vec2(700, 260), rgbm(0, 0, 0, 0.45))
  local L = {
    "NCM DEEP  -  run by Assetto Corsa (the same Deep as Night City)",
    ("ALTITUDE   %.2f km"):format((M.alt or 0) / 1000),
    ("SPEED      %.0f m/s"):format(M.speed or 0),
    ("POSITION   %.3f, %.3f"):format(M.lat or 0, M.lon or 0),
    ("THRUST     %.1f kN"):format((M.thrustN or 0) / 1000),
    ("FUEL       %s"):format(devFuel and "DEV FUEL (development only)" or ("%.1f kg"):format(fuelKg)),
    ("RACE WEEK  %s"):format(ctx.weekText()),
    ("ATTITUDE   %s%s  spin %.2f rad/s"):format(M.authority or "-", M.waiver and "   DEV WAIVER (not physical)" or "", M.spin or 0),
  }
  for i, l in ipairs(L) do text(l, 28, 22 + i * 24) end
  text("D-pad up / G: GUIDANCE   left stick: attitude (rig, not physical)   your bindings: your parts", 28, sw.y - 30, 13, rgbm(0.8, 0.85, 0.85, 1))
  if GD.open or GD.engaged or GD.msg then
    local x = sw.x - 580
    ui.drawRectFilled(vec2(x, 16), vec2(sw.x - 16, 200), rgbm(0, 0.05, 0.02, 0.6))
    local sel = list[GD.sel]
    local g = { "GUIDANCE" .. (GD.engaged and "  -  AUTOPILOT ENGAGED" or "") }
    if GD.engaged and GD.route then
      g[#g + 1] = "TARGET  " .. GD.route.venue.name
      g[#g + 1] = ("DIST    %.0f km   ETA %d min"):format(GD.km or 0, math.floor((GD.eta or 0) / 60))
      g[#g + 1] = "PHASE   " .. tostring(GD.phase or "planning")
    else
      g[#g + 1] = "SELECT  " .. sel.name .. "  (" .. tostring(sel.region) .. ")"
      g[#g + 1] = ("DIST    %.0f km"):format(D.distance(M.lat or 0, M.lon or 0, sel.lat, sel.lon) / 1000)
      g[#g + 1] = "< > destination   A engage   B close"
    end
    if GD.msg then g[#g + 1] = GD.msg end
    for i, l in ipairs(g) do text(l, x + 12, 22 + i * 24, 16, rgbm(0.49, 1, 0.49, 1)) end
  end
end

return M
