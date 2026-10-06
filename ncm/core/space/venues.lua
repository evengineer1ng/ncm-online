-- ncm-core module: space.venues
--
-- L327: places on NCM Earth that an external host can physically express. Assetto Corsa is NOT a universe: its tracks are
-- locations on the same Earth `space.deep` flies over, and AC is the engine that embodies them at motorsport fidelity.
--
-- Registered = installed on this PC (2026-10-06 inventory: AC 1.16 content, 17 real venues / 34 layouts) AND defensibly
-- located. Kunos ships `geotags = ["lat","lon"]` placeholders, so every coordinate here is AUTHORED from the circuit's
-- real location (start/finish area, decimal degrees). Fictional content stays unregistered: Black Cat County, Highlands,
-- Drift, the drag strips -- no invented Earth coordinates.
--
-- Time: NCM's one clock is real UTC (`week.clock`). A venue's LOCAL time is UTC + its standard offset (no DST in v1);
-- its SOLAR time (what the sun does) is UTC + longitude / 15. `daylight(utc)` drives scheduling and the sun in AC.
-- Lighting: CSP 0.2.11 ships no lighting configs for these tracks, so every venue is `lit = false` -- night is real dark.
local Core = NcmCore

Core.define("space.venues", function(C)
    local M = { version = "0.1.0" }

    -- host = "assetto_corsa"; track = AC folder; layouts = AC layout folders ("" = the track has one layout)
    -- kind: circuit | road_course | hillclimb | historic ; families: which NCM championship families may race here
    M.VENUES = {
        { id = "monza", name = "Autodromo Nazionale Monza", region = "Italy", lat = 45.6156, lon = 9.2811, alt = 162, tz = 1,
          host = "assetto_corsa", track = "monza", layouts = { "" }, kind = "circuit", families = { "open_wheel", "gt", "touring", "endurance" } },
        { id = "monza_1966", name = "Monza 1966 (with the banking)", region = "Italy", lat = 45.6156, lon = 9.2811, alt = 162, tz = 1,
          host = "assetto_corsa", track = "ks_monza66", layouts = { "full", "road", "junior" }, kind = "historic", families = { "historic", "open_wheel" } },
        { id = "spa", name = "Circuit de Spa-Francorchamps", region = "Belgium", lat = 50.4372, lon = 5.9714, alt = 400, tz = 1,
          host = "assetto_corsa", track = "spa", layouts = { "" }, kind = "circuit", families = { "open_wheel", "gt", "endurance", "touring" } },
        { id = "nordschleife", name = "Nürburgring Nordschleife", region = "Germany", lat = 50.3356, lon = 6.9475, alt = 620, tz = 1,
          host = "assetto_corsa", track = "ks_nordschleife", layouts = { "nordschleife", "endurance", "endurance_cup", "touristenfahrten" },
          kind = "road_course", families = { "gt", "endurance", "road" } },
        { id = "nurburgring_gp", name = "Nürburgring GP-Strecke", region = "Germany", lat = 50.3341, lon = 6.9433, alt = 620, tz = 1,
          host = "assetto_corsa", track = "ks_nurburgring", layouts = { "layout_gp_a", "layout_gp_b", "layout_sprint_a", "layout_sprint_b" },
          kind = "circuit", families = { "open_wheel", "gt", "touring" } },
        { id = "silverstone", name = "Silverstone Circuit", region = "England", lat = 52.0786, lon = -1.0169, alt = 153, tz = 0,
          host = "assetto_corsa", track = "ks_silverstone", layouts = { "gp", "international", "national" }, kind = "circuit",
          families = { "open_wheel", "gt", "touring" } },
        { id = "silverstone_1967", name = "Silverstone 1967", region = "England", lat = 52.0786, lon = -1.0169, alt = 153, tz = 0,
          host = "assetto_corsa", track = "ks_silverstone1967", layouts = { "" }, kind = "historic", families = { "historic" } },
        { id = "imola", name = "Autodromo Enzo e Dino Ferrari, Imola", region = "Italy", lat = 44.3439, lon = 11.7167, alt = 37, tz = 1,
          host = "assetto_corsa", track = "imola", layouts = { "" }, kind = "circuit", families = { "open_wheel", "gt", "touring" } },
        { id = "mugello", name = "Autodromo Internazionale del Mugello", region = "Italy", lat = 43.9975, lon = 11.3719, alt = 250, tz = 1,
          host = "assetto_corsa", track = "mugello", layouts = { "" }, kind = "circuit", families = { "open_wheel", "gt" } },
        { id = "barcelona", name = "Circuit de Barcelona-Catalunya", region = "Spain", lat = 41.5700, lon = 2.2611, alt = 120, tz = 1,
          host = "assetto_corsa", track = "ks_barcelona", layouts = { "layout_gp", "layout_moto" }, kind = "circuit",
          families = { "open_wheel", "gt", "touring" } },
        { id = "brands_hatch", name = "Brands Hatch", region = "England", lat = 51.3569, lon = 0.2631, alt = 120, tz = 0,
          host = "assetto_corsa", track = "ks_brands_hatch", layouts = { "gp", "indy" }, kind = "circuit", families = { "touring", "gt" } },
        { id = "laguna_seca", name = "WeatherTech Raceway Laguna Seca", region = "California", lat = 36.5843, lon = -121.7535, alt = 245, tz = -8,
          host = "assetto_corsa", track = "ks_laguna_seca", layouts = { "" }, kind = "circuit", families = { "gt", "touring", "road" } },
        { id = "red_bull_ring", name = "Red Bull Ring", region = "Austria", lat = 47.2197, lon = 14.7647, alt = 680, tz = 1,
          host = "assetto_corsa", track = "ks_red_bull_ring", layouts = { "layout_gp", "layout_national" }, kind = "circuit",
          families = { "open_wheel", "gt" } },
        { id = "zandvoort", name = "Circuit Zandvoort", region = "Netherlands", lat = 52.3888, lon = 4.5409, alt = 5, tz = 1,
          host = "assetto_corsa", track = "ks_zandvoort", layouts = { "" }, kind = "circuit", families = { "open_wheel", "touring" } },
        { id = "vallelunga", name = "Autodromo di Vallelunga", region = "Italy", lat = 42.1586, lon = 12.3697, alt = 190, tz = 1,
          host = "assetto_corsa", track = "ks_vallelunga", layouts = { "extended_circuit", "classic_circuit", "club_circuit" }, kind = "circuit",
          families = { "touring", "gt", "road" } },
        { id = "magione", name = "Autodromo dell'Umbria, Magione", region = "Italy", lat = 43.1367, lon = 12.0600, alt = 280, tz = 1,
          host = "assetto_corsa", track = "magione", layouts = { "" }, kind = "circuit", families = { "touring", "road" } },
        { id = "trento_bondone", name = "Trento-Bondone hillclimb", region = "Italy", lat = 46.0400, lon = 11.0800, alt = 300, tz = 1,
          host = "assetto_corsa", track = "trento-bondone", layouts = { "" }, kind = "hillclimb", families = { "road" } },
    }
    -- every registered venue is unlit (no CSP lighting config installed for these tracks)
    for _, v in ipairs(M.VENUES) do v.lit = false end

    local byId = {}
    for _, v in ipairs(M.VENUES) do byId[v.id] = v end
    function M.get(id) return byId[id] end

    --- Unregistered on purpose (fictional), so a future inventory can tell "ignored" from "missed".
    M.UNREGISTERED = { ks_black_cat_county = "fictional", ks_highlands = "fictional", drift = "fictional", ks_drag = "fictional" }

    --- Standard local time and solar time at a venue for a UTC instant (seconds). Returns local hour (0..24), solar hour.
    function M.localHour(v, utc)
        local h = ((utc % 86400) / 3600 + (v.tz or 0)) % 24
        local s = ((utc % 86400) / 3600 + v.lon / 15) % 24
        return h, s
    end

    --- Is the sun up there (solar time between ~06:30 and ~18:30, equinox approximation)?
    function M.daylight(v, utc)
        local _, s = M.localHour(v, utc)
        return s >= 6.5 and s < 18.5, s
    end

    --- The AC sun angle for a solar hour (vanilla AC: -80 at ~08:00 .. +80 at ~18:00; CSP extends it): 16 degrees an hour,
    --- noon at 0. Returned unclamped; the launcher clamps for vanilla and lets CSP go past it.
    function M.acSunAngle(solarHour) return (solarHour - 13) * 16 end

    return M
end)
