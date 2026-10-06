-- ncm_observer / client / panel -- the Observer's controls (owner, 2026-10-04: "think iRacing simulator replay UI ...
-- the ability to select what camera type, what onboard, what race ... turning your current client into observer needs
-- some UX, not just console commands").
--
--   F3            the panel: RACES NOW (click to see its order; click again to watch its leader), RUNNING ORDER (click a
--                 driver to watch), CAMERA (eight shots), DIRECTOR / BATTLE / LEADER / CLEAN HUD, ENTER / EXIT OBSERVER
--   the strip     while observing with the panel closed: who, where, which shot, the keys
--   hotkeys       while observing: 1-8 camera, PgUp/PgDn previous/next car, Home leader, B battle, N director, H clean.
--                 Rebindable (Settings -> KEY BINDINGS); a mapped key never fires while the panel holds the keyboard, so
--                 the page answers the same keys itself.
--
-- The panel is built from what this client already receives -- the racer snapshot (`ncm:paddock:racers`) and the lens's
-- own state (`NcmObs`, client/observer.lua) -- so nothing new crosses the network.
--
-- KB-61 (a focused page that died took the player's input with it): focus FOLLOWS the page's confirmation that it drew
-- (`obs:drawn`), a watchdog closes the panel if that never comes, and while it is open a physical read of Esc / F3
-- closes it from Lua, whatever state the page is in.
local D = NcmCore.get("observer.director")
local function log(fmt, ...) print(("[ncm_observer/panel] " .. fmt):format(...)) end

local page, ready = nil, false
local open, focused = false, false
local selected = nil                  -- the race the panel is showing (defaults to the one being watched)
local openToken = 0
local lastPushKey = nil
local FOCUS_CONFIRM_MS = 2500

local TIER_RANK = { premier = 1, pro = 2, regional = 3, street = 4 }

local function focus(on)
    if not page then return end
    local ok, r, why = pcall(function() return page:setFocus(on, on) end)
    if not ok then log("setFocus failed: %s", tostring(r))
    elseif r == false then log("setFocus refused: %s", tostring(why)) end
    focused = on and ok and r ~= false
end

-- ------------------------------------------------------------------------------------------------- the state

local function races(snap)
    local out = {}
    for _, race in ipairs((snap and snap.races) or {}) do
        out[#out + 1] = { r = race.r, series = race.series or race.r, tier = race.tier or "street", n = #(race.cars or {}) }
    end
    table.sort(out, function(a, b)
        local ra, rb = TIER_RANK[a.tier] or 9, TIER_RANK[b.tier] or 9
        if ra ~= rb then return ra < rb end
        return tostring(a.series) < tostring(b.series)
    end)
    return out
end

local function fieldOf(snap, raceId)
    local race = raceId and D.findRace(snap, raceId)
    local out = {}
    for _, c in ipairs((race and race.cars) or {}) do
        out[#out + 1] = { k = c.k, n = c.n, p = c.p, g = c.g, live = c.v ~= nil or nil, h = c.h }
    end
    table.sort(out, function(a, b) return (a.p or 999) < (b.p or 999) end)
    while #out > 30 do out[#out] = nil end
    return out
end

local function targetView(snap)
    local t = NcmObs.target and NcmObs.target()
    if not t then return nil end
    local car, race = nil, nil
    if snap then car, race = D.findCar(snap, t.raceId, t.key) end
    return { raceId = t.raceId, key = t.key, name = (car and car.n) or t.name, p = car and car.p or nil,
        series = race and race.series or nil, live = car and car.v ~= nil or nil }
end

local function push(force)
    if not (page and ready) then return end
    local on = NcmObs.isOn and NcmObs.isOn() or false
    if not on and not open then
        if lastPushKey ~= "off" then lastPushKey = "off"; pcall(function() page:send("obs:state", { on = false, open = false }) end) end
        return
    end
    local snap = NcmObs.snapshot and NcmObs.snapshot() or nil
    local list = races(snap)
    local t = targetView(snap)
    if not selected or not (snap and D.findRace(snap, selected)) then selected = (t and t.raceId) or (list[1] and list[1].r) or nil end
    local tgt = NcmObs.target and NcmObs.target()
    local state = { on = on, open = open, mode = NcmObs.mode(), auto = tgt and tgt.auto or false, clean = NcmObs.isClean(),
        target = t, races = list, selected = selected, field = open and fieldOf(snap, selected) or {} }
    -- the strip changes rarely; the panel redraws on every snapshot while it is open
    local key = table.concat({ tostring(on), tostring(open), tostring(state.mode), tostring(state.auto), tostring(state.clean),
        t and (t.key .. ":" .. tostring(t.p) .. ":" .. tostring(t.live)) or "-", tostring(selected), tostring(#list) }, "|")
    if not force and not open and key == lastPushKey then return end
    lastPushKey = key
    pcall(function() page:send("obs:state", state) end)
end

NcmObs.onChange = function() push(false) end
NcmObs.toast = function(text)
    if not (page and ready) then return false end
    local on = NcmObs.isOn and NcmObs.isOn() or false
    if not (on or open) then return false end
    return (pcall(function() page:send("obs:toast", { text = text }) end))
end

-- ------------------------------------------------------------------------------------------------- open / close

local function close(why)
    if not open then return end
    open = false
    openToken = openToken + 1
    focus(false)
    log("panel closed (%s)", tostring(why))
    push(true)
end

local function openPanel()
    if open or not (page and ready) then
        if not ready then log("panel not ready yet") end
        return
    end
    open = true
    openToken = openToken + 1
    local token = openToken
    push(true)
    -- KB-61: no confirmation, no focus
    CreateThread(function()
        Wait(FOCUS_CONFIRM_MS)
        if token == openToken and open and not focused then
            log("panel did not draw in %d ms -- closing, input released", FOCUS_CONFIRM_MS)
            close("did not draw")
        end
    end)
    -- the escape hatch that does not depend on the page: physical Esc / F3
    CreateThread(function()
        local held = { escape = true, f3 = true }       -- ignore the press that opened it
        while open and token == openToken do
            for _, k in ipairs({ "ESCAPE", "F3" }) do
                local ok, down = pcall(Open77.input.isDown, k)
                local key = k:lower()
                if ok and down == true then
                    if not held[key] then close("key " .. k); return end
                else
                    held[key] = false
                end
            end
            Wait(50)
        end
    end)
end

local function toggle() if open then close("F3") else openPanel() end end

-- ------------------------------------------------------------------------------------------------- actions

local function current()
    local snap = NcmObs.snapshot and NcmObs.snapshot() or nil
    local t = NcmObs.target and NcmObs.target()
    return snap, t
end

--- The car `step` places away from the one being watched (+1 = the car behind, -1 = the car ahead), wrapping.
local function stepCar(step)
    local snap, t = current()
    if not snap then return end
    local raceId = (t and t.raceId) or selected
    local race = raceId and D.findRace(snap, raceId)
    if not race or #(race.cars or {}) == 0 then return end
    local cars = {}
    for _, c in ipairs(race.cars) do cars[#cars + 1] = c end
    table.sort(cars, function(a, b) return (a.p or 999) < (b.p or 999) end)
    local at = 0
    for i, c in ipairs(cars) do if t and tostring(c.k) == tostring(t.key) then at = i end end
    local nextI = ((at - 1 + step) % #cars) + 1
    if at == 0 then nextI = 1 end
    NcmObs.watch(("car %s %s"):format(race.r, cars[nextI].k))
end

local function act(a)
    local on = NcmObs.isOn()
    if a == "enter" then NcmObs.enter(); return end
    if not on then return end
    if a == "exit" then NcmObs.exit()
    elseif a == "auto" then
        local t = NcmObs.target()
        if t and t.auto then NcmObs.watch(("car %s %s"):format(t.raceId, t.key))   -- hold this car: director off
        else NcmObs.watch("auto") end
    elseif a == "battle" then NcmObs.watch("battle")
    elseif a == "leader" then NcmObs.watch("leader")
    elseif a == "clean" then NcmObs.toggleClean()
    elseif a == "next" then stepCar(1)
    elseif a == "prev" then stepCar(-1) end
end

-- ------------------------------------------------------------------------------------------------- the page

local function bringUp()
    if page then return end
    local p, why = WebUI.create({ entry = "web/observer.html", layer = "menu", width = 1920, height = 1080,
        fps = 30, zIndex = 880, transparent = true, visible = true })
    if not p then log("WebUI failed: %s", tostring(why)); return end
    page = p
    page:on("obs:ready", function() ready = true; log("panel ready"); push(true) end)
    page:on("obs:drawn", function()
        if open and not focused then focus(true) end
    end)
    page:on("obs:close", function() close("page") end)
    page:on("obs:select", function(m)
        if type(m) == "table" and m.raceId then selected = tostring(m.raceId); push(true) end
    end)
    page:on("obs:watch", function(m)
        if type(m) == "table" and type(m.text) == "string" then
            if not NcmObs.isOn() then NcmObs.toast("Enter Observer first."); return end
            NcmObs.watch(m.text)
        end
    end)
    page:on("obs:cam", function(m) if type(m) == "table" and NcmObs.isOn() then NcmObs.setMode(tostring(m.mode)) end end)
    page:on("obs:act", function(m) if type(m) == "table" then act(tostring(m.act)) end end)
end

CreateThread(function()
    Wait(3000)
    bringUp()
end)

-- ------------------------------------------------------------------------------------------------- keys

local function map(id, name, key, fn)
    local ok, installed, eff = pcall(RegisterKeyMapping, id, name, key, function() pcall(fn) end)
    if not (ok and installed ~= false) then log("key %s (%s) refused: %s", id, key, tostring(ok and eff or installed)) end
end

map("ncm.observer.panel", "NCM Observer: panel", "F3", toggle)
for i, m in ipairs(D.MODES) do
    map("ncm.observer.cam" .. i, "NCM Observer: camera " .. m, tostring(i), function()
        if NcmObs.isOn() and NcmObs.setMode(m) then NcmObs.toast("Camera: " .. m:upper()) end
    end)
end
map("ncm.observer.next", "NCM Observer: next car", "PAGEDOWN", function() if NcmObs.isOn() then stepCar(1) end end)
map("ncm.observer.prev", "NCM Observer: previous car", "PAGEUP", function() if NcmObs.isOn() then stepCar(-1) end end)
map("ncm.observer.leader", "NCM Observer: leader", "HOME", function() act("leader") end)
map("ncm.observer.battle", "NCM Observer: closest battle", "B", function() act("battle") end)
map("ncm.observer.director", "NCM Observer: director on/off", "N", function() act("auto") end)
map("ncm.observer.clean", "NCM Observer: clean HUD", "H", function() act("clean") end)

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_observer" then return end
    if focused then focus(false) end
    if page then pcall(function() page:destroy() end) end
end)
