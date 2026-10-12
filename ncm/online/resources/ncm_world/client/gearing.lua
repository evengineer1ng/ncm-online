-- ncm_world / client / gearing -- stacked gearboxes on the Machine you are driving (owner, 2026-10-08).
--
-- client/engineering.lua hands over the Machine's installed DRIVELINE boxes (NcmClientGearingApply); core
-- `engineering.gearing` composes them into paths (the car's box + inline boxes in series; each side box its own path)
-- and this file relays that, through the Carrier (owner: "relay through carrier"), to NCM Gearbox, which drives it.
--
--   * the paths travel as one line of text (`engineering.gearing.encode`), re-sent every second while bound, so a
--     Gearbox that stops hearing it (left the Machine, Carrier gone) falls back to the car's own box by itself;
--   * a bound control on a side box's `engage` command asks for that path. NCM Gearbox decides -- it knows the speed and
--     the gear, so it owns the `when` rule and the toggle back to the car's box -- this side only counts presses.
-- Nothing here is a hard-wired button: a box answers whatever control its owner bound in the Parts panel.
local Core = NcmCore
local Gearing = Core.get("engineering.gearing")
local Controls = Core.get("engineering.controls")

local function log(fmt, ...) print(("[ncm_world/client/gearing] " .. fmt):format(...)) end

local HEARTBEAT_MS = 1000
local G = nil          -- { assetId, devices, bindings, controls, ctl, text, pathOf, selectSeq, request, lastSend, sentClear }

local function ms() return GetGameTimer() end

local function send(force)
    if not (G and NcmClientMachineGearing) then return end
    local t = ms()
    if not force and t - (G.lastSend or 0) < HEARTBEAT_MS then return end
    if G.text == "" and G.sentClear then return end
    local ok = NcmClientMachineGearing({ v = 1, assetId = G.assetId, text = G.text, selectSeq = G.selectSeq, path = G.request })
    if ok then
        G.lastSend = t
        if G.text == "" then G.sentClear = true end
    end
end

function NcmClientGearingApply(assetId, driveline, bindings)
    local composed = Gearing.compose(driveline)
    local text = Gearing.encode(composed)
    local mine = {}
    local ids = {}
    for _, d in ipairs(driveline) do ids[d.componentId] = true end
    for _, b in ipairs(bindings or {}) do if ids[b.componentId] and b.command == "engage" then mine[#mine + 1] = b end end
    local same = G and G.assetId == assetId
    G = {
        assetId = assetId, devices = driveline, bindings = mine, controls = Controls.controls(mine), ctl = Controls.newState(),
        text = text, pathOf = composed.pathOf, selectSeq = same and G.selectSeq or 0, request = same and G.request or 0,
        lastSend = 0, sentClear = false,
    }
    local b = {}
    for _, x in ipairs(mine) do b[#b + 1] = ("%s:%s->..%s"):format(x.control, x.gesture, tostring(x.componentId):sub(-6)) end
    for _, r in ipairs(composed.refused) do log("box ..%s refused: %s", tostring(r.componentId):sub(-6), r.reason) end
    if text ~= "" then
        log("Machine ..%s driveline: %s | engage controls %s", tostring(assetId):sub(-6), composed.summary, #b > 0 and table.concat(b, ", ") or "none")
    end
    send(true)
end

local function bound()
    if not NcmClientEngineering then return nil end
    local aid = NcmClientEngineering.bound()
    return aid
end

local function down(control)
    local okC, captured = pcall(Open77.input.isCaptured)
    if okC and captured == true then return false end    -- typing in chat or a menu is not driving
    local ok, d = pcall(Open77.input.isDown, control)
    return ok and d == true
end

CreateThread(function()
    Wait(10000)
    while true do
        if not G then
            Wait(500)
        else
            if bound() ~= G.assetId then
                -- off this Machine: tell the Gearbox once (it would fall back by itself within seconds anyway)
                G.text, G.sentClear = "", false
                send(true)
                G = nil
            else
                if #G.bindings > 0 then
                    local pressed = {}
                    for _, c in ipairs(G.controls) do pressed[c] = down(c) end
                    local _, events = Controls.step(G.ctl, G.bindings, G.devices, pressed, ms())
                    for _, e in ipairs(events) do
                        local path = G.pathOf[e.componentId]
                        if e.command == "engage" and path then
                            G.selectSeq = G.selectSeq + 1
                            G.request = path - 1
                            log("engage ..%s -> path %d (request %d)", tostring(e.componentId):sub(-6), path - 1, G.selectSeq)
                            send(true)
                        end
                    end
                end
                send(false)
            end
            Wait(#(G and G.bindings or {}) > 0 and 0 or 250)
        end
    end
end)
