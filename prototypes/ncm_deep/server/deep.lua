-- ncm_deep / server: write the client's WebGL report where the coder can read it (the dev server log).
local function log(fmt, ...) print(("[ncm_deep] " .. fmt):format(...)) end

RegisterNetEvent("ncm:deep.report", function(r)
    local pid = tonumber(source) or 0
    if type(r) ~= "table" then return end
    log("player=%d phase=%s webgl=%s version=%s renderer=%s vendor=%s | fps=%s frames=%s | canvas %sx%s dpr %s | %s",
        pid, tostring(r.phase), tostring(r.webgl), tostring(r.version), tostring(r.renderer), tostring(r.vendor),
        tostring(r.fps), tostring(r.frames), tostring(r.w), tostring(r.h), tostring(r.dpr), tostring(r.note or ""))
end)

AddEventHandler("onResourceStart", function(name)
    if name == "ncm_deep" then log("probe 0 ready: /ncm.deep opens the WebGL space surface for 20 s") end
end)
