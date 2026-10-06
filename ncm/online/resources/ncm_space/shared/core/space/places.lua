-- ncm-core module: space.places
--
-- L329 (owner, "NCM 3.0 - one universe", item 5): where a host's location is on NCM Earth, resolved GENERICALLY so that
-- adding a track means NCM learning where it is -- never custom code per track, never an invented coordinate.
--
-- Sources, strongest first:
--   verified  -- `space.venues`, authored from the real circuit (17 today).
--   csp       -- Custom Shaders Patch's own `ac.getTrackCoordinatesDeg()`, reported by the AC adapter when a track loads.
--   geotag    -- numeric `geotags` in the track's ui_track.json (mods often carry real ones).
--   override  -- a manifest entry (`ncm/assetto/places_override.json`): the later community / user correction path.
--   unresolved -- nothing trustworthy: never offered as a destination. Kunos ships `["lat","lon"]` placeholders on
--                 every stock layout (all 45 here, 2026-10-06), and (0, 0) is "unknown", not the Gulf of Guinea.
-- A curated venue that a host reports more than MISMATCH_M away is flagged (the curated one still wins).
local Core = NcmCore

Core.define("space.places", function(C)
    local M = { version = "0.1.0", MISMATCH_M = 2000 }
    local VN = C.get("space.venues")
    local D = C.get("space.deep")

    local function num(x)
        if type(x) == "number" then return x end
        if type(x) ~= "string" then return nil end
        local v, hemi = x:match("^%s*([%-%+]?%d+%.?%d*)%s*([NnSsEeWw]?)%s*$")
        v = tonumber(v)
        if not v then return nil end
        if hemi == "S" or hemi == "s" or hemi == "W" or hemi == "w" then v = -math.abs(v) end
        return v
    end

    local function plausible(lat, lon)
        return lat and lon and lat >= -90 and lat <= 90 and lon >= -180 and lon <= 180 and not (math.abs(lat) < 1e-6 and math.abs(lon) < 1e-6)
    end

    --- ui_track.json `geotags` -> lat, lon, or nil + why. Accepts {"36.58 N","121.75 W"}, {"36.58","-121.75"}, numbers.
    function M.parseGeotags(tags)
        if type(tags) ~= "table" or #tags < 2 then return nil, "no geotags" end
        local lat, lon = num(tags[1]), num(tags[2])
        if not lat or not lon then return nil, "placeholder geotags" end
        if not plausible(lat, lon) then return nil, "implausible geotags" end
        return lat, lon
    end

    --- The curated venue for a host track/layout, if any.
    function M.curated(host, track)
        for _, v in ipairs(VN.VENUES) do
            if v.host == host and v.track == track then return v end
        end
        return nil
    end

    --- Resolve one host location. `obs` = { host, track, layout, csp = { lat, lon, tzS }, geotags, override = { lat, lon } }.
    --- Returns { id, host, track, layout, lat, lon, alt, tz, status, provenance, flags }.
    function M.resolve(obs)
        local host, track, layout = obs.host or "assetto_corsa", obs.track, obs.layout or ""
        local rec = { host = host, track = track, layout = layout, flags = {} }
        local v = M.curated(host, track)
        local cspLat, cspLon = obs.csp and tonumber(obs.csp.lat), obs.csp and tonumber(obs.csp.lon)
        local cspOk = plausible(cspLat, cspLon)
        if v then
            rec.id, rec.name, rec.lat, rec.lon, rec.alt, rec.tz = v.id, v.name, v.lat, v.lon, v.alt or 0, v.tz
            rec.status, rec.provenance = "verified", "space.venues (authored)"
            if cspOk then
                local d = D.distance(v.lat, v.lon, cspLat, cspLon)
                rec.cspDeltaM = d
                if d > M.MISMATCH_M then rec.flags[#rec.flags + 1] = ("csp reports %.1f km away"):format(d / 1000) end
            end
            return rec
        end
        rec.id = host == "assetto_corsa" and ("ac:" .. tostring(track) .. (layout ~= "" and ("/" .. layout) or "")) or (host .. ":" .. tostring(track))
        rec.name = obs.name or track
        local ovLat, ovLon = obs.override and tonumber(obs.override.lat), obs.override and tonumber(obs.override.lon)
        if plausible(ovLat, ovLon) then
            rec.lat, rec.lon, rec.status, rec.provenance = ovLat, ovLon, "resolved", "override manifest"
        elseif cspOk then
            rec.lat, rec.lon, rec.status, rec.provenance = cspLat, cspLon, "resolved", "csp ac.getTrackCoordinatesDeg"
        else
            local la, lo = M.parseGeotags(obs.geotags)   -- lat, lon -- or nil, why
            if la then rec.lat, rec.lon, rec.status, rec.provenance = la, lo, "resolved", "ui_track.json geotags"
            else rec.status, rec.provenance = "unresolved", lo or "no trustworthy coordinates" end
        end
        if obs.csp and tonumber(obs.csp.tzS) then rec.tz = tonumber(obs.csp.tzS) / 3600 end
        if rec.status == "resolved" and not rec.tz then rec.tz = math.floor(rec.lon / 15 + 0.5) end   -- solar zone, flagged
        if rec.status == "resolved" and not (obs.csp and obs.csp.tzS) then rec.flags[#rec.flags + 1] = "timezone from longitude" end
        rec.alt = 0
        return rec
    end

    --- Can NCM fly someone there? Only to a place it knows.
    function M.destination(rec) return rec and (rec.status == "verified" or rec.status == "resolved") or false end

    return M
end)
