-- ncm-core module: engineering.loadout
--
-- A Machine fitted for a discipline, from any catalogue key (aerospace racing brief, 2026-10-07). An NPC Formula car
-- needs what the owner's Hella has to race through Deep -- a drive, its propellant, and something that can turn it --
-- and it needs them on ITS body: the same `engineering.installation` designs and hardpoints, re-sited on the Machine's
-- own length and height (`engineering.flightbody.siteDevices`), assembled on the Machine's own passport body. The loadout
-- names parts; it never names a performance. Two Machines with the same loadout differ only by what they physically are.
local Core = NcmCore

Core.define("engineering.loadout", function(C)
    local M = { version = "0.1.0" }
    local Inst = C.get("engineering.installation")
    local FM = C.get("engineering.flightmodel")
    local FB = C.get("engineering.flightbody")

    --- Named fits (installation items). DEEP_RACER is the owner's L334 Hella fit: the FD-1 at the rear facing aft, the
    --- PT-400 tank at the front, the AC-6 on the roof.
    M.FITS = {
        deep_racer = {
            { componentId = "fd1", designId = "eng:zetatech:fd1:r1", mountId = "mount.rear", facing = "aft" },
            { componentId = "pt", designId = "eng:zetatech:pt500:r1", mountId = "mount.front", facing = "fore" },
            { componentId = "ac6", designId = "eng:zetatech:ac6:r1", mountId = "mount.roof", facing = "up" },
        },
        -- the pre-L334 fit: RP-16 + IA-10 (Night City hop and push), no attitude
        city_hop = {
            { componentId = "rp", designId = "eng:zetatech:rp16:r1", mountId = "mount.rear", facing = "aft" },
            { componentId = "ia", designId = "eng:archer:ia10:r1", mountId = "mount.underside", facing = "down" },
        },
    }

    --- A fitted Machine. opts = { fit = name | items, fuelKg = 40 (the car's own tank, for the AC-6), live = passport live
    --- facts (a measured mass ...), fusionKg = fill of the propellant tank part (default full) }.
    --- Returns { model, body, devices, refused }.
    function M.build(vehicleKey, opts)
        opts = opts or {}
        local items = type(opts.fit) == "table" and opts.fit or M.FITS[opts.fit or "deep_racer"]
        assert(items, "no such fit: " .. tostring(opts.fit))
        local copy = {}
        for i, it in ipairs(items) do
            copy[i] = { componentId = it.componentId, designId = it.designId, mountId = it.mountId, facing = it.facing, fillKg = it.fillKg }
            if opts.fusionKg and it.designId == "eng:zetatech:pt500:r1" then copy[i].fillKg = opts.fusionKg end
        end
        local body = FB.forKey(vehicleKey, opts.live)
        local devices, refused = Inst.resolve(copy, vehicleKey)
        local sited = FB.siteDevices(devices, body)
        local fuel = opts.fuelKg or 40
        local model = FM.build(sited, { vehicleKey = vehicleKey, fuelKg = fuel, tankKg = fuel, body = body })
        return { model = model, body = body, devices = sited, refused = refused }
    end

    return M
end)
