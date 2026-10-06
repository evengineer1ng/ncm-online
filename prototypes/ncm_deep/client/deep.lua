-- ncm_deep / client: open the WebGL space surface on `/ncm.deep`, relay its reports, close it after 20 s.
-- KB-61: nothing here takes focus, and closing never depends on the page being healthy.
local function log(fmt, ...) print(("[ncm_deep/client] " .. fmt):format(...)) end

local page, openedAt = nil, 0
local OPEN_MS = 20000

local function close(why)
    if page then
        pcall(function() page:hide() end)
        pcall(function() page:destroy() end)
        page = nil
        log("closed (%s)", why)
    end
end

RegisterCommand("ncm.deep", function()
    if page then close("toggled"); return end
    local ok, p, why = pcall(Open77.webui.create, { entry = "web/index.html", layer = "hud", zIndex = 900,
        transparent = false, visible = true, fps = 60 })
    if not ok or not p then
        log("webui.create failed: %s %s", tostring(p), tostring(why))
        TriggerServerEvent("ncm:deep.report", { phase = "create_failed", note = tostring(p) .. " " .. tostring(why) })
        return
    end
    page, openedAt = p, GetGameTimer()
    page:on("deep:report", function(r)
        if type(r) == "table" then
            log("report %s webgl=%s renderer=%s fps=%s", tostring(r.phase), tostring(r.webgl), tostring(r.renderer), tostring(r.fps))
            TriggerServerEvent("ncm:deep.report", r)
        end
    end)
    log("opened")
    CreateThread(function()
        local mine = page
        Wait(OPEN_MS)
        if page == mine then close("20 s probe window") end
    end)
end, false)
