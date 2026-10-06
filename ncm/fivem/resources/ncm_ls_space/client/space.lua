-- ncm_ls_space / client / space: what you see while Snowglobe owns you (L319/L320; doc 53). Client-local only.
--
-- Keyed to the FRAME (client/frame.lua), not to a car: on foot in Snowglobe you still see space.
--   * night, clear, no clouds, empty roads -- the view, not the server's weather
--   * Earth, Moon and Sun stand-ins: `space.universe.proxy` gives each body's true direction and angular size from the
--     camera's UNIVERSE position (frame u + the camera's offset from the body); a sphere marker `drawAt` metres away
--     with radius R * drawAt / d. Earth is the compressed Snowglobe Earth (`earthRadius`). No asset.
local Core = NcmCore
local U = Core.get("space.universe")
local V = U.vec
local C = NcmLsConfig

local frame = U.anchorFrame(C.anchor)
local spaceView = false

local function setSpaceView(on)
    if on == spaceView then return end
    spaceView = on
    if on then
        NetworkOverrideClockTime(0, 0, 0)
        SetOverrideWeather("EXTRASUNNY")
        SetWeatherTypeNowPersist("EXTRASUNNY")
        ClearCloudHat()
    else
        NetworkClearClockTimeOverride()
        ClearOverrideWeather()
        ClearWeatherTypePersist()
    end
end

local BODY_STYLE = {
    { id = "earth", drawAt = 1500.0, r = 40, g = 90, b = 200, a = 255 },
    { id = "moon", drawAt = 1500.0, r = 190, g = 190, b = 185, a = 255 },
    { id = "sun", drawAt = 1500.0, r = 255, g = 240, b = 200, a = 255 },
}

CreateThread(function()
    while true do
        local F = NcmLsFrame
        if not (F and F.active and F.u) then
            setSpaceView(false)
            Wait(200)
        else
            Wait(0)
            setSpaceView(true)
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetPedDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            local body = GetEntityCoords(veh ~= 0 and veh or ped)
            local cam = GetFinalRenderedCamCoord()
            local eye = V.add(F.u, U.localToEarth(frame, { cam.x - body.x, cam.y - body.y, cam.z - body.z }))
            for _, style in ipairs(BODY_STYLE) do
                local p = U.proxy(U.BODIES[style.id], eye, style.drawAt, frame)
                local rad = math.max(p.radius, 2.0)
                DrawMarker(28, cam.x + p.dir[1] * style.drawAt, cam.y + p.dir[2] * style.drawAt, cam.z + p.dir[3] * style.drawAt,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, rad, rad, rad, style.r, style.g, style.b, style.a, false, false, 2, false, nil, nil, false)
            end
        end
    end
end)
