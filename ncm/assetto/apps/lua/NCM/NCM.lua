-- NCM (L327): the Assetto Corsa side of an NCM embodiment. NCM is canonical; this app makes the place physical.
--
-- From the host bridge (tools/ncm-host-bridge.py, http://127.0.0.1:47710) it takes the HANDOFF: the Machine arriving from
-- NCM Deep (height above the venue, velocity, its installed components and bindings) and the NCM race already running
-- here (each NPC's identity, traits and canonical track position). It then:
--   * ARRIVAL: puts the player's car in the air above the start line, moving (physics.setCarPosition + setCarVelocity);
--   * COMPONENTS: the same Triangle that hops the Machine in Cyberpunk fires its impulse actuator here, as a real force at
--     the mount (physics.addForce), and holding it runs the propulsor -- parts stay parts, never a horsepower buff;
--   * NPC FIELD: names the AI cars after NCM's drivers and sets level / aggression / mistakes from their traits (NCM
--     decides; AC's AI steers), and moves them to their canonical positions so a late arrival meets the race where it is;
--   * DEPARTURE (L329): going up IS leaving. Above the ascent height NCM's planet appears behind the near world; past
--     the seam the SAME NCM Deep runs here (ncm_deep.lua on the vendored ncm-core) -- Cyberpunk is not needed for it;
--   * RESULTS: the classification goes back to the same canonical event.
-- Every capability is MEASURED the first time and reported to the bridge (`probe` events) -- nothing is assumed.
local BRIDGE = "http://127.0.0.1:47710"
-- L329: the same ncm-core Cyberpunk runs (vendored into ./core by tools/ncm-build.ps1), and the Deep runner
local DIR = ac.dirname()
package.path = DIR .. "/core/?.lua;" .. DIR .. "/?.lua;" .. package.path
local Core = require("init")
for _, m in ipairs(require("LOAD")) do require(m) end
Core.warm()
local NcmDeep = require("ncm_deep")
local DEEP_M = 6000                 -- the seam above the track (ncm_deep.lua owns the rest)
local universe = nil                -- what NCM publishes: the clock, Race Week, the canonical records
local DEPART_M = 2500
-- KB-354: the arrival is ABOVE DEPART_M (3,131 m on 2026-10-06 13:20), so the climb-out only counts once the Machine has
-- come down below ARM_M, and only while it is climbing; otherwise AC closed itself the instant you arrived.
local ARM_M = 1000
local armed = false

local H = nil
local phase = "waiting"            -- waiting -> placed -> live -> departed
local simT, lastTele = 0, 0
local pulses = {}
local probe = { place = nil, force = nil, thrust = nil }
local fieldDone, resultSent = false, false
local started, lastStartTry = false, -1   -- the pre-race screen, pressed by the app
local liveFor, stateProbed, placements, lastHeight = 0, false, 0, nil
local note = "waiting for NCM"
M_height = nil

local function post(t)
  local ok, body = pcall(JSON.stringify, t)
  if ok then web.post(BRIDGE .. "/ac/event", { ["Content-Type"] = "application/json" }, body, function() end) end
end

--- this track, where CSP says it is (L329: the place registry learns locations from the hosts themselves)
local function reportPlace()
  local okC, c = pcall(ac.getTrackCoordinatesDeg)
  local okT, tz = pcall(ac.getTrackTimezoneBaseDst)
  post({ type = "place", observation = { host = "assetto_corsa", track = ac.getTrackID(), layout = ac.getTrackLayout(),
    csp = okC and c and { lat = c.x, lon = c.y, tzS = okT and tz and tz.x or nil } or nil } })
end
reportPlace()

local standalone = nil   -- L329: AC opened by the player; NCM's record decides what this session is
local function fromUniverse()
  web.get(BRIDGE .. "/universe", nil, function(err, response)
    if err or not response or not response.body then note = "NCM not reachable: ordinary Assetto Corsa"; return end
    local ok, u = pcall(JSON.parse, response.body)
    if not ok or type(u) ~= "table" then return end
    universe = u
    if H then return end
    local me = u.drivers and u.drivers[1]
    if not me then note = "NCM: no Machine on record"; return end
    local rec = me.rec or {}
    if me.place == "deep" then
      standalone = { kind = "deep", rec = rec }
      H = { venue = nil, driverId = me.driverId, arrival = rec, rec = rec }
      note = "NCM: your Machine is in Deep"
    elseif me.place == "host_surface" and me.locationId then
      for _, v in ipairs(Core.get("space.venues").VENUES) do
        if v.id == me.locationId and v.track == ac.getTrackID() then
          standalone = { kind = "surface" }
          H = { venue = v, driverId = me.driverId, arrival = rec, rec = rec }
          phase = "live"
          note = "NCM: your Machine at " .. v.name
        end
      end
      if not standalone then note = "NCM: your Machine is at " .. tostring(me.locationId) .. ", not here" end
    else
      note = "NCM: your Machine is " .. tostring(me.place) .. " (" .. tostring(me.locationId or "") .. ")"
    end
  end)
end
setInterval(fromUniverse, 3)

web.get(BRIDGE .. "/handoff", nil, function(err, response)
  if err or not response or not response.body then note = "no NCM handoff (" .. tostring(err) .. ")"; return end
  local ok, h = pcall(JSON.parse, response.body)
  if ok and type(h) == "table" and h.venue then
    H = h
    note = "NCM: " .. tostring(h.venue.name)
    post({ type = "probe", what = "handoff", venue = h.venue.id, physicsAllowed = physics.allowed() })
  end
end)

local function v3(a) return vec3(a[1] or a.x or 0, a[2] or a.y or 0, a[3] or a.z or 0) end
local controlDownRef   -- set below (the binding reader the components use)

--- ground height under a point (raycast down); nil when nothing is below
local function groundBelow(pos)
  local d = physics.raycastTrack(pos, vec3(0, -1, 0), 20000)
  if d and d >= 0 then return pos.y - d end
  return nil
end

--- NCM machine frame (x right, y forward, z up) -> AC world, with the car's own axes.
local function toWorld(car, v)
  return car.side * (-(v[1] or 0)) + car.look * (v[2] or 0) + car.up * (v[3] or 0)
end

local function arrive(car)
  placements = placements + 1
  local a = H.arrival or {}
  -- Guidance hands an AC venue over LOW and slow (space.guidance HOST_ARRIVE_ABOVE_M): the Machine drops onto the circuit
  local above = math.max(30, math.min(8000, (a.alt or 80) - (a.venueAlt or 0)))
  local p0 = ac.trackProgressToWorldCoordinate(0.0)
  local p1 = ac.trackProgressToWorldCoordinate(0.01)
  local dir = (p1 - p0):normalize()
  local g = groundBelow(p0 + vec3(0, 50, 0)) or p0.y
  local target = vec3(p0.x, g + above, p0.z)
  physics.setCarPosition(0, target, dir)
  -- the arrival velocity, translated: its horizontal speed along the track's start direction, its vertical as vertical
  local v = a.v or { 0, 0, 0 }
  local hs = math.sqrt((v[1] or 0) ^ 2 + (v[2] or 0) ^ 2)
  physics.setCarVelocity(0, dir * math.min(hs, 15) + vec3(0, math.max(-30, math.min(30, v[3] or 0)), 0))
  probe.place = { asked = above, at = simT, ground = g }
  ac.setMessage("NCM", ("Arrived above %s from NCM Deep. Descend -- Triangle is your Machine."):format(H.venue.name), nil, 8)
end

local function placeField()
  local st = H.state
  if not st or not st.cars then return end
  local sim = ac.getSim()
  for i, c in ipairs(st.cars) do
    local idx = i
    if idx < sim.carsCount then
      pcall(physics.setAIDriverName, idx, c.name, "")
      pcall(physics.setAILevel, idx, 0.80 + 0.20 * (c.pace or 0.5))
      pcall(physics.setAIAggression, idx, c.aggression or 0.5)
      if (st.leaderLap or 1) > 1 or (c.progress or 0) > 0.01 then
        local pr = (c.progress or 0) % 1
        local p = ac.trackProgressToWorldCoordinate(pr)
        local q = ac.trackProgressToWorldCoordinate((pr + 0.005) % 1)
        pcall(physics.setAICarPosition, idx, p, (q - p):normalize())
      end
    end
  end
  post({ type = "probe", what = "field", placed = #st.cars, leaderLap = st.leaderLap, laps = st.laps })
end

--- NCM decides mistakes from each driver's own mistake rate; AC's AI lives with them.
local mistakeT = 0
local function npcDecisions(dt)
  mistakeT = mistakeT + dt
  if mistakeT < 5 or not (H.state and H.state.cars) then return end
  mistakeT = 0
  for i, c in ipairs(H.state.cars) do
    if math.random() < (c.mistake or 0.5) * 0.02 then pcall(physics.setAIBrakeMistake, i, 0.6) end
  end
end

-- KB-355: the server sends the Machine's parts and bindings inside `arrival` (the client's request), not at the top of the
-- handoff -- read from there, or Triangle finds no devices at all (owner, 2026-10-06: "Triangle currently does nothing").
local function devicesOf() return H.devices or (H.arrival and H.arrival.devices) or {} end
local function bindingsOf() return H.bindings or (H.arrival and H.arrival.bindings) or {} end

-- OPEN//77 control names (the NCM binding's `control`) -> what AC can read. Gamepads 0-3 are XInput, 4-7 DualShock.
local PAD = { padY = "Y", padX = "X", padA = "A", padB = "B", padLeftShoulder = "LeftShoulder", padRightShoulder = "RightShoulder",
  padUp = "DPadUp", padDown = "DPadDown", padLeft = "DPadLeft", padRight = "DPadRight", padLeftThumb = "LeftThumb",
  padRightThumb = "RightThumb" }
local function controlDown(c)
  local b = PAD[c]
  if b then
    for gi = 0, 7 do if ac.isGamepadButtonPressed(gi, ac.GamepadButton[b]) then return true end end
    return false
  end
  if type(c) == "string" and #c == 1 then
    local k = ac.KeyIndex[c:upper()]
    return k ~= nil and ac.isKeyDown(k)
  end
  return false
end
controlDownRef = controlDown

local HOLD_S = 0.18                -- engineering.controls HOLD_MS: a tap and a hold may share one control
local G0 = 9.80665
local ctl = {}                     -- control -> { down, since }
local dev = {}                     -- componentId -> { heatK, hot }
local spentKg, firstThrust = 0, nil

--- One device's heat, the canonical rule (engineering.installation): heat in, rejection out, shut down past the limit
--- until cool. The DEVELOPMENT heat waiver (owner, IDEA-1143) travels with the Machine.
local function heat(d, st, inKj, dt)
  local th = d.thermal
  if not th or not th.capacityKjK or (H.arrival and H.arrival.devHeat) then st.heatK, st.hot = 0, false; return end
  st.heatK = math.max(0, st.heatK + (inKj - (th.rejectKw or 0) * dt) / th.capacityKjK)
  if not st.hot and st.heatK >= (th.limitK or 1e9) then st.hot = true; post({ type = "probe", what = "thermal", component = d.code, event = "shutdown" }) end
  if st.hot and st.heatK <= (th.resumeK or 0) then st.hot = false end
end

--- Propellant, out of the Machine's own tank (nothing burns on the development server: dev fuel).
local function burn(d, kg)
  if H.arrival and H.arrival.devFuel then return true end
  local tank = tonumber(H.arrival and H.arrival.fuelKg) or 0
  if spentKg + kg > tank then return false end
  spentKg = spentKg + kg
  return true
end

-- KB-359 -> KB-367: the parts push by changing the car's VELOCITY (F x dt / m per frame), not with physics.addForce --
-- addForce lasts one physics step (it needed a 333 Hz scale) and acts at the car-local origin, which is not AC's centre
-- of gravity, so it also twisted the car. A velocity change is exact at any frame rate and makes no torque.
local hopN = 0
local function spinOf(car)
  local ok, w = pcall(function() return car.angularVelocity end)
  return (ok and w and w.length) and w:length() or nil
end
local function tiltOf(car)
  local ok, u = pcall(function() return car.up end)
  if not ok or not u then return nil end
  return math.deg(math.acos(math.max(-1, math.min(1, u.y))))
end
local function components(car, dt)
  local devices, bindings = devicesOf(), bindingsOf()
  if #devices == 0 then return end
  -- the controls the bindings read, as tap (press event) and hold (analog after HOLD_S when a tap shares the control)
  local tapOf, holdOf = {}, {}
  for _, b in ipairs(bindings) do
    if b.gesture == "tap" or b.gesture == "press" then tapOf[b.control] = true end
    if b.gesture == "hold" or b.gesture == "held" then holdOf[b.control] = true end
  end
  if #bindings == 0 then   -- no bindings came: the owner's own (tap = hop, hold = forward on Triangle)
    tapOf.padY, holdOf.padY = true, true
    for _, d in ipairs(devices) do
      bindings[#bindings + 1] = { control = "padY", gesture = d.kind == "pulse_reaction" and "tap" or "hold", componentId = d.componentId }
    end
  end
  local pressed, holding = {}, {}
  for c in pairs(tapOf) do ctl[c] = ctl[c] or { down = false } end
  for c in pairs(holdOf) do ctl[c] = ctl[c] or { down = false } end
  for c, st in pairs(ctl) do
    local d = controlDown(c)
    if d and not st.down then pressed[c], st.since = true, simT end
    st.down = d
    if not d then st.since = nil end
    holding[c] = st.since ~= nil and (not tapOf[c] or simT - st.since >= HOLD_S)
  end
  local byId = {}
  for _, d in ipairs(devices) do byId[d.componentId] = d; dev[d.componentId] = dev[d.componentId] or { heatK = 0, hot = false } end
  local thrusting = {}
  for _, b in ipairs(bindings) do
    local d = byId[b.componentId]
    if d then
      local st = dev[d.componentId]
      if d.kind == "pulse_reaction" and (b.gesture == "tap" or b.gesture == "press") and pressed[b.control] and not st.hot then
        local p = d.perf or {}
        local kg = (p.forceN or 0) * (p.pulseS or 0.2) / ((p.ispS or 3000) * G0)
        if burn(d, kg) then
          -- retrigger: a press mid-stroke restarts the stroke (the hop the owner flies in Night City)
          for i = #pulses, 1, -1 do if pulses[i].id == d.componentId then table.remove(pulses, i) end end
          -- KB-362: the direction is frozen at discharge (as in Night City), so a stroke cannot chase a rolling body
          pulses[#pulses + 1] = { id = d.componentId, code = d.code, left = p.pulseS or 0.2, force = p.forceN or 0,
            dir = toWorld(car, d.axis):normalize(), v0 = car.velocity:clone(), spin0 = spinOf(car) }
          heat(d, st, p.heatKj or 0, 0)
        end
      elseif d.kind == "reaction_engine" and (b.gesture == "hold" or b.gesture == "held") and holding[b.control] then
        thrusting[d.componentId] = d
      end
    end
  end
  -- KB-367: every push is a change of VELOCITY through the centre of mass, summed for the frame and written once --
  -- exactly what Night City's Carrier does (force at the centre of mass, no position, no moment). physics.addForce at
  -- the car-local origin is not AC's centre of gravity, and AC never damps spin in the air: each hop added a little
  -- rotation and the taps stacked it until the car was upside down. A velocity change cannot make torque.
  local dv = vec3(0, 0, 0)
  local mass = math.max(1, car.mass or 1)
  for _, d in ipairs(devices) do
    local st, p = dev[d.componentId], d.perf or {}
    local on = thrusting[d.componentId] and not st.hot
    if on then
      local kg = (p.thrustN or 0) / ((p.ispS or 2000) * G0) * dt
      on = burn(d, kg)
    end
    if on then
      dv = dv + toWorld(car, d.axis) * ((p.thrustN or 0) * dt / mass)
      if not firstThrust then firstThrust = { at = simT, v0 = car.velocity:clone(), code = d.code, thrustN = p.thrustN } end
    end
    if d.kind == "reaction_engine" then heat(d, st, (p.heatKw or 0) * (on and 1 or 0) * dt, dt) end
  end
  if firstThrust and not probe.thrust and simT - firstThrust.at >= 1 then
    local dv = (car.velocity - firstThrust.v0):length()
    probe.thrust = { component = firstThrust.code, thrustN = firstThrust.thrustN, mass = car.mass, measuredDvAfter1s = dv,
      expectedDvAfter1s = firstThrust.thrustN / car.mass }
    post({ type = "probe", what = "thrust", result = probe.thrust })
  end
  for i = #pulses, 1, -1 do
    local p = pulses[i]
    local step = math.min(dt, p.left)
    -- the stroke's impulse for this frame, exact at any frame rate (engineering.installation)
    dv = dv + p.dir * (p.force * step / mass)
    p.left = p.left - step
    if p.left <= 0 then
      if not probe.force then
        local got = (car.velocity - p.v0):length()
        probe.force = { component = p.code, force = p.force, pulseS = 0.2, mass = car.mass, measuredDv = got, expectedDv = p.force * 0.2 / car.mass }
        post({ type = "probe", what = "force", result = probe.force })
      end
      -- KB-367 evidence: does a stroke spin the car? (the first ten strokes; spin in rad/s, tilt = how far `up` is from the sky)
      hopN = hopN + 1
      if hopN <= 10 then
        post({ type = "probe", what = "hopSpin", n = hopN, spinBefore = p.spin0, spinAfter = spinOf(car), tiltDeg = tiltOf(car) })
      end
      table.remove(pulses, i)
    end
  end
  if dv:length() > 0 then physics.setCarVelocity(0, car.velocity + dv) end
end

local cmdT = 0
local clockSet = false
--- NCM's one clock (UTC), from the handoff or the universe, advanced by AC's own time since it arrived
local utcBase, utcAt = nil, 0
function NCM_utcNow() return utcBase and (utcBase + (simT - utcAt)) or nil end
local function setClock()
  if clockSet or not NCM_utcNow() then return end
  local before = ac.getSunAngle and ac.getSunAngle() or nil
  local ok, err = pcall(ac.setWeatherExactUTC0Timestamp, NCM_utcNow(), true)
  pcall(ac.setWeatherTimeMultiplier, 1)
  clockSet = true
  post({ type = "probe", what = "clock", utc = NCM_utcNow(), ok = ok, err = ok and nil or tostring(err), sunBefore = before,
    sunAfter = ac.getSunAngle and ac.getSunAngle() or nil })
end
local function weekText()
  local w = universe and universe.week
  if type(w) ~= "table" then return "-" end
  return ("run %s, day %s, hour %s"):format(tostring(w.run), tostring(w.day), tostring(w.hours))
end
NcmDeep.init({ Core = Core, dir = DIR, post = post, H = function() return H end, note = function(t) note = t end,
  controlDown = function(c) return controlDownRef and controlDownRef(c) or false end, weekText = weekText,
  utcNow = function() return NCM_utcNow and NCM_utcNow() end,
  groundY0 = function()
    local p0 = ac.trackProgressToWorldCoordinate(0.0)
    local d = physics.raycastTrack(p0 + vec3(0, 50, 0), vec3(0, -1, 0), 20000)
    return (d and d >= 0) and (p0.y + 50 - d) or p0.y
  end })

function script.update(dt)
  simT = simT + dt
  -- commands from NCM (the bridge): another host has the Machine -> release it and close
  cmdT = cmdT + dt
  if cmdT > 1 then
    cmdT = 0
    web.get(BRIDGE .. "/ac/command", nil, function(err, response)
      if err or not response or not response.body then return end
      local ok, m = pcall(JSON.parse, response.body)
      for _, c in ipairs(ok and type(m) == "table" and m.commands or {}) do
        if c.cmd == "release" then NcmDeep.release(c.why) end
        if c.cmd == "loop" then
          -- L330: the Racing Week reset is universe-wide: this place rewinds too, and the Machine wakes in Night City
          ac.setMessage("NCM", "Racing Week reset. Reconstruction reloading in Night City.", nil, 5)
          post({ type = "probe", what = "loop" })
          setTimeout(function() ac.shutdownAssettoCorsa() end, 5)
        end
      end
    end)
  end
  if not utcBase and H and tonumber(H.utc) then utcBase, utcAt = tonumber(H.utc), simT end
  if not utcBase and universe and tonumber(universe.utc) then utcBase, utcAt = tonumber(universe.utc), simT end
  if H and not ac.getSim().isInMainMenu then setClock() end
  if not H then return end
  -- AC opened while the Machine is canonically in Deep: start there
  if standalone and standalone.kind == "deep" and NcmDeep.mode() == "off" and not standalone.started then
    local car0 = ac.getCar(0)
    if car0 and not ac.getSim().isInMainMenu and physics.allowed() then standalone.started = NcmDeep.resume(standalone.rec, car0) end
  end
  if NcmDeep.mode() == "deep" or NcmDeep.mode() == "released" then
    local car1 = ac.getCar(0)
    if car1 then NcmDeep.update(dt, car1) end
    return
  end
  local car = ac.getCar(0)
  local sim = ac.getSim()
  -- owner, 2026-10-06: no pre-race "Drive" screen on an NCM arrival -- press it for them (only when NCM sent us here)
  if sim.isInMainMenu then
    if not started and simT - lastStartTry > 0.5 then
      lastStartTry = simT
      started = ac.tryToStart(true) == true
      if started then post({ type = "probe", what = "autoStart", at = simT }) end
    end
    return
  end
  if not car then return end
  -- KB-356: place only once the session is LIVE and has stayed live a moment. At 13:35 the app placed the Machine 2 s
  -- after load, before the session began; the pre-race "Drive" then reset it to the grid (and armed the departure).
  if sim.isLive and not sim.isPaused and not sim.isInMainMenu then liveFor = liveFor + dt else liveFor = 0 end
  if not stateProbed and simT > 3 then
    stateProbed = true
    post({ type = "probe", what = "simState", isInMainMenu = sim.isInMainMenu, isLive = sim.isLive, isPaused = sim.isPaused,
      isSessionStarted = sim.isSessionStarted, timeToSessionStart = sim.timeToSessionStart })
  end
  -- the race start puts every car on the grid: arrive only once the session has started (15:49: two resets mid-fall)
  -- KB-361: only a RACE has a start to wait for; practice / qualifying / a track day are running as soon as they are live
  local sk = H and H.session and H.session.kind or "race"
  local started = (sk ~= "race" and sk ~= "grid") or sim.isSessionStarted or (tonumber(sim.timeToSessionStart) or 0) <= 0
  if phase == "waiting" and liveFor > 1 and started then
    if physics.allowed() then arrive(car); phase = "placed" else
      note = "physics not allowed in this session"
      post({ type = "probe", what = "physicsAllowed", value = false })
      phase = "live"
    end
  elseif phase == "placed" and simT - probe.place.at > 1 then
    local g = groundBelow(car.position + vec3(0, 5, 0))
    probe.place.heightAfter1s = g and (car.position.y - g) or -1
    post({ type = "probe", what = "airborneSpawn", result = probe.place })
    phase = "live"
  end
  if phase ~= "live" then return end
  if not fieldDone and simT > 6 then fieldDone = true; placeField() end
  npcDecisions(dt)
  if physics.allowed() then components(car, dt) end
  local g = groundBelow(car.position + vec3(0, 2, 0))
  local height = g and (car.position.y - g) or 0
  if simT - lastTele > 1 then
    lastTele = simT
    post({ type = "telemetry", height = height, speed = car.velocity:length(), lap = car.lapCount, spline = car.splinePosition,
      propellantKg = spentKg, armed = armed, loss = "velocity change at the centre of mass (mount offsets make no torque), as the Night City Carrier; pulse direction fixed at discharge" })
  end
  if not resultSent and sim.isSessionFinished then
    resultSent = true
    local rows = {}
    for i = 0, sim.carsCount - 1 do
      local c = ac.getCar(i)
      rows[#rows + 1] = { index = i, name = ac.getDriverName(i), position = c.racePosition, laps = c.lapCount }
    end
    post({ type = "result", eventId = H.event and H.event.eventId, rows = rows, provenance = "physical" })
  end
  if g and lastHeight and lastHeight > 1000 and height < 50 and placements < 3 and simT - (probe.place and probe.place.at or 0) < 30 then
    -- no fall covers 1 km in one frame: AC put the car back on the grid (session start); arrive again
    post({ type = "probe", what = "resetAfterArrival", from = lastHeight })
    arrive(car)
    lastHeight = nil
    return
  end
  lastHeight = g and height or lastHeight
  if not armed and g and height < ARM_M then armed = true; post({ type = "probe", what = "armed", height = height }) end
  M_height = height
  if armed and height > DEEP_M and car.velocity.y > 0 then
    -- L329: no "return to NCM" button and no closing AC -- the sky is the way out, and Deep is the same Deep
    if NcmDeep.begin(car) then phase = "deep" end
  end
end

-- L329: NCM's planet in AC's own 3D pass (depth-clipped), and the Deep HUD
function script.draw3D()
  local car = ac.getCar(0)
  if car and H then NcmDeep.draw3D(car, M_height) end
end

function script.fullscreenUI()
  if H then NcmDeep.drawUI(M_height) end
end

function script.windowMain(dt)
  ui.text(note)
  ui.text("phase: " .. phase)
  if probe.place then ui.text(("arrival asked %.0f m"):format(probe.place.asked)) end
  if probe.force then ui.text(("hop dv %.2f (expected %.2f)"):format(probe.force.measuredDv, probe.force.expectedDv)) end
end
