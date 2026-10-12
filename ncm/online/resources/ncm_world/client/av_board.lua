-- ncm_world / client / av_board -- the Enter prompt the game's AVs never had (owner, 2026-10-12: "same button as
-- entering a car"). The server says when you stand at an AV or sit in one (`ncm:av.near`); F -- the vanilla enter key,
-- pad A -- boards it, and F again gets you out. Seating goes through OPEN//77 (server/av_board.lua).
local KEYS = { "F", "padA" }
local HINT_MS = 1500           -- the hint is re-shown every second while it applies, so it simply lapses when you leave

local state = nil              -- { vehicleId, seated, name } or nil
RegisterNetEvent("ncm:av.near", function(s)
    state = (type(s) == "table" and s.vehicleId) and s or nil
end)

local function call(resource, name, ...)
    local promise = Open77.exports.call(resource, name, ...)
    if not promise then return nil end
    return promise:await()
end

local function hint(s)
    pcall(call, "open77_notifications", "show", {
        id = "ncm_av_board", replace = true, type = "info", icon = "NCM",
        title = s.name or "AV",
        message = s.seated and "[F] Exit" or "[F] Enter",
        position = "middle_left", durationMs = HINT_MS, color = "#22D8E2",
    })
end

CreateThread(function()
    local wasDown, hintAt = true, 0
    while true do
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
            local now = GetGameTimer()
            if now - hintAt >= 1000 then hintAt = now; hint(state) end
            Wait(30)
        end
    end
end)
