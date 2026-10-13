-- ncm_world / client / av_board -- the Enter prompt the game's AVs never had (owner, 2026-10-12: "same button as
-- entering a car"). The server says when you stand at an AV or sit in one (`ncm:av.near`); F / pad X (Square on a DS4)
-- -- the game's own enter key -- boards it, and again gets you out (was pad A = Cross, not the game's enter, 2026-10-13). Seating goes through OPEN//77 (server/av_board.lua).
local KEYS = { "F", "padX" }

local state = nil              -- { vehicleId, seated, name } or nil
RegisterNetEvent("ncm:av.near", function(s)
    state = (type(s) == "table" and s.vehicleId) and s or nil
end)

local function call(resource, name, ...)
    local promise = Open77.exports.call(resource, name, ...)
    if not promise then return nil end
    return promise:await()
end

-- One persistent hint, shown when the state changes and dismissed when you walk away (2026-10-12: re-showing it every
-- second made the toast animate in forever).
local hintHandle, hintKey = nil, nil
local function hint(s)
    local key = s and ((s.seated and "s" or "n") .. tostring(s.vehicleId)) or nil
    if key == hintKey then return end
    hintKey = key
    if not s then
        if hintHandle then pcall(call, "open77_notifications", "dismiss", hintHandle) end
        hintHandle = nil
        return
    end
    local ok, res = pcall(call, "open77_notifications", "show", {
        id = "ncm_av_board", replace = true, type = "info", icon = "NCM",
        title = s.name or "AV",
        message = s.seated and "[F] Exit" or "[F] Enter",
        position = "middle_left", durationMs = 0, color = "#22D8E2",
    })
    if ok and type(res) == "table" and res.handle then hintHandle = res.handle end
end

CreateThread(function()
    local wasDown = true
    while true do
        hint(state)
        if not state then
            wasDown = true          -- a key held while walking up does not count as a press
            Wait(200)
        else
            local captured = false
            pcall(function() captured = Open77.input.isCaptured() == true end)
            local down = false
            if not captured then
                for _, k in ipairs(KEYS) do
                    local ok, d = pcall(Open77.input.isDown, k)
                    if ok and d == true then down = true end
                end
            end
            if down and not wasDown and not NcmClientBuildActive then
                TriggerServerEvent(state.seated and "ncm:av.leave" or "ncm:av.board")
            end
            wasDown = down
            Wait(30)
        end
    end
end)
