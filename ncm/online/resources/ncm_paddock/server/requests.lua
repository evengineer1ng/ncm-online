-- ncm_paddock / server / requests -- the net events the PADDOCK tab sends (via ncm_world/client/panel.lua).
--
--   ncm:paddock.request { view, ... }                    -> ncm:paddock.stream.begin/part (the view)
--   ncm:paddock.slip    { lineId, version, stake, idem }  -> ncm:paddock.result, then the board again
--   ncm:paddock.manager { action, args }                  -> ncm:paddock.result, then MY ORG again
-- Rate-limited per player so a held key cannot turn into a query storm.
PaddockRequests = {}

local U = PaddockUtil
local last = {}
local GAP_MS = 400

local function allowed(pid)
    local t = (Open77.time.unix() or 0) * 1000
    if last[pid] and t - last[pid] < GAP_MS then return false end
    last[pid] = t
    return true
end

local function enabled() return PaddockSettings.get("paddockEnabled", true) and PaddockWorld.ready end

local function result(pid, op, ok, text)
    TriggerClientEvent("ncm:paddock.result", pid, { op = op, ok = ok == true, text = tostring(text or "") })
end

RegisterNetEvent("ncm:paddock.request", function(req)
    local pid = tonumber(source) or 0
    if pid <= 0 or not allowed(pid) then return end
    if not enabled() then
        TriggerClientEvent("ncm:paddock.stream.begin", pid, { id = "off", head = { view = type(req) == "table" and req.view or "wire",
            error = PaddockSettings.get("paddockEnabled", true) and "warming_up" or "disabled" }, parts = 0, count = 0 })
        return
    end
    CreateThread(function() PaddockViews.send(pid, req) end)
end)

local SLIP_REASONS = {
    not_introduced = "Billie doesn't know you. Somebody has to put you in touch.",
    refused = PaddockBillie and PaddockBillie.REFUSAL or "Not that one.",
    own_series = "You manage a team in that series. Billie won't write you paper on it.",
    closed = "The board closed on that race.",
    price_moved = "The price moved. Look again.",
    over_slip_cap = "Too rich for one slip.",
    over_daily_cap = "That's your limit for today.",
    over_max_payout = "Billie won't carry that much on one slip.",
    insufficient_funds = "Not enough eddies.",
    invalid_stake = "Name a real number.",
}

RegisterNetEvent("ncm:paddock.slip", function(req)
    local pid = tonumber(source) or 0
    if pid <= 0 or not allowed(pid) or not enabled() or type(req) ~= "table" then return end
    CreateThread(function()
        local ok, res = PaddockBillie.place(pid, req)
        if ok then
            result(pid, "slip", true, ("Paper written: %d at %.2f, returns %d."):format(res.stake or 0, res.price or 0, res.returns or 0))
        else
            result(pid, "slip", false, SLIP_REASONS[res] or ("Billie says no: " .. tostring(res)))
        end
        PaddockViews.send(pid, { view = "board" })
    end)
end)

local MANAGER_REASONS = {
    one_team_rule = "You already hold a team role. One team at a time.", cooldown = "Your last team folded. Wait out the season.",
    name_too_short = "The name is too short.", name_too_long = "The name is too long.", name_characters = "Letters, numbers and simple punctuation only.",
    name_taken = "That name is taken.", insufficient_funds = "Not enough eddies.", not_a_manager = "You don't run a team.",
    roster_full = "The roster is full.", under_contract = "That driver is under contract and happy where they are.",
    cannot_afford = "The treasury can't cover it.", over_weekly_cap = "That's past this week's withdrawal limit.",
    too_many_pending = "Six moves are already waiting for the Cup boundary.",
}

RegisterNetEvent("ncm:paddock.manager", function(req)
    local pid = tonumber(source) or 0
    if pid <= 0 or not allowed(pid) or not enabled() or type(req) ~= "table" then return end
    CreateThread(function()
        local ok, res = PaddockManager.act(pid, tostring(req.action or ""), type(req.args) == "table" and req.args or {})
        if ok then
            result(pid, "manager", true, type(res) == "string" and res or (type(res) == "table" and res.name and ("Welcome to " .. res.name) or "Done."))
        else
            result(pid, "manager", false, MANAGER_REASONS[res] or tostring(res))
        end
        PaddockViews.send(pid, { view = "myorg" })
    end)
end)

AddEventHandler("onPlayerDisconnected", function(playerId) last[tonumber(playerId) or 0] = nil end)
