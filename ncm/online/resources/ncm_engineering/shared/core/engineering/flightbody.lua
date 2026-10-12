-- ncm-core module: engineering.flightbody
--
-- IDEA (aerospace racing brief, 2026-10-07): THE MACHINE, NOT THE FILENAME. Every Machine flies as the body it is: its mass,
-- its dimensions, its drag area and lift, its skin. `engineering.flightmodel.CHASSIS` knew one car (the Hella) and flew
-- everything else as a 1.7 t Hella; this module derives the same chassis description from the Machine Passport
-- (`machine.passport`), so a Formula car, a motorcycle and a Hella carrying the same propulsion are different machines
-- because they ARE different: the same thrust on less mass is more acceleration (F = m a), a bigger drag area costs more
-- in the air, a smaller nose heats faster on the way down. There is no per-vehicle speed or space bonus anywhere, and
-- there must never be one.
--
-- Every value carries provenance, the passport's rule (`{ v, src, conf }`), strongest wins:
--   measured   a host observed it (a Carrier mass, a coast-down), or `flightmodel.CHASSIS` (the Hella's flown body)
--   host_data  the host's own data (an AC spec weight)
--   authored   NCM's machine seeds (mass, length, body family)
--   inferred   a body-family PRIOR below, for whatever nobody measured or authored
-- A passport may carry `aero.cd`, `aero.areaM2`, `aero.cl`, `morphology.widthM`, `morphology.heightM` at any confidence;
-- when it does, they win over the prior. The priors are what the family typically IS (a sedan's Cd is ~0.3, an open-wheel
-- car's drag area ~1.3 m^2 with real downforce, a motorcycle with its rider ~0.55 m^2) -- shape, never a performance grant.
--
-- The driver is mass too: every Machine carries one (`DRIVER_KG`), so a 260 kg motorcycle flies at 340 kg.
local Core = NcmCore

Core.define("engineering.flightbody", function(C)
    local M = { version = "0.1.0" }
    local P = C.get("machine.passport")
    local FM = C.get("engineering.flightmodel")

    M.DRIVER_KG = 80
    M.REF_LENGTH_M, M.REF_HEIGHT_M = 4.6, 1.4      -- the body `engineering.installation.MOUNTS` was laid out on (the Hella)

    -- Body-family priors: width, height (m), drag coefficient on the frontal area, lift coefficient on the same area
    -- (negative = downforce), frontal fill (frontal area / width x height), centre of mass height as a share of height.
    M.PRIORS = {
        sedan       = { w = 1.85, h = 1.45, cd = 0.30, cl = 0.05,  fill = 0.84, comH = 0.36, len = 4.8 },
        hatch       = { w = 1.75, h = 1.45, cd = 0.32, cl = 0.05,  fill = 0.84, comH = 0.36, len = 4.1 },
        wagon       = { w = 1.85, h = 1.50, cd = 0.31, cl = 0.05,  fill = 0.84, comH = 0.37, len = 4.9 },
        coupe       = { w = 1.85, h = 1.30, cd = 0.31, cl = 0.0,   fill = 0.82, comH = 0.36, len = 4.6 },
        convertible = { w = 1.85, h = 1.30, cd = 0.34, cl = 0.05,  fill = 0.82, comH = 0.35, len = 4.6 },
        supercar    = { w = 2.00, h = 1.15, cd = 0.35, cl = -0.30, fill = 0.80, comH = 0.33, len = 4.6 },
        muscle      = { w = 1.90, h = 1.35, cd = 0.38, cl = 0.10,  fill = 0.84, comH = 0.37, len = 5.0 },
        suv         = { w = 1.95, h = 1.80, cd = 0.38, cl = 0.05,  fill = 0.86, comH = 0.40, len = 4.9 },
        pickup      = { w = 2.00, h = 1.85, cd = 0.45, cl = 0.05,  fill = 0.86, comH = 0.40, len = 5.6 },
        van         = { w = 2.00, h = 2.20, cd = 0.40, cl = 0.05,  fill = 0.90, comH = 0.42, len = 5.3 },
        microcar    = { w = 1.50, h = 1.50, cd = 0.35, cl = 0.05,  fill = 0.85, comH = 0.38, len = 2.8 },
        prototype   = { w = 2.00, h = 1.05, cd = 0.40, cl = -1.20, fill = 0.75, comH = 0.30, len = 4.7 },
        -- open wheels: drag area ~1.3 m^2, downforce area ~-4 m^2 (a high-downforce Formula car)
        formula     = { w = 2.00, h = 0.95, cd = 0.90, cl = -2.80, fill = 0.75, comH = 0.30, len = 5.6 },
        -- bike plus rider, tucked: drag area ~0.55 m^2
        bike        = { w = 0.80, h = 1.25, cd = 0.60, cl = 0.0,   fill = 0.90, comH = 0.45, len = 2.2 },
    }
    M.FALLBACK = "sedan"

    local function fld(v, src, conf) return { v = v, src = src, conf = conf } end
    local function pick(p, group, key)
        local _, f = P.get(p, group, key)
        if f and type(f.v) == "number" then return f end
        return nil
    end

    --- The flight body of a Machine from its passport. opts = { vehicleKey, massKg (measured, overrides), driverKg }.
    --- Returns the `engineering.flightmodel` chassis ({ massKg, com, bounds, cd, areaM2, cl, skin }) plus `prov`: per field
    --- { v, src, conf }, and `family`.
    function M.fromPassport(p, opts)
        opts = opts or {}
        local fam = (P.get(p, "morphology", "body")) or (P.get(p, "morphology", "kind"))
        if fam == "car" or not M.PRIORS[fam or ""] then fam = (P.get(p, "morphology", "kind") == "bike") and "bike" or nil end
        local famSrc = fam and "passport" or "fallback"
        fam = fam or M.FALLBACK
        local pr = M.PRIORS[fam]
        local prov = { family = fld(fam, famSrc == "passport" and "authored" or "inferred", famSrc == "passport" and 0.75 or 0.2) }

        -- MASS: measured beats the flown chassis beats the passport's (loaded, then bare) beats nothing
        local known = opts.vehicleKey and FM.CHASSIS[opts.vehicleKey]
        local m = opts.massKg and fld(opts.massKg, "measured", 0.95)
            or (known and fld(known.massKg, "measured", 0.9))
            or pick(p, "performance", "massLoadedKg") or pick(p, "performance", "massKg")
            or fld(1500, "inferred", 0.1)
        prov.massKg = m
        local L = pick(p, "morphology", "lengthM") or fld(pr.len, "inferred", 0.4)
        local W = pick(p, "morphology", "widthM") or fld(pr.w, "inferred", 0.4)
        local H = pick(p, "morphology", "heightM") or fld(pr.h, "inferred", 0.4)
        prov.lengthM, prov.widthM, prov.heightM = L, W, H
        prov.cd = pick(p, "aero", "cd") or fld(pr.cd, "inferred", 0.4)
        prov.cl = pick(p, "aero", "cl") or fld(pr.cl, "inferred", 0.3)
        prov.areaM2 = pick(p, "aero", "areaM2") or fld(pr.fill * W.v * H.v, "inferred", 0.4)

        local driver = opts.driverKg or M.DRIVER_KG
        local body = {
            massKg = m.v + driver,
            com = { 0, 0, pr.comH * H.v },
            bounds = { W.v, L.v, H.v },
            cd = prov.cd.v, cl = prov.cl.v, areaM2 = prov.areaM2.v,
            family = fam, lengthM = L.v, heightM = H.v,
            prov = prov,
        }
        body.skin = M.skin(body.bounds, prov.areaM2.v)
        return body
    end

    --- The skin a body heats and cools through: its wetted area (a box's surface, lightly rounded), the frontal area the
    --- airflow strikes, and a nose radius (half the smaller frontal dimension). Physical, from the bounds alone.
    function M.skin(bounds, frontalM2)
        local w, l, h = bounds[1], bounds[2], bounds[3]
        return {
            wettedM2 = 0.8 * 2 * (w * l + w * h + l * h),
            frontalM2 = frontalM2 or 0.84 * w * h,
            noseRadiusM = math.max(0.15, 0.5 * math.min(w, h)),
            emissivity = 0.8,
        }
    end

    --- The flight body for a catalogue key (seeded passport, or an inference), the convenience every caller wants.
    function M.forKey(vehicleKey, live)
        return M.fromPassport(P.forMachine(vehicleKey, nil, live), { vehicleKey = vehicleKey, massKg = live and live.massKg })
    end

    --- Re-site installed devices on this body. `engineering.installation.MOUNTS` are laid out on a 4.6 m, 1.4 m car; a
    --- 2.2 m motorcycle's rear hardpoint is not 2.2 m behind its centre. Lengthwise and vertical positions scale with the
    --- body; lateral ones do not (hardpoints sit on the centreline). Returns new device tables; the input is untouched.
    function M.siteDevices(devices, body)
        local ky = (body.lengthM or M.REF_LENGTH_M) / M.REF_LENGTH_M
        local kz = (body.heightM or M.REF_HEIGHT_M) / M.REF_HEIGHT_M
        local out = {}
        for i, d in ipairs(devices or {}) do
            local c = {}
            for k, v in pairs(d) do c[k] = v end
            if d.pos then c.pos = { d.pos[1], d.pos[2] * ky, d.pos[3] * kz } end
            out[i] = c
        end
        return out
    end

    --- One line for logs and the panel: what this body is and how sure NCM is.
    function M.summary(b)
        local pv = b.prov or {}
        local function s(k, fmt) local f = pv[k]; return f and (fmt:format(f.v) .. " " .. f.src) or "?" end
        return ("%s %s +%dkg driver | %s x %s x %s | Cd %s A %s Cl %s"):format(tostring(b.family), s("massKg", "%.0fkg"),
            M.DRIVER_KG, s("lengthM", "%.2f"), s("widthM", "%.2f"), s("heightM", "%.2f"), s("cd", "%.2f"), s("areaM2", "%.2fm2"), s("cl", "%.2f"))
    end

    return M
end)
